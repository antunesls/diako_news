/// De onde veio o cadastro da visita.
abstract final class OrigemVisita {
  /// A própria pessoa, pelo QR code da recepção (/visitante).
  static const qr = 'qr';

  /// O obreiro da recepção, pelo celular (/recepcao).
  static const recepcao = 'recepcao';

  /// A secretaria, pelo painel.
  static const painel = 'painel';

  static const todas = [qr, recepcao, painel];
}

/// O que o visitante pediu para a igreja (vira pendência no acompanhamento).
enum InteresseVisita {
  visitaPastoral('Quer receber uma visita'),
  oracao('Quer oração'),
  batismo('Quer saber sobre o batismo'),
  celula('Quer participar de um grupo/célula');

  const InteresseVisita(this.descricao);
  final String descricao;

  static InteresseVisita? porNome(Object? nome) => values.where((i) => i.name == nome).firstOrNull;
}

/// Situação do contato pós-visita (acompanhamento da secretaria/pastoral).
enum StatusContato {
  aContatar('A contatar'),
  contatado('Contatado'),
  semResposta('Sem resposta');

  const StatusContato(this.nome);
  final String nome;

  static StatusContato porNome(Object? nome) =>
      values.where((s) => s.name == nome).firstOrNull ?? StatusContato.aContatar;
}

/// Uma ida de um visitante à igreja. A pessoa fica no cadastro de membros
/// ([membroId]); a visita guarda o que é daquele dia: se pode ser citada no culto,
/// se já foi, o que a pessoa pediu e o contato depois.
class Visita {
  Visita({
    required this.id,
    required this.membroId,
    required this.nome,
    required this.data,
    required this.criadoEm,
    required this.origem,
    required this.mencionar,
    this.registradoPor,
    this.primeiraVez = true,
    this.mencionadaEm,
    this.mencionadaPor,
    this.grupoId,
    Set<InteresseVisita>? interesses,
    this.contato = StatusContato.aContatar,
    this.contatoEm,
    this.contatoPor,
    this.contatoNota,
  }) : interesses = interesses ?? {};

  final String id;
  final String membroId;

  /// Cópia do nome: telão, mural e listas não precisam abrir o cadastro.
  String nome;

  /// Dia da visita (aaaa-mm-dd, no fuso da igreja).
  final String data;
  final DateTime criadoEm;

  /// [OrigemVisita].
  final String origem;

  /// Quem cadastrou (obreiro ou secretaria); null quando foi a própria pessoa pelo QR.
  final String? registradoPor;

  /// false quando a pessoa já tinha visitado antes ("voltou").
  final bool primeiraVez;

  /// A pessoa autorizou o pastor a citar a visita do púlpito (e o nome no telão e na TV).
  final bool mencionar;
  DateTime? mencionadaEm;
  String? mencionadaPor;

  /// Visitas de quem chegou junto (família, amigos) têm o mesmo grupo.
  final String? grupoId;
  final Set<InteresseVisita> interesses;

  StatusContato contato;
  DateTime? contatoEm;
  String? contatoPor;
  String? contatoNota;

