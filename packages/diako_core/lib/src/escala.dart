import 'membro.dart';

/// As duas escalas do culto.
enum TipoEscala {
  pastoral('Pastoral', ['Direção', 'Pregação', 'Oração e ofertas', funcaoCeia]),
  louvor('Louvor', ['Ministro', 'Vocal', 'Teclado', 'Violão', 'Baixo', 'Bateria']);

  const TipoEscala(this.nome, this.funcoes);
  final String nome;

  /// Todas as funções desta escala, na ordem das colunas.
  final List<String> funcoes;

  static TipoEscala? porNome(Object? nome) => values.where((t) => t.name == nome).firstOrNull;
}

/// Função da escala pastoral que só existe no culto de Santa Ceia.
const funcaoCeia = 'Santa Ceia';

/// Uma música do culto, na ordem do ministro.
class Musica {
  Musica(this.titulo, {this.tom = ''});

  final String titulo;
  final String tom;

  Map<String, dynamic> toJson() => {'titulo': titulo, if (tom.isNotEmpty) 'tom': tom};

  factory Musica.fromJson(Map<String, dynamic> j) {
    final titulo = (j['titulo'] as String? ?? '').trim();
    if (titulo.isEmpty || titulo.length > 120) throw const FormatException('Música sem título (ou longo demais).');
    final tom = (j['tom'] as String? ?? '').trim();
    if (tom.length > 12) throw const FormatException('Tom da música longo demais.');
    return Musica(titulo, tom: tom);
  }
}

/// Um culto do mês com quem serve em cada função. [pastoral] e [louvor]: função → ids de membros.
class CultoEscala {
  CultoEscala({
    required this.id,
    required this.data,
    required this.hora,
    this.nome = 'Culto',
    this.ceia = false,
    this.tema = '',
    Map<String, List<String>>? pastoral,
    Map<String, List<String>>? louvor,
    List<Musica>? musicas,
  })  : pastoral = pastoral ?? {},
        louvor = louvor ?? {},
        musicas = musicas ?? [];

  final String id;

  /// aaaa-mm-dd
  final String data;

  /// hh:mm
  final String hora;
  final String nome;
  final bool ceia;

  /// Tema da pregação (opcional).
  final String tema;
  final Map<String, List<String>> pastoral;
  final Map<String, List<String>> louvor;
  final List<Musica> musicas;

  Map<String, List<String>> da(TipoEscala tipo) => tipo == TipoEscala.pastoral ? pastoral : louvor;

  /// Funções deste culto: a Santa Ceia só aparece no culto de ceia.
  List<String> funcoes(TipoEscala tipo) => [
        for (final f in tipo.funcoes)
          if (f != funcaoCeia || ceia) f,
      ];

  /// Quem serve neste culto, em qualquer função das duas escalas.
  Iterable<({TipoEscala tipo, String funcao, String membroId})> get servindo sync* {
    for (final tipo in TipoEscala.values) {
      for (final f in funcoes(tipo)) {
        for (final id in da(tipo)[f] ?? const <String>[]) {
          yield (tipo: tipo, funcao: f, membroId: id);
        }
      }
    }
  }

  DateTime get dia => DateTime.parse(data);

  CultoEscala copiar({
    String? nome,
    String? hora,
    bool? ceia,
    String? tema,
    Map<String, List<String>>? pastoral,
    Map<String, List<String>>? louvor,
    List<Musica>? musicas,
  }) =>
      CultoEscala(
        id: id,
        data: data,
        hora: hora ?? this.hora,
        nome: nome ?? this.nome,
        ceia: ceia ?? this.ceia,
        tema: tema ?? this.tema,
        pastoral: pastoral ?? this.pastoral,
        louvor: louvor ?? this.louvor,
        musicas: musicas ?? this.musicas,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'data': data,
        'hora': hora,
        'nome': nome,
        if (ceia) 'ceia': true,
        if (tema.isNotEmpty) 'tema': tema,
        'pastoral': {for (final e in pastoral.entries) if (e.value.isNotEmpty) e.key: e.value},
        'louvor': {for (final e in louvor.entries) if (e.value.isNotEmpty) e.key: e.value},
        if (musicas.isNotEmpty) 'musicas': [for (final m in musicas) m.toJson()],
      };

