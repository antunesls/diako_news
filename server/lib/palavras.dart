import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

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

/// Id do documento num link do Google Docs ("docs.google.com/document/d/<id>/edit"); null se não for um.
String? idDocumentoGoogle(String link) =>
    RegExp(r'docs\.google\.com/document/(?:u/\d+/)?d/([A-Za-z0-9_-]{20,})').firstMatch(link)?.group(1);

/// Texto exportado pelo Google Docs (um parágrafo por linha) no formato do editor: parágrafos
/// separados por linha em branco.
String textoDoGoogleDocs(String exportado) => exportado
    .replaceFirst('﻿', '')
    .replaceAll('\r\n', '\n')
    .split('\n')
    .map((l) => l.trim())
    .where((l) => l.isNotEmpty)
    .join('\n\n');

/// Lê documentos do Google Docs com a conta de serviço do Google (a mesma da agenda). O documento
/// precisa estar compartilhado com o e-mail da conta, como leitor.
class DocumentosGoogle {
  DocumentosGoogle({required Future<http.Client> Function() cliente, this.emailConta = ''}) : _cliente = cliente;

  factory DocumentosGoogle.daConta(Map<String, dynamic> chave) => DocumentosGoogle(
        emailConta: chave['client_email'] as String? ?? '',
        cliente: () => clientViaServiceAccount(
          ServiceAccountCredentials.fromJson(chave),
          const ['https://www.googleapis.com/auth/drive.readonly'],
        ),
      );

  final Future<http.Client> Function() _cliente;
  final String emailConta;

  static const timeout = Duration(seconds: 20);

  /// Texto do documento do [link]. Lança [FormatException] com o que fazer.
  Future<String> texto(String link) async {
    final id = idDocumentoGoogle(link);
    if (id == null) {
      throw const FormatException('Cole o link do documento do Google Docs (docs.google.com/document/d/...).');
    }
    http.Client? cliente;
    try {
      cliente = await _cliente().timeout(timeout);
      final r = await cliente
          .get(Uri.parse('https://www.googleapis.com/drive/v3/files/$id/export?mimeType=text/plain'))
          .timeout(timeout);
      if (r.statusCode == 200) return textoDoGoogleDocs(utf8.decode(r.bodyBytes, allowMalformed: true));
      final erro = utf8.decode(r.bodyBytes, allowMalformed: true);
      if (r.statusCode == 403 && (erro.contains('has not been used') || erro.contains('is disabled'))) {
        throw const FormatException('Ative a "Google Drive API" no projeto da conta de serviço do Google '
            '(console.cloud.google.com › APIs e serviços) e tente de novo.');
      }
      if (r.statusCode == 403 || r.statusCode == 404) {
        throw FormatException('O documento não foi encontrado ou não está compartilhado. No Google Docs, toque em '
            '"Compartilhar" e adicione ${emailConta.isEmpty ? 'a conta de serviço' : emailConta} como leitor.');
      }
      throw FormatException('O Google não entregou o documento (erro ${r.statusCode}). Tente de novo.');
    } on TimeoutException {
      throw const FormatException('O Google não respondeu. Tente de novo.');
    } on SocketException {
      throw const FormatException('Sem conexão com o Google. Confira a internet do servidor.');
    } on AccessDeniedException {
      throw const FormatException('O Google recusou a chave da conta de serviço. Confira em Administração › Agenda.');
    } finally {
      cliente?.close();
    }
  }
}
