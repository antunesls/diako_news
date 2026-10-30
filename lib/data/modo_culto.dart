import 'dart:convert';

import 'package:diako_core/diako_core.dart';
import 'package:flutter/foundation.dart';

import '../app_scope.dart';
import '../sync/server_api.dart';
import 'escala_repo.dart';

/// Estado do Modo Culto: escolhe o culto de hoje, monta o roteiro com os dados do app,
/// guarda onde o culto está (sobrevive ao app fechar) e executa cada passo no Holyrics.
///
/// O roteiro é remontado sempre que os dados mudam (pedido aprovado, visitante novo); a
/// posição é guardada pelo tipo de momento, então não se perde.
class ModoCultoController extends ChangeNotifier {
  ModoCultoController(this.scope, {Set<String> recadosSelecionados = const {}, DateTime Function()? agora})
      : _agora = agora ?? DateTime.now {
    _restaurar(recadosSelecionados);
    _fontes = Listenable.merge([scope.repo, scope.motivos, scope.visitas, scope.agenda, scope.escalas, scope.settings, scope.palavra]);
    _fontes.addListener(_remontar);
    _remontar();
    _conferirPix();
  }

  final AppScope scope;
  final DateTime Function() _agora;
  late final Listenable _fontes;

  Set<String> _recados = {};
  bool _iniciado = false;
  PosicaoRoteiro? _posicao;
  /// Hora em que cada momento começou, pela chave do momento.
  final Map<String, DateTime> _inicios = {};
  List<Momento> _roteiro = [];
  CultoDoDia? _culto;

  /// O servidor tem o QR do PIX (chave configurada em Administração).
  bool _pix = false;
  bool _descartado = false;

  /// Trecho da Palavra na TV do palco (null = a leitura ainda não começou).
  int? _trecho;

  /// Versículo no telão durante a Palavra (ex: Rm 5.8); null = tela preta.
  String? _versiculo;

  /// Hora em que cada tópico da Palavra começou (o primeiro trecho dele na TV do palco).
  final Map<String, DateTime> _inicioTopicos = {};

  List<Momento> get roteiro => _roteiro;

  /// Culto de hoje na escala; null se não há (o roteiro sai sem contagem e sem louvor).
  CultoDoDia? get culto => _culto;

  /// Já passou da tela "Antes do culto".
  bool get iniciado => _iniciado;

  /// O passo que está no telão; null antes de começar.
  PosicaoRoteiro? get posicao => _posicao == null ? null : localizar(_roteiro, _posicao!);

  Momento? get momentoAtual {
    final p = posicao;
    return p == null ? null : momentoDe(p);
  }

  Passo? get passoAtual {
    final p = posicao;
    return p == null ? null : momentoAtual!.passos[p.passo];
  }

  /// O que um toque em Avançar vai projetar.
  PosicaoRoteiro? get proxima {
    final p = _posicao;
    if (p == null) return _roteiro.isEmpty ? null : PosicaoRoteiro.de(_roteiro.first);
    return proximaPosicao(_roteiro, p);
  }

  Momento momentoDe(PosicaoRoteiro p) => _roteiro.firstWhere((m) => m.chave == p.chave);
  Passo passoDe(PosicaoRoteiro p) => momentoDe(p).passos[p.passo];

  /// Quando o momento começou (null se ainda não chegou nele).
  DateTime? inicioDe(Momento m) => _inicios[m.chave];

  /// Início do culto propriamente dito: o primeiro momento depois da contagem.
  DateTime? get inicioDoCulto {
    final inicios = [for (final e in _inicios.entries) if (e.key != TipoMomento.contagem.name) e.value]..sort();
    return inicios.firstOrNull;
  }

  /// Minutos previstos para o momento (do modelo); a Palavra usa o tempo dela (do painel) ou o
  /// ajustado no tablet.
  int previsto(Momento m) =>
      m.tipo == TipoMomento.palavra ? palavra?.minutos ?? scope.settings.minutosPregacao : m.minutos;

  /// A Palavra pronta de hoje (preparada no painel); null = Palavra sem texto (só cronômetro).
  PalavraDoCulto? get palavra => scope.palavra.palavra;

  /// Índice do trecho na TV do palco; null antes de começar a leitura.
  int? get trecho {
    final t = _trecho, p = palavra;
    return t == null || p == null || p.trechos.isEmpty ? null : t.clamp(0, p.trechos.length - 1);
  }

  /// Versículo no telão durante a Palavra; null = tela preta.
  String? get versiculo => _versiculo;

  /// Frase de destaque no telão durante a Palavra; null = nenhuma.
  String? get destaque => _destaque;
  String? _destaque;

