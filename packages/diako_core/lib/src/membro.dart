/// Situação da pessoa na igreja.
enum StatusMembro {
  visitante('Visitante'),
  congregado('Congregado'),
  membro('Membro'),
  inativo('Inativo'),
  transferido('Transferido');

  const StatusMembro(this.nome);
  final String nome;

  /// Entra na lista de aniversariantes do telão e nas estatísticas de pessoas ativas.
  bool get ativo => this == StatusMembro.visitante || this == StatusMembro.congregado || this == StatusMembro.membro;

  /// Aceita o nome exato e a forma feminina ("congregada", "membra", "inativa"…).
  static StatusMembro? porNome(String? nome) {
    final n = semAcento(nome?.trim().toLowerCase());
    if (n == null || n.isEmpty) return null;
    for (final s in StatusMembro.values) {
      if (s.name == n) return s;
      if (s.name.endsWith('o') && '${s.name.substring(0, s.name.length - 1)}a' == n) return s;
    }
    return null;
  }

  /// Para documentos antigos, gravados antes de existir status (só tinham "ativo").
  static StatusMembro legado(bool ativo) => ativo ? StatusMembro.membro : StatusMembro.inativo;
}

/// Uma mudança de status do membro (quando aconteceu e para qual).
class MudancaStatus {
  MudancaStatus(this.status, this.em);

  final StatusMembro status;
  final DateTime em;

  Map<String, dynamic> toJson() => {'status': status.name, 'em': em.toIso8601String()};

