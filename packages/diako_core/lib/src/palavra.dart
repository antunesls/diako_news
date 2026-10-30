import 'membro.dart' show semAcento;

/// Livro da Bíblia: número (1–66, ordem protestante), nome completo e abreviação.
class LivroBiblia {
  const LivroBiblia(this.numero, this.nome, this.abreviacao, [this.outrosNomes = const []]);

  final int numero;
  final String nome;
  final String abreviacao;

  /// Outras grafias aceitas no texto (ex: "Salmo", "Cantares").
  final List<String> outrosNomes;
}

const livrosBiblia = [
  LivroBiblia(1, 'Gênesis', 'Gn'),
  LivroBiblia(2, 'Êxodo', 'Êx', ['Ex']),
  LivroBiblia(3, 'Levítico', 'Lv'),
  LivroBiblia(4, 'Números', 'Nm'),
  LivroBiblia(5, 'Deuteronômio', 'Dt'),
  LivroBiblia(6, 'Josué', 'Js'),
  LivroBiblia(7, 'Juízes', 'Jz'),
  LivroBiblia(8, 'Rute', 'Rt'),
  LivroBiblia(9, '1 Samuel', '1Sm'),
  LivroBiblia(10, '2 Samuel', '2Sm'),
  LivroBiblia(11, '1 Reis', '1Rs'),
  LivroBiblia(12, '2 Reis', '2Rs'),
  LivroBiblia(13, '1 Crônicas', '1Cr'),
  LivroBiblia(14, '2 Crônicas', '2Cr'),
  LivroBiblia(15, 'Esdras', 'Ed'),
  LivroBiblia(16, 'Neemias', 'Ne'),
  LivroBiblia(17, 'Ester', 'Et'),
  LivroBiblia(18, 'Jó', 'Jó'),
  LivroBiblia(19, 'Salmos', 'Sl', ['Salmo']),
  LivroBiblia(20, 'Provérbios', 'Pv'),
  LivroBiblia(21, 'Eclesiastes', 'Ec'),
  LivroBiblia(22, 'Cânticos', 'Ct', ['Cantares']),
  LivroBiblia(23, 'Isaías', 'Is'),
  LivroBiblia(24, 'Jeremias', 'Jr'),
  LivroBiblia(25, 'Lamentações', 'Lm'),
  LivroBiblia(26, 'Ezequiel', 'Ez'),
  LivroBiblia(27, 'Daniel', 'Dn'),
  LivroBiblia(28, 'Oséias', 'Os', ['Oseias']),
  LivroBiblia(29, 'Joel', 'Jl'),
  LivroBiblia(30, 'Amós', 'Am'),
  LivroBiblia(31, 'Obadias', 'Ob'),
  LivroBiblia(32, 'Jonas', 'Jn'),
  LivroBiblia(33, 'Miquéias', 'Mq', ['Miqueias']),
  LivroBiblia(34, 'Naum', 'Na'),
  LivroBiblia(35, 'Habacuque', 'Hc'),
  LivroBiblia(36, 'Sofonias', 'Sf'),
  LivroBiblia(37, 'Ageu', 'Ag'),
  LivroBiblia(38, 'Zacarias', 'Zc'),
  LivroBiblia(39, 'Malaquias', 'Ml'),
  LivroBiblia(40, 'Mateus', 'Mt'),
  LivroBiblia(41, 'Marcos', 'Mc'),
  LivroBiblia(42, 'Lucas', 'Lc'),
  LivroBiblia(43, 'João', 'Jo'),
  LivroBiblia(44, 'Atos', 'At'),
  LivroBiblia(45, 'Romanos', 'Rm'),
  LivroBiblia(46, '1 Coríntios', '1Co'),
  LivroBiblia(47, '2 Coríntios', '2Co'),
  LivroBiblia(48, 'Gálatas', 'Gl'),
  LivroBiblia(49, 'Efésios', 'Ef'),
  LivroBiblia(50, 'Filipenses', 'Fp'),
  LivroBiblia(51, 'Colossenses', 'Cl'),
  LivroBiblia(52, '1 Tessalonicenses', '1Ts'),
  LivroBiblia(53, '2 Tessalonicenses', '2Ts'),
  LivroBiblia(54, '1 Timóteo', '1Tm'),
  LivroBiblia(55, '2 Timóteo', '2Tm'),
  LivroBiblia(56, 'Tito', 'Tt'),
  LivroBiblia(57, 'Filemom', 'Fm', ['Filemon']),
  LivroBiblia(58, 'Hebreus', 'Hb'),
  LivroBiblia(59, 'Tiago', 'Tg'),
  LivroBiblia(60, '1 Pedro', '1Pe'),
  LivroBiblia(61, '2 Pedro', '2Pe'),
  LivroBiblia(62, '1 João', '1Jo'),
  LivroBiblia(63, '2 João', '2Jo'),
  LivroBiblia(64, '3 João', '3Jo'),
  LivroBiblia(65, 'Judas', 'Jd'),
  LivroBiblia(66, 'Apocalipse', 'Ap'),
];