  /// Valida tudo: data, hora, funções conhecidas, ids e músicas.
  factory CultoEscala.fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    if (id is! String || id.isEmpty) throw const FormatException('Culto sem id.');
    final data = dataEscala(j['data']);
    final hora = horaEscala(j['hora']);
    if (data == null) throw const FormatException('Data do culto inválida.');
    if (hora == null) throw const FormatException('Horário do culto inválido.');
    final nome = (j['nome'] as String? ?? '').trim();
    if (nome.length > 80) throw const FormatException('Nome do culto longo demais.');
    final tema = (j['tema'] as String? ?? '').trim();
    if (tema.length > 120) throw const FormatException('Tema longo demais.');
    return CultoEscala(
      id: id,
      data: data,
      hora: hora,
      nome: nome.isEmpty ? 'Culto' : nome,
      ceia: j['ceia'] == true,
      tema: tema,
      pastoral: lerFuncoes(TipoEscala.pastoral, j['pastoral']),
      louvor: lerFuncoes(TipoEscala.louvor, j['louvor']),
      musicas: [for (final m in (j['musicas'] as List? ?? const [])) Musica.fromJson(Map<String, dynamic>.from(m as Map))],
    );
  }

  /// {função: [ids]} só com funções conhecidas da escala, sem ids repetidos.
  static Map<String, List<String>> lerFuncoes(TipoEscala tipo, Object? valor) {
    if (valor == null) return {};
    if (valor is! Map) throw const FormatException('Escala inválida.');
    final r = <String, List<String>>{};
    for (final e in valor.entries) {
      if (!tipo.funcoes.contains(e.key)) throw FormatException('Função desconhecida: ${e.key}.');
      final ids = e.value;
      if (ids is! List || ids.any((i) => i is! String || i.isEmpty)) throw const FormatException('Pessoas da escala inválidas.');
      final unicos = <String>[for (final i in ids.cast<String>()) i].toSet().toList();
      if (unicos.length > 8) throw const FormatException('Pessoas demais numa função.');
      if (unicos.isNotEmpty) r[e.key as String] = unicos;
    }
    return r;
  }
}

/// Período em que a pessoa avisou que não pode servir (datas aaaa-mm-dd, inclusive).
class Indisponibilidade {
  Indisponibilidade({required this.id, required this.membroId, required this.de, required this.ate, this.motivo = ''});

  final String id;
  final String membroId;
  final String de;
  final String ate;
  final String motivo;

  bool cobre(String data) => de.compareTo(data) <= 0 && ate.compareTo(data) >= 0;

  Map<String, dynamic> toJson() =>
      {'id': id, 'membroId': membroId, 'de': de, 'ate': ate, if (motivo.isNotEmpty) 'motivo': motivo};

  factory Indisponibilidade.fromJson(Map<String, dynamic> j) {
    final id = j['id'], membroId = j['membroId'];
    final de = dataEscala(j['de']), ate = dataEscala(j['ate']);
    if (id is! String || membroId is! String || membroId.isEmpty) throw const FormatException('Indisponibilidade inválida.');
    if (de == null || ate == null || ate.compareTo(de) < 0) throw const FormatException('Período inválido.');
    final motivo = (j['motivo'] as String? ?? '').trim();
    if (motivo.length > 80) throw const FormatException('Motivo longo demais.');
    return Indisponibilidade(id: id, membroId: membroId, de: de, ate: ate, motivo: motivo);
  }
}

/// Aceita aaaa-mm-dd ou dd/mm/aaaa (data real); devolve aaaa-mm-dd.
String? dataEscala(Object? v) => Membro.dataDe(v);

/// "19h", "19h30", "19:30" ou "9:00" → "19:00", "19:30", "09:00".
String? horaEscala(Object? v) {
  if (v is! String) return null;
  final m = RegExp(r'^\s*(\d{1,2})\s*(?:h|:)\s*(\d{2})?\s*(?:h|min)?\s*$', caseSensitive: false).firstMatch(v);
  if (m == null) return null;
  final h = int.parse(m.group(1)!), min = int.parse(m.group(2) ?? '0');
  if (h > 23 || min > 59) return null;
  return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
}

/// "19:00" → "19h", "19:30" → "19h30".
String horaCurtaEscala(String hora) {
  final p = hora.split(':');
  return p.length == 2 && p[1] != '00' ? '${int.parse(p[0])}h${p[1]}' : '${int.parse(p[0])}h';
}

