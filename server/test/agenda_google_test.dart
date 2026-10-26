import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:diako_server/agenda.dart';
import 'package:diako_server/agenda_google_api.dart';
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
const calId = 'abc@group.calendar.google.com';
const urlAgenda = 'https://calendar.google.com/calendar/ical/abc%40group.calendar.google.com/private-xyz/basic.ics';

/// Chave com o formato de uma conta de serviço (a assinatura não é usada: o cliente é falso).
Map<String, dynamic> chaveFalsa({String id = 'k1'}) => {
      'type': 'service_account',
      'project_id': 'diako-teste',
      'private_key_id': id,
      'private_key': '-----BEGIN PRIVATE KEY-----\nNAO-E-UMA-CHAVE-DE-VERDADE\n-----END PRIVATE KEY-----\n',
      'client_email': 'diako-agenda@diako-teste.iam.gserviceaccount.com',
      'client_id': '123',
    };

/// Imita a API do Google Calendar v3 em memória.
class GoogleFalso {
  final eventos = <String, Map<String, dynamic>>{};
  var permissao = 'writer';
  var apiDesativada = false;
  var foraDoAr = false;
  var porPagina = 2;
  final pedidos = <http.Request>[];
  var _proximo = 1;

  void adicionar(Map<String, dynamic> e) => eventos[e['id'] as String] = e;

  late final cliente = MockClient((req) async {
    pedidos.add(req);
    if (foraDoAr) throw const SocketException('sem internet');
    if (apiDesativada) {
      return _json(403, {
        'error': {
          'code': 403,
          'message': 'Google Calendar API has not been used in project 1 before or it is disabled.',
          'errors': [{'reason': 'accessNotConfigured'}],
        }
      });
    }
    final seg = req.url.pathSegments; // calendar v3 calendars <id> events [<evento>]
    if (seg.length < 5 || seg[2] != 'calendars' || seg[4] != 'events') return _json(404, {});
    if (seg[3] != calId) return _json(404, {'error': {'code': 404, 'message': 'Not Found'}});
    final escrita = req.method != 'GET';
    if (escrita && permissao == 'reader') {
      return _json(403, {
        'error': {'code': 403, 'message': 'You need to have writer access to this calendar.', 'errors': [{'reason': 'requiredAccessLevel'}]}
      });
    }
    if (seg.length == 5 && req.method == 'GET') {
      final todos = eventos.values.toList()..sort((a, b) => _inicio(a).compareTo(_inicio(b)));
      final pagina = int.tryParse(req.url.queryParameters['pageToken'] ?? '0') ?? 0;
      final fatia = todos.skip(pagina * porPagina).take(porPagina).toList();
      return _json(200, {
        'summary': 'Igreja',
        'accessRole': permissao,
        'items': fatia,
        if ((pagina + 1) * porPagina < todos.length) 'nextPageToken': '${pagina + 1}',
      });
    }
    if (seg.length == 5 && req.method == 'POST') {
      final e = {...jsonDecode(req.body) as Map<String, dynamic>, 'id': 'novo${_proximo++}', 'status': 'confirmed'};
      eventos[e['id'] as String] = _limpar(e);
      return _json(200, eventos[e['id']]!);
    }
    final id = seg[5];
    final atual = eventos[id];
    if (atual == null) return _json(404, {'error': {'code': 404, 'message': 'Not Found'}});
    switch (req.method) {
      case 'GET':
        return _json(200, atual);
      case 'PATCH':
        final mudancas = jsonDecode(req.body) as Map<String, dynamic>;
        eventos[id] = _limpar({...atual, ...mudancas});
        return _json(200, eventos[id]!);
      case 'DELETE':
        eventos.remove(id);
        return http.Response('', 204);
    }
    return _json(405, {});
  });

  static Map<String, dynamic> _limpar(Map<String, dynamic> e) => {
        for (final kv in e.entries)
          kv.key: kv.value is Map ? {for (final x in (kv.value as Map).entries) if (x.value != null) x.key: x.value} : kv.value,
      };

  static String _inicio(Map<String, dynamic> e) => (e['start']['dateTime'] ?? e['start']['date']) as String;

  static http.Response _json(int status, Object corpo) =>
      http.Response.bytes(utf8.encode(jsonEncode(corpo)), status, headers: {'content-type': 'application/json'});
}

Map<String, dynamic> eventoApi(String id, String titulo, String inicio, String fim, {String? recorrente, bool diaInteiro = false}) => {
      'id': id,
      'status': 'confirmed',
      'summary': titulo,
      'start': diaInteiro ? {'date': inicio} : {'dateTime': '$inicio-03:00', 'timeZone': 'America/Sao_Paulo'},
      'end': diaInteiro ? {'date': fim} : {'dateTime': '$fim-03:00', 'timeZone': 'America/Sao_Paulo'},
      if (recorrente != null) 'recurringEventId': recorrente,
    };

