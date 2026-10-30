import 'dart:convert';

import 'package:archive/archive.dart';

/// Tamanho máximo do arquivo enviado para importar uma Palavra.
const tamanhoMaximoImportacao = 10 * 1024 * 1024;

/// Texto de uma Palavra a partir do arquivo enviado (Word .docx ou texto .txt), no formato do
/// editor: parágrafos separados por linha em branco e títulos com "#".
String textoDoArquivo(String nome, List<int> bytes) {
  final extensao = nome.toLowerCase().split('.').last;
  return switch (extensao) {
    'docx' => textoDoDocx(bytes),
    'txt' || 'md' => _textoSimples(bytes),
    'pdf' => throw const FormatException('PDF ainda não é aceito: abra o PDF, copie o texto e cole no editor.'),
    'doc' => throw const FormatException('Arquivo .doc antigo: abra no Word e salve como .docx, ou copie e cole o texto.'),
    _ => throw const FormatException('Envie um arquivo do Word (.docx) ou de texto (.txt).'),
  };
}

String _textoSimples(List<int> bytes) {
  final utf = utf8.decode(bytes, allowMalformed: true);
  // Texto salvo no Bloco de Notas antigo (Windows-1252) vira "�" em UTF-8.
  final texto = utf.contains('�') ? latin1.decode(bytes) : utf;
  return texto.replaceFirst('﻿', '').replaceAll('\r\n', '\n').trim();
}

final _paragrafo = RegExp(r'<w:p[ >].*?</w:p>', dotAll: true);
final _estiloTitulo = RegExp(r'<w:pStyle w:val="(?:Heading|Ttulo|Titulo|Título|Title)\d*"');
final _pedaco = RegExp(r'<w:t(?: [^>]*)?>(.*?)</w:t>|<w:tab/>|<w:br/>', dotAll: true);

/// Parágrafos do documento do Word; os com estilo de título viram "# título".
String textoDoDocx(List<int> bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException('Não foi possível abrir o arquivo do Word.');
  }
  final documento = zip.findFile('word/document.xml');
  if (documento == null) throw const FormatException('Este arquivo não parece ser um documento do Word (.docx).');
  final xml = utf8.decode(documento.content, allowMalformed: true);
  final paragrafos = <String>[];
  for (final p in _paragrafo.allMatches(xml)) {
    final bloco = p.group(0)!;
    final texto = StringBuffer();
    for (final t in _pedaco.allMatches(bloco)) {
      final pedaco = t.group(0)!;
      texto.write(pedaco == '<w:tab/>' ? ' ' : pedaco == '<w:br/>' ? '\n' : _entidades(t.group(1)!));
    }
    final limpo = texto.toString().trim();
    if (limpo.isEmpty) continue;
    paragrafos.add(_estiloTitulo.hasMatch(bloco) ? '# ${limpo.replaceAll('\n', ' ')}' : limpo);
  }
  return paragrafos.join('\n\n');
}

String _entidades(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');