/// Um versículo ou trecho bíblico: livro, capítulo e faixas de versículos (vazio = só o capítulo).
class RefBiblica {
  const RefBiblica(this.livro, this.capitulo, [this.faixas = const []]);

  final LivroBiblia livro;
  final int capitulo;

  /// Faixas (início, fim) de versículos; "28,31-33" vira [(28, 28), (31, 33)].
  final List<(int, int)> faixas;

  /// Tem versículos: dá para projetar. Só o capítulo ("Salmo 23") precisa de ajuste.
  bool get completa => faixas.isNotEmpty;

  String get _versos => faixas.map((f) => f.$1 == f.$2 ? '${f.$1}' : '${f.$1}-${f.$2}').join(',');

  /// "Jo 3.16-18"
  String get abreviada => completa ? '${livro.abreviacao} $capitulo.$_versos' : '${livro.abreviacao} $capitulo';

  /// "João 3.16-18", para o pastor e o telão.
  String get nome => completa ? '${livro.nome} $capitulo.$_versos' : '${livro.nome} $capitulo';

  /// Ids do Holyrics (LLCCCVVV), um por versículo.
  List<String> get ids => [
        for (final f in faixas)
          for (var v = f.$1; v <= f.$2; v++)
            '${livro.numero.toString().padLeft(2, '0')}${capitulo.toString().padLeft(3, '0')}${v.toString().padLeft(3, '0')}',
      ];

  @override
  bool operator ==(Object other) => other is RefBiblica && other.abreviada == abreviada;

  @override
  int get hashCode => abreviada.hashCode;

  @override
  String toString() => abreviada;
}

/// Uma referência encontrada num texto, com a posição dela.
class ReferenciaAchada {
  const ReferenciaAchada(this.original, this.inicio, this.fim, this.ref);

  /// Como está escrita no texto ("Romanos 5.8").
  final String original;
  final int inicio;
  final int fim;
  final RefBiblica ref;
}

String _chave(String s) => semAcento(s.toLowerCase())!;

/// Nome (sem acento, minúsculo, com o número na frente: "1 corintios") → (livro, é abreviação).
final Map<String, (LivroBiblia, bool)> _indiceLivros = () {
  final m = <String, (LivroBiblia, bool)>{};
  for (final l in livrosBiblia) {
    // "Jó" sem acento seria "jo", que é João: fica só com o acento (tratado à parte).
    if (l.numero == 18) continue;
    for (final n in [l.nome, ...l.outrosNomes]) {
      m[_chave(n)] = (l, false);
    }
    final a = RegExp(r'^(\d)(.+)$').firstMatch(l.abreviacao);
    m[_chave(a == null ? l.abreviacao : '${a.group(1)} ${a.group(2)}')] = (l, true);
  }
  return m;
}();