void main() {
  late Directory tmp;
  late GoogleFalso google;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('diako_agenda_google');
    google = GoogleFalso()
      ..adicionar(eventoApi('jovens', 'Culto de Jovens', '2026-11-07T19:30:00', '2026-11-07T21:00:00'))
      ..adicionar(eventoApi('ceia_20261108', 'Santa Ceia', '2026-11-08T19:00:00', '2026-11-08T20:30:00', recorrente: 'ceia'))
      ..adicionar(eventoApi('retiro', 'Retiro', '2026-11-14', '2026-11-16', diaInteiro: true))
      ..adicionar({...eventoApi('cancelado', 'Cancelado', '2026-11-09T10:00:00', '2026-11-09T11:00:00'), 'status': 'cancelled'});
  });
  tearDown(() => tmp.delete(recursive: true));

  CalendarioGoogle calendarioFalso(Map<String, dynamic> chave, String id) => CalendarioGoogle(
      calendarioId: id, emailConta: chave['client_email'] as String, cliente: () async => google.cliente);

  test('ID da agenda a partir do endereço iCal', () {
    expect(calendarioIdDoIcal(urlAgenda), calId);
    expect(calendarioIdDoIcal('https://calendar.google.com/calendar/ical/pessoa%40gmail.com/private-1/basic.ics'),
        'pessoa@gmail.com');
    expect(calendarioIdDoIcal('https://exemplo.com/agenda.ics'), '');
  });

  test('chave: aceita conta de serviço e recusa outros JSON', () {
    expect(ContaServicoGoogle.validar(jsonEncode(chaveFalsa()))['client_email'], contains('iam.gserviceaccount.com'));
    expect(() => ContaServicoGoogle.validar('não é json'), throwsFormatException);
    expect(() => ContaServicoGoogle.validar(jsonEncode({'type': 'authorized_user'})), throwsFormatException);
    expect(() => ContaServicoGoogle.validar(jsonEncode({...chaveFalsa(), 'private_key': ''})), throwsFormatException);
  });

  group('AgendaGoogle no modo API', () {
    late ContaServicoGoogle conta;
    var avisos = 0;

    AgendaGoogle nova() => AgendaGoogle(
          pastaDados: tmp.path,
          url: () => '',
          conta: conta,
          calendarioId: () => calId,
          criarCalendario: calendarioFalso,
          relogio: () => agora,
          aoMudar: () => avisos++,
        );

    setUp(() async {
      avisos = 0;
      conta = ContaServicoGoogle(tmp.path);
      await conta.salvar(chaveFalsa());
    });

    test('lê com paginação, ignora cancelados e marca recorrentes como não editáveis', () async {
      final a = nova();
      await a.carregar();
      expect(a.editavel, isTrue);
      expect(await a.atualizarAgora(), isTrue);
      expect(avisos, 1);
      final lista = a.proximos();
      expect(lista.map((e) => e.titulo), ['Culto de Jovens', 'Santa Ceia', 'Retiro']);
      expect(lista[0].inicio, DateTime(2026, 11, 7, 19, 30)); // relógio de parede
      expect(lista[0].editavel, isTrue);
      expect(lista[1].editavel, isFalse);
      expect(lista[2].diaInteiro, isTrue);
      expect(lista[2].fim, DateTime(2026, 11, 16));
      expect(google.pedidos.where((r) => r.url.queryParameters.containsKey('pageToken')), isNotEmpty);
      expect(a.estado()['modo'], 'google');
      expect(a.estado()['contaServico'], contains('iam.gserviceaccount.com'));
    });

    test('criar, editar (para dia inteiro) e excluir aparecem na hora', () async {
      final a = nova();
      await a.atualizarAgora();
      final criado = await a.criar(DadosEvento(
          titulo: 'Ensaio', inicio: DateTime(2026, 11, 10, 20), fim: DateTime(2026, 11, 10, 22), local: 'Templo'));
      expect(a.proximos().map((e) => e.titulo), contains('Ensaio'));
      final corpo = jsonDecode(google.pedidos.last.body) as Map;
      expect(corpo['start'], {'dateTime': '2026-11-10T20:00:00', 'timeZone': 'America/Sao_Paulo', 'date': null});

      await a.atualizar(criado.id,
          DadosEvento(titulo: 'Ensaio geral', inicio: DateTime(2026, 11, 10), fim: DateTime(2026, 11, 11), diaInteiro: true));
      final patch = google.pedidos.lastWhere((r) => r.method == 'PATCH');
      expect((jsonDecode(patch.body) as Map)['start'], {'date': '2026-11-10', 'dateTime': null, 'timeZone': null});
      final editado = a.proximos().firstWhere((e) => e.id == criado.id);
      expect(editado.titulo, 'Ensaio geral');
      expect(editado.diaInteiro, isTrue);

      await a.excluir(criado.id);
      expect(a.proximos().map((e) => e.id), isNot(contains(criado.id)));
      expect(google.eventos.containsKey(criado.id), isFalse);
    });

    test('evento recorrente não é alterado pelo DiakoNews', () async {
      final a = nova();
      await a.atualizarAgora();
      await expectLater(a.excluir('ceia_20261108'),
          throwsA(isA<ErroGoogle>().having((e) => e.ancora, 'âncora', 'recorrentes')));
      expect(google.eventos.containsKey('ceia_20261108'), isTrue);
    });

    test('sem internet mantém a última cópia (também depois de reiniciar)', () async {
      final a = nova();
      await a.atualizarAgora();
      google.foraDoAr = true;
      await a.atualizarAgora();
      expect(a.erro, contains('sem internet'));
      expect(a.proximos(), hasLength(3));
      final b = nova();
      await b.carregar();
      expect(b.proximos(), hasLength(3));
    });

    test('erros do Google viram mensagens com o link da ajuda', () async {
      final cal = calendarioFalso(chaveFalsa(), calId);
      google.permissao = 'reader';
      await expectLater(cal.testarAcesso(), throwsA(isA<ErroGoogle>().having((e) => e.ajuda, 'ajuda', '$ajudaAgenda#erro-permissao')));
      await expectLater(cal.criar(DadosEvento(titulo: 'x', inicio: agora, fim: agora.add(const Duration(hours: 1)))),
          throwsA(isA<ErroGoogle>().having((e) => e.mensagem, 'mensagem', contains('Fazer alterações e ver detalhes do evento'))));
      google.permissao = 'writer';
      google.apiDesativada = true;
      await expectLater(cal.testarAcesso(), throwsA(isA<ErroGoogle>().having((e) => e.ancora, 'âncora', 'erro-api')));
      google.apiDesativada = false;
      await expectLater(calendarioFalso(chaveFalsa(), 'outra@group.calendar.google.com').testarAcesso(),
          throwsA(isA<ErroGoogle>().having((e) => e.ancora, 'âncora', 'erro-404')));
    });

    test('sem a chave volta a ser só leitura', () async {
      final a = nova();
      await a.atualizarAgora();
      await conta.remover();
      expect(a.editavel, isFalse);
      expect(a.configurada, isFalse);
      await expectLater(a.criar(DadosEvento(titulo: 'x', inicio: agora, fim: agora.add(const Duration(hours: 1)))),
          throwsA(isA<ErroGoogle>().having((e) => e.ancora, 'âncora', 'ligar-antes')));
    });
  });

  group('servidor', () {
    late Store store;
    late Handler handler;
    late String token;

    setUp(() async {
      final config = Config.lerJson('{"senhaAdmin":"senha-teste"}', pastaBase: tmp.path);
      store = Store(config.pastaDados);
      await store.carregar();
      final cfg = await Configuracoes.carregar(config, urlDetectada: 'http://192.168.0.10:8080');
      final auth = Auth(conferirSenha: cfg.conferirSenha, pastaDados: config.pastaDados);
      final conta = ContaServicoGoogle(config.pastaDados);
      final agenda = AgendaGoogle(
        pastaDados: config.pastaDados,
        url: () => cfg.agendaUrl,
        conta: conta,
        calendarioId: () => cfg.agendaCalendarioId,
        criarCalendario: calendarioFalso,
        cliente: MockClient((_) async => http.Response('BEGIN:VCALENDAR\r\nEND:VCALENDAR', 200)),
        relogio: () => agora,
      );
      final web = Directory(p.join(tmp.path, 'web'))..createSync();
      File(p.join(web.path, 'ajuda-agenda.html')).writeAsStringSync('<h1>Ajuda</h1>');
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
    tearDown(() => store.fechar());

    Future<(int, dynamic)> chamar(String metodo, String caminho, [Object? corpo]) async {
      final r = await handler(Request(metodo, Uri.parse('http://x$caminho'),
          headers: {'authorization': 'Bearer $token', 'content-type': 'application/json'},
          body: corpo == null ? null : jsonEncode(corpo)));
      final texto = await r.readAsString();
      return (r.statusCode, texto.startsWith('{') || texto.startsWith('[') ? jsonDecode(texto) : texto);
    }

    test('página de ajuda abre sem login', () async {
      final r = await handler(Request('GET', Uri.parse('http://x$ajudaAgenda')));
      expect(r.statusCode, 200);
      expect(r.headers['content-type'], contains('text/html'));
    });

    test('ligar a conta de serviço, criar/editar/excluir eventos e desligar', () async {
      // Só leitura: criar evento é recusado com link para a ajuda.
      var (st, j) = await chamar('POST', '/api/agenda/eventos',
          {'titulo': 'Ensaio', 'inicio': '2026-11-10T20:00:00', 'fim': '2026-11-10T22:00:00'});
      expect(st, 400);
      expect(j['ajuda'], '$ajudaAgenda#ligar-antes');

      // Chave inválida e falta de ID da agenda.
      (st, j) = await chamar('POST', '/api/admin/agenda/conta-servico', {'chave': '{"type":"x"}'});
      expect(st, 400);
      expect(j['ajuda'], '$ajudaAgenda#erro-chave');
      (st, j) = await chamar('POST', '/api/admin/agenda/conta-servico', {'chave': jsonEncode(chaveFalsa())});
      expect(st, 400);
      expect(j['ajuda'], '$ajudaAgenda#id-agenda');

      // Agenda compartilhada só para leitura: não salva a chave.
      google.permissao = 'reader';
      await chamar('PUT', '/api/admin/configuracoes', {'agendaUrl': urlAgenda});
      (st, j) = await chamar('POST', '/api/admin/agenda/conta-servico', {'chave': jsonEncode(chaveFalsa())});
      expect(st, 400);
      expect(j['contaServico'], contains('iam.gserviceaccount.com'));
      expect(j['ajuda'], '$ajudaAgenda#erro-permissao');
      expect(File(p.join(tmp.path, 'data', 'google-conta-servico.json')).existsSync(), isFalse);

      // Com permissão de alteração: o ID vem do endereço iCal.
      google.permissao = 'writer';
      (st, j) = await chamar('POST', '/api/admin/agenda/conta-servico', {'chave': jsonEncode(chaveFalsa())});
      expect(st, 200, reason: '$j');
      expect(j['agenda'], 'Igreja');
      expect(j['estado']['editavel'], isTrue);
      (st, j) = await chamar('GET', '/api/agenda');
      expect(j['editavel'], isTrue);
      expect((j['eventos'] as List).map((e) => e['titulo']), ['Culto de Jovens', 'Santa Ceia', 'Retiro']);

      // A chave nunca sai do servidor nem vai para o backup.
      (st, j) = await chamar('GET', '/api/admin/configuracoes');
      expect(jsonEncode(j), isNot(contains('PRIVATE KEY')));
      expect(j['agenda']['contaServico'], contains('iam.gserviceaccount.com'));
      final b = await handler(Request('GET', Uri.parse('http://x/api/backups/agora/download'),
          headers: {'authorization': 'Bearer $token'}));
      final zip = ZipDecoder().decodeBytes(await b.read().expand((x) => x).toList());
      for (final f in zip.files) {
        expect(utf8.decode(f.content, allowMalformed: true), isNot(contains('PRIVATE KEY')), reason: f.name);
      }

      // Validação dos dados do evento.
      (st, j) = await chamar('POST', '/api/agenda/eventos',
          {'titulo': ' ', 'inicio': '2026-11-10T20:00:00', 'fim': '2026-11-10T22:00:00'});
      expect(st, 400);
      expect(j['erro'], contains('título'));
      (st, j) = await chamar('POST', '/api/agenda/eventos',
          {'titulo': 'Ensaio', 'inicio': '2026-11-10T22:00:00', 'fim': '2026-11-10T20:00:00'});
      expect(st, 400);

      // Criar, editar, excluir.
      (st, j) = await chamar('POST', '/api/agenda/eventos',
          {'titulo': 'Ensaio', 'inicio': '2026-11-10T20:00:00', 'fim': '2026-11-10T22:00:00', 'local': 'Templo'});
      expect(st, 201);
      final id = j['id'] as String;
      expect(j['horario'], '20h–22h');
      (st, j) = await chamar('PUT', '/api/agenda/eventos/$id',
          {'titulo': 'Ensaio geral', 'inicio': '2026-11-10T19:00:00', 'fim': '2026-11-10T22:00:00'});
      expect(st, 200);
      expect(j['titulo'], 'Ensaio geral');
      (st, j) = await chamar('DELETE', '/api/agenda/eventos/ceia_20261108');
      expect(st, 400);
      expect(j['ajuda'], '$ajudaAgenda#recorrentes');
      (st, j) = await chamar('DELETE', '/api/agenda/eventos/$id');
      expect(st, 200);
      expect(google.eventos.containsKey(id), isFalse);

      // Desligar volta ao iCal (só leitura) e apaga a chave.
      (st, j) = await chamar('DELETE', '/api/admin/agenda/conta-servico');
      expect(st, 200);
      expect(j['estado']['modo'], 'ical');
      expect(File(p.join(tmp.path, 'data', 'google-conta-servico.json')).existsSync(), isFalse);
    });
  });
}
