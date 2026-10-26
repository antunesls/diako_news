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
}