const _letras = r'A-Za-zÀ-ÖØ-öø-ÿ';
final _padrao = RegExp(
  '(?<![$_letras\\d])'
  r'(?:([123]|I{1,3})\s*[ºª°]?\s*)?'
  '([$_letras]+)'
  r'\.?\s*(\d{1,3})'
  r'(?:\s*[:.]\s*(\d{1,3}(?:\s*[-–]\s*\d{1,3})?(?:\s*,\s*\d{1,3}(?:\s*[-–]\s*\d{1,3})?)*))?'
  '(?![$_letras\\d])',
);

(LivroBiblia, bool)? _livro(String? numero, String nome) {
  final n = switch (numero) { 'I' => '1', 'II' => '2', 'III' => '3', _ => numero };
  if (n == null && (nome == 'Jó' || nome == 'jó' || nome == 'JÓ')) return (livrosBiblia[17], false);
  return _indiceLivros[_chave(n == null ? nome : '$n $nome')];
}

List<(int, int)>? _faixas(String? texto) {
  if (texto == null) return const [];
  final faixas = <(int, int)>[];
  for (final parte in texto.split(',')) {
    final nums = parte.split(RegExp(r'[-–]')).map((s) => int.parse(s.trim())).toList();
    final ini = nums.first, fim = nums.length > 1 ? nums[1] : nums.first;
    if (ini < 1 || fim < ini || fim - ini > 200) return null;
    faixas.add((ini, fim));
  }
  return faixas;
}

/// Referências bíblicas num texto, na ordem em que aparecem.
///
/// Abreviações ("Jo", "Os", "At") só contam com inicial maiúscula e com versículo, para não
/// confundir com palavras comuns ("os 3 irmãos"). Nome completo sem versículo ("Salmo 23") entra
/// como referência incompleta, para o pastor ajustar.
List<ReferenciaAchada> acharReferencias(String texto) {
  final achadas = <ReferenciaAchada>[];
  var pos = 0;
  while (pos < texto.length) {
    final m = _padrao.allMatches(texto, pos).firstOrNull;
    if (m == null) break;
    // O que não é referência ("em 1" em "em 1 Coríntios") não pode engolir o número da seguinte:
    // a busca recomeça logo depois do início do que foi descartado.
    pos = m.start + 1;
    final numero = m.group(1), nome = m.group(2)!, versos = m.group(4);
    var achado = _livro(numero, nome);
    var inicio = m.start;
    // Número solto antes de um livro sem número ("3 Jo" existe; "2 Romanos" não): vale só o nome.
    if (achado == null && numero != null) {
      achado = _livro(null, nome);
      if (achado != null) inicio = m.start + m.group(0)!.indexOf(nome);
    }
    if (achado == null) continue;
    final (livro, abreviacao) = achado;
    if (abreviacao && (versos == null || nome[0] != nome[0].toUpperCase())) continue;
    final capitulo = int.parse(m.group(3)!);
    final faixas = _faixas(versos);
    if (capitulo < 1 || capitulo > 150 || faixas == null) continue;
    achadas.add(ReferenciaAchada(texto.substring(inicio, m.end), inicio, m.end, RefBiblica(livro, capitulo, faixas)));
    pos = m.end;
  }
  return achadas;
}

/// Lê uma referência digitada pelo pastor ("Jo 3.16", "1 Coríntios 13:4-7"). Null se não for uma.
RefBiblica? lerReferencia(String texto) {
  final t = texto.trim();
  final achada = acharReferencias(t).where((r) => r.inicio == 0 && r.fim == t.length).firstOrNull;
  return achada?.ref;
}

final _tempoDoTopico = RegExp(r'\s*[(\[]\s*(\d{1,3})\s*min(?:utos?)?\s*[)\]]\s*$', caseSensitive: false);

