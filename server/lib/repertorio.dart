import 'package:diako_core/diako_core.dart';

/// Música cadastrada pela equipe; a planilha serve apenas para importação inicial.
class RepertorioMusica {
  const RepertorioMusica({
    this.id = '',
    required this.titulo,
    required this.cantor,
    this.compositor = '',
    this.ano = '',
    this.referencia = '',
    this.solicitadoPor = '',
    this.observacoes = '',
    this.status = 'Ok',
    this.tomOriginal = '',
    this.tomDiakonia = '',
    this.bpm = '',
    this.biografiaCantor = '',
    this.biografiaCompositor = '',
    this.ativo = true,
  });

  final String id, titulo, cantor, compositor, ano, referencia, solicitadoPor, observacoes;
  final String status, tomOriginal, tomDiakonia, bpm, biografiaCantor, biografiaCompositor;
  final bool ativo;

  /// O primeiro tom da anotação (ex.: "Em (Intro: C...)" → "Em").
  String get tomPadrao => RegExp(r'(?:^|[^A-Za-z])([A-G](?:#|b)?m?)(?=$|[^A-Za-z#])', caseSensitive: false)
      .firstMatch(tomDiakonia.split(RegExp(r'\r?\n')).first)?.group(1) ?? '';

  RepertorioMusica comId(String novoId) => RepertorioMusica.fromJson({...toJson(), 'id': novoId});

  Map<String, dynamic> toJson() => {
        'id': id, 'titulo': titulo, 'cantor': cantor, 'compositor': compositor, 'ano': ano,
        'referencia': referencia, 'solicitadoPor': solicitadoPor, 'observacoes': observacoes,
        'status': status, 'tomOriginal': tomOriginal, 'tomDiakonia': tomDiakonia, 'bpm': bpm,
        'biografiaCantor': biografiaCantor, 'biografiaCompositor': biografiaCompositor, 'ativo': ativo,
      };

  factory RepertorioMusica.fromJson(Map<String, dynamic> j) {
    String campo(String chave, int maximo) {
      final v = j[chave];
      if (v != null && v is! String) throw FormatException('Campo $chave inválido.');
      final texto = (v as String? ?? '').trim();
      if (texto.length > maximo) throw FormatException('Campo $chave longo demais.');
      return texto;
    }

    final id = campo('id', 100), titulo = campo('titulo', 120), cantor = campo('cantor', 120);
    if (titulo.isEmpty || cantor.isEmpty) throw const FormatException('Título e cantor são obrigatórios.');
    if (j['ativo'] != null && j['ativo'] is! bool) throw const FormatException('Status ativo inválido.');
    return RepertorioMusica(
      id: id, titulo: titulo, cantor: cantor, compositor: campo('compositor', 400),
      ano: campo('ano', 40), referencia: campo('referencia', 500),
      solicitadoPor: campo('solicitadoPor', 120), observacoes: campo('observacoes', 4000),
      status: campo('status', 80), tomOriginal: campo('tomOriginal', 120),
      tomDiakonia: campo('tomDiakonia', 500), bpm: campo('bpm', 40),
      biografiaCantor: campo('biografiaCantor', 10000),
      biografiaCompositor: campo('biografiaCompositor', 10000), ativo: j['ativo'] as bool? ?? true,
    );
  }
}

String chaveRepertorio(String titulo, String cantor) {
  String normalizar(String valor) =>
      (semAcento(valor.toLowerCase()) ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
  return '${normalizar(titulo)}|${normalizar(cantor)}';
}

/// CSV padrão RFC 4180, inclusive campos entre aspas contendo vírgulas e novas linhas.
List<List<String>> _linhasCsv(String texto) {
  final linhas = <List<String>>[];
  var linha = <String>[];
  final campo = StringBuffer();
  var aspas = false;
  for (var i = 0; i < texto.length; i++) {
    final c = texto[i];
    if (aspas) {
      if (c == '"' && i + 1 < texto.length && texto[i + 1] == '"') {
        campo.write('"');
        i++;
      } else if (c == '"') {
        aspas = false;
      } else {
        campo.write(c);
      }
    } else if (c == '"') {
      if (campo.isNotEmpty) throw const FormatException('Aspas fora do início de uma coluna.');
      aspas = true;
    } else if (c == ',' || c == '\n' || c == '\r') {
      linha.add(campo.toString());
      campo.clear();
      if (c != ',') {
        if (linha.any((v) => v.trim().isNotEmpty)) linhas.add(linha);
        linha = <String>[];
        if (c == '\r' && i + 1 < texto.length && texto[i + 1] == '\n') i++;
      }
    } else {
      campo.write(c);
    }
  }
  if (aspas) throw const FormatException('CSV com aspas não fechadas.');
  if (campo.isNotEmpty || linha.isNotEmpty) {
    linha.add(campo.toString());
    if (linha.any((v) => v.trim().isNotEmpty)) linhas.add(linha);
  }
  return linhas;
}

/// Importação do CSV exportado pela aba 0 da planilha; não acessa o Google.
List<RepertorioMusica> lerRepertorioCsv(String csv) {
  final linhas = _linhasCsv(csv.replaceFirst(RegExp(r'^\uFEFF'), ''));
  if (linhas.isEmpty) throw const FormatException('CSV vazio.');
  final colunas = {for (var i = 0; i < linhas.first.length; i++) linhas.first[i].trim().toLowerCase(): i};
  if (!colunas.containsKey('louvor') || !colunas.containsKey('cantor')) {
    throw const FormatException('CSV precisa das colunas Louvor e Cantor.');
  }
  String ler(List<String> linha, String coluna) {
    final i = colunas[coluna.toLowerCase()];
    return i == null || i >= linha.length ? '' : linha[i].trim();
  }
  return [
    for (final linha in linhas.skip(1))
      RepertorioMusica.fromJson({
        'titulo': ler(linha, 'Louvor'), 'cantor': ler(linha, 'Cantor'),
        'compositor': ler(linha, 'Compositor'), 'ano': ler(linha, 'Ano'),
        'referencia': ler(linha, 'Link Versão'), 'solicitadoPor': ler(linha, 'Solicitado por'),
        'observacoes': ler(linha, 'Observações'), 'status': ler(linha, 'Status'),
        'tomOriginal': ler(linha, 'Tom Original'), 'tomDiakonia': ler(linha, 'Tom Diakonia'),
        'bpm': ler(linha, 'Bpm'), 'biografiaCantor': ler(linha, 'Resumo Biografia Cantor'),
        'biografiaCompositor': ler(linha, 'Resumo Biografia Compositor'),
        'ativo': ler(linha, 'Status').toLowerCase() == 'ok',
      }),
  ];
}
