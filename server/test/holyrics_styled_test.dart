import 'dart:convert';

import 'package:diako_server/holyrics.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final enviados = <http.Request>[];
  late HolyricsDireto holyrics;

  setUp(() {
    enviados.clear();
    holyrics = HolyricsDireto(host: '127.0.0.1', porta: 8091, token: 'teste',
        cliente: MockClient((req) async {
          enviados.add(req);
          return http.Response('{"status":"ok"}', 200);
        }));
  });

  test('apresentação única interpreta o negrito com Styled Text', () async {
    await holyrics.chamar('ShowQuickPresentation', jsonEncode({'text': '<b>Aviso</b>\nMensagem', 'theme': {'name': 'Culto'}}));
    final corpo = jsonDecode(enviados.single.body) as Map;
    expect(corpo['text'], '<styled><b>Aviso</b>\nMensagem');
    expect(corpo['theme'], {'name': 'Culto'});
  });

  test('cada slide com negrito recebe Styled Text sem mudar ordem e duração', () async {
    await holyrics.chamar('ShowQuickPresentation', jsonEncode({
      'slides': [
        {'text': '<b>Primeiro</b>\nTexto', 'duration': 10},
        {'text': 'Apenas texto', 'duration': 15},
        {'text': '<styled><b>Terceiro</b>', 'duration': 20},
      ],
      'automatic': {'seconds': 10, 'repeat': true},
    }));
    final corpo = jsonDecode(enviados.single.body) as Map;
    expect(corpo['slides'], [
      {'text': '<styled><b>Primeiro</b>\nTexto', 'duration': 10},
      {'text': 'Apenas texto', 'duration': 15},
      {'text': '<styled><b>Terceiro</b>', 'duration': 20},
    ]);
    expect(corpo['automatic'], {'seconds': 10, 'repeat': true});
  });

  test('outros comandos não recebem marcação de apresentação rápida', () async {
    const corpo = '{"text":"<b>Palco</b>","show":true}';
    await holyrics.chamar('SetTextCP', corpo);
    expect(enviados.single.body, corpo);
  });
}