/// Linha de tópico ("# A mesa preparada (10 min)") lida como título e minutos previstos.
({String titulo, int? minutos}) lerTopico(String linha) {
  final semMarca = linha.trim().replaceFirst(RegExp(r'^#+\s*'), '');
  final m = _tempoDoTopico.firstMatch(semMarca);
  if (m == null) return (titulo: semMarca, minutos: null);
  final minutos = int.parse(m.group(1)!);
  return (titulo: semMarca.substring(0, m.start).trim(), minutos: minutos > 0 ? minutos : null);
}

/// Minutos previstos de cada tópico do texto, na ordem (só os tópicos com tempo).
Map<String, int> minutosDosTopicos(String texto) => {
      for (final linha in texto.split('\n'))
        if (linha.trim().startsWith('#'))
          if (lerTopico(linha) case (titulo: final titulo, minutos: final int minutos) when titulo.isNotEmpty) titulo: minutos,
    };

/// Desvio do tempo da pregação no tópico [atual], em minutos (positivo = atrasado, negativo =
/// adiantado): o atraso com que o tópico começou mais o que ele já passou do tempo dele. Null se o
/// tópico atual não tem tempo previsto.
int? desvioDaPregacao({
  required List<int?> minutosPorTopico,
  required int atual,
  required Duration desdeOInicio,
  required Duration noTopico,
}) {
  final previsto = minutosPorTopico[atual];
  if (previsto == null) return null;
  final inicioPrevisto = Duration(minutes: minutosPorTopico.take(atual).fold(0, (s, m) => s + (m ?? 0)));
  final inicioReal = desdeOInicio - noTopico;
  final estouro = noTopico - Duration(minutes: previsto);
  final desvio = (inicioReal - inicioPrevisto) + (estouro.isNegative ? Duration.zero : estouro);
  return (desvio.inSeconds / 60).round();
}

/// Um trecho do sermão: o que vai de uma vez para a TV do palco.
class TrechoPalavra {
  const TrechoPalavra(this.numero, this.topico, this.texto);

  /// 1, 2, 3…
  final int numero;

  /// Tópico em que o trecho está ("" antes do primeiro tópico).
  final String topico;
  final String texto;
}

/// Divide o texto do sermão em trechos: linha em branco separa; linha com "#" é tópico;
/// parágrafo maior que [maximo] caracteres é cortado nas frases.
List<TrechoPalavra> dividirEmTrechos(String texto, {int maximo = 500}) {
  final trechos = <TrechoPalavra>[];
  var topico = '';
  final paragrafo = <String>[];

  void fechar() {
    final p = paragrafo.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    paragrafo.clear();
    if (p.isEmpty) return;
    for (final parte in _cortar(p, maximo)) {
      trechos.add(TrechoPalavra(trechos.length + 1, topico, parte));
    }
  }

  for (final linha in texto.replaceAll('\r\n', '\n').split('\n')) {
    final l = linha.trim();
    if (l.startsWith('#')) {
      fechar();
      topico = lerTopico(l).titulo;
    } else if (l.isEmpty) {
      fechar();
    } else {
      paragrafo.add(l);
    }
  }
  fechar();
  return trechos;
}

/// Corta nas frases (". ", "? ", "! "), juntando frases até [maximo]. Frase maior que o máximo fica inteira.
List<String> _cortar(String p, int maximo) {
  if (p.length <= maximo) return [p];
  final frases = RegExp(r'[^.!?]+[.!?]+["”’)]*\s*|[^.!?]+$').allMatches(p).map((m) => m.group(0)!).toList();
  final partes = <String>[];
  var atual = '';
  for (final f in frases) {
    if (atual.isNotEmpty && (atual + f).trim().length > maximo) {
      partes.add(atual.trim());
      atual = '';
    }
    atual += f;
  }
  if (atual.trim().isNotEmpty) partes.add(atual.trim());
  return partes;
}

/// O que o pastor decidiu sobre uma referência achada no texto.
enum StatusReferencia {
  /// Achada e ainda não conferida (vai ao tablet, mas o painel avisa).
  pendente,
  confirmada,
  ignorada,

