import 'agenda.dart';
import 'motivo.dart';
import 'recado.dart';
import 'visita.dart';

/// Momentos do Modo Culto, na ordem do roteiro padrão (o [livre] não entra no padrão).
enum TipoMomento {
  contagem('Antes do culto', 0),
  boasVindas('Boas-vindas', 5),
  louvor('Louvor', 30),
  recados('Recados', 10),
  ofertas('Dízimos e ofertas', 5),
  ceia('Santa Ceia', 15),
  motivos('Motivos de oração', 10),
  palavra('Palavra', 40),
  oracaoFinal('Oração final e bênção', 5),
  encerramento('Encerramento', 5),

  /// Momento criado no modelo do painel (apresentação de crianças, batismo…): um slide ou tela vazia.
  livre('Momento livre', 5);

  const TipoMomento(this.titulo, this.minutos);
  final String titulo;

  /// Tempo sugerido; 0 = sem tempo (a contagem tem a própria hora).
  final int minutos;

  static TipoMomento? porNome(Object? nome) => values.where((t) => t.name == nome).firstOrNull;
}

/// Um momento num modelo de roteiro (montado no painel). A [chave] identifica o momento no culto:
/// é o nome do tipo para os momentos do sistema e "livre-<id>" para os livres.
class ItemRoteiro {
  const ItemRoteiro({required this.chave, required this.tipo, this.titulo = '', this.texto = '', int? minutos})
      : minutos = minutos ?? -1;

  final String chave;
  final TipoMomento tipo;

  /// Título do momento livre (os do sistema usam o título do tipo).
  final String titulo;

  /// Slide do momento livre; vazio = tela vazia.
  final String texto;

  /// Minutos previstos; -1 = o padrão do tipo.
  final int minutos;

  String get tituloEfetivo => tipo == TipoMomento.livre && titulo.trim().isNotEmpty ? titulo.trim() : tipo.titulo;
  int get minutosEfetivos => minutos < 0 ? tipo.minutos : minutos;

  Map<String, dynamic> toJson() => {
        'chave': chave,
        'tipo': tipo.name,
        if (titulo.isNotEmpty) 'titulo': titulo,
        if (texto.isNotEmpty) 'texto': texto,
        if (minutos >= 0) 'minutos': minutos,
      };

  factory ItemRoteiro.fromJson(Map<String, dynamic> j) {
    final tipo = TipoMomento.porNome(j['tipo']);
    if (tipo == null) throw const FormatException('Momento de tipo desconhecido.');
    final chave = (j['chave'] as String? ?? '').trim();
    if (tipo == TipoMomento.livre ? !RegExp(r'^livre-[A-Za-z0-9_-]{1,40}$').hasMatch(chave) : chave != tipo.name) {
      throw const FormatException('Chave de momento inválida.');
    }
    final titulo = (j['titulo'] as String? ?? '').trim();
    final texto = (j['texto'] as String? ?? '').trim();
    final minutos = (j['minutos'] as num?)?.toInt();
    if (titulo.length > 60) throw const FormatException('Título do momento muito longo (máximo 60 letras).');
    if (texto.length > 600) throw const FormatException('Texto do slide muito longo (máximo 600 letras).');
    if (minutos != null && (minutos < 0 || minutos > 180)) throw const FormatException('Minutos devem ficar entre 0 e 180.');
    if (tipo == TipoMomento.livre && titulo.isEmpty) throw const FormatException('Dê um título ao momento livre.');
    return ItemRoteiro(chave: chave, tipo: tipo, titulo: titulo, texto: texto, minutos: minutos);
  }
}

/// O roteiro que vale quando a igreja ainda não montou um modelo no painel.
final roteiroPadrao = [
  for (final t in TipoMomento.values)
    if (t != TipoMomento.livre) ItemRoteiro(chave: t.name, tipo: t),
];

/// Modelo de roteiro montado no painel ("Domingo", "Quarta de oração"…).
class ModeloRoteiro {
  ModeloRoteiro({required this.id, required this.nome, required this.itens, this.cultos = const [], this.padrao = false});