  /// Ritmo da pregação no tópico atual, só para o pastor: tempo no tópico, previsto e desvio em
  /// minutos (positivo = atrasado). Null sem leitura começada ou fora de um tópico.
  ({int indice, int total, Duration noTopico, int? minutos, int? desvio})? get ritmo {
    final p = palavra, t = trecho;
    if (p == null || t == null) return null;
    final topicos = p.topicos;
    final atual = p.trechos[t].topico;
    final indice = topicos.indexWhere((x) => x.$1 == atual);
    if (indice < 0) return null;
    final agora = _agora();
    final inicioTopico = _inicioTopicos[atual] ?? agora;
    final momento = _roteiro.where((m) => m.tipo == TipoMomento.palavra).firstOrNull;
    final inicioPalavra = (momento == null ? null : _inicios[momento.chave]) ?? _inicioTopicos[topicos.first.$1] ?? inicioTopico;
    final minutos = [for (final x in topicos) p.minutosTopicos[x.$1]];
    return (
      indice: indice,
      total: topicos.length,
      noTopico: agora.difference(inicioTopico),
      minutos: minutos[indice],
      desvio: desvioDaPregacao(
        minutosPorTopico: minutos,
        atual: indice,
        desdeOInicio: agora.difference(inicioPalavra),
        noTopico: agora.difference(inicioTopico),
      ),
    );
  }

  /// Passa o trecho [indice] para a TV do palco.
  Future<void> irParaTrecho(int indice) async {
    final p = palavra;
    if (p == null || indice < 0 || indice >= p.trechos.length) return;
    await scope.client.leituraPalco(p.trechos[indice].texto);
    _trecho = indice;
    final topico = p.trechos[indice].topico;
    if (topico.isNotEmpty) _inicioTopicos.putIfAbsent(topico, _agora);
    await _salvar();
    notifyListeners();
  }

  /// Próximo trecho (o primeiro, se a leitura não começou). Retorna false no fim.
  Future<bool> proximoTrecho() async {
    final p = palavra;
    final seguinte = trecho == null ? 0 : trecho! + 1;
    if (p == null || seguinte >= p.trechos.length) return false;
    await irParaTrecho(seguinte);
    return true;
  }

  Future<bool> trechoAnterior() async {
    final t = trecho;
    if (t == null || t == 0) return false;
    await irParaTrecho(t - 1);
    return true;
  }

  /// Projeta no telão um versículo citado no trecho (a tela preta da pregação sai antes).
  Future<void> projetarVersiculo(RefBiblica ref) async {
    final status = scope.status;
    if (status.telaPreta) {
      await scope.client.telaPreta(false);
      status.telaPreta = false;
    }
    if (status.telaVazia) {
      await scope.client.telaVazia(false);
      status.telaVazia = false;
    }
    await scope.client.mostrarVersiculo(ref.ids);
    _versiculo = ref.abreviada;
    _destaque = null;
    notifyListeners();
    await status.atualizar();
  }

  /// Projeta no telão uma frase marcada no trecho (a tela preta da pregação sai antes).
  Future<void> projetarDestaque(String frase) async {
    final status = scope.status;
    if (status.telaPreta) {
      await scope.client.telaPreta(false);
      status.telaPreta = false;
    }
    if (status.telaVazia) {
      await scope.client.telaVazia(false);
      status.telaVazia = false;
    }
    await scope.client.projetarTexto(slideDestaque(frase), tema: scope.settings.tema);
    _destaque = frase;
    _versiculo = null;
    notifyListeners();
    await status.atualizar();
  }

  /// Tira o versículo ou a frase: volta a tela preta da pregação.
  Future<void> tirarVersiculo() async {
    await scope.client.telaPreta(true);
    scope.status.telaPreta = true;
    _versiculo = null;
    _destaque = null;
    notifyListeners();
    await scope.status.atualizar();
  }

  /// Hora do culto (hh:mm de hoje) já chegou.
  bool get horaDoCulto {
    final hora = _culto?.hora ?? '';
    final m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(hora);
    if (m == null) return false;
    final agora = _agora();
    return !agora.isBefore(DateTime(agora.year, agora.month, agora.day, int.parse(m.group(1)!), int.parse(m.group(2)!)));
  }

  /// Recados que vão ao culto: os selecionados na tela de organizar; sem seleção, os que não expiraram.
  List<Recado> get recados {
    final todos = scope.repo.todos;
    final agora = _agora();
    return ordenarParaExibicao(
        _recados.isEmpty ? todos.where((r) => !r.expirado(agora)) : todos.where((r) => _recados.contains(r.id)));
  }