  /// Só o capítulo, sem decisão: precisa de ajuste para projetar.
  incompleta,
}

/// Uma referência num trecho já com a decisão do pastor aplicada.
class ReferenciaNoTrecho {
  const ReferenciaNoTrecho({required this.original, required this.inicio, required this.fim, required this.status, this.ref});

  final String original;
  final int inicio;
  final int fim;
  final StatusReferencia status;

  /// A referência que vale (a ajustada, se houver); null se incompleta sem ajuste.
  final RefBiblica? ref;

  bool get projetavel => ref != null && ref!.completa && status != StatusReferencia.ignorada;

  Map<String, dynamic> toJson() => {
        'original': original,
        'inicio': inicio,
        'fim': fim,
        'status': status.name,
        if (ref != null) ...{'ref': ref!.abreviada, 'nome': ref!.nome, 'ids': ref!.ids},
      };

  factory ReferenciaNoTrecho.fromJson(Map<String, dynamic> j) => ReferenciaNoTrecho(
        original: j['original'] as String? ?? '',
        inicio: (j['inicio'] as num?)?.toInt() ?? 0,
        fim: (j['fim'] as num?)?.toInt() ?? 0,
        status: StatusReferencia.values.where((s) => s.name == j['status']).firstOrNull ?? StatusReferencia.pendente,
        ref: j['ref'] is String ? lerReferencia(j['ref'] as String) : null,
      );
}

/// Trecho com as referências que o tablet mostra como botões.
class TrechoAnalisado {
  const TrechoAnalisado({required this.numero, required this.topico, required this.texto, required this.referencias});

  final int numero;
  final String topico;
  final String texto;
  final List<ReferenciaNoTrecho> referencias;

  Map<String, dynamic> toJson() => {
        'numero': numero,
        'topico': topico,
        'texto': texto,
        'referencias': [for (final r in referencias) r.toJson()],
      };

  factory TrechoAnalisado.fromJson(Map<String, dynamic> j) => TrechoAnalisado(
        numero: (j['numero'] as num?)?.toInt() ?? 0,
        topico: j['topico'] as String? ?? '',
        texto: j['texto'] as String? ?? '',
        referencias: [
          for (final r in j['referencias'] as List? ?? const []) ReferenciaNoTrecho.fromJson(Map<String, dynamic>.from(r as Map)),
        ],
      );
}

/// Decisão sobre uma referência, guardada pelo texto original (vale em qualquer trecho).
class DecisaoReferencia {
  const DecisaoReferencia(this.status, [this.ajuste = '']);

  /// confirmada ou ignorada.
  final StatusReferencia status;

  /// Referência digitada pelo pastor no lugar da achada ("Jo 5.24").
  final String ajuste;

  Map<String, dynamic> toJson() => {'status': status.name, if (ajuste.isNotEmpty) 'ajuste': ajuste};

  factory DecisaoReferencia.fromJson(Map<String, dynamic> j) => DecisaoReferencia(
        StatusReferencia.values.where((s) => s.name == j['status']).firstOrNull ?? StatusReferencia.confirmada,
        j['ajuste'] as String? ?? '',
      );
}

/// Chave da decisão: o texto original sem espaços sobrando.
String chaveReferencia(String original) => original.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Trechos do [texto] com as referências e as [decisoes] do pastor aplicadas.
List<TrechoAnalisado> analisarPalavra(String texto, Map<String, DecisaoReferencia> decisoes) => [
      for (final t in dividirEmTrechos(texto))
        TrechoAnalisado(
          numero: t.numero,
          topico: t.topico,
          texto: t.texto,
          referencias: [
            for (final a in acharReferencias(t.texto))
              () {
                final d = decisoes[chaveReferencia(a.original)];
                final ajustada = d == null || d.ajuste.isEmpty ? null : lerReferencia(d.ajuste);
                final ref = ajustada ?? a.ref;
                final status = d?.status ?? (ref.completa ? StatusReferencia.pendente : StatusReferencia.incompleta);
                return ReferenciaNoTrecho(
                  original: a.original,
                  inicio: a.inicio,
                  fim: a.fim,
                  status: status == StatusReferencia.confirmada && !ref.completa ? StatusReferencia.incompleta : status,
                  ref: ref.completa ? ref : null,
                );
              }(),
          ],
        ),
    ];

