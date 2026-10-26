import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:diako_server/agenda.dart';
import 'package:diako_server/app.dart';
import 'package:diako_server/auth.dart';
import 'package:diako_server/backup.dart';
import 'package:diako_server/cartazes.dart';
import 'package:diako_server/config.dart';
import 'package:diako_server/configuracoes.dart';
import 'package:diako_server/historico.dart';
import 'package:diako_server/holyrics.dart';
import 'package:diako_server/store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

final agora = DateTime(2026, 11, 7, 10); // sábado

String ics(List<String> eventos) => ['BEGIN:VCALENDAR', 'VERSION:2.0', ...eventos, 'END:VCALENDAR'].join('\r\n');
String evento(String uid, String titulo, String inicio, String fim, {String local = '', String descricao = ''}) => [
      'BEGIN:VEVENT',
      'UID:$uid',
      'SUMMARY:$titulo',
      'DTSTART;TZID=America/Sao_Paulo:$inicio',
      'DTEND;TZID=America/Sao_Paulo:$fim',
      if (local.isNotEmpty) 'LOCATION:$local',
      if (descricao.isNotEmpty) 'DESCRIPTION:$descricao',
      'END:VEVENT',
    ].join('\r\n');

final icsPadrao = ics([
  evento('jovens', 'Culto de Jovens', '20261107T193000', '20261107T210000', local: 'Salão', descricao: 'Tragam lanche'),
  evento('ceia', 'Santa Ceia', '20261108T190000', '20261108T203000', local: 'Templo'),
  evento('passado', 'Já passou', '20261101T100000', '20261101T110000'),
]);