  /// Pode citar e ainda não foi citada: é a pendência do pastor.
  bool get pendente => mencionar && mencionadaEm == null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'membroId': membroId,
        'nome': nome,
        'data': data,
        'criadoEm': criadoEm.toIso8601String(),
        'origem': origem,
        if (registradoPor != null) 'registradoPor': registradoPor,
        'primeiraVez': primeiraVez,
        'mencionar': mencionar,
        if (mencionadaEm != null) 'mencionadaEm': mencionadaEm!.toIso8601String(),
        if (mencionadaPor != null) 'mencionadaPor': mencionadaPor,
        if (grupoId != null) 'grupoId': grupoId,
        if (interesses.isNotEmpty) 'interesses': [for (final i in interesses) i.name],
        'contato': contato.name,
        if (contatoEm != null) 'contatoEm': contatoEm!.toIso8601String(),
        if (contatoPor != null) 'contatoPor': contatoPor,
        if (contatoNota != null && contatoNota!.isNotEmpty) 'contatoNota': contatoNota,
      };

  /// Lança [FormatException] em documento sem os campos essenciais (validação do backup).
  factory Visita.fromJson(Map<String, dynamic> j) {
    final id = j['id'], membroId = j['membroId'], nome = j['nome'], data = j['data'];
    if (id is! String || membroId is! String || nome is! String || data is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(data)) {
      throw const FormatException('Visita inválida.');
    }
    final origem = j['origem'];
    return Visita(
      id: id,
      membroId: membroId,
      nome: nome,
      data: data,
      criadoEm: DateTime.tryParse(j['criadoEm'] as String? ?? '') ?? DateTime.parse(data),
      origem: OrigemVisita.todas.contains(origem) ? origem as String : OrigemVisita.painel,
      registradoPor: j['registradoPor'] as String?,
      primeiraVez: j['primeiraVez'] as bool? ?? true,
      mencionar: j['mencionar'] as bool? ?? false,
      mencionadaEm: DateTime.tryParse(j['mencionadaEm'] as String? ?? ''),
      mencionadaPor: j['mencionadaPor'] as String?,
      grupoId: j['grupoId'] as String?,
      interesses: {
        if (j['interesses'] is List)
          for (final i in j['interesses'] as List)
            if (InteresseVisita.porNome(i) case final interesse?) interesse,
      },
      contato: StatusContato.porNome(j['contato']),
      contatoEm: DateTime.tryParse(j['contatoEm'] as String? ?? ''),
      contatoPor: j['contatoPor'] as String?,
      contatoNota: j['contatoNota'] as String?,
    );
  }
}

/// "aaaa-mm-dd" de [d] (no fuso em que [d] está).
String diaIso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Visitas de hoje que podem ser citadas e ainda não foram: a lista do pastor.
List<Visita> pendenciasDoPastor(Iterable<Visita> visitas, DateTime hoje) {
  final dia = diaIso(hoje);
  return visitas.where((v) => v.data == dia && v.pendente).toList()..sort((a, b) => a.criadoEm.compareTo(b.criadoEm));
}

/// Nomes de hoje que podem aparecer em público (telão, TV de boas-vindas), na ordem de chegada,
/// sem repetir quem foi cadastrado duas vezes no mesmo dia.
List<String> nomesParaBoasVindas(Iterable<Visita> visitas, DateTime hoje) {
  final dia = diaIso(hoje);
  final doDia = visitas.where((v) => v.data == dia && v.mencionar).toList()
    ..sort((a, b) => a.criadoEm.compareTo(b.criadoEm));
  final vistos = <String>{};
  return [for (final v in doDia) if (vistos.add(v.membroId)) v.nome];
}

/// Slides "Sejam bem-vindos" para o telão: [porSlide] nomes em cada um.
List<String> montarSlidesBoasVindas(List<String> nomes, {int porSlide = 6, bool negritoTitulo = true}) {
  if (nomes.isEmpty) return [];
  final n = porSlide < 1 ? 1 : porSlide;
  final total = (nomes.length / n).ceil();
  final titulo = 'Sejam bem-vindos!';
  return [
    for (var i = 0; i < total; i++)
      [
        negritoTitulo ? '<b>$titulo</b>' : titulo,
        ...nomes.skip(i * n).take(n),
      ].join('\n'),
  ];
}

/// Páginas da TV de boas-vindas: os nomes em blocos de [porPagina] (vazia: nenhuma página).
List<List<String>> montarTelaBoasVindas(List<String> nomes, {int porPagina = 8}) {
  final n = porPagina < 1 ? 1 : porPagina;
  return [for (var i = 0; i < nomes.length; i += n) nomes.sublist(i, (i + n).clamp(0, nomes.length))];
}
