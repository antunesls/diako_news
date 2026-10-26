import 'dart:convert';
import 'dart:io';

import 'package:diako_news/data/visita_repo.dart';
import 'package:diako_news/sync/server_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> visita(String id, String nome, {String data = '2026-10-25', bool mencionar = true, String? mencionadaEm}) => {
      'id': id,
      'membroId': 'm-$id',
      'nome': nome,
      'data': data,
      'criadoEm': '${data}T19:0${id.length}:00.000',
      'origem': 'recepcao',
      'primeiraVez': true,
      'mencionar': mencionar,
      if (mencionadaEm != null) 'mencionadaEm': mencionadaEm,
      'contato': 'aContatar',
    };

void main() {
  test('hoje e pendências do pastor; marcar citado e projetar boas-vindas', () async {
    final tmp = await Directory.systemTemp.createTemp('diako_visitas_app');
    addTearDown(() => tmp.delete(recursive: true));
    var lista = [
      visita('a', 'Rita Alves'),
      visita('bb', 'Léo', mencionar: false),
      visita('ccc', 'Ontem', data: '2026-10-24'),
    ];
    final pedidos = <String>[];
    var holyricsOk = true;
    final api = ServerApi(
      () => const ServidorConfig(base: 'http://srv:8080', sessao: 's'),
      httpClient: MockClient((r) async {
        pedidos.add('${r.method} ${r.url.path} ${r.body}');
        http.Response json(Object corpo) => http.Response.bytes(utf8.encode(jsonEncode(corpo)), 200);
        if (r.method == 'GET') return json(lista);
        if (r.url.path == '/api/visitas/a/mencionada') {
          lista = [{...lista[0], 'mencionadaEm': '2026-10-25T20:00:00.000'}, ...lista.skip(1)];
          return json(lista[0]);
        }
        if (r.url.path == '/api/projetar/boas-vindas') {
          return json(holyricsOk ? {'status': 'ok'} : {'status': 'error', 'error': 'Holyrics fechado'});
        }
        return http.Response('{}', 404);
      }),
    );
    final repo = VisitaRepo(
      api: api,
      cache: () async => File('${tmp.path}/visitas.json'),
      relogio: () => DateTime(2026, 10, 25, 20),
    );
    await repo.carregar();
    expect(repo.hoje.map((v) => v.nome), ['Rita Alves', 'Léo']);
    expect(repo.pendentes.map((v) => v.nome), ['Rita Alves']);

    holyricsOk = false;
    await expectLater(repo.projetarBoasVindas(), throwsA(isA<ServidorException>()));
    holyricsOk = true;
    await repo.projetarBoasVindas(ids: ['a']);
    expect(pedidos.where((p) => p.startsWith('POST /api/projetar/boas-vindas')).last, contains('"ids":["a"]'));

    await repo.marcarMencionada(repo.hoje.first);
    expect(repo.pendentes, isEmpty);
    expect(repo.hoje.first.mencionadaEm, isNotNull);
  });
}