  final String id;
  final String nome;
  final List<ItemRoteiro> itens;

  /// Nomes de culto da escala em que este modelo vale ("Culto da família").
  final List<String> cultos;

  /// Vale para os cultos sem modelo próprio.
  final bool padrao;

  /// O modelo vale para o culto chamado [nome] (sem diferenciar maiúsculas e espaços).
  bool valePara(String nome) {
    String n(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return cultos.any((c) => n(c) == n(nome));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nome': nome,
        'cultos': cultos,
        'padrao': padrao,
        'itens': [for (final i in itens) i.toJson()],
      };

  /// Lê e valida (lança [FormatException] com o motivo).
  factory ModeloRoteiro.fromJson(Map<String, dynamic> j) {
    final nome = (j['nome'] as String? ?? '').trim();
    if (nome.isEmpty) throw const FormatException('Dê um nome ao modelo.');
    if (nome.length > 60) throw const FormatException('Nome do modelo muito longo (máximo 60 letras).');
    final itens = [for (final i in j['itens'] as List? ?? const []) ItemRoteiro.fromJson(Map<String, dynamic>.from(i as Map))];
    if (itens.isEmpty) throw const FormatException('O modelo precisa de pelo menos um momento.');
    if (itens.length > 30) throw const FormatException('Momentos demais (máximo 30).');
    if (itens.map((i) => i.chave).toSet().length != itens.length) throw const FormatException('Há momentos repetidos.');
    final cultos = [
      for (final c in j['cultos'] as List? ?? const [])
        if ('$c'.trim().isNotEmpty) '$c'.trim(),
    ];
    if (cultos.length > 20 || cultos.any((c) => c.length > 60)) throw const FormatException('Nomes de culto demais ou longos demais.');
    return ModeloRoteiro(id: j['id'] as String? ?? '', nome: nome, itens: itens, cultos: cultos, padrao: j['padrao'] == true);
  }
}

/// O modelo do culto chamado [nomeCulto]: o que cita o nome, senão o padrão; null = roteiro do sistema.
ModeloRoteiro? modeloDoCulto(List<ModeloRoteiro> modelos, String nomeCulto) =>
    modelos.where((m) => m.valePara(nomeCulto)).firstOrNull ?? modelos.where((m) => m.padrao).firstOrNull;

/// O que um passo faz no Holyrics.
enum AcaoPasso {
  /// Slide de texto (apresentação rápida). [Passo.valor] é o texto do slide.
  texto,

  /// Imagem da pasta do Holyrics. [Passo.valor] é o arquivo.
  imagem,

  /// Contagem até a hora do culto. [Passo.valor] é "HH:MM".
  contagem,

  /// Boas-vindas aos visitantes, projetadas pelo servidor. [Passo.ids] são as visitas.
  boasVindas,
  telaVazia,
  telaPreta,
  qrOracao,
  qrMensagens,

  /// QR do PIX da igreja (momento das ofertas), gerado pelo servidor.
  qrPix,
}

/// Um toque em Avançar: uma ação no telão, com o rótulo que o pastor vê.
class Passo {
  const Passo(this.acao, this.rotulo, {this.valor = '', this.ids = const []});

  final AcaoPasso acao;
  final String rotulo;
  final String valor;
  final List<String> ids;
}

class Momento {
  const Momento(this.tipo,
      {required this.passos, String? chave, this.ordem = 0, String? titulo, int? minutos, this.detalhe = '', this.linhas = const []})
      : chave = chave ?? '',
        _titulo = titulo,
        _minutos = minutos;

  final TipoMomento tipo;
  final List<Passo> passos;

  /// Identifica o momento no culto (ver [ItemRoteiro.chave]).
  final String chave;

  /// Posição no modelo (contando os momentos que ficaram de fora por falta de conteúdo).
  final int ordem;
  final String? _titulo;
  final int? _minutos;

  String get titulo => _titulo ?? tipo.titulo;
  int get minutos => _minutos ?? tipo.minutos;

