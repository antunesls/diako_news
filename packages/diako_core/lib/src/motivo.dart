enum TipoMotivo {
  saude('Saúde'),
  familia('Família'),
  trabalho('Trabalho'),
  gratidao('Gratidão'),
  outro('Outro');

  const TipoMotivo(this.label);
  final String label;

  static TipoMotivo fromName(String? name) =>
      TipoMotivo.values.firstWhere((t) => t.name == name, orElse: () => TipoMotivo.outro);
}

enum StatusMotivo {
  /// Enviado pelo site; espera o pastor aprovar.
  aguardando,

  /// Aprovado: entra na lista de oração.
  pendente,

  /// Oração respondida.
  atendido;

  static StatusMotivo fromName(String? name) =>
      StatusMotivo.values.firstWhere((s) => s.name == name, orElse: () => StatusMotivo.pendente);
}

enum OrigemMotivo {
  app,
  site,
  painel;

  static OrigemMotivo fromName(String? name) =>
      OrigemMotivo.values.firstWhere((o) => o.name == name, orElse: () => OrigemMotivo.app);
}

class Motivo {
  Motivo({
    required this.id,
    this.para = '',
    required this.motivo,
    this.tipo = TipoMotivo.outro,
    DateTime? criadoEm,
    this.status = StatusMotivo.pendente,
    this.origem = OrigemMotivo.app,
    this.publico = true,
    this.enviadoPor = '',
    this.atendidoEm,
    this.testemunho = '',
    this.observacao = '',
    this.aprovadoPor = '',
  }) : criadoEm = criadoEm ?? DateTime.now();

  final String id;

  /// Por quem orar (pessoa ou família); pode ficar vazio.
  String para;
  String motivo;
  TipoMotivo tipo;
  final DateTime criadoEm;
  StatusMotivo status;
  final OrigemMotivo origem;

  /// Se pode ser lido no telão. Pedidos privados ficam só para o pastor.
  bool publico;

  /// Quem enviou pelo site (opcional).
  String enviadoPor;

  /// Quando foi marcado como atendido (o servidor preenche).
  DateTime? atendidoEm;

  /// Como a oração foi respondida (opcional), para os testemunhos.
  String testemunho;

  /// Nota interna do painel. Não compõe texto público nem slides.
  String observacao;

  /// Nome de quem aprovou o pedido vindo do site (vazio em pedidos antigos ou criados já aprovados).
  String aprovadoPor;

  bool get atendido => status == StatusMotivo.atendido;

  /// Pode aparecer nas "orações respondidas": atendido e público.
  bool get testemunhoPublico => atendido && publico;
  bool get aguardando => status == StatusMotivo.aguardando;

  /// Pode ir para o telão: aprovado, ainda não atendido e autorizado como público.
  bool get projetavel => status == StatusMotivo.pendente && publico;

  String get linha {
    final p = para.trim(), m = motivo.trim();
    if (p.isEmpty) return m;
    if (m.isEmpty) return p;
    return '$p — $m';
  }

  /// Versão discreta para o telão: por quem orar e a categoria, sem o texto do pedido.
  /// "Outro" não diz nada, então fica de fora.
  String get linhaResumida {
    final p = para.trim(), cat = tipo == TipoMotivo.outro ? '' : tipo.label;
    if (p.isEmpty) return cat.isEmpty ? 'Pedido de oração' : cat;
    if (cat.isEmpty) return p;
    return '$p · $cat';
  }

  /// Linha para lugares públicos, conforme a regra da igreja (texto do pedido ou só o resumo).
  String linhaPublica(bool comTexto) => comTexto ? linha : linhaResumida;

  /// Testemunho para lugares públicos: sem o texto do pedido, ele também fica de fora.
  String testemunhoPublicoTexto(bool comTexto) => comTexto ? testemunho.trim() : '';

