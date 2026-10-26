import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:diako_server/app.dart';
import 'package:diako_server/auth.dart';
import 'package:diako_server/backup.dart';
import 'package:diako_server/cartazes.dart';
import 'package:diako_server/config.dart';
import 'package:diako_server/configuracoes.dart';
import 'package:diako_server/historico.dart';
import 'package:diako_server/holyrics.dart';
import 'package:diako_server/qr_oracao.dart';
import 'package:diako_server/store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 9, 9]);

late Directory tmp;
late Store store;
late Configuracoes cfg;
late Handler handler;
late List<http.Request> chamadasHolyrics;
late String token;
late String pastaCartazes;
late String pastaBackups;

Future<void> criar() async {
  final config = Config.lerJson(
    '{"senhaAdmin":"senha-inicial","holyrics":{"token":"tk-velho"},"chaveMural":"m1"}',
    pastaBase: tmp.path,
  );
  store = Store(config.pastaDados);
  await store.carregar();
  cfg = await Configuracoes.carregar(config, urlDetectada: 'http://192.168.0.10:8080');
  final auth = Auth(conferirSenha: cfg.conferirSenha, pastaDados: config.pastaDados);
  await auth.carregar();
  pastaCartazes = config.pastaCartazes;
  pastaBackups = p.join(config.pastaDados, 'backups');
  await gravarQr(pastaCartazes, cfg.urlOracao);
  final web = Directory(p.join(tmp.path, 'web'))..createSync(recursive: true);
  for (final f in ['mural.html', 'admin.html']) {
    File(p.join(web.path, f)).writeAsStringSync('<h1>$f</h1>');
  }
  chamadasHolyrics = [];
  final backup = Backup(
    pastaDados: config.pastaDados,
    pastaCartazes: pastaCartazes,
    manter: () => cfg.backupsManter,
    configuracoes: cfg.publicas,
  );
  handler = Servidor(
    store: store,
    auth: auth,
    holyrics: HolyricsDireto(
      host: cfg.holyricsHost,
      porta: cfg.holyricsPorta,
      token: cfg.holyricsToken,
      cliente: MockClient((req) async {
        chamadasHolyrics.add(req);
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      }),
    ),
    cartazes: Cartazes(pastaCartazes),
    backup: backup,
    pastaWeb: web.path,
    urlOracao: cfg.urlOracao,
    cartazesNoHolyrics: false,
    historico: Historico(config.pastaDados),
    cfg: cfg,
    senhaMinima: 10,
    restauracao: Restauracao(
      store: store,
      backup: backup,
      pastaDados: config.pastaDados,
      pastaCartazes: pastaCartazes,
      aplicarConfiguracoes: cfg.restaurarPublicas,
    ),
  ).handler;
}

Future<Response> req(String metodo, String caminho, {Object? json, List<int>? bytes, String? comToken}) {
  final headers = <String, String>{'authorization': 'Bearer ${comToken ?? token}'};
  Object? body;
  if (json != null) {
    body = jsonEncode(json);
    headers['content-type'] = 'application/json';
  } else {
    body = bytes;
  }
  return Future.sync(() => handler(Request(metodo, Uri.parse('http://localhost$caminho'), headers: headers, body: body)));
}

Future<dynamic> corpo(Response r) async => jsonDecode(await r.readAsString());

Future<String> logar(String senha) async {
  final r = await handler(Request('POST', Uri.parse('http://localhost/api/login'), body: jsonEncode({'senha': senha})));
  return r.statusCode == 200 ? (await corpo(r))['token'] as String : '';
}

