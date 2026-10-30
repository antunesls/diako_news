import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:diako_core/diako_core.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'agenda_google_api.dart';

/// Agenda da igreja no Google Agenda, em um de dois modos:
/// - **iCal** (só leitura): baixa o endereço secreto no formato iCal;
/// - **API** (leitura e escrita): com a chave de uma conta de serviço e o ID da agenda, lê e altera
///   eventos pela API do Google Calendar. Tem prioridade sobre o iCal quando está configurado.
/// Baixa periodicamente e guarda a última cópia boa em data/ (agenda.ics ou agenda-api.json), para
/// continuar mostrando os eventos mesmo se a internet cair.
class AgendaGoogle {
  AgendaGoogle({
    required String pastaDados,
    required this.url,
    http.Client? cliente,
    this.aoMudar,
    DateTime Function()? relogio,
    this.intervalo = const Duration(minutes: 15),
    this.conta,
    String Function()? calendarioId,
    CalendarioGoogle Function(Map<String, dynamic> chave, String calendarioId)? criarCalendario,
  })  : _http = cliente ?? http.Client(),
        _agora = relogio ?? DateTime.now,
        calendarioId = calendarioId ?? (() => ''),
        _criarCalendarioInformado = criarCalendario,
        _arquivo = File(p.join(pastaDados, 'agenda.ics')),
        _estado = File(p.join(pastaDados, 'agenda.json')),
        _arquivoApi = File(p.join(pastaDados, 'agenda-api.json'));

  /// Chave da conta de serviço (modo API); null mantém só o modo iCal.
  final ContaServicoGoogle? conta;

  /// ID da agenda no Google (configurado ou tirado do endereço iCal).
  final String Function() calendarioId;
  final CalendarioGoogle Function(Map<String, dynamic> chave, String calendarioId)? _criarCalendarioInformado;
  final File _arquivoApi;

  CalendarioGoogle? _cal;
  String? _calAssinatura;

  /// Eventos lidos pela API (de ontem até ~4 meses à frente), ou null se ainda não leu.
  List<Evento>? _eventosApi;
  String? _calendarioDoCache;

  CalendarioGoogle _criarCalendario(Map<String, dynamic> chave, String id) =>
      (_criarCalendarioInformado ?? (c, i) => CalendarioGoogle.daConta(c, i, base: _http))(chave, id);

  /// Cliente da API, quando há chave e ID da agenda. Refeito se a chave ou o ID mudarem.
  CalendarioGoogle? get calendario {
    final chave = conta?.dados;
    final id = calendarioId();
    if (chave == null || id.isEmpty) {
      _cal?.fechar();
      _cal = null;
      _calAssinatura = null;
      return null;
    }
    final assinatura = '${chave['private_key_id']}|${chave['client_email']}|$id';
    if (_cal == null || _calAssinatura != assinatura) {
      _cal?.fechar();
      _cal = _criarCalendario(chave, id);
      _calAssinatura = assinatura;
    }
    return _cal;
  }

  /// A agenda pode ser alterada pelo DiakoHub (modo API).
  bool get editavel => calendario != null;

  /// Endereço atual (lido das configurações a cada atualização).
  final String Function() url;
  final void Function()? aoMudar;
  final Duration intervalo;
  final http.Client _http;
  final DateTime Function() _agora;
  final File _arquivo;
  final File _estado;

  String? _ics;
  String? _etag;
  String? _urlDoCache;
  DateTime? ultimaAtualizacao;
  String? erro;
  Timer? _timer;
  Future<bool>? _emAndamento;

  // Memória da última leitura (o mural consulta a cada minuto).
  ({String chave, List<Evento> eventos})? _memo;

  static const timeout = Duration(seconds: 20);

  bool get configurada => editavel || url().isNotEmpty;

  Future<void> carregar() async {
    if (await _arquivo.exists()) _ics = await _arquivo.readAsString();
    if (await _estado.exists()) {
      try {
        final j = jsonDecode(await _estado.readAsString()) as Map<String, dynamic>;
        ultimaAtualizacao = DateTime.tryParse(j['atualizado'] as String? ?? '');
        _etag = j['etag'] as String?;
        _urlDoCache = j['url'] as String?;
        erro = j['erro'] as String?;
      } catch (_) {}
    }
    // A cópia guardada é de outro endereço (trocado com o servidor parado): descarta.
    if (_urlDoCache != null && _urlDoCache != url()) await _limpar();
    if (await _arquivoApi.exists()) {
      try {
        final j = jsonDecode(await _arquivoApi.readAsString()) as Map<String, dynamic>;
        _calendarioDoCache = j['calendario'] as String?;
        _eventosApi = [for (final e in j['eventos'] as List) Evento.fromJson(Map<String, dynamic>.from(e as Map))];
        if (editavel) {
          ultimaAtualizacao = DateTime.tryParse(j['atualizado'] as String? ?? '');
          erro = j['erro'] as String?;
        }
      } catch (_) {
        _eventosApi = null;
      }
    }
  }