  Map<String, dynamic> toJson() => {
        'id': id,
        'para': para,
        'motivo': motivo,
        'tipo': tipo.name,
        'criadoEm': criadoEm.toIso8601String(),
        'status': status.name,
        'origem': origem.name,
        'publico': publico,
        'enviadoPor': enviadoPor,
        'atendidoEm': atendidoEm?.toIso8601String(),
        'testemunho': testemunho,
        'observacao': observacao,
        if (aprovadoPor.isNotEmpty) 'aprovadoPor': aprovadoPor,
      };

  factory Motivo.fromJson(Map<String, dynamic> j) => Motivo(
        id: j['id'] as String,
        para: j['para'] as String? ?? '',
        motivo: j['motivo'] as String? ?? '',
        tipo: TipoMotivo.fromName(j['tipo'] as String?),
        criadoEm: DateTime.tryParse(j['criadoEm'] as String? ?? ''),
        // Arquivos antigos guardavam só "atendido".
        status: j['status'] != null
            ? StatusMotivo.fromName(j['status'] as String?)
            : (j['atendido'] == true ? StatusMotivo.atendido : StatusMotivo.pendente),
        origem: OrigemMotivo.fromName(j['origem'] as String?),
        publico: j['publico'] as bool? ?? true,
        enviadoPor: j['enviadoPor'] as String? ?? '',
        atendidoEm: DateTime.tryParse(j['atendidoEm'] as String? ?? ''),
        testemunho: j['testemunho'] as String? ?? '',
        observacao: j['observacao'] as String? ?? '',
        aprovadoPor: j['aprovadoPor'] as String? ?? '',
      );
}

/// Atendidos e públicos nos últimos [dias], do mais recente para o mais antigo.
List<Motivo> oracoesRespondidas(Iterable<Motivo> motivos, DateTime agora, {int dias = 30}) {
  final limite = agora.subtract(Duration(days: dias));
  final lista = motivos.where((m) => m.testemunhoPublico && (m.atendidoEm ?? m.criadoEm).isAfter(limite)).toList();
  lista.sort((a, b) => (b.atendidoEm ?? b.criadoEm).compareTo(a.atendidoEm ?? a.criadoEm));
  return lista;
}

/// Slides "Orações respondidas": cada linha é a pessoa/motivo e, se houver, o testemunho.
/// Sem [comTexto], só por quem orar e a categoria, sem o testemunho.
List<String> montarSlidesGratidao(List<Motivo> motivos,
    {int porSlide = 3, bool negritoTitulo = true, bool comTexto = true}) {
  if (motivos.isEmpty) return [];
  final n = porSlide < 1 ? 1 : porSlide;
  final total = (motivos.length / n).ceil();
  return [
    for (var i = 0; i < total; i++)
      [
        _titulo('Orações respondidas${total > 1 ? ' (${i + 1}/$total)' : ''}', negritoTitulo),
        for (final m in motivos.skip(i * n).take(n))
          if (m.testemunhoPublicoTexto(comTexto) case final t when t.isNotEmpty)
            '✓ ${m.linhaPublica(comTexto)}\n   $t'
          else
            '✓ ${m.linhaPublica(comTexto)}',
      ].join('\n'),
  ];
}

/// Divide os motivos em slides com [porSlide] linhas cada, todos com o título
/// "Motivos de oração" (e "1/3" quando houver mais de um slide).
/// Sem [comTexto], cada linha mostra só por quem orar e a categoria ([Motivo.linhaResumida]).
List<String> montarSlidesOracao(List<Motivo> motivos,
    {int porSlide = 4, bool negritoTitulo = true, bool comTexto = true}) {
  if (motivos.isEmpty) return [];
  final n = porSlide < 1 ? 1 : porSlide;
  final total = (motivos.length / n).ceil();
  return [
    for (var i = 0; i < total; i++)
      [
        _titulo('Motivos de oração${total > 1 ? ' (${i + 1}/$total)' : ''}', negritoTitulo),
        for (final m in motivos.skip(i * n).take(n)) '• ${m.linhaPublica(comTexto)}',
      ].join('\n'),
  ];
}

String _titulo(String t, bool negrito) => negrito ? '<b>$t</b>' : t;
