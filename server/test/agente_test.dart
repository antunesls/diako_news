import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:diako_server/agente/agente.dart';
import 'package:diako_server/agente_hub.dart';
import 'package:diako_server/app.dart';
import 'package:diako_server/auth.dart';
import 'package:diako_server/backup.dart';
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
      final servidor = Servidor(
        store: store,
        auth: auth,
        holyrics: hub,
        cartazes: cartazes,
        backup: Backup(pastaDados: dados),
        pastaWeb: web.path,
        urlOracao: 'https://exemplo.org/oracao',
        cartazesNoHolyrics: false,
        historico: Historico(dados),
        agente: hub,
        chaveAgente: chaveAgente,
        chaveMural: 'chave-mural',
        confiarProxy: true,
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