  void iniciar() {
    _timer?.cancel();
    unawaited(atualizarAgora());
    _timer = Timer.periodic(intervalo, (_) => atualizarAgora());
  }

  void parar() => _timer?.cancel();

  /// Baixa a agenda agora. Retorna true se os eventos mudaram.
  Future<bool> atualizarAgora() => _emAndamento ??= _atualizar().whenComplete(() => _emAndamento = null);

  Future<bool> _atualizar() async {
    if (editavel) return _atualizarApi();
    final endereco = url();
    if (endereco != _urlDoCache && (_ics != null || _urlDoCache != null)) {
      // Endereço trocado ou removido no /admin: a agenda antiga não vale mais.
      await _limpar();
      aoMudar?.call();
    }
    if (endereco.isEmpty) return false;
    try {
      final r = await _http.get(Uri.parse(endereco), headers: {if (_etag != null) 'If-None-Match': _etag!}).timeout(timeout);
      if (r.statusCode == 304) {
        await _gravarEstado(erro: null);
        return false;
      }
      if (r.statusCode != 200) throw HttpException(_mensagemHttp(r.statusCode));
      final texto = utf8.decode(r.bodyBytes, allowMalformed: true);
      if (!texto.contains('BEGIN:VCALENDAR')) {
        throw const FormatException('O endereço não devolveu uma agenda no formato iCal.');
      }
      final mudou = texto != _ics;
      _ics = texto;
      _etag = r.headers['etag'];
      _urlDoCache = endereco;
      if (mudou) {
        _memo = null;
        final tmp = File('${_arquivo.path}.tmp');
        await tmp.writeAsString(texto, flush: true);
        await tmp.rename(_arquivo.path);
      }
      await _gravarEstado(erro: null);
      if (mudou) aoMudar?.call();
      return mudou;
    } catch (e) {
      await _gravarEstado(erro: _resumo(e));
      return false;
    }
  }

  // ---------- Modo API (conta de serviço) ----------

  Future<bool> _atualizarApi() async {
    final cal = calendario!;
    final agora = _agora();
    final de = DateTime(agora.year, agora.month, agora.day - 1);
    try {
      final lista = await cal.listar(de, de.add(const Duration(days: 125)));
      final antes = _eventosApi;
      final mudou =
          antes == null || _calendarioDoCache != cal.calendarioId || jsonEncode(antes) != jsonEncode(lista);
      _eventosApi = lista;
      _calendarioDoCache = cal.calendarioId;
      erro = null;
      ultimaAtualizacao = agora;
      await _gravarApi();
      if (mudou) aoMudar?.call();
      return mudou;
    } on ErroGoogle catch (e) {
      erro = e.mensagem;
      await _gravarApi();
      return false;
    }
  }

  Future<void> _gravarApi() async {
    final tmp = File('${_arquivoApi.path}.tmp');
    await tmp.writeAsString(
        jsonEncode({
          'calendario': _calendarioDoCache,
          'atualizado': ultimaAtualizacao?.toIso8601String(),
          'erro': erro,
          'eventos': [for (final e in _eventosApi ?? const <Evento>[]) e.toJson()],
        }),
        flush: true);
    await tmp.rename(_arquivoApi.path);
  }

  CalendarioGoogle get _calOuErro =>
      calendario ??
      (throw ErroGoogle(
          'A agenda está ligada só para leitura. Ligue a conta de serviço em Administração para criar eventos.',
          ancora: 'ligar-antes',
          status: 400));

  /// Cria o evento no Google e já mostra na lista (sem esperar a próxima atualização).
  Future<Evento> criar(DadosEvento d) async {
    final e = await _calOuErro.criar(d);
    await _aplicarLocal(e.id, e);
    return e;
  }

  Future<Evento> atualizar(String id, DadosEvento d) async {
    final e = await _calOuErro.atualizar(id, d);
    await _aplicarLocal(id, e);
    return e;
  }

  Future<void> excluir(String id) async {
    await _calOuErro.excluir(id);
    await _aplicarLocal(id, null);
  }

