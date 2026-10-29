import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:diako_server/app.dart';
import 'package:diako_server/auth.dart';
import 'package:diako_server/backup.dart';
import 'package:diako_server/cartazes.dart';
import 'package:diako_server/historico.dart';
import 'package:diako_server/holyrics.dart';
import 'package:diako_server/qr_oracao.dart';
import 'package:diako_server/store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

const senha = 'senha-forte';
final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0]);

late Directory tmp;
late Store store;
late Handler handler;
late List<http.Request> chamadasHolyrics;
late String token;
bool temasIndisponiveis = false;

Future<Servidor> criar({DateTime? agora, LimiteTaxa? limitePedidos}) async {
  final dados = p.join(tmp.path, 'data');
  store = Store(dados);
  await store.carregar();
  final auth = Auth(senha: senha, pastaDados: dados);
  await auth.carregar();
  final web = Directory(p.join(tmp.path, 'web'))..createSync(recursive: true);
  File(p.join(web.path, 'oracao.html')).writeAsStringSync('<h1>oracao</h1>');
  File(p.join(web.path, 'painel.html')).writeAsStringSync('<h1>painel</h1>');
  chamadasHolyrics = [];
  final holyrics = HolyricsDireto(
    host: '127.0.0.1',
    porta: 8091,
    token: 'tk',
    cliente: MockClient((req) async {
      chamadasHolyrics.add(req);
      if (req.url.path.endsWith('/GetThemes')) {
        if (temasIndisponiveis) return http.Response(jsonEncode({'status': 'error', 'error': 'offline'}), 200);
        return http.Response(jsonEncode({'status': 'ok', 'data': [
          {'id': '7', 'name': 'Avisos'}, {'id': '8', 'name': 'Culto'}
        ]}), 200);
      }
      if (req.url.path.endsWith('/GetThumbnail')) {
        return http.Response(jsonEncode({'status': 'ok', 'data': [
          {'type': 'theme', 'id': '7', 'image': 'iVBORw0KGgo='}
        ]}), 200);
      }
      return http.Response(jsonEncode({'status': 'ok'}), 200);
    }),
  );
  final s = Servidor(
    store: store,
    auth: auth,
    holyrics: holyrics,
    cartazes: Cartazes(p.join(tmp.path, 'imagens', 'Diako')),
    backup: Backup(pastaDados: dados, pastaDestino: p.join(tmp.path, 'backup')),
    pastaWeb: web.path,
    urlOracao: 'http://192.168.0.10:8080/oracao',
    cartazesNoHolyrics: true,
    historico: Historico(dados, relogio: agora == null ? null : () => agora),
    relogio: agora == null ? null : () => agora,
    limitePedidos: limitePedidos,
  );
  handler = s.handler;
  return s;
}

Future<Response> req(String metodo, String caminho, {Object? json, String? texto, List<int>? bytes, bool autenticado = true}) async {
  final headers = <String, String>{if (autenticado) 'authorization': 'Bearer $token'};
  Object? body;
  if (json != null) {
    body = jsonEncode(json);
    headers['content-type'] = 'application/json';
  } else {
    body = texto ?? bytes;
  }
  return handler(Request(metodo, Uri.parse('http://localhost$caminho'), headers: headers, body: body));
}

Future<dynamic> corpo(Response r) async => jsonDecode(await r.readAsString());

Future<void> logar() async {
  token = '';
  final r = await req('POST', '/api/login', json: {'senha': senha}, autenticado: false);
  token = (await corpo(r))['token'] as String;
}