  CultoDoDia? _escolherCulto() {
    final escalas = scope.escalas;
    if (!escalas.hoje || escalas.cultos.isEmpty) return null;
    final agora = _agora();
    // O primeiro culto de hoje que ainda não terminou (até 3 h depois do início).
    return escalas.cultos.where((c) => cultoProximo(c.data, c.hora, agora) || c.hora.isEmpty).firstOrNull ??
        escalas.cultos.where((c) => c.hora.compareTo(_hhmm(agora)) > 0).firstOrNull ??
        escalas.cultos.last;
  }

  /// Pergunta ao servidor se há QR do PIX; sem conexão, o momento das ofertas fica só com o slide.
  Future<void> _conferirPix() async {
    try {
      final pix = (await scope.api.estado())['qrPixHolyrics'] is String;
      if (pix != _pix && !_descartado) {
        _pix = pix;
        _remontar();
      }
    } on ErroAmigavel catch (_) {}
  }

  static String _hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  void _remontar() {
    final c = _culto = _escolherCulto();
    // Com dois cultos no dia, a Palavra que desce é a ligada a este.
    if (c != null && c.id.isNotEmpty && scope.palavra.culto != c.id) {
      scope.palavra.culto = c.id;
      scope.palavra.sincronizar();
    }
    final s = scope.settings;
    _roteiro = montarRoteiro(
      horaCulto: c?.hora ?? '',
      ceia: c?.ceia ?? false,
      musicas: [for (final m in c?.musicas ?? const <Musica>[]) m.tom.isEmpty ? m.titulo : '${m.titulo} · ${m.tom}'],
      louvor: c?.louvor ?? const {},
      pastoral: c?.pastoral ?? const {},
      tema: c?.tema ?? '',
      recados: recados,
      motivos: scope.motivos.projetaveis,
      respondidas: oracoesRespondidas(scope.motivos.todos, _agora()),
      visitas: scope.visitas.hoje,
      proximoEvento: scope.agenda.proximo,
      motivosPorSlide: s.motivosPorSlide,
      negritoTitulo: s.negritoTitulo,
      pix: _pix,
      modelo: c?.roteiro ?? scope.escalas.roteiroPadrao,
    );
    notifyListeners();
  }

  /// Projeta o passo em [destino] e passa a posição para ele. Se o Holyrics recusar, a posição
  /// não muda (o erro sobe para quem chamou mostrar).
  Future<void> irPara(PosicaoRoteiro destino) async {
    final p = localizar(_roteiro, destino);
    if (p == null) return;
    final anterior = _posicao == null ? null : localizar(_roteiro, _posicao!);
    final saindoDaPalavra = anterior != null && momentoDe(anterior).tipo == TipoMomento.palavra &&
        momentoDe(p).tipo != TipoMomento.palavra;
    await _executar(passoDe(p));
    if (saindoDaPalavra) {
      _versiculo = null;
      _destaque = null;
      // A TV do palco volta a ficar livre (frases e contagem); falha aqui não segura o culto.
      if (_trecho != null) {
        try {
          await scope.client.mensagemPalco('', mostrar: false);
        } on ErroAmigavel catch (_) {}
      }
    }
    _iniciado = true;
    _posicao = p;
    _inicios.putIfAbsent(p.chave, _agora);
    await _salvar();
    notifyListeners();
  }

  /// Próximo passo. Retorna false no fim do roteiro.
  Future<bool> avancar() async {
    final p = proxima;
    if (p == null) return false;
    await irPara(p);
    return true;
  }

  /// Passo anterior. Retorna false no começo do roteiro.
  Future<bool> voltar() async {
    final atual = _posicao;
    final p = atual == null ? null : posicaoAnterior(_roteiro, atual);
    if (p == null) return false;
    await irPara(p);
    return true;
  }

  /// Contagem no telão até a hora do culto (primeiro momento do roteiro).
  Future<void> iniciarContagem() async {
    final contagem = _roteiro.where((m) => m.tipo == TipoMomento.contagem).firstOrNull;
    if (contagem != null) await irPara(PosicaoRoteiro.de(contagem));
  }

  /// Pula a contagem e começa pelo primeiro momento do culto.
  Future<void> comecarCulto() {
    final primeiro = _roteiro.firstWhere((m) => m.tipo != TipoMomento.contagem, orElse: () => _roteiro.first);
    return irPara(PosicaoRoteiro.de(primeiro));
  }

  /// Sai do Modo Culto e esquece o progresso deste culto.
  Future<void> encerrar() async {
    _iniciado = false;
    _posicao = null;
    _inicios.clear();
    _trecho = null;
    _versiculo = null;
    _destaque = null;
    _inicioTopicos.clear();
    await scope.settings.salvarModoCulto('');
  }