  factory MudancaStatus.fromJson(Map<String, dynamic> j) => MudancaStatus(
        StatusMembro.porNome(j['status'] as String?) ?? StatusMembro.membro,
        DateTime.tryParse(j['em'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Pessoa cadastrada pela igreja. Os campos [nome], [dia], [mes] e [ativo] (derivado do
/// status) são o formato antigo, usado pelo aniversariantes do telão, do mural e do app.
class Membro {
  Membro({
    required this.id,
    required this.nome,
    required this.dia,
    required this.mes,
    this.ano,
    this.sexo,
    this.estadoCivil,
    this.foto,
    this.cpf,
    this.rg,
    this.telefone,
    this.whatsapp,
    this.email,
    this.cep,
    this.rua,
    this.numero,
    this.complemento,
    this.bairro,
    this.cidade,
    this.estado,
    StatusMembro? status,
    bool? ativo,
    this.dataChegada,
    this.dataBatismo,
    this.dataMembresia,
    this.ministerios = const [],
    this.funcao,
    this.observacoes,
    this.conjugeId,
    this.paisIds = const [],
    this.emergenciaNome,
    this.emergenciaTelefone,
    this.emergenciaVinculo,
    List<MudancaStatus>? historicoStatus,
    this.criadoEm,
    this.atualizadoEm,
  })  : status = status ?? StatusMembro.legado(ativo ?? true),
        historicoStatus = historicoStatus ?? [];

  final String id;
  String nome;

  /// Dia e mês do aniversário. O ano ([ano]) é opcional.
  int dia;
  int mes;
  int? ano;

  /// 'M' ou 'F' (null quando não informado).
  String? sexo;
  String? estadoCivil;

  /// Nome do arquivo da foto em data/fotos-membros (sem a miniatura "-m").
  String? foto;

  /// Somente dígitos.
  String? cpf;
  String? rg;
  String? telefone;
  String? whatsapp;
  String? email;
  String? cep;
  String? rua;
  String? numero;
  String? complemento;
  String? bairro;
  String? cidade;
  String? estado;

  StatusMembro status;

  /// Datas no formato aaaa-mm-dd.
  String? dataChegada;
  String? dataBatismo;
  String? dataMembresia;
  List<String> ministerios;
  String? funcao;
  String? observacoes;

  /// Id do cônjuge (o servidor mantém o vínculo nos dois lados).
  String? conjugeId;

  /// Ids dos pais (cada um também é um membro). Os filhos de alguém são todos os
  /// membros que têm o id dele aqui — não há vínculo duplicado para limpar.
  List<String> paisIds;

  String? emergenciaNome;
  String? emergenciaTelefone;
  String? emergenciaVinculo;

  final List<MudancaStatus> historicoStatus;
  final DateTime? criadoEm;
  final DateTime? atualizadoEm;

  /// Entra nos aniversariantes do telão (derivado do status).
  bool get ativo => status.ativo;

  /// "dd/mm" (formato antigo, sem o ano).
  String get aniversario => '${dia.toString().padLeft(2, '0')}/${mes.toString().padLeft(2, '0')}';

  /// Idade que a pessoa tem hoje (null quando o ano não é guardado).
  int? idadeEm(DateTime agora) {
    if (ano == null) return null;
    var idade = agora.year - ano!;
    final aniversarioEsteAno = DateTime(agora.year, mes, dia);
    return aniversarioEsteAno.isAfter(agora) ? idade - 1 : idade;
  }

  static bool dataValida(int dia, int mes) {
    if (mes < 1 || mes > 12 || dia < 1) return false;
    const maximo = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    return dia <= maximo[mes - 1];
  }

  /// CPF só com dígitos (remove pontos, traço e espaços).
  static String? soDigitos(String? cpf) {
    final d = cpf?.replaceAll(RegExp(r'\D'), '');
    return d == null || d.isEmpty ? null : d;
  }

  /// Confere o formato e os dois dígitos verificadores.
  static bool cpfValido(String cpf) {
    final d = soDigitos(cpf)!;
    if (d.length != 11) return false;
    if (RegExp(r'^(\d)\1{10}$').hasMatch(d)) return false; // 111.111.111-11 etc.
    int digito(int n) {
      var soma = 0;
      for (var i = 0; i < n; i++) {
        soma += int.parse(d[i]) * (n + 1 - i);
      }
      final r = (soma * 10) % 11;
      return r == 10 ? 0 : r;
    }
    return digito(9) == int.parse(d[9]) && digito(10) == int.parse(d[10]);
  }

  /// Data "aaaa-mm-dd" válida (usada em chegada, batismo e membresia).
  static bool dataIsoValida(String? data) {
    if (data == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(data)) return false;
    final d = DateTime.tryParse(data);
    return d != null && d.year >= 1900 && !d.isAfter(DateTime.now().add(const Duration(days: 1)));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nome': nome,
        'dia': dia,
        'mes': mes,
        'ativo': ativo,
        if (ano != null) 'ano': ano,
        if (sexo != null && sexo!.isNotEmpty) 'sexo': sexo,
        if (!(estadoCivil ?? '').isEmpty) 'estadoCivil': estadoCivil,
        if (!(foto ?? '').isEmpty) 'foto': foto,
        if (!(cpf ?? '').isEmpty) 'cpf': cpf,
        if (!(rg ?? '').isEmpty) 'rg': rg,
        if (!(telefone ?? '').isEmpty) 'telefone': telefone,
        if (!(whatsapp ?? '').isEmpty) 'whatsapp': whatsapp,
        if (!(email ?? '').isEmpty) 'email': email,
        if (!(cep ?? '').isEmpty) 'cep': cep,
        if (!(rua ?? '').isEmpty) 'rua': rua,
        if (!(numero ?? '').isEmpty) 'numero': numero,
        if (!(complemento ?? '').isEmpty) 'complemento': complemento,
        if (!(bairro ?? '').isEmpty) 'bairro': bairro,
        if (!(cidade ?? '').isEmpty) 'cidade': cidade,
        if (!(estado ?? '').isEmpty) 'estado': estado,
        'status': status.name,
        if (dataChegada != null) 'dataChegada': dataChegada,
        if (dataBatismo != null) 'dataBatismo': dataBatismo,
        if (dataMembresia != null) 'dataMembresia': dataMembresia,
        if (ministerios.isNotEmpty) 'ministerios': ministerios,
        if (!(funcao ?? '').isEmpty) 'funcao': funcao,
        if (!(observacoes ?? '').isEmpty) 'observacoes': observacoes,
        if (conjugeId != null) 'conjugeId': conjugeId,
        if (paisIds.isNotEmpty) 'paisIds': paisIds,
        if (!(emergenciaNome ?? '').isEmpty) 'emergenciaNome': emergenciaNome,
        if (!(emergenciaTelefone ?? '').isEmpty) 'emergenciaTelefone': emergenciaTelefone,
        if (!(emergenciaVinculo ?? '').isEmpty) 'emergenciaVinculo': emergenciaVinculo,
        if (historicoStatus.isNotEmpty) 'historicoStatus': [for (final m in historicoStatus) m.toJson()],
        if (criadoEm != null) 'criadoEm': criadoEm!.toIso8601String(),
        if (atualizadoEm != null) 'atualizadoEm': atualizadoEm!.toIso8601String(),
      };

  factory Membro.fromJson(Map<String, dynamic> j) {
    final status =
        StatusMembro.porNome(j['status'] as String?) ?? StatusMembro.legado(j['ativo'] as bool? ?? true);
    List<String> lista(Object? v) =>
        v is List ? [for (final e in v) e.toString().trim()].where((s) => s.isNotEmpty).toList() : const [];
    return Membro(
      id: j['id'] as String,
      nome: j['nome'] as String? ?? '',
      dia: (j['dia'] as num?)?.toInt() ?? 1,
      mes: (j['mes'] as num?)?.toInt() ?? 1,
      ano: (j['ano'] as num?)?.toInt(),
      sexo: _sexo(j['sexo']),
      estadoCivil: _texto(j['estadoCivil']),
      foto: _texto(j['foto']),
      cpf: soDigitos(_texto(j['cpf'])),
      rg: _texto(j['rg']),
      telefone: _texto(j['telefone']),
      whatsapp: _texto(j['whatsapp']),
      email: _texto(j['email']),
      cep: soDigitos(_texto(j['cep'])),
      rua: _texto(j['rua']),
      numero: _texto(j['numero']),
      complemento: _texto(j['complemento']),
      bairro: _texto(j['bairro']),
      cidade: _texto(j['cidade']),
      estado: _texto(j['estado']),
      status: status,
      dataChegada: dataDe(j['dataChegada']),
      dataBatismo: dataDe(j['dataBatismo']),
      dataMembresia: dataDe(j['dataMembresia']),
      ministerios: lista(j['ministerios']),
      funcao: _texto(j['funcao']),
      observacoes: _texto(j['observacoes']),
      conjugeId: _texto(j['conjugeId']),
      paisIds: lista(j['paisIds']),
      emergenciaNome: _texto(j['emergenciaNome']),
      emergenciaTelefone: _texto(j['emergenciaTelefone']),
      emergenciaVinculo: _texto(j['emergenciaVinculo']),
      historicoStatus: j['historicoStatus'] is List
          ? [for (final m in j['historicoStatus'] as List) MudancaStatus.fromJson(Map<String, dynamic>.from(m as Map))]
          : null,
      criadoEm: DateTime.tryParse(j['criadoEm'] as String? ?? ''),
      atualizadoEm: DateTime.tryParse(j['atualizadoEm'] as String? ?? ''),
    );
  }

  static String? _texto(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

  /// Mantém 'M' ou 'F', aceitando "masculino"/"feminino".
  static String? _sexo(Object? v) {
    final s = semAcento(_texto(v)?.toLowerCase());
    if (s == null) return null;
    if (s.startsWith('m')) return 'M';
    if (s.startsWith('f')) return 'F';
    return null;
  }

  /// Guarda datas como "aaaa-mm-dd" (aceita "dd/mm/aaaa" de planilhas).
  /// Retorna null para datas que não batem com os dois formatos ou não existem (31/02).
  static String? dataDe(Object? v) {
    final s = _texto(v);
    if (s == null) return null;
    final br = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(s);
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
    final int ano, mes, dia;
    if (br != null) {
      (ano, mes, dia) = (int.parse(br.group(3)!), int.parse(br.group(2)!), int.parse(br.group(1)!));
    } else if (iso != null) {
      (ano, mes, dia) = (int.parse(iso.group(1)!), int.parse(iso.group(2)!), int.parse(iso.group(3)!));
    } else {
      return null;
    }
    // DateTime "corrige" 31/02 para 03/03: se mudou, a data não existe.
    final d = DateTime(ano, mes, dia);
    if (d.year != ano || d.month != mes || d.day != dia) return null;
    return '$ano-${mes.toString().padLeft(2, '0')}-${dia.toString().padLeft(2, '0')}';
  }
}

/// Minúsculas sem acento (para comparar "membro", "Membro", "inativo" etc.).
String? semAcento(String? s) => s?.replaceAll('á', 'a').replaceAll('à', 'a').replaceAll('â', 'a').replaceAll('ã', 'a')
    .replaceAll('é', 'e').replaceAll('ê', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o').replaceAll('ô', 'o').replaceAll('õ', 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ç', 'c');

/// Uma linha do CSV de importação (só [nome], [dia] e [mes] são obrigatórios).
class MembroCsv {
  MembroCsv({required this.nome, required this.dia, required this.mes});

  final String nome;
  final int dia;
  final int mes;
  int? ano;
  String? sexo;
  String? estadoCivil;
  String? cpf;
  String? rg;
  String? telefone;
  String? whatsapp;
  String? email;
  String? cep;
  String? rua;
  String? numero;
  String? complemento;
  String? bairro;
  String? cidade;
  String? estado;
  StatusMembro status = StatusMembro.membro;
  String? dataChegada;
  String? dataBatismo;
  String? dataMembresia;
  List<String> ministerios = const [];
  String? funcao;
  String? observacoes;

  Map<String, dynamic> toJson() => {
        'nome': nome,
        'dia': dia,
        'mes': mes,
        if (ano != null) 'ano': ano,
        if (sexo != null) 'sexo': sexo,
        if (estadoCivil != null) 'estadoCivil': estadoCivil,
        if (cpf != null) 'cpf': cpf,
        if (rg != null) 'rg': rg,
        if (telefone != null) 'telefone': telefone,
        if (whatsapp != null) 'whatsapp': whatsapp,
        if (email != null) 'email': email,
        if (cep != null) 'cep': cep,
        if (rua != null) 'rua': rua,
        if (numero != null) 'numero': numero,
        if (complemento != null) 'complemento': complemento,
        if (bairro != null) 'bairro': bairro,
        if (cidade != null) 'cidade': cidade,
        if (estado != null) 'estado': estado,
        'status': status.name,
        if (dataChegada != null) 'dataChegada': dataChegada,
        if (dataBatismo != null) 'dataBatismo': dataBatismo,
        if (dataMembresia != null) 'dataMembresia': dataMembresia,
        if (ministerios.isNotEmpty) 'ministerios': ministerios,
        if (funcao != null) 'funcao': funcao,
        if (observacoes != null) 'observacoes': observacoes,
      };
}

/// Lê o CSV de membros de duas formas:
/// - com cabeçalho na primeira linha: `Nome;Aniversário;Telefone;Email;Status;…`
///   (separador `;` ou tabulação; "Aniversário" aceita dd/mm ou dd/mm/aaaa);
/// - o formato antigo, sem cabeçalho: `Nome;dd/mm` por linha.
/// Retorna os válidos e, para cada linha com problema, o número e o motivo.
({List<MembroCsv> membros, List<int> linhasComErro, List<String> detalhes}) lerCsvMembros(String texto) {
  final membros = <MembroCsv>[];
  final erros = <int>[];
  final detalhes = <String>[];
  final linhas = texto.split(RegExp(r'\r?\n'));

  // Cabeçalho quando a primeira linha traz o nome e mais alguma coluna conhecida
  // ("Nome;Aniversário;Telefone…"). A lista antiga ("Nome;dd/mm" sem cabeçalho ou com
  // "Nome;Data") continua no formato simples.
  final primeira = linhas.isNotEmpty ? linhas[0] : '';
  final colunasCabecalho = _colunas(primeira);
  final temCabecalho = colunasCabecalho.containsKey('nome') && colunasCabecalho.length >= 2;

  for (var i = 0; i < linhas.length; i++) {
    final n = i + 1;
    final linha = linhas[i].trim();
    if (linha.isEmpty) continue;
    if (temCabecalho && i == 0) continue;

    if (temCabecalho) {
      final m = _lerLinhaComCabecalho(linha, colunasCabecalho);
      if (m.membro != null) {
        membros.add(m.membro!);
      } else {
        erros.add(n);
        detalhes.add('linha $n: ${m.erro}');
      }
      continue;
    }

    // Formato antigo: Nome;dd/mm
    final partes = linha.split(RegExp(r'[;,\t]'));
    final data = partes.length >= 2 ? RegExp(r'^(\d{1,2})/(\d{1,2})').firstMatch(partes[1].trim()) : null;
    if (data == null) {
      // Ignora um cabeçalho na primeira linha.
      if (i > 0 || !linha.toLowerCase().contains('nome')) {
        erros.add(n);
        detalhes.add('linha $n: use "Nome;dd/mm"');
      }
      continue;
    }
    final dia = int.parse(data.group(1)!), mes = int.parse(data.group(2)!);
    final nome = partes[0].trim();
    if (nome.isEmpty || !Membro.dataValida(dia, mes)) {
      erros.add(n);
      detalhes.add('linha $n: aniversário inválido');
      continue;
    }
    membros.add(MembroCsv(nome: nome, dia: dia, mes: mes));
  }
  return (membros: membros, linhasComErro: erros, detalhes: detalhes);
}

/// Mapa "coluna normalizada" → posição. Só as colunas reconhecidas entram.
Map<String, int> _colunas(String linha) {
  final mapa = <String, int>{};
  final partes = linha.split(RegExp(r'[;\t]'));
  for (var i = 0; i < partes.length; i++) {
    final nome = semAcento(partes[i].trim().toLowerCase());
    if (nome == null) continue;
    final chave = _nomesColuna[nome];
    if (chave != null && !mapa.containsKey(chave)) mapa[chave] = i;
  }
  return mapa;
}

const _nomesColuna = {
  'nome': 'nome',
  'aniversario': 'aniversario',
  'nascimento': 'aniversario',
  'data de nascimento': 'aniversario',
  'sexo': 'sexo',
  'estado civil': 'estadoCivil',
  'cpf': 'cpf',
  'rg': 'rg',
  'telefone': 'telefone',
  'fone': 'telefone',
  'celular': 'telefone',
  'whatsapp': 'whatsapp',
  'whatssap': 'whatsapp',
  'email': 'email',
  'e-mail': 'email',
  'cep': 'cep',
  'rua': 'rua',
  'endereco': 'rua',
  'endereço': 'rua',
  'numero': 'numero',
  'número': 'numero',
  'complemento': 'complemento',
  'bairro': 'bairro',
  'cidade': 'cidade',
  'estado': 'estado',
  'uf': 'estado',
  'status': 'status',
  'situacao': 'status',
  'situação': 'status',
  'data de chegada': 'dataChegada',
  'chegada': 'dataChegada',
  'data de batismo': 'dataBatismo',
  'batismo': 'dataBatismo',
  'batizado em': 'dataBatismo',
  'data de membresia': 'dataMembresia',
  'membresia': 'dataMembresia',
  'membro desde': 'dataMembresia',
  'ministerios': 'ministerios',
  'ministérios': 'ministerios',
  'ministerio': 'ministerios',
  'ministério': 'ministerios',
  'funcao': 'funcao',
  'função': 'funcao',
  'observacoes': 'observacoes',
  'observações': 'observacoes',
};

({MembroCsv? membro, String? erro}) _lerLinhaComCabecalho(String linha, Map<String, int> colunas) {
  final partes = linha.split(RegExp(r'[;\t]'));
  String celula(String coluna) {
    final i = colunas[coluna];
    return i != null && i < partes.length ? partes[i].trim() : '';
  }

  final nome = celula('nome');
  if (nome.isEmpty) return (membro: null, erro: 'sem nome');

  final aniversario = celula('aniversario');
  final m = RegExp(r'^(\d{1,2})/(\d{1,2})(?:/(\d{4}))?$').firstMatch(aniversario);
  if (m == null) return (membro: null, erro: 'aniversário "$aniversario" (use dd/mm ou dd/mm/aaaa)');
  final dia = int.parse(m.group(1)!), mes = int.parse(m.group(2)!);
  if (!Membro.dataValida(dia, mes)) return (membro: null, erro: 'aniversário "$aniversario" inválido');

  final r = MembroCsv(nome: nome, dia: dia, mes: mes);
  if (m.group(3) != null) r.ano = int.parse(m.group(3)!);
  r.sexo = Membro._sexo(celula('sexo'));
  r.estadoCivil = _textoCsv(celula('estadoCivil'));
  r.cpf = Membro.soDigitos(celula('cpf'));
  r.rg = _textoCsv(celula('rg'));
  r.telefone = _textoCsv(celula('telefone'));
  r.whatsapp = _textoCsv(celula('whatsapp'));
  r.email = _textoCsv(celula('email'));
  r.cep = Membro.soDigitos(celula('cep'));
  r.rua = _textoCsv(celula('rua'));
  r.numero = _textoCsv(celula('numero'));
  r.complemento = _textoCsv(celula('complemento'));
  r.bairro = _textoCsv(celula('bairro'));
  r.cidade = _textoCsv(celula('cidade'));
  r.estado = _textoCsv(celula('estado'));
  r.status = StatusMembro.porNome(celula('status')) ?? StatusMembro.membro;
  r.dataChegada = Membro.dataDe(celula('dataChegada'));
  r.dataBatismo = Membro.dataDe(celula('dataBatismo'));
  r.dataMembresia = Membro.dataDe(celula('dataMembresia'));
  final ministerios = celula('ministerios');
  if (ministerios.isNotEmpty) {
    r.ministerios = ministerios.split(RegExp(r'[|,]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }
  r.funcao = _textoCsv(celula('funcao'));
  r.observacoes = _textoCsv(celula('observacoes'));
  return (membro: r, erro: null);
}

String? _textoCsv(String v) => v.trim().isEmpty ? null : v.trim();