void main() {
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('diako_admin');
    await criar();
    token = await logar('senha-inicial');
  });
  tearDown(() async {
    await store.fechar();
    await tmp.delete(recursive: true);
  });

  group('configurações', () {
    test('exigem login e não expõem segredos', () async {
      expect((await req('GET', '/api/admin/configuracoes', comToken: 'x')).statusCode, 401);
      final c = await corpo(await req('GET', '/api/admin/configuracoes')) as Map;
      expect(c['nomeIgreja'], 'Igreja Diakonia Tulipas');
      expect(c['holyricsTokenDefinido'], isTrue);
      expect(c.containsKey('holyricsToken'), isFalse);
      expect(c.containsKey('senhaHash'), isFalse);
      expect(c['sessoes'], 1);
    });

    test('salvar valida, persiste e aparece no site público', () async {
      final r = await req('PUT', '/api/admin/configuracoes', json: {
        'nomeIgreja': 'Igreja Teste',
        'pedidoIntro': 'Escreva seu pedido.',
        'motivosPorSlide': 5,
        'horaBackup': '04:30',
      });
      expect(r.statusCode, 200);
      expect((await req('PUT', '/api/admin/configuracoes', json: {'motivosPorSlide': 99})).statusCode, 400);
      expect((await req('PUT', '/api/admin/configuracoes', json: {'horaBackup': '25:00'})).statusCode, 400);
      expect((await req('PUT', '/api/admin/configuracoes', json: {'urlPublica': 'ftp://x'})).statusCode, 400);
      expect((await req('PUT', '/api/admin/configuracoes', json: {'campoInventado': 1})).statusCode, 400);

      final site = await corpo(await handler(Request('GET', Uri.parse('http://localhost/api/public/site')))) as Map;
      expect(site['nomeIgreja'], 'Igreja Teste');
      expect(site['pedidoIntro'], 'Escreva seu pedido.');

      // Recarrega do disco.
      await store.fechar();
      await criar();
      expect(cfg.nomeIgreja, 'Igreja Teste');
      expect(cfg.motivosPorSlide, 5);
      expect(cfg.horaBackup, '04:30');
    });

    test('token do Holyrics novo vale na hora; vazio mantém o atual', () async {
      await req('PUT', '/api/admin/configuracoes', json: {'holyricsToken': 'tk-novo', 'holyricsPorta': 9000});
      await req('POST', '/api/admin/testar-holyrics');
      expect(chamadasHolyrics.last.url.toString(), 'http://127.0.0.1:9000/api/GetCPInfo?token=tk-novo');
      await req('PUT', '/api/admin/configuracoes', json: {'holyricsToken': ''});
      await req('POST', '/api/admin/testar-holyrics');
      expect(chamadasHolyrics.last.url.queryParameters['token'], 'tk-novo');
    });

    test('endereço público novo refaz o QR', () async {
      final antes = File(p.join(pastaCartazes, arquivoQr)).readAsBytesSync();
      await req('PUT', '/api/admin/configuracoes', json: {'urlPublica': 'https://diako.exemplo.org/'});
      final estado = await corpo(await req('GET', '/api/estado')) as Map;
      expect(estado['urlOracao'], 'https://diako.exemplo.org/oracao');
      expect(estado['urlMensagens'], 'https://diako.exemplo.org/mensagens');
      expect(File(p.join(pastaCartazes, arquivoQr)).readAsBytesSync(), isNot(equals(antes)));
      expect(File(p.join(pastaCartazes, arquivoQrMensagens)).existsSync(), isTrue);
    });

    test('SMTP valida dados e mantém senha fora do painel e backup', () async {
      expect((await req('PUT', '/api/admin/configuracoes', json: {'smtpDestinatario': 'inválido'})).statusCode, 400);
      final resposta = await req('PUT', '/api/admin/configuracoes', json: {
        'smtpHost': 'smtp.example.org', 'smtpPorta': 587, 'smtpUsuario': 'equipe',
        'smtpSenha': 'senha-de-aplicativo', 'smtpRemetente': 'caixa@example.org',
        'smtpDestinatario': 'equipe@example.org', 'smtpSsl': false,
      });
      final config = await corpo(resposta) as Map;
      expect(config['smtpConfigurado'], true);
      expect(config['smtpSenhaDefinida'], true);
      expect(config.containsKey('smtpSenha'), false);
      await req('PUT', '/api/admin/configuracoes', json: {'smtpSenha': ''});
      expect(cfg.smtpSenha, 'senha-de-aplicativo');
      final zip = await Backup(pastaDados: store.pasta, configuracoes: cfg.publicas).gerarZip();
      expect(utf8.decode(ZipDecoder().decodeBytes(zip).findFile('configuracoes.json')!.content),
          isNot(contains('senha-de-aplicativo')));
    });

    test('chave do mural: gerar nova e desativar', () async {
      final nova = (await corpo(await req('POST', '/api/admin/chave', json: {'tipo': 'mural'})))['chaveMural'] as String;
      expect(nova, isNot('m1'));
      Future<int> mural(String q) async => (await handler(Request('GET', Uri.parse('http://localhost/mural$q')))).statusCode;
      expect(await mural('?chave=m1'), 403);
      expect(await mural('?chave=$nova'), 200);
      await req('POST', '/api/admin/chave', json: {'tipo': 'mural-desativar'});
      expect(await mural(''), 200);
      // Chave do agente só existe no modo agente.
      expect((await req('POST', '/api/admin/chave', json: {'tipo': 'agente'})).statusCode, 400);
    });
  });

  group('senha e sessões', () {
    test('trocar senha encerra os outros aparelhos e vale após reiniciar', () async {
      final outro = await logar('senha-inicial');
      expect((await req('POST', '/api/admin/senha', json: {'atual': 'errada', 'nova': 'nova-senha-123'})).statusCode, 403);
      expect((await req('POST', '/api/admin/senha', json: {'atual': 'senha-inicial', 'nova': 'curta'})).statusCode, 400);
      final r = await corpo(await req('POST', '/api/admin/senha', json: {'atual': 'senha-inicial', 'nova': 'nova-senha-123'}));
      expect(r['sessoesEncerradas'], 1);
      expect((await req('GET', '/api/recados')).statusCode, 200); // quem trocou continua
      expect((await req('GET', '/api/recados', comToken: outro)).statusCode, 401);
      expect(await logar('senha-inicial'), isEmpty);

      await store.fechar();
      await criar();
      expect(await logar('nova-senha-123'), isNotEmpty);
      expect(File(p.join(tmp.path, 'data', 'configuracoes.json')).readAsStringSync(), isNot(contains('nova-senha-123')));
    });

    test('desconectar todos os aparelhos', () async {
      final outro = await logar('senha-inicial');
      final r = await corpo(await req('POST', '/api/admin/sessoes/encerrar'));
      expect(r['sessoesEncerradas'], 1);
      expect((await req('GET', '/api/recados', comToken: outro)).statusCode, 401);
      expect((await req('GET', '/api/recados')).statusCode, 200);
    });
  });

  group('backup e restauração', () {
    test('baixar na hora traz dados, cartazes e configurações sem segredos', () async {
      await req('POST', '/api/recados', json: {'titulo': 'Santa Ceia'});
      await req('POST', '/api/cartazes?nome=retiro.png', bytes: png);
      final r = await req('GET', '/api/backups/agora/download');
      expect(r.headers['content-type'], 'application/zip');
      final zip = ZipDecoder().decodeBytes(await r.read().expand((b) => b).toList());
      expect(utf8.decode(zip.findFile('data/recados.json')!.content), contains('Santa Ceia'));
      expect(zip.findFile('cartazes/retiro.png'), isNotNull);
      expect(zip.findFile('cartazes/$arquivoQr'), isNull);
      final cfgZip = utf8.decode(zip.findFile('configuracoes.json')!.content);
      expect(cfgZip, isNot(contains('tk-velho')));
      expect(jsonDecode(utf8.decode(zip.findFile('manifest.json')!.content))['versao'], versaoBackup);
    });

    test('restaurar da lista volta ao estado do backup e guarda um backup de segurança', () async {
      final a = await corpo(await req('POST', '/api/recados', json: {'titulo': 'Antes'}));
      await req('POST', '/api/cartazes?nome=retiro.png', bytes: png);
      final nome = (await corpo(await req('POST', '/api/backup')))['nome'] as String;

      await req('DELETE', '/api/recados/${a['id']}');
      await req('POST', '/api/recados', json: {'titulo': 'Depois'});
      await req('DELETE', '/api/cartazes/retiro.png');
      await req('POST', '/api/cartazes?nome=novo.png', bytes: png);

      final resumo = await corpo(await req('POST', '/api/backups/$nome/restaurar', json: {})) as Map;
      expect(resumo['colecoes']['recados'], 1);
      expect(resumo['cartazes'], 1);
      expect(resumo['backupSeguranca'], contains('antes-restauracao'));

      final recados = await corpo(await req('GET', '/api/recados')) as List;
      expect(recados.map((r) => r['titulo']), ['Antes']);
      expect(File(p.join(pastaCartazes, 'retiro.png')).existsSync(), isTrue);
      expect(File(p.join(pastaCartazes, 'novo.png')).existsSync(), isFalse);
      expect(File(p.join(pastaCartazes, arquivoQr)).existsSync(), isTrue); // QR nunca é apagado

      final lista = (await corpo(await req('GET', '/api/backups')))['backups'] as List;
      expect(lista.map((b) => b['nome']), contains(resumo['backupSeguranca']));
    });

    test('restaurar de arquivo enviado, com e sem configurações', () async {
      await req('PUT', '/api/admin/configuracoes', json: {'nomeIgreja': 'Do backup'});
      await req('POST', '/api/membros', json: {'nome': 'Ana', 'dia': 1, 'mes': 2});
      final zip = await (await req('GET', '/api/backups/agora/download')).read().expand((b) => b).toList();

      await req('PUT', '/api/admin/configuracoes', json: {'nomeIgreja': 'Atual'});
      final membros = await corpo(await req('GET', '/api/membros')) as List;
      await req('DELETE', '/api/membros/${membros.single['id']}');

      await req('POST', '/api/backups/restaurar', bytes: zip);
      expect((await corpo(await req('GET', '/api/membros')) as List).single['nome'], 'Ana');
      expect(cfg.nomeIgreja, 'Atual'); // sem ?configuracoes=1 mantém as atuais

      await req('POST', '/api/backups/restaurar?configuracoes=1', bytes: zip);
      expect(cfg.nomeIgreja, 'Do backup');
      expect(cfg.holyricsToken, 'tk-velho'); // segredos nunca vêm do backup
    });

    test('arquivo inválido ou com dados quebrados não muda nada', () async {
      await req('POST', '/api/recados', json: {'titulo': 'Fica'});
      expect((await req('POST', '/api/backups/restaurar', bytes: utf8.encode('não é zip'))).statusCode, 400);

      final quebrado = Archive()..add(ArchiveFile.string('data/recados.json', '{"isso": "não é lista"}'));
      final r = await req('POST', '/api/backups/restaurar', bytes: ZipEncoder().encodeBytes(quebrado));
      expect(r.statusCode, 400);
      expect((await corpo(r))['erro'], contains('recados.json'));
      expect((await corpo(await req('GET', '/api/recados')) as List).single['titulo'], 'Fica');

      final vazio = Archive()..add(ArchiveFile.string('leia-me.txt', 'oi'));
      expect((await req('POST', '/api/backups/restaurar', bytes: ZipEncoder().encodeBytes(vazio))).statusCode, 400);
    });

    test('backup antigo (sem cartazes/) mantém os cartazes atuais', () async {
      await req('POST', '/api/cartazes?nome=retiro.png', bytes: png);
      final v1 = Archive()..add(ArchiveFile.string('data/recados.json', '[]'));
      final r = await corpo(await req('POST', '/api/backups/restaurar', bytes: ZipEncoder().encodeBytes(v1)));
      expect(r['cartazes'], 0);
      expect(File(p.join(pastaCartazes, 'retiro.png')).existsSync(), isTrue);
    });

    test('baixar, excluir e nomes estranhos', () async {
      final nome = (await corpo(await req('POST', '/api/backup')))['nome'] as String;
      expect((await req('GET', '/api/backups/$nome/download')).statusCode, 200);
      expect((await req('GET', '/api/backups/..%2Fconfiguracoes.json/download')).statusCode, 404);
      expect((await req('GET', '/api/backups/$nome/download', comToken: 'x')).statusCode, 401);
      expect((await req('DELETE', '/api/backups/$nome')).statusCode, 200);
      expect((await corpo(await req('GET', '/api/backups')))['backups'], isEmpty);
    });

    test('quantidade de backups mantidos é configurável', () async {
      await req('PUT', '/api/admin/configuracoes', json: {'backupsManter': 2});
      final b = Backup(pastaDados: p.join(tmp.path, 'data'), manter: () => cfg.backupsManter);
      for (var d = 1; d <= 4; d++) {
        await b.executar(agora: DateTime(2026, 10, d));
      }
      final nomes = (await b.listar()).map((x) => x.nome);
      expect(nomes, ['diako-backup-2026-10-04.zip', 'diako-backup-2026-10-03.zip']);
      expect(Directory(pastaBackups).existsSync(), isTrue);
    });
  });
}