  Future<void> _executar(Passo passo) async {
    final client = scope.client;
    final status = scope.status;
    final tema = scope.settings.tema;
    // Tela vazia/preta escondem tudo: desliga antes de projetar outra coisa.
    Future<void> limpar({bool vazia = true, bool preta = true}) async {
      if (vazia && status.telaVazia) {
        await client.telaVazia(false);
        status.telaVazia = false;
      }
      if (preta && status.telaPreta) {
        await client.telaPreta(false);
        status.telaPreta = false;
      }
    }

    switch (passo.acao) {
      case AcaoPasso.telaVazia:
        await limpar(vazia: false);
        await client.telaVazia(true);
        status.telaVazia = true;
      case AcaoPasso.telaPreta:
        await limpar(preta: false);
        await client.telaPreta(true);
        status.telaPreta = true;
      case AcaoPasso.texto:
        await limpar();
        await client.projetarTexto(passo.valor, tema: tema);
      case AcaoPasso.imagem:
        await limpar();
        await client.mostrarImagem(passo.valor);
      case AcaoPasso.contagem:
        await limpar();
        await client.contagemTela(passo.valor, horaExata: true, textoAntes: 'O culto começa em', tema: tema);
      case AcaoPasso.boasVindas:
        await limpar();
        await scope.visitas.projetarBoasVindas(ids: passo.ids);
      case AcaoPasso.qrOracao || AcaoPasso.qrMensagens || AcaoPasso.qrPix:
        await limpar();
        final estado = await scope.api.estado();
        final chave = switch (passo.acao) {
          AcaoPasso.qrOracao => 'qrHolyrics',
          AcaoPasso.qrMensagens => 'qrMensagensHolyrics',
          _ => 'qrPixHolyrics',
        };
        final arquivo = estado[chave];
        if (arquivo is! String) throw ServidorException('O QR não está disponível no servidor.');
        await client.mostrarImagem(arquivo);
    }
    await status.atualizar();
  }

  Future<void> _salvar() => scope.settings.salvarModoCulto(jsonEncode({
        'dia': diaIso(_agora()),
        'iniciado': _iniciado,
        if (_posicao != null) 'momento': _posicao!.chave,
        if (_posicao != null) 'ordem': _posicao!.ordem,
        if (_posicao != null) 'passo': _posicao!.passo,
        'inicios': {for (final e in _inicios.entries) e.key: e.value.toIso8601String()},
        'recados': _recados.toList(),
        if (_trecho != null) 'trecho': _trecho,
        if (_inicioTopicos.isNotEmpty) 'topicos': {for (final e in _inicioTopicos.entries) e.key: e.value.toIso8601String()},
      }));

  /// Retoma o culto de hoje se o app fechou no meio. A seleção nova de recados, se houver, vale mais.
  void _restaurar(Set<String> selecionados) {
    _recados = {...selecionados};
    try {
      final texto = scope.settings.modoCulto;
      if (texto.isEmpty) return;
      final j = Map<String, dynamic>.from(jsonDecode(texto) as Map);
      if (j['dia'] != diaIso(_agora())) return;
      _iniciado = j['iniciado'] == true;
      final chave = j['momento'];
      if (chave is String && chave.isNotEmpty) {
        _posicao = PosicaoRoteiro(chave, (j['passo'] as num?)?.toInt() ?? 0, (j['ordem'] as num?)?.toInt() ?? -1);
      }
      for (final e in Map<String, dynamic>.from(j['inicios'] as Map? ?? const {}).entries) {
        final quando = DateTime.tryParse('${e.value}');
        if (quando != null) _inicios[e.key] = quando;
      }
      _trecho = (j['trecho'] as num?)?.toInt();
      for (final e in Map<String, dynamic>.from(j['topicos'] as Map? ?? const {}).entries) {
        final quando = DateTime.tryParse('${e.value}');
        if (quando != null) _inicioTopicos[e.key] = quando;
      }
      if (_recados.isEmpty) _recados = {for (final id in j['recados'] as List? ?? const []) '$id'};
    } catch (_) {
      // Estado salvo ilegível: começa do zero.
    }
  }

  /// Há um culto de hoje em andamento salvo no tablet (para o aviso "Voltar ao Modo Culto").
  static bool emAndamento(String salvo, DateTime agora) {
    try {
      final j = Map<String, dynamic>.from(jsonDecode(salvo) as Map);
      return j['dia'] == diaIso(agora) && j['iniciado'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _descartado = true;
    _fontes.removeListener(_remontar);
    super.dispose();
  }
}