/// O sermão de um pregador, guardado no servidor.
class Palavra {
  Palavra({
    required this.id,
    required this.titulo,
    required this.autorId,
    this.autorNome = '',
    this.data = '',
    this.cultoId = '',
    this.serie = '',
    this.minutos = 40,
    this.pronta = false,
    this.texto = '',
    Map<String, DecisaoReferencia>? decisoes,
    this.criadoEm,
    this.atualizadoEm,
    List<VersaoPalavra>? versoes,
  })  : decisoes = decisoes ?? {},
        versoes = versoes ?? [];

  final String id;
  final String titulo;

  /// Conta que criou (cada pregador só vê as suas, salvo quem revisa todas).
  final String autorId;
  final String autorNome;

  /// Dia do culto (aaaa-mm-dd), vazio se ainda sem data.
  final String data;

  /// Culto da escala, quando há mais de um no dia.
  final String cultoId;
  final String serie;

  /// Tempo previsto da pregação.
  final int minutos;

  /// Pronta para o culto: só a pronta desce para o tablet.
  final bool pronta;
  final String texto;
  final Map<String, DecisaoReferencia> decisoes;
  final DateTime? criadoEm;
  final DateTime? atualizadoEm;

  /// Versões anteriores, a mais recente primeiro.
  final List<VersaoPalavra> versoes;

  static const maximoVersoes = 20;
  static const tamanhoMaximo = 200000;

  /// "rascunho", "pronta" ou "pregada" (pronta com a data já passada).
  String situacao(String hoje) => !pronta ? 'rascunho' : (data.isNotEmpty && data.compareTo(hoje) < 0 ? 'pregada' : 'pronta');

  List<TrechoAnalisado> get trechos => analisarPalavra(texto, decisoes);

  /// Problemas que impedem marcar como pronta (vazio = pode).
  List<String> pendencias() {
    final t = trechos;
    final refs = t.expand((x) => x.referencias);
    return [
      if (titulo.trim().isEmpty) 'Falta o título.',
      if (t.isEmpty) 'O texto está vazio.',
      if (data.isEmpty) 'Falta a data do culto.',
      if (refs.any((r) => r.status == StatusReferencia.pendente)) 'Há versículos para conferir.',
      if (refs.any((r) => r.status == StatusReferencia.incompleta)) 'Há referências incompletas para ajustar ou ignorar.',
    ];
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'titulo': titulo,
        'autorId': autorId,
        'autorNome': autorNome,
        'data': data,
        'cultoId': cultoId,
        'serie': serie,
        'minutos': minutos,
        'pronta': pronta,
        'texto': texto,
        'decisoes': {for (final e in decisoes.entries) e.key: e.value.toJson()},
        if (criadoEm != null) 'criadoEm': criadoEm!.toIso8601String(),
        if (atualizadoEm != null) 'atualizadoEm': atualizadoEm!.toIso8601String(),
        'versoes': [for (final v in versoes) v.toJson()],
      };

