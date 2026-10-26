import 'dart:convert';
import 'dart:io';

import 'package:diako_core/diako_core.dart';
import 'package:diako_server/agenda.dart';
import 'package:diako_server/app.dart';
import 'package:diako_server/auth.dart';
import 'package:diako_server/backup.dart';
import 'package:diako_server/cartazes.dart';
import 'package:diako_server/config.dart';
import 'package:diako_server/configuracoes.dart';
import 'package:diako_server/historico.dart';
import 'package:diako_server/holyrics.dart';
import 'package:diako_server/pagina_inicial.dart';
import 'package:diako_server/store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

final agora = DateTime(2026, 11, 7, 10); // sábado

const ics = 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\n'
    'BEGIN:VEVENT\r\nUID:jovens\r\nSUMMARY:Culto de Jovens\r\nLOCATION:Salão\r\n'
    'DTSTART;TZID=America/Sao_Paulo:20261107T193000\r\nDTEND;TZID=America/Sao_Paulo:20261107T210000\r\nEND:VEVENT\r\n'
    'END:VCALENDAR';
const urlAgenda = 'https://calendar.google.com/calendar/ical/abc%40group.calendar.google.com/private-xyz/basic.ics';

void main() {
  group('PIX', () {
    test('CRC confere com o exemplo do manual do BR Code', () {
      const exemplo = '00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-426655440000'
          '5204000053039865802BR5913Fulano de Tal6008BRASILIA62070503***6304';
      expect(crc16Pix(exemplo), '1D3D');
    });

    test('copia e cola com nome e cidade sem acento, em maiúsculas e no limite do padrão', () {
      final pix = payloadPix(chave: 'igreja@exemplo.com', nome: 'Igreja Diakonia Tulipas de São Paulo', cidade: 'São José dos Campos');
      expect(pix, startsWith('000201'));
      expect(pix, contains('0014br.gov.bcb.pix0118igreja@exemplo.com'));
      expect(pix, contains('5925IGREJA DIAKONIA TULIPAS D6015')); // nome cortado em 25
      expect(pix, contains('6015SAO JOSE DOS CA6207')); // cidade cortada em 15
      expect(pix, contains('5303986'));
      final semCrc = pix.substring(0, pix.length - 4);
      expect(semCrc, endsWith('6304'));
      expect(pix.substring(pix.length - 4), crc16Pix(semCrc));
    });
  });

  test('horários dos cultos', () {
    expect(lerCultos('Domingo — 19h\nQuarta (oração) | 19h30\n\nSábado - 17h\nTodo dia 19:30'), [
      {'dia': 'Domingo', 'hora': '19h'},
      {'dia': 'Quarta (oração)', 'hora': '19h30'},
      {'dia': 'Sábado', 'hora': '17h'},
      {'dia': 'Todo dia 19:30', 'hora': ''},
    ]);
  });

  test('convite de calendário (.ics) em UTC, dia inteiro e textos escapados', () {
    final e = Evento(
        id: 'x@1', titulo: 'Culto; ceia, louvor', inicio: DateTime(2026, 11, 7, 19, 30), fim: DateTime(2026, 11, 7, 21), local: 'Templo');
    final t = icsDoEvento(e, igreja: 'Igreja', agora: DateTime.utc(2026, 11, 1, 12));
    expect(t, contains('DTSTART:20261107T223000Z'));
    expect(t, contains('DTEND:20261108T000000Z'));
    expect(t, contains(r'SUMMARY:Culto\; ceia\, louvor'));
    expect(t, contains('LOCATION:Templo'));
    final dia = icsDoEvento(
        Evento(id: 'r', titulo: 'Retiro', inicio: DateTime(2026, 11, 14), fim: DateTime(2026, 11, 16), diaInteiro: true),
        igreja: 'Igreja',
        agora: DateTime.utc(2026, 11, 1));
    expect(dia, contains('DTSTART;VALUE=DATE:20261114'));
    expect(dia, contains('DTEND;VALUE=DATE:20261116'));
  });

  test('links do mapa e do WhatsApp', () {
    expect(linkMapa('Rua A, 10'), 'https://www.google.com/maps/search/?api=1&query=Rua+A%2C+10');
    expect(linkWhatsapp('11912345678'), 'https://wa.me/5511912345678');
    expect(linkWhatsapp('5511912345678'), 'https://wa.me/5511912345678');
  });

  group('servidor', () {
    late Directory tmp;
    late Store store;
    late Handler handler;
    late String token;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('diako_inicio');
      final config = Config.lerJson('{"senhaAdmin":"senha-teste"}', pastaBase: tmp.path);
      store = Store(config.pastaDados);
      await store.carregar();
      final cfg = await Configuracoes.carregar(config, urlDetectada: 'http://192.168.0.10:8080');
      final auth = Auth(conferirSenha: cfg.conferirSenha, pastaDados: config.pastaDados);
      final agenda = AgendaGoogle(
        pastaDados: config.pastaDados,
        url: () => cfg.agendaUrl,
        cliente: MockClient((_) async => http.Response.bytes(utf8.encode(ics), 200)),
        relogio: () => agora,
      );
      final web = Directory(p.join(tmp.path, 'web'))..createSync();
      File(p.join(web.path, 'inicio.html')).writeAsStringSync('<h1>Início</h1>');
      handler = Servidor(
        store: store,
        auth: auth,
        holyrics: HolyricsDireto(host: 'h', porta: 1, token: 't', cliente: MockClient((_) async => http.Response('{}', 200))),
        cartazes: Cartazes(config.pastaCartazes),
        backup: Backup(pastaDados: config.pastaDados, configuracoes: cfg.publicas),
        pastaWeb: web.path,
        urlOracao: cfg.urlOracao,
        cartazesNoHolyrics: false,
        historico: Historico(config.pastaDados),
        cfg: cfg,
        agenda: agenda,
        relogio: () => agora,
      ).handler;
      final r = await handler(Request('POST', Uri.parse('http://x/api/login'), body: jsonEncode({'senha': 'senha-teste'})));
      token = (jsonDecode(await r.readAsString()) as Map)['token'] as String;
    });
    tearDown(() async {
      await store.fechar();
      await tmp.delete(recursive: true);
    });

    Future<Response> chamar(String metodo, String caminho, [Object? corpo, bool login = true]) async => handler(Request(
        metodo, Uri.parse('http://x$caminho'),
        headers: {if (login) 'authorization': 'Bearer $token', 'content-type': 'application/json'},
        body: corpo == null ? null : jsonEncode(corpo)));

    Future<Map<String, dynamic>> inicio() async {
      final r = await chamar('GET', '/api/public/inicio', null, false);
      expect(r.statusCode, 200);
      return jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    }

    test('/ abre a página inicial (ou o painel, se desligada)', () async {
      var r = await chamar('GET', '/', null, false);
      expect(r.statusCode, 200);
      expect(await r.readAsString(), contains('Início'));
      await chamar('PUT', '/api/admin/configuracoes', {'siteAtivo': false});
      r = await chamar('GET', '/', null, false);
      expect(r.statusCode, 302);
      expect(r.headers['location'], '/painel');
      expect((await chamar('GET', '/api/public/inicio', null, false)).statusCode, 404);
    });

    test('só recados marcados, sem vencidos; urgentes à parte; nada privado', () async {
      Future<void> recado(Map<String, dynamic> dados) async =>
          expect((await chamar('POST', '/api/recados', {'categoria': 'aviso', ...dados})).statusCode, 201);
      await recado({'titulo': 'Interno', 'texto': 'só no telão'});
      await recado({'titulo': 'Santa ceia', 'texto': 'domingo', 'site': true});
      await recado({'titulo': 'Agasalho', 'site': true, 'fixo': true});
      await recado({'titulo': 'Vencido', 'site': true, 'validoAte': '2026-11-06T00:00:00.000'});
      await recado({'titulo': 'Culto às 20h', 'urgente': true});
      await chamar('POST', '/api/public/pedidos', {'motivo': 'Pedido particular', 'tipo': 'saude', 'publico': false});

      final j = await inicio();
      expect((j['avisos'] as List).map((a) => a['titulo']), ['Agasalho', 'Santa ceia']); // fixo primeiro
      expect((j['urgentes'] as List).map((a) => a['titulo']), ['Culto às 20h']);
      final texto = jsonEncode(j);
      expect(texto, isNot(contains('Interno')));
      expect(texto, isNot(contains('Vencido')));
      expect(texto, isNot(contains('Pedido particular')));
    });

    test('agenda só aparece quando liberada; convite .ics segue a mesma regra', () async {
      await chamar('PUT', '/api/admin/configuracoes', {'agendaUrl': urlAgenda});
      var j = await inicio();
      expect(j['agenda'], isFalse);
      expect(j['eventos'], isEmpty);
      final idIcs = '/api/public/eventos/${Uri.encodeComponent('jovens@2026-11-07T19:30:00.000')}.ics';
      expect((await chamar('GET', idIcs, null, false)).statusCode, 404);

      await chamar('PUT', '/api/admin/configuracoes', {'siteAgenda': true});
      j = await inicio();
      expect(j['agenda'], isTrue);
      final evento = (j['eventos'] as List).single as Map;
      expect(evento['titulo'], 'Culto de Jovens');
      expect(evento['horario'], '19h30–21h');
      final r = await chamar('GET', evento['ics'] as String, null, false);
      expect(r.statusCode, 200);
      expect(r.headers['content-type'], contains('text/calendar'));
      expect(await r.readAsString(), contains('SUMMARY:Culto de Jovens'));
    });

    test('cultos, endereço, PIX e redes; validação no /admin', () async {
      var j = await inicio();
      expect(j.containsKey('pix'), isFalse);
      expect((await chamar('GET', '/pix.png', null, false)).statusCode, 404);
      expect(j['redes'], isEmpty);

      expect((await chamar('PUT', '/api/admin/configuracoes', {'siteInstagram': 'instagram.com/igreja'})).statusCode, 400);
      expect((await chamar('PUT', '/api/admin/configuracoes', {'siteWhatsapp': '123'})).statusCode, 400);
      expect((await chamar('PUT', '/api/admin/configuracoes', {'sitePixNome': 'x' * 26})).statusCode, 400);

      final ok = await chamar('PUT', '/api/admin/configuracoes', {
        'siteCultos': 'Domingo — 19h\nQuarta — 19h30',
        'siteEndereco': 'Rua das Tulipas, 100',
        'sitePixChave': '12345678000199',
        'sitePixNome': 'Igreja Diakonia',
        'sitePixCidade': 'Sao Paulo',
        'siteInstagram': 'https://instagram.com/igreja',
        'siteWhatsapp': '(11) 91234-5678',
      });
      expect(ok.statusCode, 200);
      j = await inicio();
      expect(j['cultos'], [{'dia': 'Domingo', 'hora': '19h'}, {'dia': 'Quarta', 'hora': '19h30'}]);
      expect(j['mapa'], contains('Rua+das+Tulipas'));
      expect(j['pix'], {'chave': '12345678000199', 'nome': 'Igreja Diakonia', 'qr': '/pix.png'});
      expect(j['redes'], {'instagram': 'https://instagram.com/igreja', 'whatsapp': 'https://wa.me/5511912345678'});
      final png = await chamar('GET', '/pix.png', null, false);
      expect(png.statusCode, 200);
      expect(png.headers['content-type'], 'image/png');
    });
  });
}