  /// Uma linha de contexto (pregador e tema, quantos visitantes…).
  final String detalhe;

  /// Informação só para o pastor (músicas, escalados); não vai ao telão.
  final List<String> linhas;
}

/// Slide fixo do momento de ofertas.
const slideOfertas = 'Dízimos e ofertas\n'
    '“Trazei todos os dízimos à casa do tesouro, para que haja mantimento na minha casa.”\n'
    'Malaquias 3.10';

/// Slide fixo da Santa Ceia.
const slideCeia = 'Santa Ceia\n“Fazei isto em memória de mim.”\n1 Coríntios 11.24';

String _negrito(String slide, bool negrito) {
  if (!negrito) return slide;
  final i = slide.indexOf('\n');
  return i < 0 ? '<b>$slide</b>' : '<b>${slide.substring(0, i)}</b>${slide.substring(i)}';
}

/// Monta o roteiro do culto com o que o app já tem, na ordem do [modelo] (sem modelo, o
/// [roteiroPadrao]). Momentos sem conteúdo ficam de fora.
///
/// [visitas] são as de hoje que autorizaram ser citadas (já citadas ou não), para o
/// momento continuar no roteiro depois que o servidor dá baixa nas boas-vindas.
List<Momento> montarRoteiro({
  required String horaCulto,
  required bool ceia,
  required List<String> musicas,
  required Map<String, List<String>> louvor,
  required Map<String, List<String>> pastoral,
  required String tema,
  required List<Recado> recados,
  required List<Motivo> motivos,
  required List<Motivo> respondidas,
  required List<Visita> visitas,
  Evento? proximoEvento,
  int motivosPorSlide = 4,
  bool negritoTitulo = true,
  /// Regra da igreja (/admin): sem o texto, os motivos mostram só por quem orar e a categoria.
  bool textoMotivos = true,

  /// O servidor tem o QR do PIX: entra depois do slide das ofertas.
  bool pix = false,
  List<ItemRoteiro>? modelo,
}) {
  String nomes(Map<String, List<String>> funcoes, String funcao) => (funcoes[funcao] ?? const []).join(', ');
  List<String> escalados(Map<String, List<String>> funcoes) => [
        for (final e in funcoes.entries)
          if (e.value.isNotEmpty) '${e.key}: ${e.value.join(', ')}',
      ];

  final vistos = <String>{};
  final citaveis = [for (final v in visitas) if (v.mencionar && vistos.add(v.membroId)) v];
  final pregador = nomes(pastoral, 'Pregação');
  final textos = [
    for (final r in recados)
      r.ehImagem
          ? Passo(AcaoPasso.imagem, r.titulo.isEmpty ? 'Cartaz' : r.titulo, valor: r.imagemHolyrics!.trim())
          : Passo(AcaoPasso.texto, r.titulo, valor: montarSlide(r, negritoTitulo: negritoTitulo)),
  ];
  final oracao = montarSlidesOracao(motivos, porSlide: motivosPorSlide, negritoTitulo: negritoTitulo, comTexto: textoMotivos);
  final gratidao = montarSlidesGratidao(respondidas, negritoTitulo: negritoTitulo, comTexto: textoMotivos);

  /// Conteúdo de cada tipo (null = sem conteúdo hoje, o momento fica de fora).
  ({List<Passo> passos, String detalhe, List<String> linhas})? conteudo(ItemRoteiro item) => switch (item.tipo) {
        TipoMomento.contagem => RegExp(r'^\d{2}:\d{2}$').hasMatch(horaCulto)
            ? (
                passos: [Passo(AcaoPasso.contagem, 'Contagem até $horaCulto', valor: horaCulto)],
                detalhe: 'Contagem no telão até as $horaCulto',
                linhas: const <String>[],
              )
            : null,
        TipoMomento.boasVindas => citaveis.isEmpty
            ? null
            : (
                passos: [Passo(AcaoPasso.boasVindas, 'Sejam bem-vindos!', ids: [for (final v in citaveis) v.id])],
                detalhe: citaveis.length == 1 ? '1 visitante para citar' : '${citaveis.length} visitantes para citar',
                linhas: [for (final v in citaveis) v.nome],
              ),
        TipoMomento.louvor => musicas.isEmpty && escalados(louvor).isEmpty
            ? null
            : (
                passos: const [Passo(AcaoPasso.telaVazia, 'Tela vazia durante o louvor')],
                detalhe: musicas.isEmpty ? 'Músicas ainda não escolhidas' : '${musicas.length} música(s)',
                linhas: [...musicas, ...escalados(louvor)],
              ),
        TipoMomento.recados =>
          textos.isEmpty ? null : (passos: textos, detalhe: '${textos.length} recado(s), um por vez', linhas: const <String>[]),
        TipoMomento.ofertas => (
            passos: [
              Passo(AcaoPasso.texto, 'Dízimos e ofertas', valor: _negrito(slideOfertas, negritoTitulo)),
              if (pix) const Passo(AcaoPasso.qrPix, 'QR do PIX'),
            ],
            detalhe: nomes(pastoral, 'Oração e ofertas'),
            linhas: const <String>[],
          ),
        TipoMomento.ceia => !ceia
            ? null
            : (
                passos: [
                  Passo(AcaoPasso.texto, 'Santa Ceia', valor: _negrito(slideCeia, negritoTitulo)),
                  const Passo(AcaoPasso.telaVazia, 'Tela vazia'),
                ],
                detalhe: nomes(pastoral, 'Santa Ceia'),
                linhas: const <String>[],
              ),
        TipoMomento.motivos => oracao.isEmpty && gratidao.isEmpty
            ? null
            : (
                passos: [
                  for (var i = 0; i < oracao.length; i++)
                    Passo(AcaoPasso.texto, oracao.length == 1 ? 'Motivos de oração' : 'Motivos ${i + 1}/${oracao.length}',
                        valor: oracao[i]),
                  for (var i = 0; i < gratidao.length; i++)
                    Passo(AcaoPasso.texto,
                        gratidao.length == 1 ? 'Orações respondidas' : 'Respondidas ${i + 1}/${gratidao.length}',
                        valor: gratidao[i]),
                ],
                detalhe: [
                  if (motivos.isNotEmpty) '${motivos.length} aprovado(s)',
                  if (respondidas.isNotEmpty) '${respondidas.length} respondida(s)',
                ].join(' · '),
                linhas: const <String>[],
              ),
        TipoMomento.palavra => (
            passos: const [Passo(AcaoPasso.telaPreta, 'Tela preta durante a pregação')],
            detalhe: [if (pregador.isNotEmpty) pregador, if (tema.trim().isNotEmpty) '“${tema.trim()}”'].join(' · '),
            linhas: const <String>[],
          ),
        TipoMomento.oracaoFinal =>
          (passos: const [Passo(AcaoPasso.telaVazia, 'Tela vazia')], detalhe: '', linhas: const <String>[]),
        TipoMomento.encerramento => (
            passos: [
              const Passo(AcaoPasso.qrOracao, 'QR dos pedidos de oração'),
              const Passo(AcaoPasso.qrMensagens, 'QR da caixa de mensagens'),
              if (proximoEvento != null)
                Passo(AcaoPasso.texto, 'Próximo: ${proximoEvento.titulo}',
                    valor: montarSlideEvento(proximoEvento, negritoTitulo: negritoTitulo)),
            ],
            detalhe: '',
            linhas: const <String>[],
          ),
        TipoMomento.livre => (
            passos: [
              item.texto.isEmpty
                  ? const Passo(AcaoPasso.telaVazia, 'Tela vazia')
                  : Passo(AcaoPasso.texto, item.tituloEfetivo, valor: _negrito(item.texto, negritoTitulo)),
            ],
            detalhe: '',
            linhas: const <String>[],
          ),
      };

  final itens = modelo ?? roteiroPadrao;
  return [
    for (var i = 0; i < itens.length; i++)
      if (conteudo(itens[i]) case final c?)
        Momento(
          itens[i].tipo,
          chave: itens[i].chave,
          ordem: i,
          titulo: itens[i].tituloEfetivo,
          minutos: itens[i].minutosEfetivos,
          passos: c.passos,
          detalhe: c.detalhe,
          linhas: c.linhas,
        ),
  ];
}

/// Onde o culto está: o momento (pela chave, que não muda quando o roteiro é remontado), o passo e a
/// ordem do momento no modelo (para seguir em frente se ele sair do roteiro).
class PosicaoRoteiro {
  const PosicaoRoteiro(this.chave, this.passo, [this.ordem = -1]);

