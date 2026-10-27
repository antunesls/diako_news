import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:diako_server/agente/agente.dart';
import 'package:diako_server/agente_hub.dart';
import 'package:diako_server/app.dart';
import 'package:diako_server/auth.dart';
import 'package:diako_server/backup.dart';
import 'package:diako_server/backup_cifrado.dart';
import 'package:diako_server/cartazes.dart';
import 'package:diako_server/config.dart';
import 'package:diako_server/historico.dart';
import 'package:diako_server/qr_oracao.dart';
import 'package:diako_server/store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const senha = 'senha-forte-123';
const chaveAgente = 'chave-do-agente-com-mais-de-24-caracteres';
final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3]);

/// Espera até [cond] ser verdadeira (ou falha após [limite]).
Future<void> ate(bool Function() cond, {Duration limite = const Duration(seconds: 5)}) async {
  final fim = DateTime.now().add(limite);
  while (!cond()) {
    if (DateTime.now().isAfter(fim)) throw TimeoutException('condição não atingida');
    await Future.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  group('Config', () {
    test('monitor exige porta válida e backend não aceita credenciais na URL', () {
      expect(() => AgenteConfig.lerJson('{"servidor":"https://usuario:segredo@exemplo.org",'
          '"chaveAgente":"chave","pastaImagensHolyrics":"X:/img"}'), throwsFormatException);
      expect(() => AgenteConfig.lerJson('{"servidor":"https://exemplo.org",'
          '"chaveAgente":"chave","pastaImagensHolyrics":"X:/img","monitor":{"porta":70000}}'),
          throwsFormatException);
    });
    test('cópia do backup: ligada por padrão, pasta e quantidade configuráveis', () {
      const base = '{"servidor":"https://exemplo.org","chaveAgente":"chave","pastaImagensHolyrics":"X:/img"';
      final padrao = AgenteConfig.lerJson('$base}');
      expect([padrao.pastaBackup, padrao.backupsManter], ['', 7]);
      expect(Agente(padrao, pastaDados: p.join('C:', 'DiakoNews')).pastaBackup, p.join('C:', 'DiakoNews', 'backups-servidor'));
      final drive = AgenteConfig.lerJson('$base,"backup":{"pasta":"G:/Meu Drive/Backup","manter":3}}');
      expect(Agente(drive).pastaBackup, 'G:/Meu Drive/Backup');
      expect(drive.backupsManter, 3);
      expect(Agente(AgenteConfig.lerJson('$base,"backup":{"manter":0}}'), pastaDados: 'C:/DiakoNews').pastaBackup, isNull);
      expect(() => AgenteConfig.lerJson('$base,"backup":{"manter":-1}}'), throwsFormatException);
    });
    test('modo agente exige chave longa e senha de 10+', () {
      expect(() => Config.lerJson('{"senhaAdmin":"1234567890","holyrics":{"modo":"agente"}}', pastaBase: '.'),
          throwsFormatException);
      expect(
          () => Config.lerJson('{"senhaAdmin":"curta12","chaveAgente":"$chaveAgente","holyrics":{"modo":"agente"}}',
              pastaBase: '.'),
          throwsFormatException);
      final c = Config.lerJson(
          '\uFEFF{"senhaAdmin":"1234567890","chaveAgente":"$chaveAgente","holyrics":{"modo":"agente"},'
          '"pastaImagensHolyrics":"X:/img","urlPublica":"https://d.com/"}',
          pastaBase: '/opt/diako');
      expect(c.modoHolyrics, ModoHolyrics.agente);
      expect(c.pastaCartazes, p.join('/opt/diako', 'data', 'cartazes')); // no modo agente, sempre em data/
      expect(c.urlPublica, 'https://d.com');
    });

    test('modo local continua igual', () {
      final c = Config.lerJson('{"senhaAdmin":"123456","pastaImagensHolyrics":"X:/img"}', pastaBase: '.');
      expect(c.modoHolyrics, ModoHolyrics.local);
      expect(c.pastaCartazes, p.join('X:/img', 'Diako'));
      expect(c.endereco, '0.0.0.0');
    });
  });

  test('histórico do monitor é limitado e estado não contém credenciais', () {
    final a = Agente(AgenteConfig(servidor: 'https://exemplo.org', chaveAgente: 'segredo-agente',
        holyricsToken: 'segredo-holyrics', pastaImagensHolyrics: Directory.systemTemp.path));
    for (var i = 0; i < 220; i++) { a.registrar('backend', 'Evento $i'); }
    a.registrar('backend', 'token=segredo-holyrics chave=segredo-agente');
    expect(a.eventos.length, 200);
    expect(a.eventos.first['mensagem'], 'Evento 21');
    expect(a.eventos.last['mensagem'], isNot(contains('segredo')));
    final estado = jsonEncode(a.estado);
    expect(estado, isNot(contains('segredo-agente')));
    expect(estado, isNot(contains('segredo-holyrics')));
  });

  test('ipDe usa X-Forwarded-For só com confiarProxy', () {
    final req = Request('GET', Uri.parse('http://x/'), headers: {'x-forwarded-for': '200.1.2.3, 10.0.0.1'});
    expect(ipDe(req, confiarProxy: true), '200.1.2.3');
    expect(ipDe(req), 'desconhecido');
  });

  group('SincronizadorCartazes', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('diako_sync'));
    tearDown(() => tmp.delete(recursive: true));

    test('baixa novos, troca alterados, apaga removidos e respeita a pasta', () async {
      final pasta = p.join(tmp.path, 'Diako');
      final baixados = <String>[];
      final sync = SincronizadorCartazes(pasta: pasta, baixar: (n) async {
        baixados.add(n);
        return utf8.encode('conteudo-$n');
      });
      final data = DateTime.utc(2026, 10, 20, 12);
      await Directory(pasta).create(recursive: true);
      await File(p.join(pasta, 'velho.png')).writeAsString('x');
      await File(p.join(pasta, 'anotacoes.txt')).writeAsString('não é imagem: fica');
      await File(p.join(tmp.path, 'fora.png')).writeAsString('fora da pasta: fica');

      final r1 = await sync.sincronizar([
        {'nome': 'retiro.png', 'tamanho': 19, 'modificado': data.toIso8601String()},
        {'nome': '../escapar.png', 'tamanho': 1, 'modificado': data.toIso8601String()},
      ]);
      expect(r1.baixados, ['retiro.png']);
      expect(r1.apagados, ['velho.png']);
      expect(File(p.join(pasta, 'anotacoes.txt')).existsSync(), isTrue);
      expect(File(p.join(tmp.path, 'fora.png')).existsSync(), isTrue);
      expect(File(p.join(tmp.path, 'escapar.png')).existsSync(), isFalse);

      // Mesmo tamanho e data: não baixa de novo.
      baixados.clear();
      final r2 = await sync.sincronizar([
        {'nome': 'retiro.png', 'tamanho': 19, 'modificado': data.toIso8601String()},
      ]);
      expect(r2.baixados, isEmpty);

      // Data diferente: baixa de novo.
      final r3 = await sync.sincronizar([
        {'nome': 'retiro.png', 'tamanho': 19, 'modificado': data.add(const Duration(hours: 1)).toIso8601String()},
      ]);
      expect(r3.baixados, ['retiro.png']);
    });
  });

  group('HolyricsViaAgente', () {
    test('sem agente responde erro no formato do Holyrics', () async {
      final r = await HolyricsViaAgente().chamar('GetCPInfo', '{}');
      expect(jsonDecode(r.corpo), {'status': 'error', 'error': contains('desconectado')});
    });

    test('agente que não responde vira timeout', () async {
      final hub = HolyricsViaAgente(timeout: const Duration(milliseconds: 200));
      final srv = await io.serve(webSocketHandler((WebSocketChannel c, String? _) => hub.conectar(c)),
          InternetAddress.loopbackIPv4, 0);
      final mudo = WebSocketChannel.connect(Uri.parse('ws://127.0.0.1:${srv.port}'));
      await mudo.ready;
      await ate(() => hub.agenteConectado);
      final r = await hub.chamar('ShowImage', '{"file":"x"}');
      expect(jsonDecode(r.corpo)['error'], contains('não respondeu'));
      await mudo.sink.close();
      await srv.close(force: true);
    });
  });

  group('servidor na internet + agente no PC da igreja', () {
    late Directory tmp;
    late Store store;
    late HttpServer http_;
    late HolyricsViaAgente hub;
    late String base;
    late List<http.Request> chamadasHolyrics;
    late Agente agente;
    late String token;
    final logs = <String>[];

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('diako_agente');
      final dados = p.join(tmp.path, 'servidor', 'data');
      final web = Directory(p.join(tmp.path, 'servidor', 'web'))..createSync(recursive: true);
      File(p.join(web.path, 'mural.html')).writeAsStringSync('<h1>mural</h1>');
      store = Store(dados);
      await store.carregar();
      final auth = Auth(senha: senha, pastaDados: dados);
      final cartazes = Cartazes(p.join(dados, 'cartazes'));
      await gravarQr(cartazes.pasta, 'https://exemplo.org/oracao');
      hub = HolyricsViaAgente();
      final backup = Backup(pastaDados: dados);
      final servidor = Servidor(
        store: store,
        auth: auth,
        holyrics: hub,
        cartazes: cartazes,
        backup: backup,
        pastaWeb: web.path,
        urlOracao: 'https://exemplo.org/oracao',
        cartazesNoHolyrics: false,
        historico: Historico(dados),
        agente: hub,
        chaveAgente: chaveAgente,
        chaveMural: 'chave-mural',
        confiarProxy: true,
        senhaBackup: SenhaBackup(dados, iteracoes: 1000),
        restauracao: Restauracao(store: store, backup: backup, pastaDados: dados, pastaCartazes: cartazes.pasta),
      );
      http_ = await io.serve(servidor.handler, InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${http_.port}';

      chamadasHolyrics = [];
      final holyricsFalso = MockClient((req) async {
        chamadasHolyrics.add(req);
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });
      agente = Agente(
        AgenteConfig(
          servidor: base,
          chaveAgente: chaveAgente,
          holyricsToken: 'tk',
          pastaImagensHolyrics: p.join(tmp.path, 'igreja', 'imagens'),
          pastaBackup: p.join(tmp.path, 'igreja', 'backups'),
          backupsManter: 2,
        ),
        clienteHolyrics: holyricsFalso,
        log: logs.add,
      );
      unawaited(agente.rodar());
      await ate(() => hub.agenteConectado);

      final r = await http.post(Uri.parse('$base/api/login'), body: jsonEncode({'senha': senha}));
      token = (jsonDecode(r.body) as Map)['token'] as String;
    });

    tearDown(() async {
      await agente.parar();
      await http_.close(force: true);
      await store.fechar();
      await tmp.delete(recursive: true);
    });

    Map<String, String> auth() => {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
    String pastaIgreja(String nome) => p.join(tmp.path, 'igreja', 'imagens', 'Diako', nome);

    test('comando do tablet chega ao Holyrics da igreja pelo agente', () async {
      final r = await http.post(Uri.parse('$base/api/holyrics/ShowQuickPresentation'),
          headers: auth(), body: jsonEncode({'text': 'Oração'}));
      expect(jsonDecode(r.body), {'status': 'ok'});
      expect(chamadasHolyrics.single.url.toString(), 'http://127.0.0.1:8091/api/ShowQuickPresentation?token=tk');
      expect(jsonDecode(chamadasHolyrics.single.body), {'text': 'Oração'});

      final estado = jsonDecode((await http.get(Uri.parse('$base/api/estado'), headers: auth())).body) as Map;
      expect(estado['modo'], 'agente');
      expect(estado['agenteConectado'], isTrue);
      expect(estado['holyricsConectado'], isTrue);
    });

    test('QR e cartazes vão para a pasta de imagens da igreja e somem quando apagados', () async {
      await ate(() => File(pastaIgreja(arquivoQr)).existsSync());
      await http.post(Uri.parse('$base/api/cartazes?nome=retiro.png'), headers: auth(), body: png);
      await ate(() => File(pastaIgreja('retiro.png')).existsSync());
      expect(File(pastaIgreja('retiro.png')).readAsBytesSync(), png);

      await http.delete(Uri.parse('$base/api/cartazes/retiro.png'), headers: auth());
      await ate(() => !File(pastaIgreja('retiro.png')).existsSync());
      expect(File(pastaIgreja(arquivoQr)).existsSync(), isTrue);
    });

    test('backup vai cifrado para o PC da igreja só depois de definida a senha', () async {
      const senhaBk = 'senha do backup da igreja';
      final noServidor = p.join(tmp.path, 'servidor', 'data', 'backups');
      final noPc = p.join(tmp.path, 'igreja', 'backups');
      await Directory(noServidor).create(recursive: true);
      await Directory(noPc).create(recursive: true);
      final zipFalso = [0x50, 0x4B, 0x03, 0x04, 1, 2, 3];
      for (final dia in ['20', '21']) {
        await File(p.join(noServidor, 'diako-backup-2026-10-$dia.zip')).writeAsBytes(zipFalso);
      }
      await File(p.join(noPc, 'diako-backup-2026-10-01.zip.cifrado')).writeAsBytes([1]); // velho: sai
      await File(p.join(noPc, 'leia-me.txt')).writeAsString('não é backup'); // fica
      Future<Map> backups() async => jsonDecode((await http.get(Uri.parse('$base/api/backups'), headers: auth())).body) as Map;

      await store.salvar('recados', {'id': 'r1', 'titulo': 'Culto de domingo'});
      // Sem senha do backup, nada sai do servidor: a cópia fica desligada e o painel avisa.
      final r = await http.post(Uri.parse('$base/api/backup'), headers: auth());
      final nome = (jsonDecode(r.body) as Map)['nome'] as String;
      await ate(() => (agente.estado['erroBackup'] as String? ?? '').contains('senha do backup'));
      expect(File(p.join(noPc, '$nome.cifrado')).existsSync(), isFalse);
      expect((await backups())['alertas'].single, contains('Defina a senha do backup'));
      expect((await backups())['senhaDefinidaEm'], isNull);

      final curta = await http.put(Uri.parse('$base/api/backup/senha'), headers: auth(), body: jsonEncode({'senha': 'curta'}));
      expect(curta.statusCode, 400);
      final ok = await http.put(Uri.parse('$base/api/backup/senha'), headers: auth(), body: jsonEncode({'senha': senhaBk}));
      expect(ok.statusCode, 200);

      // Definida a senha, o agente copia sozinho os 2 mais novos (backupsManter), cifrados.
      await ate(() => File(p.join(noPc, '$nome.cifrado')).existsSync() &&
          !File(p.join(noPc, 'diako-backup-2026-10-01.zip.cifrado')).existsSync());
      expect(Directory(noPc).listSync().map((e) => p.basename(e.path)).toSet(),
          {'$nome.cifrado', 'diako-backup-2026-10-21.zip.cifrado', 'leia-me.txt'});
      final copia = File(p.join(noPc, '$nome.cifrado')).readAsBytesSync();
      final original = File(p.join(noServidor, nome)).readAsBytesSync();
      expect(copia.sublist(0, 2), isNot([0x50, 0x4B])); // não é um zip aberto
      expect(decifrarBackup(copia, senhaBk), original);

      for (var i = 0; i < 50 && (await backups())['copiaPc'] == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      final b = await backups();
      expect(b['copiaPc'], isNotNull);
      expect(b['senhaDefinidaEm'], isNotNull);
      expect(b['alertas'], isEmpty);
      final estado = jsonDecode((await http.get(Uri.parse('$base/api/estado'), headers: auth())).body) as Map;
      expect(estado['alertasBackup'], isEmpty);
      expect(estado['copiaBackupPc'], isNotNull);
      expect(agente.estado['ultimoBackupCopiado'], nome);

      // A chave só vale no cabeçalho nas rotas de backup (nunca na URL, que vai para logs).
      Future<int> get(String caminho, [Map<String, String>? h]) async =>
          (await http.get(Uri.parse('$base/agente/$caminho'), headers: h)).statusCode;
      expect(await get('backups'), 401);
      expect(await get('backups?chave=$chaveAgente'), 401);
      expect(await get('backups/$nome?chave=$chaveAgente'), 401);
      expect(await get('backups', {'x-chave-agente': 'errada'}), 401);
      expect(await get('backups', {'x-chave-agente': chaveAgente}), 200);
      expect(await get('backups/..%2Fusuarios.json', {'x-chave-agente': chaveAgente}), 404);

      // Restaurar a cópia do PC no /admin exige a senha (no cabeçalho).
      Future<http.Response> restaurar([String? s]) => http.post(Uri.parse('$base/api/backups/restaurar'),
          headers: {...auth(), 'Content-Type': 'application/zip', if (s != null) 'x-senha-backup': s}, body: copia);
      expect((await restaurar()).body, contains('digite a senha'));
      expect((await restaurar('senha errada de novo')).body, contains('errada'));
      final restaurado = await restaurar(senhaBk);
      expect(restaurado.statusCode, 200, reason: restaurado.body);

      // Sem senha de novo: a cópia volta a ficar desligada.
      expect((await http.delete(Uri.parse('$base/api/backup/senha'), headers: auth())).statusCode, 200);
      expect(await get('backups', {'x-chave-agente': chaveAgente}), 409);
    });

    test('agente desconectado vira aviso; chave errada é recusada', () async {
      await agente.parar();
      await ate(() => !hub.agenteConectado);
      final r = await http.post(Uri.parse('$base/api/holyrics/GetCPInfo'), headers: auth(), body: '{}');
      expect((jsonDecode(r.body) as Map)['error'], contains('desconectado'));

      expect((await http.get(Uri.parse('$base/agente/cartazes?chave=errada'))).statusCode, 401);
      expect((await http.get(Uri.parse('$base/agente/cartazes'))).statusCode, 401);
      expect((await http.get(Uri.parse('$base/agente/cartazes/$arquivoQr?chave=errada'))).statusCode, 401);
    });

    test('mural exige a chave; cabeçalhos de segurança', () async {
      expect((await http.get(Uri.parse('$base/mural'))).statusCode, 403);
      expect((await http.get(Uri.parse('$base/api/public/mural'))).statusCode, 403);
      final ok = await http.get(Uri.parse('$base/mural?chave=chave-mural'));
      expect(ok.statusCode, 200);
      expect(ok.headers['x-content-type-options'], 'nosniff');
      expect(ok.headers['content-security-policy'], contains("frame-ancestors 'none'"));
      expect((await http.get(Uri.parse('$base/api/public/mural?chave=chave-mural'))).statusCode, 200);
    });
  });
}
