import 'dart:convert';
import 'dart:io';

import 'package:diako_core/diako_core.dart';
import 'package:diako_news/data/agenda_repo.dart';
import 'package:diako_news/sync/server_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('diako_agenda_app'));
  tearDown(() => tmp.delete(recursive: true));

  final agora = DateTime(2026, 11, 7, 20);
  Map<String, dynamic> ev(String id, String titulo, DateTime inicio, DateTime fim) =>
      Evento(id: id, titulo: titulo, inicio: inicio, fim: fim, local: 'Templo').toJson();

  test('carrega do servidor, esconde o que já terminou e usa o cache sem conexão', () async {
    var foraDoAr = false;
    late http.Request ultimo;
    final api = ServerApi(
      () => const ServidorConfig(base: 'http://srv:8080', sessao: 's'),
      httpClient: MockClient((req) async {
        ultimo = req;
        if (foraDoAr) throw const SocketException('sem rede');
        return http.Response.bytes(
            utf8.encode(jsonEncode({
              'configurada': true,
              'atualizado': '2026-11-07T19:55:00.000',
              'eventos': [
                ev('a', 'Ensaio', DateTime(2026, 11, 7, 17), DateTime(2026, 11, 7, 18)), // já terminou
                ev('b', 'Culto de Jovens', DateTime(2026, 11, 7, 19, 30), DateTime(2026, 11, 7, 21)),
                ev('c', 'Santa Ceia', DateTime(2026, 11, 8, 19), DateTime(2026, 11, 8, 20)),
              ],
            })),
            200);
      }),
    );
    AgendaRepo novo() => AgendaRepo(api: api, cache: () async => File('${tmp.path}/agenda.json'), relogio: () => agora);

    final r = novo();
    await r.carregar();
    expect(ultimo.url.path, '/api/agenda');
    expect(ultimo.url.queryParameters['dias'], '30');
    expect(r.configurada, isTrue);
    expect(r.online, isTrue);
    expect(r.eventos.map((e) => e.titulo), ['Culto de Jovens', 'Santa Ceia']);
    expect(r.proximo!.titulo, 'Culto de Jovens'); // acontecendo agora

    foraDoAr = true;
    final r2 = novo();
    await r2.carregar();
    expect(r2.online, isFalse);
    expect(r2.erro, isNotNull);
    expect(r2.eventos.map((e) => e.titulo), ['Culto de Jovens', 'Santa Ceia']);
  });

  test('agenda não configurada no servidor', () async {
    final api = ServerApi(
      () => const ServidorConfig(base: 'http://srv:8080', sessao: 's'),
      httpClient: MockClient((_) async => http.Response(jsonEncode({'configurada': false, 'eventos': []}), 200)),
    );
    final r = AgendaRepo(api: api, cache: () async => File('${tmp.path}/agenda.json'));
    await r.carregar();
    expect(r.configurada, isFalse);
    expect(r.eventos, isEmpty);
    expect(r.proximo, isNull);
  });

  test('com a conta de serviço: cria, edita e exclui pelo servidor e ressincroniza', () async {
    final pedidos = <http.Request>[];
    final api = ServerApi(
      () => const ServidorConfig(base: 'http://srv:8080', sessao: 's'),
      httpClient: MockClient((req) async {
        pedidos.add(req);
        if (req.url.path == '/api/agenda') {
          return http.Response.bytes(utf8.encode(jsonEncode({'configurada': true, 'editavel': true, 'eventos': []})), 200);
        }
        if (req.method == 'DELETE') return http.Response('{"ok":true}', 200);
        final corpo = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response.bytes(
            utf8.encode(jsonEncode({...corpo, 'id': 'g1', 'editavel': true})), req.method == 'POST' ? 201 : 200);
      }),
    );
    final r = AgendaRepo(api: api, cache: () async => File('${tmp.path}/agenda.json'), relogio: () => agora);
    await r.carregar();
    expect(r.editavel, isTrue);

    final dados = AgendaRepo.dadosEvento(
        titulo: ' Ensaio ', inicio: DateTime(2026, 11, 10, 20), fim: DateTime(2026, 11, 10, 22), diaInteiro: false, local: 'Templo');
    final criado = await r.criar(dados);
    expect(criado.id, 'g1');
    final post = pedidos.firstWhere((p) => p.method == 'POST');
    expect(post.url.path, '/api/agenda/eventos');
    expect(jsonDecode(post.body), {
      'titulo': 'Ensaio',
      'inicio': '2026-11-10T20:00:00.000',
      'fim': '2026-11-10T22:00:00.000',
      'diaInteiro': false,
      'local': 'Templo',
      'descricao': '',
    });
    expect(pedidos.last.url.path, '/api/agenda'); // ressincronizou

    await r.atualizar('g1', dados);
    expect(pedidos.firstWhere((p) => p.method == 'PUT').url.path, '/api/agenda/eventos/g1');
    await r.excluir('g1');
    expect(pedidos.firstWhere((p) => p.method == 'DELETE').url.path, '/api/agenda/eventos/g1');

    // O cache guarda que a agenda é editável (para abrir sem conexão).
    final semServidor = AgendaRepo(
        api: ServerApi(() => const ServidorConfig(base: '', sessao: '')),
        cache: () async => File('${tmp.path}/agenda.json'),
        relogio: () => agora);
    await semServidor.carregar();
    expect(semServidor.editavel, isTrue);
  });
}
