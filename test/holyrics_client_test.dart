import 'dart:convert';

import 'package:diako_news/holyrics/holyrics_client.dart';
import 'package:diako_news/sync/server_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late http.Request ultima;

  ServerApi api(Object? resposta, {int status = 200, ServidorConfig? config}) => ServerApi(
        () => config ?? const ServidorConfig(base: 'http://192.168.0.10:8080', sessao: 'sess'),
        httpClient: MockClient((req) async {
          ultima = req;
          return http.Response.bytes(utf8.encode(jsonEncode(resposta)), status);
        }),
      );

  HolyricsClient cliente(Map<String, dynamic> resposta) => HolyricsClient(api(resposta));
  Map<String, dynamic> corpo() => jsonDecode(ultima.body) as Map<String, dynamic>;

  group('normalizarServidor', () {
    test('completa esquema e porta', () {
      expect(normalizarServidor('192.168.0.10'), 'http://192.168.0.10:8080');
      expect(normalizarServidor(' 192.168.0.10:9000/ '), 'http://192.168.0.10:9000');
      expect(normalizarServidor('http://pc-igreja:8080'), 'http://pc-igreja:8080');
      expect(normalizarServidor('pc-igreja'), 'http://pc-igreja:8080');
      expect(normalizarServidor('localhost'), 'http://localhost:8080');
      expect(normalizarServidor(''), '');
    });

    test('domínio vira https sem porta', () {
      expect(normalizarServidor('diako.minhaigreja.com.br'), 'https://diako.minhaigreja.com.br');
      expect(normalizarServidor('diako.minhaigreja.com.br/'), 'https://diako.minhaigreja.com.br');
      expect(normalizarServidor('https://diako.minhaigreja.com.br'), 'https://diako.minhaigreja.com.br');
      expect(normalizarServidor('diako.minhaigreja.com.br:8443'), 'http://diako.minhaigreja.com.br:8443');
    });

    test('WebSocket usa wss com https', () {
      final api = ServerApi(() => const ServidorConfig(base: 'https://diako.minhaigreja.com.br', sessao: 's'));
      expect(api.wsUri().toString(), 'wss://diako.minhaigreja.com.br/ws?token=s');
    });
  });

  group('HolyricsClient via servidor', () {
    test('usa /api/holyrics/<ação> com a sessão', () async {
      await cliente({'status': 'ok'}).testar();
      expect(ultima.method, 'POST');
      expect(ultima.url.toString(), 'http://192.168.0.10:8080/api/holyrics/GetCPInfo');
      expect(ultima.headers['Authorization'], 'Bearer sess');
    });

    test('projetar texto com tema e acentos', () async {
      await cliente({'status': 'ok'}).projetarTexto('<b>Oração</b>\nIrmã Maria', tema: 'Avisos');
      expect(corpo(), {
        'text': '<b>Oração</b>\nIrmã Maria',
        'theme': {'name': 'Avisos'},
      });
    });

    test('sequência envia slides e automatic', () async {
      await cliente({'status': 'ok'}).projetarSequencia(['A', 'B'], segundos: 8, repetir: true);
      expect(corpo(), {
        'slides': [
          {'text': 'A', 'duration': 8},
          {'text': 'B', 'duration': 8},
        ],
        'automatic': {'seconds': 8, 'repeat': true},
      });
    });

    test('controles usam as ações corretas', () async {
      final c = cliente({'status': 'ok'});
      await c.proximo();
      expect(ultima.url.path, '/api/holyrics/ActionNext');
      await c.anterior(rapida: true);
      expect(ultima.url.path, '/api/holyrics/ActionPreviousQuickPresentation');
      await c.telaPreta(true);
      expect(corpo(), {'enable': true});
      await c.mostrarImagem('Diako/retiro.jpg');
      expect(corpo(), {'file': 'Diako/retiro.jpg'});
    });

    test('apresentação atual', () async {
      final a = await cliente({
        'status': 'ok',
        'data': {'type': 'quick_presentation', 'name': 'Recados', 'slide_number': 2, 'total_slides': 5},
      }).apresentacaoAtual();
      expect(a!.rapida, isTrue);
      expect(a.slide, 2);
      expect(await cliente({'status': 'ok', 'data': null}).apresentacaoAtual(), isNull);
    });

    test('erro do Holyrics vira mensagem', () async {
      expect(
        () => cliente({'status': 'error', 'error': 'Holyrics não respondeu.'}).testar(),
        throwsA(isA<HolyricsException>().having((e) => e.message, 'message', contains('não respondeu'))),
      );
    });

    test('mensagem de palco vai sem tema: só texto, fundo transparente', () async {
      await cliente({'status': 'ok'}).mensagemPalco('Faltam 5 minutos');
      expect(corpo(), {
        'text': 'Faltam 5 minutos',
        'show': true,
        'display_ahead': true,
        'custom_theme': {
          'background': {'type': 'transparent', 'id': 'transparent'},
          'font': {'bold': true, 'size': 14, 'color': 'FFFFFF'},
          'align': {'horizontal': 'center', 'vertical': 'middle'},
          'effect': {'shadow_color': '000000', 'shadow_x_weight': 20, 'shadow_y_weight': 20},
        },
      });
    });

    test('ocultar a mensagem de palco mantém o mesmo visual', () async {
      await cliente({'status': 'ok'}).mensagemPalco('', mostrar: false);
      expect(corpo()['show'], isFalse);
      expect((corpo()['custom_theme'] as Map)['background'], {'type': 'transparent', 'id': 'transparent'});
    });
  });

  group('ServerApi', () {
    test('sem configuração não faz requisição', () async {
      expect(() => api({}, config: const ServidorConfig(base: '', sessao: '')).listar('recados'),
          throwsA(isA<ServidorException>()));
    });

    test('mensagem de erro do servidor e sessão expirada', () async {
      expect(() => api({'erro': 'Informe o título.'}, status: 400).criar('recados', {}),
          throwsA(isA<ServidorException>().having((e) => e.message, 'message', 'Informe o título.')));
      expect(() => api({'erro': 'Faça login.'}, status: 401).listar('recados'),
          throwsA(isA<ServidorException>().having((e) => e.naoAutorizado, 'naoAutorizado', isTrue)));
    });

    test('login não manda sessão', () async {
      final t = await api({'token': 'novo'}).login('http://srv:8080', 'senha', usuario: ' telao ');
      expect(t, 'novo');
      expect(ultima.url.toString(), 'http://srv:8080/api/login');
      expect(ultima.headers.containsKey('Authorization'), isFalse);
      expect(jsonDecode(ultima.body), {'usuario': 'telao', 'senha': 'senha'});
    });

    test('cartazes com endereço completo e upload de bytes', () async {
      final lista = await api([
        {'nome': 'retiro.jpg', 'holyrics': 'Diako/retiro.jpg', 'url': '/cartazes/retiro.jpg'},
      ]).cartazes();
      expect(lista.single.url, 'http://192.168.0.10:8080/cartazes/retiro.jpg');

      final caminho = await api({'nome': 'foto.jpg', 'holyrics': 'Diako/foto.jpg'}).enviarCartaz('Foto 1.jpg', [1, 2, 3]);
      expect(caminho, 'Diako/foto.jpg');
      expect(ultima.url.queryParameters['nome'], 'Foto 1.jpg');
      expect(ultima.bodyBytes, [1, 2, 3]);
    });

    test('endereço do WebSocket', () {
      expect(api({}).wsUri().toString(), 'ws://192.168.0.10:8080/ws?token=sess');
    });
  });
}
