class Membro {
  Membro({required this.id, required this.nome, required this.dia, required this.mes, this.ativo = true});

  final String id;
  String nome;

  /// Dia e mês do aniversário (o ano não é guardado).
  int dia;
  int mes;
  bool ativo;

  /// "dd/mm"
  String get aniversario => '${dia.toString().padLeft(2, '0')}/${mes.toString().padLeft(2, '0')}';

  static bool dataValida(int dia, int mes) {
    if (mes < 1 || mes > 12 || dia < 1) return false;
    const maximo = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    return dia <= maximo[mes - 1];
  }

  Map<String, dynamic> toJson() => {'id': id, 'nome': nome, 'dia': dia, 'mes': mes, 'ativo': ativo};

  factory Membro.fromJson(Map<String, dynamic> j) => Membro(
        id: j['id'] as String,
        nome: j['nome'] as String? ?? '',
        dia: (j['dia'] as num?)?.toInt() ?? 1,
        mes: (j['mes'] as num?)?.toInt() ?? 1,
        ativo: j['ativo'] as bool? ?? true,
      );
}

/// Lê linhas "Nome;dd/mm" (ou com vírgula/tab). Retorna os válidos e as linhas com erro.
({List<({String nome, int dia, int mes})> membros, List<int> linhasComErro}) lerCsvMembros(String texto) {
  final membros = <({String nome, int dia, int mes})>[];
  final erros = <int>[];
  final linhas = texto.split(RegExp(r'\r?\n'));
  for (var i = 0; i < linhas.length; i++) {
    final linha = linhas[i].trim();
    if (linha.isEmpty) continue;
    final partes = linha.split(RegExp(r'[;,\t]'));
    final data = partes.length >= 2 ? RegExp(r'^(\d{1,2})/(\d{1,2})').firstMatch(partes[1].trim()) : null;
    if (data == null) {
      // Ignora um cabeçalho na primeira linha.
      if (i > 0 || !linha.toLowerCase().contains('nome')) erros.add(i + 1);
      continue;
    }
    final dia = int.parse(data.group(1)!), mes = int.parse(data.group(2)!);
    final nome = partes[0].trim();
    if (nome.isEmpty || !Membro.dataValida(dia, mes)) {
      erros.add(i + 1);
      continue;
    }
    membros.add((nome: nome, dia: dia, mes: mes));
  }
  return (membros: membros, linhasComErro: erros);
}
