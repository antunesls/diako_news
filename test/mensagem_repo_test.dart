import 'dart:convert';
import 'dart:io';

import 'package:diako_news/data/mensagem_repo.dart';
import 'package:diako_news/sync/server_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('sincroniza mensagens e atualiza somente o status', () async {
    final tmp = await Directory.systemTemp.createTemp('diako_mensagem_app');
    addTearDown(() => tmp.delete(recursive: true));
    final item = {
      'id': 'a',
      'tipo': 'duvida',
      'texto': 'Qual horário?',
      'nome': '',
      'contato': '',
      'criadoEm': '2026-10-25T09:00:00.000',
      'status': 'nova',
      'avisoEmail': 'enviado',
    };
    final api = ServerApi(
      () => const ServidorConfig(base: 'http://srv:8080', sessao: 's'),
      // Respostas em UTF-8, como o servidor manda ("Qual horário?" tem acento;
      // http.Response(String) sem charset codificaria em Latin-1).
      httpClient: MockClient((r) async {
        if (r.method == 'GET') return http.Response.bytes(utf8.encode(jsonEncode([item])), 200);
        expect(r.url.path, '/api/mensagens/a');
        expect(jsonDecode(r.body), {'status': 'emAnalise'});
        return http.Response.bytes(utf8.encode(jsonEncode({...item, 'status': 'emAnalise'})), 200);
      }),
    );
    final repo = MensagemRepo(
      api: api,
      cache: () async => File('${tmp.path}/mensagens.json'),
    );
    await repo.carregar();
    expect(repo.novas, 1);
    await repo.mudarStatus(repo.todos.single, 'emAnalise');
    expect(repo.novas, 0);
    expect(repo.todos.single.texto, 'Qual horário?');
  });
}