void main() {
  setUp(() async {
    temasIndisponiveis = false;
    tmp = await Directory.systemTemp.createTemp('diako_test');
    await criar();
    await logar();
  });

  tearDown(() async {
    await store.fechar();
    await tmp.delete(recursive: true);
  });

  group('autenticação', () {
    test('catálogo de temas exige login e obtém miniaturas sem projetar', () async {
      expect((await req('GET', '/api/admin/temas', autenticado: false)).statusCode, 401);
      expect((await req('GET', '/api/temas', autenticado: false)).statusCode, 401);
      final dados = await corpo(await req('GET', '/api/admin/temas')) as Map;
      expect((dados['temas'] as List).first['thumbnail'], 'iVBORw0KGgo=');
      expect(dados['miniaturasDisponiveis'], true);
      expect((dados['temas'] as List).last['name'], 'Culto');
      expect(chamadasHolyrics.map((r) => r.url.pathSegments.last).toList(), ['GetThemes', 'GetThumbnail']);
      expect(jsonDecode(chamadasHolyrics.last.body)['type'], 'theme');
      await req('GET', '/api/admin/temas');
      expect((await req('GET', '/api/temas')).statusCode, 200);
      expect(chamadasHolyrics.length, 2); // cache curto no backend
    });

    test('catálogo preserva última lista em memória quando Holyrics cai', () async {
      await req('GET', '/api/temas');
      temasIndisponiveis = true;
      final dados = await corpo(await req('GET', '/api/temas?atualizar=1')) as Map;
      expect(dados['desatualizado'], true);
      expect((dados['temas'] as List).singleWhere((t) => t['id'] == '7')['name'], 'Avisos');
    });
    test('rotas da API exigem login; páginas e pedido público não', () async {
      expect((await req('GET', '/api/recados', autenticado: false)).statusCode, 401);
      expect((await req('GET', '/ws', autenticado: false)).statusCode, 401);
      expect((await req('GET', '/oracao', autenticado: false)).statusCode, 200);
      expect((await req('GET', '/painel', autenticado: false)).statusCode, 200);
      expect((await req('GET', '/api/recados')).statusCode, 200);
    });

    test('senha errada e limite de tentativas', () async {
      for (var i = 0; i < 4; i++) {
        expect((await req('POST', '/api/login', json: {'senha': 'x'}, autenticado: false)).statusCode, 401);
      }
      // 1 login certo no setUp + 4 errados = 5; a sexta tentativa é bloqueada.
      expect((await req('POST', '/api/login', json: {'senha': senha}, autenticado: false)).statusCode, 429);
    });

    test('sessão sobrevive a reinício do servidor; logout invalida', () async {
      await criar();
      expect((await req('GET', '/api/recados')).statusCode, 200);
      await req('POST', '/api/logout');
      expect((await req('GET', '/api/recados')).statusCode, 401);
    });
  });

  group('recados', () {
    test('criar, listar, editar, ordenar e excluir', () async {
      final a = await corpo(await req('POST', '/api/recados', json: {'titulo': 'Culto de Jovens', 'categoria': 'evento'}));
      final b = await corpo(await req('POST', '/api/recados', json: {'titulo': 'Santa Ceia'}));
      expect(a['ordem'], 0);
      expect(b['ordem'], 1);

      final editado = await corpo(await req('PUT', '/api/recados/${a['id']}', json: {'texto': 'Sábado 19h30'}));
      expect(editado['titulo'], 'Culto de Jovens');
      expect(editado['texto'], 'Sábado 19h30');

      await req('PUT', '/api/recados/ordem', json: [b['id'], a['id']]);
      final lista = await corpo(await req('GET', '/api/recados')) as List;
      expect({for (final r in lista) r['id']: r['ordem']}, {b['id']: 0, a['id']: 1});

      expect((await req('DELETE', '/api/recados/${a['id']}')).statusCode, 200);
      expect((await req('DELETE', '/api/recados/${a['id']}')).statusCode, 404);
    });

    test('validação', () async {
      expect((await req('POST', '/api/recados', json: {'titulo': '  '})).statusCode, 400);
      expect((await req('POST', '/api/recados', texto: 'não é json')).statusCode, 400);
      expect((await req('PUT', '/api/recados/naoexiste', json: {'titulo': 'x'})).statusCode, 404);
    });

    test('dados persistem no disco', () async {
      await req('POST', '/api/recados', json: {'titulo': 'Persistente'});
      await store.fechar();
      await criar();
      await logar();
      final lista = await corpo(await req('GET', '/api/recados')) as List;
      expect(lista.single['titulo'], 'Persistente');
    });
  });

  group('aniversariantes', () {
    test('recado automático aparece e não pode ser editado', () async {
      await store.fechar();
      await criar(agora: DateTime(2026, 10, 28));
      await req('POST', '/api/membros', json: {'nome': 'Ana', 'dia': 26, 'mes': 10, 'consentimentoEm': '2026-01-10'});
      await req('POST', '/api/membros', json: {'nome': 'Bia', 'dia': 5, 'mes': 11, 'consentimentoEm': '2026-01-10'});
      // Aniversário na semana, mas sem autorização da LGPD: fica só na ficha.
      await req('POST', '/api/membros', json: {'nome': 'Caio', 'dia': 27, 'mes': 10});
      final lista = await corpo(await req('GET', '/api/recados')) as List;
      expect(lista.single['id'], 'auto-aniversariantes');
      expect(lista.single['texto'], 'Ana (26/10)');
      final resumo = await corpo(await req('GET', '/api/resumo-semanal')) as Map;
      expect(resumo['texto'], contains('Ana (26/10)'));
      expect(resumo['texto'], isNot(contains('Caio')));
      expect((await corpo(await req('GET', '/api/membros')) as List).map((m) => m['nome']), contains('Caio'));
      expect((await req('PUT', '/api/recados/auto-aniversariantes', json: {'titulo': 'x'})).statusCode, 400);
    });

    test('membro com data inválida', () async {
      expect((await req('POST', '/api/membros', json: {'nome': 'Ana', 'dia': 31, 'mes': 2})).statusCode, 400);
    });

    test('importar CSV sem duplicar', () async {
      final r1 = await corpo(await req('POST', '/api/membros/importar', texto: 'Nome;Aniversário\nAna;12/03\nBruno;5/11\nErro;40/01'));
      expect(r1['importados'], 2);
      expect(r1['linhasComErro'], [4]);
      final r2 = await corpo(await req('POST', '/api/membros/importar', texto: 'Ana;12/03\nCarla;01/01'));
      expect(r2['importados'], 1);
      expect((await corpo(await req('GET', '/api/membros')) as List).length, 3);
    });
  });

  group('pedidos de oração pelo site', () {
    test('entra como aguardando, origem site, e é aprovado', () async {
      final r = await req('POST', '/api/public/pedidos',
          json: {'para': 'Irmã Maria', 'motivo': 'Cirurgia', 'tipo': 'saude', 'publico': true, 'enviadoPor': 'Ana'},
          autenticado: false);
      expect(r.statusCode, 201);
      final m = (await corpo(await req('GET', '/api/motivos')) as List).single;
      expect(m['status'], 'aguardando');
      expect(m['origem'], 'site');
      expect(m['publico'], true);

      final estado = await corpo(await req('GET', '/api/estado'));
      expect(estado['aguardandoAprovacao'], 1);

      final aprovado = await corpo(await req('POST', '/api/motivos/${m['id']}/aprovar'));
      expect(aprovado['status'], 'pendente');
    });

    test('público só se marcado explicitamente', () async {
      await req('POST', '/api/public/pedidos', json: {'motivo': 'Particular'}, autenticado: false);
      expect((await corpo(await req('GET', '/api/motivos')) as List).single['publico'], false);
    });

    test('honeypot descarta em silêncio; motivo vazio e longo recusados', () async {
      final robo = await req('POST', '/api/public/pedidos', json: {'motivo': 'spam', 'website': 'http://x'}, autenticado: false);
      expect(robo.statusCode, 200);
      expect(await corpo(await req('GET', '/api/motivos')), isEmpty);
      expect((await req('POST', '/api/public/pedidos', json: {'motivo': ' '}, autenticado: false)).statusCode, 400);
      expect((await req('POST', '/api/public/pedidos', json: {'motivo': 'a' * 501}, autenticado: false)).statusCode, 400);
    });

    test('limite de envios por IP', () async {
      await store.fechar();
      await criar(limitePedidos: LimiteTaxa(maximo: 2, janela: const Duration(minutes: 10)));
      await logar();
      for (var i = 0; i < 2; i++) {
        expect((await req('POST', '/api/public/pedidos', json: {'motivo': 'm$i'}, autenticado: false)).statusCode, 201);
      }
      expect((await req('POST', '/api/public/pedidos', json: {'motivo': 'm3'}, autenticado: false)).statusCode, 429);
    });

    test('motivo pelo app não pode fingir origem site; edição mantém origem', () async {
      final m = await corpo(await req('POST', '/api/motivos', json: {'motivo': 'Pela cidade', 'origem': 'site'}));
      expect(m['origem'], 'app');
      expect(m['status'], 'pendente');
      final e = await corpo(await req('PUT', '/api/motivos/${m['id']}', json: {'status': 'atendido', 'origem': 'painel'}));
      expect(e['status'], 'atendido');
      expect(e['origem'], 'app');
    });
  });

  group('cartazes', () {
    test('enviar, listar, servir e excluir', () async {
      final r = await corpo(await req('POST', '/api/cartazes?nome=Retiro de Casais.jpg', bytes: png));
      expect(r['nome'], 'retiro-de-casais.png'); // a extensão segue o conteúdo real
      expect(r['holyrics'], 'Diako/retiro-de-casais.png');
      final r2 = await corpo(await req('POST', '/api/cartazes?nome=Retiro de Casais.png', bytes: png));
      expect(r2['nome'], 'retiro-de-casais-2.png');

      final lista = await corpo(await req('GET', '/api/cartazes')) as List;
      expect(lista.length, 2);
      expect((await req('GET', '/cartazes/retiro-de-casais.png', autenticado: false)).statusCode, 200);

      expect((await req('DELETE', '/api/cartazes/retiro-de-casais.png')).statusCode, 200);
      expect((await corpo(await req('GET', '/api/cartazes')) as List).length, 1);
    });

    test('recusa arquivo que não é imagem e caminhos estranhos', () async {
      expect((await req('POST', '/api/cartazes?nome=x.jpg', bytes: utf8.encode('<script>'))).statusCode, 400);
      expect((await req('GET', '/cartazes/..%2Fdata%2Fsessoes.json', autenticado: false)).statusCode, 404);
      expect(Cartazes('x').arquivo('../segredo.png'), isNull);
    });

    test('nomeSeguro', () {
      expect(nomeSeguro('Ação de Graças 2026!'), 'acao-de-gracas-2026');
      expect(nomeSeguro('***'), '');
    });
  });

  group('holyrics', () {
    test('encaminha ações permitidas com o token do servidor', () async {
      final r = await req('POST', '/api/holyrics/ShowQuickPresentation', json: {'text': 'Oi'});
      expect(await corpo(r), {'status': 'ok'});
      final c = chamadasHolyrics.single;
      expect(c.url.toString(), 'http://127.0.0.1:8091/api/ShowQuickPresentation?token=tk');
      expect(jsonDecode(c.body), {'text': 'Oi'});
    });

    test('bloqueia ações fora da lista', () async {
      expect((await req('POST', '/api/holyrics/DeleteSong', json: {})).statusCode, 403);
      expect(chamadasHolyrics, isEmpty);
    });

    test('Holyrics fora do ar vira erro no formato do Holyrics', () async {
      final proxy = HolyricsDireto(host: 'h', porta: 1, token: 't', cliente: MockClient((_) async => throw const SocketException('x')));
      final r = await proxy.chamar('GetCPInfo', '{}');
      expect(jsonDecode(r.corpo)['status'], 'error');
      expect(await proxy.conectado(), isFalse);
    });
  });

  group('backup', () {
    test('gera zip com os dados e mantém só os mais recentes', () async {
      await req('POST', '/api/recados', json: {'titulo': 'No backup'});
      final b = Backup(
        pastaDados: p.join(tmp.path, 'data'),
        pastaDestino: p.join(tmp.path, 'backup'),
        manter: () => 3,
        configuracoes: () => {'nomeIgreja': 'Teste'},
      );
      for (var d = 1; d <= 5; d++) {
        await b.executar(agora: DateTime(2026, 10, d));
      }
      final arquivos = Directory(p.join(tmp.path, 'backup')).listSync().map((e) => p.basename(e.path)).toList()..sort();
      expect(arquivos, ['diako-backup-2026-10-03.zip', 'diako-backup-2026-10-04.zip', 'diako-backup-2026-10-05.zip']);

      final zip = ZipDecoder().decodeBytes(File(p.join(tmp.path, 'backup', arquivos.last)).readAsBytesSync());
      final recados = zip.findFile('data/recados.json')!;
      expect(utf8.decode(recados.content), contains('No backup'));
      expect(zip.findFile('configuracoes.json'), isNotNull);
      expect(zip.findFile('manifest.json'), isNotNull);
      expect(zip.files.any((f) => f.name.contains('sessoes')), isFalse);
      expect(await b.ultimo(), DateTime(2026, 10, 5));
    });
  });

  group('testemunhos, histórico, resumo e mural', () {
    setUp(() async {
      await store.fechar();
      await criar(agora: DateTime(2026, 10, 28, 10));
      await logar();
    });

    test('atendidoEm é preenchido pelo servidor e limpo ao voltar', () async {
      final m = await corpo(await req('POST', '/api/motivos', json: {'para': 'Ana', 'motivo': 'Emprego'}));
      expect(m['atendidoEm'], isNull);
      final a = await corpo(await req('PUT', '/api/motivos/${m['id']}',
          json: {'status': 'atendido', 'testemunho': 'Contratada!', 'atendidoEm': '2000-01-01T00:00:00.000'}));
      expect(a['atendidoEm'], DateTime(2026, 10, 28, 10).toIso8601String());
      expect(a['testemunho'], 'Contratada!');
      // Editar o testemunho depois não muda a data.
      final b = await corpo(await req('PUT', '/api/motivos/${m['id']}', json: {'testemunho': 'Contratada na segunda!'}));
      expect(b['atendidoEm'], a['atendidoEm']);
      final c = await corpo(await req('PUT', '/api/motivos/${m['id']}', json: {'status': 'pendente'}));
      expect(c['atendidoEm'], isNull);
    });

    test('projetar orações respondidas monta slides e registra no histórico', () async {
      expect((await req('POST', '/api/projetar/oracoes-respondidas')).statusCode, 400);
      final m = await corpo(await req('POST', '/api/motivos', json: {'para': 'Ana', 'motivo': 'Emprego'}));
      await req('PUT', '/api/motivos/${m['id']}', json: {'status': 'atendido', 'testemunho': 'Contratada!'});
      final r = await req('POST', '/api/projetar/oracoes-respondidas', json: {'tema': 'Avisos'});
      expect(await corpo(r), {'status': 'ok'});
      final enviado = jsonDecode(chamadasHolyrics.single.body) as Map;
      expect((enviado['slides'] as List).single['text'], '<styled><b>Orações respondidas</b>\n✓ Ana — Emprego\n   Contratada!');
      expect(enviado['theme'], {'name': 'Avisos'});

      final h = await corpo(await req('GET', '/api/historico')) as List;
      expect(h.single['descricao'], 'Orações respondidas');
    });

    test('histórico registra projeções e ignora consultas', () async {
      await req('POST', '/api/holyrics/GetCurrentPresentation', json: {});
      await req('POST', '/api/holyrics/ShowQuickPresentation', json: {
        'slides': [
          {'text': '<b>Motivos de oração (1/2)</b>\n• A'},
          {'text': '<b>Motivos de oração (2/2)</b>\n• B'},
        ]
      });
      await req('POST', '/api/holyrics/ShowImage', json: {'file': 'Diako/retiro.jpg'});
      await req('POST', '/api/holyrics/SetTextCP', json: {'text': '', 'show': false});
      final h = await corpo(await req('GET', '/api/historico')) as List;
      expect(h.map((e) => e['descricao']), ['Imagem: Diako/retiro.jpg', 'Motivos de oração (1/2) (2 slides)']);
      expect(h.first['quando'], DateTime(2026, 10, 28, 10).toIso8601String());
    });

    test('resumo semanal', () async {
      await req('POST', '/api/recados', json: {'titulo': 'Santa Ceia', 'texto': 'Domingo'});
      await req('POST', '/api/membros', json: {'nome': 'Pedro', 'dia': 31, 'mes': 10, 'consentimentoEm': '2026-01-10'});
      final t = (await corpo(await req('GET', '/api/resumo-semanal')))['texto'] as String;
      expect(t, contains('• *Santa Ceia* — Domingo'));
      expect(t, contains('• Pedro (31/10)'));
      expect(t, contains('http://192.168.0.10:8080/oracao'));
    });

    test('mural é público e não expõe pedidos particulares nem quem enviou', () async {
      await req('POST', '/api/recados', json: {'titulo': 'Retiro', 'imagemHolyrics': 'Diako/retiro.png'});
      await req('POST', '/api/cartazes?nome=retiro.png', bytes: png);
      await req('POST', '/api/recados', json: {'titulo': 'Cartaz sumido', 'imagemHolyrics': 'Diako/nao-existe.png'});
      await req('POST', '/api/public/pedidos', json: {'motivo': 'Segredo', 'publico': false, 'enviadoPor': 'Zé'}, autenticado: false);
      final pub = await corpo(await req('POST', '/api/motivos', json: {'para': 'Bia', 'motivo': 'Saúde'}));
      expect(pub['status'], 'pendente');

      final r = await req('GET', '/api/public/mural', autenticado: false);
      expect(r.statusCode, 200);
      final texto = await r.readAsString();
      expect(texto, isNot(contains('Segredo')));
      expect(texto, isNot(contains('Zé')));
      final slides = (jsonDecode(texto) as Map)['slides'] as List;
      expect(slides.map((s) => s['tipo']), ['imagem', 'texto', 'lista', 'qr', 'qr']);
      expect(slides.last['imagem'], '/qr-mensagens.png');
      expect(slides[0]['imagem'], '/cartazes/retiro.png');
      expect(slides[2]['itens'], ['Bia — Saúde']);
      expect((await req('GET', '/mural', autenticado: false)).statusCode, 404); // mural.html não existe no teste
    });

    test('backup inclui o histórico', () async {
      await req('POST', '/api/holyrics/ShowImage', json: {'file': 'Diako/x.png'});
      final b = await corpo(await req('POST', '/api/backup'));
      final zip = ZipDecoder().decodeBytes(File(b['arquivo'] as String).readAsBytesSync());
      expect(zip.findFile('data/historico.jsonl'), isNotNull);
    });
  });

  test('QR gera PNG', () {
    final bytes = gerarPngQr('http://192.168.0.10:8080/oracao');
    expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });

  test('WebSocket exige token', () async {
    expect((await req('GET', '/ws', autenticado: false)).statusCode, 401);
  });
}