const _diasSemana = ['segunda', 'terca', 'quarta', 'quinta', 'sexta', 'sabado', 'domingo'];
const _diasCurtos = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
const nomesMeses = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro',
  'outubro', 'novembro', 'dezembro'];

/// "Dom 01/11".
String rotuloDia(String data) {
  final d = DateTime.parse(data);
  return '${_diasCurtos[d.weekday - 1]} ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

/// Um culto que se repete toda semana.
typedef HorarioCulto = ({int diaSemana, String hora, String nome});

/// Horários da página inicial ("Domingo — 19h", "Quarta-feira | 20h — Culto de oração", um por linha)
/// em cultos semanais. Linhas sem dia da semana ou sem hora reconhecível são ignoradas.
List<HorarioCulto> horariosDosCultos(String texto) {
  final r = <HorarioCulto>[];
  for (final linha in texto.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty)) {
    final partes = linha.split(RegExp(r'\s*(?:—|–|\||\s-\s)\s*'));
    final dia = semAcento(partes.first.toLowerCase()) ?? '';
    final i = _diasSemana.indexWhere((d) => dia.startsWith(d));
    if (i < 0) continue;
    String? hora;
    final nome = <String>[];
    for (final p in partes.skip(1)) {
      hora ??= horaEscala(p);
      if (horaEscala(p) == null && p.isNotEmpty) nome.add(p);
    }
    if (hora == null) continue;
    r.add((diaSemana: i + 1, hora: hora, nome: nome.isEmpty ? 'Culto' : nome.join(' · ')));
  }
  return r;
}

/// Os cultos do mês ([mes] 1–12) a partir dos horários semanais, em ordem.
/// O primeiro domingo do mês vem marcado como Santa Ceia.
List<({String data, String hora, String nome, bool ceia})> cultosDoMes(int ano, int mes, List<HorarioCulto> horarios) {
  final r = <({String data, String hora, String nome, bool ceia})>[];
  for (var d = DateTime(ano, mes, 1); d.month == mes; d = DateTime(d.year, d.month, d.day + 1)) {
    for (final h in horarios) {
      if (h.diaSemana != d.weekday) continue;
      r.add((data: diaEscala(d), hora: h.hora, nome: h.nome, ceia: d.weekday == DateTime.sunday && d.day <= 7));
    }
  }
  r.sort((a, b) => '${a.data} ${a.hora}'.compareTo('${b.data} ${b.hora}'));
  return r;
}

