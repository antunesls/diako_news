import 'dart:convert';
import 'dart:io';

import 'package:diako_news/holyrics/agente_local.dart';
import 'package:diako_news/holyrics/holyrics_client.dart';
import 'package:diako_news/sync/server_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late List<http.Request> pedidosServidor;
  late List<http.Request> pedidosLocal;
  late DateTime agora;

  ServerApi api() => ServerApi(
        () => const ServidorConfig(base: 'https://diako.igreja.org', sessao: 'sess'),
        httpClient: MockClient((req) async {
          pedidosServidor.add(req);
          return http.Response(jsonEncode({'status': 'ok', 'data': 'servidor'}), 200);
        }),
      );

  AgenteLocal local(Future<http.Response> Function(http.Request req) responder, {String token = 'tk'}) => AgenteLocal(
        () => (base: 'http://192.168.0.20:8097', token: token),
        httpClient: MockClient((req) {
          pedidosLocal.add(req);
          return responder(req);
        }),
        relogio: () => agora,
      );

  setUp(() {
    pedidosServidor = [];
    pedidosLocal = [];
    agora = DateTime(2026, 10, 26, 19);
  });

  test('normalizarAgenteLocal completa esquema e porta 8097', () {
    expect(normalizarAgenteLocal('192.168.0.20'), 'http://192.168.0.20:8097');
    expect(normalizarAgenteLocal(' 192.168.0.20:9000/ '), 'http://192.168.0.20:9000');
    expect(normalizarAgenteLocal('http://pc-igreja'), 'http://pc-igreja:8097');
    expect(normalizarAgenteLocal(''), '');
  });

  test('pareado: vai pela rede local com o token, sem passar pelo servidor', () async {
    final l = local((_) async => http.Response(jsonEncode({'status': 'ok', 'data': 'local'}), 200));
    final c = HolyricsClient(api(), local: l);
    await c.projetarTexto('Bem-vindos');
    expect(pedidosServidor, isEmpty);
    expect(pedidosLocal.single.url.toString(), 'http://192.168.0.20:8097/holyrics/ShowQuickPresentation');
    expect(pedidosLocal.single.headers['Authorization'], 'Bearer tk');
    expect(jsonDecode(pedidosLocal.single.body), {'text': 'Bem-vindos'});
    expect(l.ultimoCaminho, 'rede local');
  });

  test('PC não responde: usa a internet e só tenta a rede local de novo depois da pausa', () async {
    final l = local((_) async => throw const SocketException('sem rota'));
    final c = HolyricsClient(api(), local: l);
    await c.testar();
    expect(pedidosLocal, hasLength(1));
    expect(pedidosServidor, hasLength(1));
    expect(l.ultimoCaminho, 'internet');

    await c.testar(); // ainda na pausa: direto pela internet, sem esperar o PC
    expect(pedidosLocal, hasLength(1));
    expect(pedidosServidor, hasLength(2));

    agora = agora.add(AgenteLocal.pausa + const Duration(seconds: 1));
    await c.testar();
    expect(pedidosLocal, hasLength(2));
  });

  test('token recusado (pareamento removido): avisa e usa a internet', () async {
    final l = local((_) async => http.Response(jsonEncode({'erro': 'Tablet não pareado com este PC.'}), 401));
    final c = HolyricsClient(api(), local: l);
    await c.testar();
    expect(l.recusado, isTrue);
    expect(pedidosServidor, hasLength(1));
  });

  test('erro do próprio Holyrics pela rede local não repete pela internet', () async {
    // O agente responde em UTF-8 (application/json; charset=utf-8).
    final l = local((_) async =>
        http.Response.bytes(utf8.encode(jsonEncode({'status': 'error', 'error': 'Holyrics não respondeu.'})), 200));
    final c = HolyricsClient(api(), local: l);
    await expectLater(c.testar(), throwsA(isA<HolyricsException>()));
    expect(pedidosServidor, isEmpty);
  });

  test('sem pareamento: só internet, como antes', () async {
    final l = local((_) async => http.Response('{}', 200), token: '');
    final c = HolyricsClient(api(), local: l);
    await c.testar();
    expect(pedidosLocal, isEmpty);
    expect(pedidosServidor, hasLength(1));
    expect(l.ultimoCaminho, isNull);
  });

  test('testar: 401 vira aviso de pareamento pendente', () async {
    final l = local((_) async => http.Response('{}', 401));
    await expectLater(l.testar(), throwsA(isA<ServidorException>().having((e) => e.naoAutorizado, 'naoAutorizado', isTrue)));
    final ok = local((_) async => http.Response(jsonEncode({'ok': true}), 200));
    expect(await ok.testar(), greaterThanOrEqualTo(0));
    expect(pedidosLocal.last.url.path, '/ping');
  });
}