  /// O primeiro (ou o [passo]) do momento [m].
  PosicaoRoteiro.de(Momento m, [int passo = 0]) : this(m.chave, passo, m.ordem);

  final String chave;
  final int passo;
  final int ordem;

  @override
  bool operator ==(Object other) => other is PosicaoRoteiro && other.chave == chave && other.passo == passo;

  @override
  int get hashCode => Object.hash(chave, passo);

  @override
  String toString() => '$chave/$passo';
}

/// Índice do momento da [posicao] no [roteiro]. Se o momento saiu do roteiro, o primeiro que vem
/// depois dele no modelo; -1 se não há nenhum.
int indiceDoMomento(List<Momento> roteiro, PosicaoRoteiro posicao) {
  final exato = roteiro.indexWhere((m) => m.chave == posicao.chave);
  if (exato >= 0) return exato;
  return roteiro.indexWhere((m) => m.ordem > posicao.ordem);
}

/// A posição válida mais próxima de [posicao] depois de remontar o roteiro.
PosicaoRoteiro? localizar(List<Momento> roteiro, PosicaoRoteiro posicao) {
  final i = indiceDoMomento(roteiro, posicao);
  if (i < 0) return null;
  final m = roteiro[i];
  if (m.chave != posicao.chave) return PosicaoRoteiro.de(m);
  return PosicaoRoteiro.de(m, posicao.passo.clamp(0, m.passos.length - 1));
}

/// O passo seguinte: o próximo do mesmo momento ou o primeiro do momento seguinte. Null no fim.
/// Se o momento atual saiu do roteiro, o seguinte é o primeiro passo do momento que veio no lugar.
PosicaoRoteiro? proximaPosicao(List<Momento> roteiro, PosicaoRoteiro atual) {
  final p = localizar(roteiro, atual);
  if (p == null) return null;
  if (p.chave != atual.chave) return p;
  final i = indiceDoMomento(roteiro, p);
  if (p.passo + 1 < roteiro[i].passos.length) return PosicaoRoteiro.de(roteiro[i], p.passo + 1);
  return i + 1 < roteiro.length ? PosicaoRoteiro.de(roteiro[i + 1]) : null;
}

/// O passo anterior, voltando para o último passo do momento anterior. Null no começo.
PosicaoRoteiro? posicaoAnterior(List<Momento> roteiro, PosicaoRoteiro atual) {
  final p = localizar(roteiro, atual);
  if (p == null) return null;
  final i = indiceDoMomento(roteiro, p);
  if (p.passo > 0) return PosicaoRoteiro.de(roteiro[i], p.passo - 1);
  if (i == 0) return null;
  final m = roteiro[i - 1];
  return PosicaoRoteiro.de(m, m.passos.length - 1);
}

/// Texto de um slide sem as marcações do Holyrics, para a prévia no tablet.
String textoSemMarcacao(String slide) => slide.replaceAll(RegExp(r'<[^>]+>'), '');

/// O culto está perto o bastante para sugerir o Modo Culto: de 1 h antes até 3 h depois do início.
bool cultoProximo(String data, String hora, DateTime agora) {
  final m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(hora);
  final d = DateTime.tryParse(data);
  if (m == null || d == null) return false;
  final inicio = DateTime(d.year, d.month, d.day, int.parse(m.group(1)!), int.parse(m.group(2)!));
  return !agora.isBefore(inicio.subtract(const Duration(hours: 1))) && agora.isBefore(inicio.add(const Duration(hours: 3)));
}