String diaEscala(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Qual ocorrência do dia da semana no mês (1ª quarta = 1): para repetir o mês anterior.
int ocorrenciaNoMes(String data) => (DateTime.parse(data).day - 1) ~/ 7 + 1;

const _funcoesPastorais = ['pastor', 'pastora', 'presbitero', 'presbitera', 'diacono', 'diaconisa', 'evangelista',
  'missionario', 'missionaria', 'bispo', 'apostolo'];

/// A pessoa aparece na lista para escalar: ativa e com o ministério (ou função) da escala na ficha.
bool podeServir(Membro m, TipoEscala tipo) {
  if (!m.ativo) return false;
  final ministerios = [for (final x in m.ministerios) semAcento(x.toLowerCase()) ?? ''];
  if (tipo == TipoEscala.louvor) return ministerios.any((x) => x.contains('louvor') || x.contains('musica'));
  final funcao = semAcento((m.funcao ?? '').toLowerCase()) ?? '';
  return ministerios.any((x) => x.contains('pastoral') || x.contains('lideranca')) ||
      _funcoesPastorais.any((f) => RegExp('\\b$f\\b').hasMatch(funcao));
}

/// "na pregação", "no violão": a função numa frase.
String naFuncao(String funcao) => switch (funcao) {
      'Direção' => 'na direção',
      'Pregação' => 'na pregação',
      'Oração e ofertas' => 'na oração e ofertas',
      funcaoCeia => 'na Santa Ceia',
      'Ministro' => 'como ministro',
      'Bateria' => 'na bateria',
      _ => 'no ${funcao.toLowerCase()}',
    };

/// Aviso sobre uma pessoa escalada num culto ("Indisponível", "Também no violão"), ou null.
String? avisoDaPessoa(CultoEscala c, TipoEscala tipo, String funcao, String membroId, List<Indisponibilidade> indisponiveis) {
  if (indisponiveis.any((i) => i.membroId == membroId && i.cobre(c.data))) return 'Indisponível';
  final outra = c.servindo.where((s) => s.membroId == membroId && !(s.tipo == tipo && s.funcao == funcao)).firstOrNull;
  return outra == null ? null : 'Também ${naFuncao(outra.funcao)}';
}

/// Um aviso do mês para o quadro "Avisos do mês".
typedef AvisoEscala = ({String tipo, String titulo, String texto});

/// Conflitos, indisponibilidades e funções vazias de uma escala no mês.
List<AvisoEscala> avisosDoMes(
  List<CultoEscala> cultos,
  TipoEscala tipo,
  String Function(String membroId) nomeDe,
  List<Indisponibilidade> indisponiveis,
) {
  final avisos = <AvisoEscala>[];
  final vazias = <String, List<String>>{};
  for (final c in cultos) {
    final dia = rotuloDia(c.data).substring(4);
    for (final f in c.funcoes(tipo)) {
      final ids = c.da(tipo)[f] ?? const [];
      if (ids.isEmpty) (vazias[f] ??= []).add(dia);
      for (final id in ids) {
        final ind = indisponiveis.where((i) => i.membroId == id && i.cobre(c.data)).firstOrNull;
        if (ind != null) {
          avisos.add((
            tipo: 'indisponivel',
            titulo: '${nomeDe(id)} marcou indisponível em $dia',
            texto: '${ind.motivo.isEmpty ? '' : 'Motivo: ${ind.motivo}. '}Está escalado(a) ${naFuncao(f)}.',
          ));
          continue;
        }
        final outras = c.servindo.where((s) => s.membroId == id && !(s.tipo == tipo && s.funcao == f)).toList();
        // Conflito dentro da mesma escala aparece uma vez só (na primeira função).
        final jaContado = outras.any((s) => s.tipo == tipo && tipo.funcoes.indexOf(s.funcao) < tipo.funcoes.indexOf(f));
        if (outras.isEmpty || jaContado) continue;
        avisos.add((
          tipo: 'conflito',
          titulo: '${nomeDe(id)} em duas funções no dia $dia',
          texto: 'Escalado(a) ${[naFuncao(f), for (final s in outras) naFuncao(s.funcao)].join(' e ')} do mesmo culto.',
        ));
      }
    }
  }
  if (vazias.isNotEmpty) {
    avisos.add((
      tipo: 'vazias',
      titulo: 'Funções vazias',
      texto: [for (final f in tipo.funcoes) if (vazias[f] != null) '$f em ${vazias[f]!.join(', ')}'].join(' · '),
    ));
  }
  return avisos;
}

/// Nome curto para o WhatsApp: primeiro e último nome ("Ana Maria Souza" → "Ana Souza").
String nomeCurto(String nome) {
  final p = nome.trim().split(RegExp(r'\s+'));
  return p.length <= 2 ? p.join(' ') : '${p.first} ${p.last}';
}

/// Texto da escala do mês para o grupo do WhatsApp (o envio é feito pela pessoa).
String textoEscalaWhatsapp(List<CultoEscala> cultos, TipoEscala tipo, int mes, String Function(String membroId) nomeDe) {
  final linhas = <String>['*Escala ${tipo == TipoEscala.pastoral ? 'pastoral' : 'do louvor'} — ${nomesMeses[mes - 1]}*'];
  for (final c in cultos) {
    final partes = <String>[
      for (final f in c.funcoes(tipo))
        if ((c.da(tipo)[f] ?? const []).isNotEmpty) '$f: ${c.da(tipo)[f]!.map((id) => nomeCurto(nomeDe(id))).join(', ')}',
    ];
    if (partes.isEmpty && (tipo == TipoEscala.pastoral || c.musicas.isEmpty)) continue;
    linhas
      ..add('')
      ..add('*${rotuloDia(c.data)} · ${horaCurtaEscala(c.hora)}*${c.ceia ? ' (Santa Ceia)' : ''}${c.nome != 'Culto' ? ' — ${c.nome}' : ''}');
    if (partes.isNotEmpty) linhas.add(partes.join(' · '));
    if (tipo == TipoEscala.pastoral && c.tema.isNotEmpty) linhas.add('Tema: ${c.tema}');
    if (tipo == TipoEscala.louvor && c.musicas.isNotEmpty) {
      linhas.add('Músicas: ${[for (final m in c.musicas) m.tom.isEmpty ? m.titulo : '${m.titulo} (${m.tom})'].join('; ')}');
    }
  }
  return linhas.join('\n');
}
