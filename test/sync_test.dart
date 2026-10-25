import 'dart:convert';
import 'dart:io';

import 'package:diako_core/diako_core.dart';
import 'package:diako_news/data/motivo_repo.dart';
import 'package:diako_news/data/recado_repo.dart';
import 'package:diako_news/sync/server_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Servidor falso em memória, com interruptor de "fora do ar".
class _Falso {
  bool foraDoAr = false;
  final recados = <Map<String, dynamic>>[];
  final motivos = <Map<String, dynamic>>[];
  var _n = 0;

  http.Client get cliente => MockClient((req) async {
        if (foraDoAr) throw const SocketException('sem rede');
        final partes = req.url.pathSegments; // api, colecao, [id], [acao]
        final lista = partes[1] == 'recados' ? recados : motivos;
        dynamic resposta;
        switch ((req.method, partes.length)) {
          case ('GET', 2):
            resposta = lista;
          case ('POST', 2):
            resposta = {...jsonDecode(req.body) as Map<String, dynamic>, 'id': 'id${_n++}'};
            lista.add(resposta);
          case ('PUT', 3) when partes[2] == 'ordem':
            resposta = {'ok': true};
          case ('PUT', 3):
            resposta = {...jsonDecode(req.body) as Map<String, dynamic>, 'id': partes[2]};
            lista[lista.indexWhere((x) => x['id'] == partes[2])] = resposta;
          case ('DELETE', 3):
            lista.removeWhere((x) => x['id'] == partes[2]);
            resposta = {'ok': true};
          case ('POST', 4):
            final i = lista.indexWhere((x) => x['id'] == partes[2]);
            lista[i] = {...lista[i], 'status': 'pendente'};
            resposta = lista[i];
        }
        return http.Response.bytes(utf8.encode(jsonEncode(resposta)), 200);
      });
}

void main() {
  late Directory tmp;
  late _Falso servidor;
  late ServerApi api;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('diako_app');
    servidor = _Falso();
    api = ServerApi(() => const ServidorConfig(base: 'http://srv:8080', sessao: 's'), httpClient: servidor.cliente);
  });
  tearDown(() => tmp.delete(recursive: true));

  RecadoRepo recados() => RecadoRepo(api: api, cache: () async => File('${tmp.path}/recados.json'));
  MotivoRepo motivos() => MotivoRepo(api: api, cache: () async => File('${tmp.path}/motivos.json'));

  test('carrega do servidor e usa a cópia local quando ele cai', () async {
    servidor.recados.add(Recado(id: 'a', titulo: 'Santa Ceia').toJson());
    final r1 = recados();
    await r1.carregar();
    expect(r1.online, isTrue);
    expect(r1.todos.single.titulo, 'Santa Ceia');

    servidor.foraDoAr = true;
    final r2 = recados();
    await r2.carregar();
    expect(r2.online, isFalse);
    expect(r2.erro, isNotNull);
    expect(r2.todos.single.titulo, 'Santa Ceia'); // veio do cache
  });

  test('criar, atualizar e excluir passam pelo servidor', () async {
    final r = recados();
    await r.carregar();
    final criado = await r.criar(Recado(id: '', titulo: 'Culto de Jovens'));
    expect(criado.id, 'id0');
    expect(servidor.recados.single['titulo'], 'Culto de Jovens');

    await r.atualizar(Recado.fromJson(criado.toJson())..texto = 'Sábado');
    expect(r.todos.single.texto, 'Sábado');

    await r.excluir('id0');
    expect(r.todos, isEmpty);
    expect(servidor.recados, isEmpty);
  });

  test('sem servidor, a alteração falha e a lista não muda', () async {
    final r = recados();
    await r.carregar();
    servidor.foraDoAr = true;
    await expectLater(r.criar(Recado(id: '', titulo: 'x')), throwsA(isA<ServidorException>()));
    expect(r.todos, isEmpty);
  });

  test('reordenar ignora o recado automático', () async {
    servidor.recados.addAll([
      Recado(id: 'auto-aniversariantes', titulo: 'Aniversariantes', auto: true, fixo: true).toJson(),
      Recado(id: 'a', titulo: 'A', ordem: 0).toJson(),
      Recado(id: 'b', titulo: 'B', ordem: 1).toJson(),
    ]);
    final r = recados();
    await r.carregar();
    final lista = ordenarParaExibicao(r.todos);
    await r.reordenar([lista[0], lista[2], lista[1]]);
    expect({for (final x in r.todos.where((x) => !x.auto)) x.id: x.ordem}, {'b': 0, 'a': 1});
  });

  test('motivos: filtros, aprovação e atendido', () async {
    servidor.motivos.addAll([
      Motivo(id: 'm1', motivo: 'Do site', status: StatusMotivo.aguardando, origem: OrigemMotivo.site).toJson(),
      Motivo(id: 'm2', motivo: 'Particular', publico: false).toJson(),
      Motivo(id: 'm3', motivo: 'Público').toJson(),
    ]);
    final m = motivos();
    await m.carregar();
    expect(m.aguardando.map((x) => x.id), ['m1']);
    expect(m.pendentes.map((x) => x.id), ['m2', 'm3']);
    expect(m.projetaveis.map((x) => x.id), ['m3']);

    await m.aprovar(m.aguardando.single);
    expect(m.aguardando, isEmpty);
    expect(m.projetaveis.map((x) => x.id), ['m1', 'm3']);

    await m.alternarAtendido(m.todos.firstWhere((x) => x.id == 'm3'));
    expect(m.atendidos.single.id, 'm3');
    expect(servidor.motivos.firstWhere((x) => x['id'] == 'm3')['status'], 'atendido');
  });
}