const urlAgenda = 'https://calendar.google.com/calendar/ical/abc%40group.calendar.google.com/private-xyz/basic.ics';

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('diako_agenda'));
  tearDown(() => tmp.delete(recursive: true));

  group('AgendaGoogle', () {
    test('baixa, avisa quando muda, guarda cópia e mantém quando a internet cai', () async {
      var conteudo = icsPadrao;
      var foraDoAr = false;
      var avisos = 0;
      final cliente = MockClient((req) async {
        if (foraDoAr) throw const SocketException('sem internet');
        return http.Response.bytes(utf8.encode(conteudo), 200);
      });
      AgendaGoogle nova() => AgendaGoogle(
            pastaDados: tmp.path, url: () => urlAgenda, cliente: cliente, relogio: () => agora, aoMudar: () => avisos++);

      final a = nova();
      await a.carregar();
      expect(await a.atualizarAgora(), isTrue);
      expect(avisos, 1);
      expect(a.proximos().map((e) => e.titulo), ['Culto de Jovens', 'Santa Ceia']);
      expect(a.erro, isNull);
      expect(a.ultimaAtualizacao, agora);

      expect(await a.atualizarAgora(), isFalse); // igual: não avisa
      expect(avisos, 1);

      foraDoAr = true;
      await a.atualizarAgora();
      expect(a.erro, contains('sem internet'));
      expect(a.proximos(), hasLength(2)); // continua com a última cópia

      // Reinício do servidor sem internet: usa a cópia do disco.
      final b = nova();
      await b.carregar();
      expect(b.proximos(), hasLength(2));

      foraDoAr = false;
      conteudo = ics([evento('novo', 'Retiro', '20261110T080000', '20261110T180000')]);
      expect(await b.atualizarAgora(), isTrue);
      expect(b.proximos().single.titulo, 'Retiro');
    });

    test('trocar ou remover o endereço descarta a agenda antiga', () async {
      var url = urlAgenda;
      final a = AgendaGoogle(
        pastaDados: tmp.path,
        url: () => url,
        cliente: MockClient((_) async => http.Response.bytes(utf8.encode(icsPadrao), 200)),
        relogio: () => agora,
      );
      await a.atualizarAgora();
      expect(a.proximos(), isNotEmpty);
      url = '';
      await a.atualizarAgora();
      expect(a.configurada, isFalse);
      expect(a.proximos(), isEmpty);
      expect(File(p.join(tmp.path, 'agenda.ics')).existsSync(), isFalse);
    });

    test('ETag: 304 não baixa de novo', () async {
      final pedidos = <http.Request>[];
      final a = AgendaGoogle(
        pastaDados: tmp.path,
        url: () => urlAgenda,
        relogio: () => agora,
        cliente: MockClient((req) async {
          pedidos.add(req);
          if (req.headers['If-None-Match'] == '"v1"') return http.Response('', 304);
          return http.Response.bytes(utf8.encode(icsPadrao), 200, headers: {'etag': '"v1"'});
        }),
      );
      await a.atualizarAgora();
      expect(await a.atualizarAgora(), isFalse);
      expect(pedidos.last.headers['If-None-Match'], '"v1"');
      expect(a.proximos(), hasLength(2));
    });

    test('resposta que não é agenda vira erro amigável', () async {
      final a = AgendaGoogle(
        pastaDados: tmp.path,
        url: () => urlAgenda,
        cliente: MockClient((_) async => http.Response('<html>login</html>', 200)),
      );
      await a.atualizarAgora();
      expect(a.erro, contains('iCal'));
      await expectLater(
          AgendaGoogle.testar(urlAgenda, cliente: MockClient((_) async => http.Response('', 404))),
          throwsA(isA<FormatException>().having((e) => e.message, 'm', contains('404'))));
    });
  });

  group('servidor', () {
    late Store store;
    late Configuracoes cfg;
    late Handler handler;
    late String token;

    setUp(() async {
      final config = Config.lerJson('{"senhaAdmin":"senha-teste"}', pastaBase: tmp.path);
      store = Store(config.pastaDados);
      await store.carregar();
      cfg = await Configuracoes.carregar(config, urlDetectada: 'http://192.168.0.10:8080');
      final auth = Auth(conferirSenha: cfg.conferirSenha, pastaDados: config.pastaDados);
      final clienteGoogle = MockClient((req) async => req.url.path.endsWith('.ics')
          ? http.Response.bytes(utf8.encode(icsPadrao), 200)
          : http.Response('<html></html>', 200));
      final agenda = AgendaGoogle(
          pastaDados: config.pastaDados, url: () => cfg.agendaUrl, cliente: clienteGoogle, relogio: () => agora);
      final web = Directory(p.join(tmp.path, 'web'))..createSync();
      final backup = Backup(pastaDados: config.pastaDados, configuracoes: cfg.publicas);
      handler = Servidor(
        store: store,
        auth: auth,
        holyrics: HolyricsDireto(host: 'h', porta: 1, token: 't', cliente: MockClient((_) async => http.Response('{}', 200))),
        cartazes: Cartazes(config.pastaCartazes),
        backup: backup,
        pastaWeb: web.path,
        urlOracao: cfg.urlOracao,
        cartazesNoHolyrics: false,
        historico: Historico(config.pastaDados),
        cfg: cfg,
        agenda: agenda,
        clienteAgenda: clienteGoogle,
        relogio: () => agora,
      ).handler;
      final r = await handler(Request('POST', Uri.parse('http://x/api/login'), body: jsonEncode({'senha': 'senha-teste'})));
      token = (jsonDecode(await r.readAsString()) as Map)['token'] as String;
    });
    tearDown(() => store.fechar());

    Future<dynamic> get(String caminho, {bool login = true}) async {
      final r = await handler(Request('GET', Uri.parse('http://x$caminho'),
          headers: {if (login) 'authorization': 'Bearer $token'}));
      return r.statusCode == 200 ? jsonDecode(await r.readAsString()) : r.statusCode;
    }

    Future<Response> post(String metodo, String caminho, Object corpo) => Future.sync(() => handler(Request(
        metodo, Uri.parse('http://x$caminho'),
        headers: {'authorization': 'Bearer $token', 'content-type': 'application/json'}, body: jsonEncode(corpo))));

    test('configurar a agenda: testar, salvar, ver eventos, mural e resumo', () async {
      expect(await get('/api/agenda', login: false), 401);
      expect((await get('/api/agenda'))['configurada'], isFalse);

      final teste = await post('POST', '/api/admin/agenda/testar', {'url': urlAgenda});
      expect((jsonDecode(await teste.readAsString()) as Map)['eventos'], 2);
      final ruim = await post('POST', '/api/admin/agenda/testar', {'url': 'https://calendar.google.com/naoeics'});
      expect(ruim.statusCode, 400);
      expect((await post('PUT', '/api/admin/configuracoes', {'agendaUrl': 'ftp://x'})).statusCode, 400);

      expect((await post('PUT', '/api/admin/configuracoes', {'agendaUrl': urlAgenda, 'agendaDiasMural': 3})).statusCode, 200);
      final agenda = await get('/api/agenda') as Map;
      expect(agenda['configurada'], isTrue);
      expect((agenda['eventos'] as List).map((e) => e['titulo']), ['Culto de Jovens', 'Santa Ceia']);

      final mural = await get('/api/public/mural', login: false) as Map;
      final slides = mural['slides'] as List;
      expect(slides.first['tipo'], 'hoje');
      expect(slides.first['eventos'][0], {'quando': '19h30–21h', 'titulo': 'Culto de Jovens', 'local': 'Salão', 'descricao': 'Tragam lanche'});
      expect(slides[1]['tipo'], 'agenda');
      expect(slides[1]['eventos'][0]['quando'], 'dom 08/11 · 19h–20h30');

      await post('PUT', '/api/admin/configuracoes', {'agendaMostrarDescricao': false});
      final semDescricao = await get('/api/public/mural', login: false) as Map;
      expect((semDescricao['slides'] as List).first['eventos'][0].containsKey('descricao'), isFalse);

      // 07/11 é sábado: o resumo traz só o que vai até sábado (o domingo 08/11 já é outra semana).
      final resumo = (await get('/api/resumo-semanal') as Map)['texto'] as String;
      expect(resumo, contains('• *Culto de Jovens* — sáb 07/11 19h30–21h · Salão'));
    });

    test('o endereço secreto não aparece no painel nem no backup', () async {
      await post('PUT', '/api/admin/configuracoes', {'agendaUrl': urlAgenda});
      final c = await get('/api/admin/configuracoes') as Map;
      expect(jsonEncode(c), isNot(contains('private-xyz')));
      expect(c['agendaConfigurada'], isTrue);
      expect(c['agenda']['configurada'], isTrue);

      final r = await handler(Request('GET', Uri.parse('http://x/api/backups/agora/download'),
          headers: {'authorization': 'Bearer $token'}));
      final zip = ZipDecoder().decodeBytes(await r.read().expand((b) => b).toList());
      expect(utf8.decode(zip.findFile('configuracoes.json')!.content), isNot(contains('private-xyz')));
    });
  });
}