  Future<void> _aplicarLocal(String id, Evento? novo) async {
    final lista = [...?_eventosApi]..removeWhere((e) => e.id == id);
    if (novo != null) lista.add(novo);
    lista.sort((a, b) => a.inicio.compareTo(b.inicio));
    _eventosApi = lista;
    _calendarioDoCache = calendario?.calendarioId;
    await _gravarApi();
    aoMudar?.call();
  }

  /// Testa uma chave e um ID de agenda antes de salvar. Lança [ErroGoogle].
  Future<AcessoAgenda> testarConta(Map<String, dynamic> chave, String id) async {
    final cal = _criarCalendario(chave, id);
    try {
      return await cal.testarAcesso();
    } finally {
      cal.fechar();
    }
  }

  /// Eventos (ocorrências) que se sobrepõem a [de, ate).
  List<Evento> eventos({required DateTime de, required DateTime ate}) {
    if (editavel) {
      if (_calendarioDoCache != calendario!.calendarioId) return const [];
      return [
        for (final e in _eventosApi ?? const <Evento>[])
          if (e.inicio.isBefore(ate) && (e.fim.isAfter(de) || (!e.fim.isAfter(e.inicio) && !e.inicio.isBefore(de)))) e
      ];
    }
    final ics = _ics;
    if (ics == null || !configurada) return const [];
    final chave = '${ics.length}|${ics.hashCode}|$de|$ate';
    final m = _memo;
    if (m != null && m.chave == chave) return m.eventos;
    final lista = lerIcs(ics, de: de, ate: ate);
    _memo = (chave: chave, eventos: lista);
    return lista;
  }

  /// Próximos eventos a partir de agora (o que ainda não terminou), por [dias].
  List<Evento> proximos({int dias = 30}) {
    final agora = _agora();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    return proximosEventos(eventos(de: hoje, ate: hoje.add(Duration(days: dias + 1))), agora, dias: dias);
  }

  Map<String, dynamic> estado() => {
        'configurada': configurada,
        'modo': editavel ? 'google' : (url().isNotEmpty ? 'ical' : null),
        'editavel': editavel,
        'contaServico': conta?.email,
        'calendarioId': calendarioId(),
        'atualizado': ultimaAtualizacao?.toIso8601String(),
        'erro': erro,
        'proximos30dias': configurada ? proximos().length : 0,
      };

  /// Testa um endereço antes de salvar: devolve os próximos eventos ou lança uma mensagem amigável.
  static Future<List<Evento>> testar(String endereco, {http.Client? cliente, DateTime? agora}) async {
    final c = cliente ?? http.Client();
    final http.Response r;
    try {
      r = await c.get(Uri.parse(endereco)).timeout(timeout);
    } catch (e) {
      throw FormatException('Não foi possível acessar o endereço: ${_resumo(e)}');
    }
    if (r.statusCode != 200) throw FormatException(_mensagemHttp(r.statusCode));
    final texto = utf8.decode(r.bodyBytes, allowMalformed: true);
    if (!texto.contains('BEGIN:VCALENDAR')) {
      throw const FormatException('O endereço não devolveu uma agenda no formato iCal. Copie o "Endereço secreto no formato iCal".');
    }
    final a = agora ?? DateTime.now();
    final hoje = DateTime(a.year, a.month, a.day);
    return proximosEventos(lerIcs(texto, de: hoje, ate: hoje.add(const Duration(days: 61))), a, dias: 60);
  }

  Future<void> _limpar() async {
    _ics = null;
    _etag = null;
    _urlDoCache = null;
    _memo = null;
    ultimaAtualizacao = null;
    erro = null;
    if (await _arquivo.exists()) await _arquivo.delete();
    if (await _estado.exists()) await _estado.delete();
  }

  Future<void> _gravarEstado({required String? erro}) async {
    this.erro = erro;
    if (erro == null) ultimaAtualizacao = _agora();
    await _estado.writeAsString(jsonEncode({
      'atualizado': ultimaAtualizacao?.toIso8601String(),
      'etag': _etag,
      'url': _urlDoCache,
      'erro': erro,
    }));
  }

  static String _mensagemHttp(int status) => switch (status) {
        404 => 'Agenda não encontrada (404). Confira o endereço secreto iCal.',
        401 || 403 => 'Sem permissão ($status). Use o "Endereço secreto no formato iCal".',
        _ => 'O Google respondeu HTTP $status.',
      };

  static String _resumo(Object e) => e is FormatException ? e.message : e.toString().split('\n').first;
}
