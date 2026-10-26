import 'dart:convert';
import 'dart:io';

import 'package:diako_news/data/conta_repo.dart';
import 'package:diako_news/sync/server_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('diako_conta_app'));
  tearDown(() => tmp.delete(recursive: true));

  ServerApi api(http.Response Function(http.Request) resposta) =>
      ServerApi(() => const ServidorConfig(base: 'http://srv:8080', sessao: 's'),
          httpClient: MockClient((req) async => resposta(req)));

  http.Response json(Object corpo, [int status = 200]) => http.Response.bytes(utf8.encode(jsonEncode(corpo)), status);

  test('perfil do servidor, guardado para abrir sem conexão', () async {
    var foraDoAr = false;
    final servidor = api((req) {
      if (foraDoAr) throw const SocketException('sem rede');
      expect(req.url.path, '/api/eu');
      return json({'nome': 'Tablet do culto', 'perfilNome': 'Telão (tablet)', 'permissoes': ['recados', 'projetar', 'motivosVer']});
    });
    final conta = ContaRepo(api: servidor, cache: () async => File('${tmp.path}/conta.json'));
    expect(conta.pode('mensagens'), isTrue); // antes de saber: tudo liberado (o servidor recusa)
    await conta.sincronizar();
    expect(conta.nome, 'Tablet do culto');
    expect(conta.pode('projetar'), isTrue);
    expect(conta.pode('mensagens'), isFalse);
    expect(conta.pode('motivosEditar'), isFalse);

    foraDoAr = true;
    final outra = ContaRepo(api: servidor, cache: () async => File('${tmp.path}/conta.json'));
    await outra.carregar();
    await outra.sincronizar(); // sem conexão: mantém o cache
    expect(outra.pode('mensagens'), isFalse);
    expect(outra.perfil, 'Telão (tablet)');

    await outra.limpar();
    expect(outra.nome, '');
    expect(File('${tmp.path}/conta.json').existsSync(), isFalse);
  });

  test('servidor antigo (sem /api/eu): tudo liberado, como antes dos perfis', () async {
    final conta = ContaRepo(api: api((_) => json({'erro': 'Não encontrado'}, 404)), cache: () async => File('${tmp.path}/conta.json'));
    await conta.sincronizar();
    expect(conta.pode('mensagens'), isTrue);
    expect(conta.pode('admin'), isTrue);
  });
}