  factory Palavra.fromJson(Map<String, dynamic> j) {
    final minutos = (j['minutos'] as num?)?.toInt() ?? 40;
    final data = j['data'] as String? ?? '';
    if (data.isNotEmpty && !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(data)) throw const FormatException('Data inválida.');
    return Palavra(
      id: j['id'] as String,
      titulo: (j['titulo'] as String? ?? '').trim(),
      autorId: j['autorId'] as String? ?? '',
      autorNome: j['autorNome'] as String? ?? '',
      data: data,
      cultoId: j['cultoId'] as String? ?? '',
      serie: (j['serie'] as String? ?? '').trim(),
      minutos: minutos.clamp(5, 180),
      pronta: j['pronta'] == true,
      texto: j['texto'] as String? ?? '',
      decisoes: {
        for (final e in Map<String, dynamic>.from(j['decisoes'] as Map? ?? const {}).entries)
          e.key: DecisaoReferencia.fromJson(Map<String, dynamic>.from(e.value as Map)),
      },
      criadoEm: DateTime.tryParse(j['criadoEm'] as String? ?? ''),
      atualizadoEm: DateTime.tryParse(j['atualizadoEm'] as String? ?? ''),
      versoes: [for (final v in j['versoes'] as List? ?? const []) VersaoPalavra.fromJson(Map<String, dynamic>.from(v as Map))],
    );
  }
}

/// Uma versão anterior do texto (guardada a cada salvamento).
class VersaoPalavra {
  const VersaoPalavra({required this.em, required this.por, required this.titulo, required this.texto});

  final DateTime em;
  final String por;
  final String titulo;
  final String texto;

  Map<String, dynamic> toJson() => {'em': em.toIso8601String(), 'por': por, 'titulo': titulo, 'texto': texto};

  factory VersaoPalavra.fromJson(Map<String, dynamic> j) => VersaoPalavra(
        em: DateTime.tryParse(j['em'] as String? ?? '') ?? DateTime(2000),
        por: j['por'] as String? ?? '',
        titulo: j['titulo'] as String? ?? '',
        texto: j['texto'] as String? ?? '',
      );
}

/// A Palavra como o tablet usa no culto: só o necessário, com as referências que dá para projetar.
class PalavraDoCulto {
  const PalavraDoCulto({
    required this.id,
    required this.titulo,
    required this.autorNome,
    required this.minutos,
    required this.trechos,
    this.minutosTopicos = const {},
  });

  final String id;
  final String titulo;
  final String autorNome;
  final int minutos;
  final List<TrechoAnalisado> trechos;

  /// Minutos previstos por tópico (os escritos no tópico, como "(10 min)").
  final Map<String, int> minutosTopicos;

  /// Tópicos na ordem, com o índice do primeiro trecho de cada um.
  List<(String, int)> get topicos {
    final r = <(String, int)>[];
    for (var i = 0; i < trechos.length; i++) {
      final t = trechos[i].topico;
      if (t.isNotEmpty && (r.isEmpty || r.last.$1 != t)) r.add((t, i));
    }
    return r;
  }

  factory PalavraDoCulto.de(Palavra p) => PalavraDoCulto(
        id: p.id,
        titulo: p.titulo,
        autorNome: p.autorNome,
        minutos: p.minutos,
        minutosTopicos: minutosDosTopicos(p.texto),
        trechos: [
          for (final t in p.trechos)
            TrechoAnalisado(
              numero: t.numero,
              topico: t.topico,
              texto: t.texto,
              referencias: [for (final r in t.referencias) if (r.projetavel) r],
            ),
        ],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'titulo': titulo,
        'autorNome': autorNome,
        'minutos': minutos,
        if (minutosTopicos.isNotEmpty) 'minutosTopicos': minutosTopicos,
        'trechos': [for (final t in trechos) t.toJson()],
      };

  factory PalavraDoCulto.fromJson(Map<String, dynamic> j) => PalavraDoCulto(
        id: j['id'] as String? ?? '',
        titulo: j['titulo'] as String? ?? '',
        autorNome: j['autorNome'] as String? ?? '',
        minutos: (j['minutos'] as num?)?.toInt() ?? 40,
        minutosTopicos: {
          for (final e in Map<String, dynamic>.from(j['minutosTopicos'] as Map? ?? const {}).entries)
            if (e.value is num) e.key: (e.value as num).toInt(),
        },
        trechos: [for (final t in j['trechos'] as List? ?? const []) TrechoAnalisado.fromJson(Map<String, dynamic>.from(t as Map))],
      );
}
