import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:diako_core/diako_core.dart';
import 'package:diako_server/app.dart';
import 'package:diako_server/auth.dart';
import 'package:diako_server/backup.dart';
import 'package:diako_server/cartazes.dart';
import 'package:diako_server/config.dart';
import 'package:diako_server/configuracoes.dart';
import 'package:diako_server/historico.dart';
import 'package:diako_server/holyrics.dart';
import 'package:diako_server/palavras.dart';
import 'package:diako_server/permissoes.dart';
import 'package:diako_server/qr_oracao.dart';
import 'package:diako_server/store.dart';
import 'package:diako_server/usuarios.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Um .docx mínimo: só o word/document.xml, como o Word grava.
List<int> docx(String corpo) {
  final xml = utf8.encode('<?xml version="1.0" encoding="UTF-8"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>$corpo</w:body></w:document>');
  final zip = Archive()..addFile(ArchiveFile('word/document.xml', xml.length, xml));
  return ZipEncoder().encode(zip);
}

void main() {
  group('importar arquivo', () {
    test('Word: títulos viram "#", parágrafos ficam separados, entidades decodificadas', () {
      final texto = textoDoArquivo('Sermão.DOCX', docx(
        '<w:p><w:pPr><w:pStyle w:val="Ttulo1"/></w:pPr><w:r><w:t>A mesa preparada</w:t></w:r></w:p>'
        '<w:p><w:r><w:t xml:space="preserve">Jesus &amp; os </w:t></w:r><w:r><w:t>discípulos.</w:t></w:r></w:p>'
        '<w:p/>'
        '<w:p><w:r><w:t>Leia</w:t><w:tab/><w:t>1Co 11.23-24.</w:t></w:r></w:p>',
      ));
      expect(texto, '# A mesa preparada\n\nJesus & os discípulos.\n\nLeia 1Co 11.23-24.');
    });

    test('texto do Bloco de Notas antigo (Windows-1252) e UTF-8 com BOM', () {
      expect(textoDoArquivo('a.txt', latin1.encode('Pregação em João 3.16')), 'Pregação em João 3.16');
      expect(textoDoArquivo('a.txt', [0xEF, 0xBB, 0xBF, ...utf8.encode('Graça\r\n\r\nPaz')]), 'Graça\n\nPaz');
    });

    test('PDF, .doc e outros formatos explicam o que fazer', () {
      expect(() => textoDoArquivo('a.pdf', [1]), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('cole'))));
      expect(() => textoDoArquivo('a.doc', [1]), throwsFormatException);
      expect(() => textoDoArquivo('a.png', [1]), throwsFormatException);
      expect(() => textoDoArquivo('a.docx', [1, 2, 3]), throwsFormatException);
    });
  });

  group('Google Docs', () {
    const id = '1AbCdEfGhIjKlMnOpQrStUvWxYz012345';
    test('link do documento', () {
      expect(idDocumentoGoogle('https://docs.google.com/document/d/$id/edit?usp=sharing'), id);
      expect(idDocumentoGoogle('https://docs.google.com/document/u/0/d/$id/edit'), id);
      expect(idDocumentoGoogle('https://drive.google.com/file/d/$id/view'), isNull);
      expect(idDocumentoGoogle('qualquer coisa'), isNull);
    });

    test('exporta como texto e separa os parágrafos', () async {
      final pedidos = <Uri>[];
      final docs = DocumentosGoogle(
        emailConta: 'diako@projeto.iam.gserviceaccount.com',
        cliente: () async => MockClient((req) async {
          pedidos.add(req.url);
          return http.Response.bytes(utf8.encode('\uFEFFIntrodução\r\nGraça e paz.\r\n\r\nLeia Jo 3.16.\r\n'), 200);
        }),
      );
      expect(await docs.texto('https://docs.google.com/document/d/$id/edit'), 'Introdução\n\nGraça e paz.\n\nLeia Jo 3.16.');
      expect(pedidos.single.path, '/drive/v3/files/$id/export');
      expect(pedidos.single.queryParameters['mimeType'], 'text/plain');
    });

    test('erros explicam o que fazer', () async {
      DocumentosGoogle com(int status, String corpo) => DocumentosGoogle(
            emailConta: 'diako@projeto.iam.gserviceaccount.com',
            cliente: () async => MockClient((_) async => http.Response(corpo, status)),
          );
      Future<String> erro(DocumentosGoogle d, [String link = 'https://docs.google.com/document/d/$id/edit']) async {
        try {
          await d.texto(link);
          return '';
        } on FormatException catch (e) {
          return e.message;
        }
      }

      expect(await erro(com(404, '{}')), contains('diako@projeto.iam.gserviceaccount.com'));
      expect(await erro(com(403, '{"error":{"message":"Google Drive API has not been used in project 1"}}')), contains('Google Drive API'));
      expect(await erro(com(200, ''), 'https://exemplo.com'), contains('Cole o link'));
    });
  });

  test('QR do PIX: gravado com a chave completa, apagado sem ela, fora da lista de cartazes', () async {
    final pasta = await Directory.systemTemp.createTemp('diako_pix');
    try {
      final f = await gravarQrPix(pasta.path, chave: '12345678000199', nome: 'Igreja Diakonia', cidade: 'Sao Paulo');
      expect(f!.existsSync(), isTrue);
      expect(f.readAsBytesSync().take(4), [0x89, 0x50, 0x4E, 0x47]);
      expect(ehArquivoDeQr(arquivoQrPix), isTrue);
      expect(await gravarQrPix(pasta.path, chave: '', nome: 'Igreja', cidade: 'Sao Paulo'), isNull);
      expect(File(p.join(pasta.path, arquivoQrPix)).existsSync(), isFalse);
    } finally {
      await pasta.delete(recursive: true);
    }
  });

  test('rotas: a do tablet pede projetar; o resto, palavras', () {
    expect(permissaoDaRota('GET', 'api/palavras/hoje'), Permissao.projetar);
    expect(permissaoDaRota('GET', 'api/palavras'), Permissao.palavras);
    expect(permissaoDaRota('PUT', 'api/palavras/x'), Permissao.palavras);
    expect(Perfil.pastor.pode(Permissao.palavrasTodas), isTrue);
    expect(Perfil.pregador.pode(Permissao.palavras), isTrue);
    expect(Perfil.pregador.pode(Permissao.palavrasTodas), isFalse);
    expect(Perfil.telao.pode(Permissao.palavras), isFalse);
  });

  group('servidor', () {
    late Directory tmp;
    late Store store;
    late Handler handler;
    late String admin;
    final hoje = diaIso(DateTime.now());

    Future<(int, dynamic)> chamar(String metodo, String caminho, {String? token, Object? json}) async {
      final r = await handler(Request(metodo, Uri.parse('http://x$caminho'),
          headers: {if (token != null) 'authorization': 'Bearer $token', 'content-type': 'application/json'},
          body: json == null ? null : jsonEncode(json)));
      final texto = await r.readAsString();
      return (r.statusCode, texto.startsWith('{') || texto.startsWith('[') ? jsonDecode(texto) : texto);
    }

    Future<String?> entrar(String usuario, String senha) async {
      final (st, j) = await chamar('POST', '/api/login', json: {'usuario': usuario, 'senha': senha});
      return st == 200 ? j['token'] as String : null;
    }

    Future<String> criar(String login, Perfil perfil) async {
      final (st, j) = await chamar('POST', '/api/admin/usuarios',
          token: admin, json: {'nome': 'Pessoa $login', 'login': login, 'perfil': perfil.name});
      expect(st, 201, reason: '$j');
      return (await entrar(login, j['senhaTemporaria'] as String))!;
    }

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('diako_palavras');
      final config = Config.lerJson('{"senhaAdmin":"senha-principal"}', pastaBase: tmp.path);
      store = Store(config.pastaDados);
      await store.carregar();
      final cfg = await Configuracoes.carregar(config, urlDetectada: 'http://192.168.0.10:8080');
      final usuarios = Usuarios(config.pastaDados);
      final auth = Auth(conferirSenha: cfg.conferirSenha, pastaDados: config.pastaDados, usuarios: usuarios);
      final web = Directory(p.join(tmp.path, 'web'))..createSync();
      handler = Servidor(
        store: store,
        auth: auth,
        holyrics: HolyricsDireto(
            host: 'h', porta: 1, token: 't', cliente: MockClient((_) async => http.Response('{"status":"ok"}', 200))),
        cartazes: Cartazes(config.pastaCartazes),
        backup: Backup(pastaDados: config.pastaDados, configuracoes: cfg.publicas),
        pastaWeb: web.path,
        urlOracao: cfg.urlOracao,
        cartazesNoHolyrics: false,
        historico: Historico(config.pastaDados),
        cfg: cfg,
      ).handler;
      admin = (await entrar('', 'senha-principal'))!;
    });
    tearDown(() async {
      await store.fechar();
      await tmp.delete(recursive: true);
    });

    test('cada pregador só vê as suas; o pastor revisa todas; outros perfis não entram', () async {
      final pastor = await criar('pastor', Perfil.pastor);
      final pregador = await criar('pregador', Perfil.pregador);
      final secretaria = await criar('secretaria', Perfil.secretaria);

      final (st1, minha) = await chamar('POST', '/api/palavras', token: pregador, json: {'titulo': 'Quando a fé espera'});
      expect(st1, 201);
      expect(minha['autorNome'], 'Pessoa pregador');
      final (st2, doPastor) = await chamar('POST', '/api/palavras', token: pastor, json: {'titulo': 'Em memória de mim'});
      expect(st2, 201);

      expect(((await chamar('GET', '/api/palavras', token: pregador)).$2 as List).map((x) => x['titulo']), ['Quando a fé espera']);
      expect(((await chamar('GET', '/api/palavras', token: pastor)).$2 as List).length, 2);
      expect((await chamar('GET', '/api/palavras/${doPastor['id']}', token: pregador)).$1, 404);
      expect((await chamar('PUT', '/api/palavras/${doPastor['id']}', token: pregador, json: {'titulo': 'X'})).$1, 404);
      expect((await chamar('DELETE', '/api/palavras/${doPastor['id']}', token: pregador)).$1, 404);
      expect((await chamar('GET', '/api/palavras/${minha['id']}', token: pastor)).$1, 200);
      expect((await chamar('GET', '/api/palavras', token: secretaria)).$1, 403);
    });

    test('edição guarda a versão anterior; pronta só sem pendências; o tablet recebe a de hoje', () async {
      final telao = await criar('telao', Perfil.telao);
      const texto = '# A mesa\nComo diz Romanos 5.8.\n\nLemos o Salmo 23.';
      final (_, nova) = await chamar('POST', '/api/palavras', token: admin,
          json: {'titulo': 'Em memória de mim', 'data': hoje, 'texto': texto});
      final id = nova['id'];
      expect((nova['trechos'] as List).length, 2);
      expect(nova['pendencias'], contains('Há versículos para conferir.'));

      // Não pode ficar pronta com versículo sem conferir ou incompleto.
      final (st, erro) = await chamar('PUT', '/api/palavras/$id', token: admin, json: {'pronta': true});
      expect(st, 400);
      expect(erro['erro'], contains('conferir'));

      final (st2, editada) = await chamar('PUT', '/api/palavras/$id', token: admin, json: {
        'texto': '$texto\n\nVenha à mesa.',
        'decisoes': {
          'Romanos 5.8': {'status': 'confirmada'},
          'Salmo 23': {'status': 'confirmada', 'ajuste': 'Sl 23.1-6'},
        },
        'pronta': true,
      });
      expect(st2, 200, reason: '$editada');
      expect(editada['situacao'], 'pronta');
      expect((editada['versoes'] as List).single['texto'], texto);

      // Só muda as decisões: não cria versão nova.
      final (_, mesma) = await chamar('PUT', '/api/palavras/$id', token: admin, json: {'minutos': 35});
      expect((mesma['versoes'] as List).length, 1);

      expect((await chamar('GET', '/api/palavras', token: telao)).$1, 403);
      final (st3, doDia) = await chamar('GET', '/api/palavras/hoje', token: telao);
      expect(st3, 200);
      final culto = PalavraDoCulto.fromJson(Map<String, dynamic>.from(doDia['palavra'] as Map));
      expect(culto.minutos, 35);
      expect(culto.topicos.single.$1, 'A mesa');
      expect(culto.trechos.expand((t) => t.referencias).map((r) => r.ref!.abreviada), ['Rm 5.8', 'Sl 23.1-6']);
      expect(culto.trechos.first.referencias.single.ref!.ids, ['45005008']);
    });

    test('prévia no editor e importação pelo painel', () async {
      final (st, previa) = await chamar('POST', '/api/palavras/analisar', token: admin, json: {'texto': 'Leia Jo 3.16.\n\nE Os 6.6.'});
      expect(st, 200);
      expect([for (final t in previa['trechos'] as List) (t['referencias'] as List).single['ref']], ['Jo 3.16', 'Os 6.6']);

      final r = await handler(Request('POST', Uri.parse('http://x/api/palavras/importar?nome=sermao.docx'),
          headers: {'authorization': 'Bearer $admin'}, body: docx('<w:p><w:r><w:t>Graça e paz.</w:t></w:r></w:p>')));
      expect(r.statusCode, 200);
      expect(jsonDecode(await r.readAsString())['texto'], 'Graça e paz.');

      final (stG, google) = await chamar('POST', '/api/palavras/google', token: admin, json: {'link': 'https://docs.google.com/document/d/x'});
      expect(stG, 400);
      expect(google['erro'], contains('Administração › Agenda'));

      final pdf = await handler(Request('POST', Uri.parse('http://x/api/palavras/importar?nome=a.pdf'),
          headers: {'authorization': 'Bearer $admin'}, body: [37, 80, 68, 70]));
      expect(pdf.statusCode, 400);
    });
  });
}
