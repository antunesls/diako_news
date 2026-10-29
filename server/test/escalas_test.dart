import 'dart:convert';
import 'dart:io';

import 'package:diako_server/app.dart';
import 'package:diako_server/auth.dart';
import 'package:diako_server/backup.dart';
import 'package:diako_server/cartazes.dart';
import 'package:diako_server/config.dart';
import 'package:diako_server/configuracoes.dart';
import 'package:diako_server/historico.dart';
import 'package:diako_server/holyrics.dart';
import 'package:diako_server/permissoes.dart';
import 'package:diako_server/store.dart';
import 'package:diako_server/usuarios.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  test('rotas e perfis das escalas', () {
    expect(permissaoDaRota('GET', 'api/escalas'), Permissao.escalasVer);
    expect(permissaoDaRota('PUT', 'api/escalas/x'), Permissao.escalasVer); // o handler confere a escala
    expect(Perfil.comissaoLouvor.toJson()['id'], 'comissao-louvor');
    expect(Perfil.comissaoLouvor.permissoes, containsAll([Permissao.escalasVer, Permissao.escalaLouvor]));
    expect(Perfil.comissaoLouvor.pode(Permissao.escalaPastoral), isFalse);
    expect(Perfil.comissaoLouvor.pode(Permissao.membros), isFalse);
    expect(Perfil.porNome('louvor'), Perfil.louvor);
    expect(Usuario.fromJson({'id': 'x', 'login': 'x', 'perfil': 'louvor'}).toJson()['perfil'], 'louvor');
    expect(Perfil.louvor.permissoes, {Permissao.sessao, Permissao.minhaEscala});
    expect(Perfil.ministro.pode(Permissao.minhaEscala), isTrue);
    expect(Perfil.ministro.pode(Permissao.escalasVer), isFalse);
    expect(Perfil.ministro.pode(Permissao.escalaLouvor), isFalse);
    expect(Perfil.telao.pode(Permissao.escalasVer), isTrue);
    expect(Perfil.telao.pode(Permissao.escalaLouvor), isFalse);
    expect(Perfil.secretaria.pode(Permissao.escalaLouvor), isFalse);
    expect(Perfil.secretaria.pode(Permissao.escalaPastoral), isFalse);
    expect(Perfil.secretaria.pode(Permissao.acessosEscala), isTrue);
    for (final p in [Perfil.administrador, Perfil.pastor]) {
      expect(p.permissoes, containsAll([Permissao.escalaPastoral, Permissao.escalaLouvor]));
    }
  });

  group('servidor', () {
    late Directory tmp;
    late Store store;
    late Backup backup;
    late Handler handler;
    late String admin;
    // Quarta-feira, 28/10/2026.
    final agora = DateTime(2026, 10, 28, 10);

    Future<(int, dynamic)> chamar(String metodo, String caminho, {String? token, Object? json}) async {
      final r = await handler(Request(metodo, Uri.parse('http://x$caminho'),
          headers: {if (token != null) 'authorization': 'Bearer $token', 'content-type': 'application/json'},
          body: json == null ? null : jsonEncode(json)));
      final texto = await r.readAsString();
      return (r.statusCode, texto.startsWith('{') || texto.startsWith('[') ? jsonDecode(texto) : texto);
    }

    Future<String> criarUsuario(String login, Perfil perfil) async {
      final (_, j) = await chamar('POST', '/api/admin/usuarios',
          token: admin, json: {'nome': 'Usuário $login', 'login': login, 'perfil': perfil.id});
      final (_, l) = await chamar('POST', '/api/login', json: {'usuario': login, 'senha': j['senhaTemporaria']});
      return l['token'] as String;
    }

    Future<String> membro(String nome, {List<String> ministerios = const [], String? funcao}) async {
      final (st, m) = await chamar('POST', '/api/membros',
          token: admin, json: {'nome': nome, 'dia': 1, 'mes': 1, 'ministerios': ministerios, if (funcao != null) 'funcao': funcao});
      expect(st, 201, reason: '$m');
      return m['id'] as String;
    }

    Future<String> musica(String titulo, {String tom = ''}) async {
      final (st, m) = await chamar('POST', '/api/repertorio', token: admin,
          json: {'titulo': titulo, 'cantor': 'Cantor', 'tomDiakonia': tom});
      expect(st, 201);
      return m['id'] as String;
    }

    Future<Map> mes(String m, {String? token}) async => (await chamar('GET', '/api/escalas?mes=$m', token: token ?? admin)).$2 as Map;
    Map culto(Map escalas, String data) => (escalas['cultos'] as List).firstWhere((c) => c['data'] == data) as Map;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('diako_escalas');
      final config = Config.lerJson('{"senhaAdmin":"senha-principal"}', pastaBase: tmp.path);
      store = Store(config.pastaDados);
      await store.carregar();
      final cfg = await Configuracoes.carregar(config, urlDetectada: 'http://192.168.0.10:8080');
      final usuarios = Usuarios(config.pastaDados);
      final auth = Auth(conferirSenha: cfg.conferirSenha, pastaDados: config.pastaDados, usuarios: usuarios);
      backup = Backup(pastaDados: config.pastaDados, configuracoes: cfg.publicas);
      handler = Servidor(
        store: store,
        auth: auth,
        holyrics: HolyricsDireto(host: 'h', porta: 1, token: 't', cliente: MockClient((_) async => http.Response('{}', 200))),
        cartazes: Cartazes(config.pastaCartazes),
        backup: backup,
        pastaWeb: (Directory(p.join(tmp.path, 'web'))..createSync()).path,
        urlOracao: cfg.urlOracao,
        cartazesNoHolyrics: false,
        historico: Historico(config.pastaDados),
        cfg: cfg,
        relogio: () => agora,
      ).handler;
      final (_, l) = await chamar('POST', '/api/login', json: {'senha': 'senha-principal'});
      admin = l['token'] as String;
    });
    tearDown(() async {
      await store.fechar();
      await tmp.delete(recursive: true);
    });

    test('gera os cultos, escala, avisa conflitos e monta o texto do WhatsApp', () async {
      final (semHorario, erro) = await chamar('POST', '/api/escalas/gerar', token: admin, json: {'mes': '2026-11'});
      expect(semHorario, 400);
      expect(erro['erro'], contains('horários dos cultos'));
      await chamar('PUT', '/api/admin/configuracoes', token: admin, json: {'siteCultos': 'Domingo — 19h\nQuarta — 20h — Culto de oração'});

      final (st, g) = await chamar('POST', '/api/escalas/gerar', token: admin, json: {'mes': '2026-11'});
      expect(st, 200);
      expect(g['criados'], 9);
      // Gerar de novo não duplica.
      expect((await chamar('POST', '/api/escalas/gerar', token: admin, json: {'mes': '2026-11'})).$2['criados'], 0);

      final pr = await membro('Pr. André Souza', funcao: 'Pastor');
      final bruno = await membro('Bruno Reis', ministerios: ['Louvor']);
      await membro('Fulano Sem Ministério');

      var nov = await mes('2026-11');
      expect(nov['titulo'], 'novembro de 2026');
      expect((nov['cultos'] as List).length, 9);
      final dom1 = culto(nov, '2026-11-01');
      expect(dom1['ceia'], isTrue);
      expect(dom1['funcoes']['pastoral'], contains('Santa Ceia'));
      expect(culto(nov, '2026-11-04')['nome'], 'Culto de oração');
      expect(culto(nov, '2026-11-08')['funcoes']['pastoral'], isNot(contains('Santa Ceia')));
      final pessoas = {for (final x in nov['pessoas'] as List) x['nome']: x};
      expect(pessoas['Pr. André Souza']['pastoral'], isTrue);
      expect(pessoas['Bruno Reis']['louvor'], isTrue);
      expect(pessoas['Fulano Sem Ministério']['louvor'], isFalse);

      final id8 = culto(nov, '2026-11-08')['id'];
      await chamar('PUT', '/api/escalas/$id8', token: admin, json: {'tipo': 'pastoral', 'funcao': 'Pregação', 'membros': [bruno]});
      final (stPut, c8) = await chamar('PUT', '/api/escalas/$id8', token: admin, json: {'tipo': 'louvor', 'funcao': 'Violão', 'membros': [bruno]});
      expect(stPut, 200);
      expect(c8['louvor']['Violão'].single, {'id': bruno, 'nome': 'Bruno Reis', 'aviso': 'Também na pregação'});
      expect((await chamar('PUT', '/api/escalas/$id8', token: admin, json: {'tipo': 'louvor', 'funcao': 'Sax', 'membros': [bruno]})).$1, 400);
      expect((await chamar('PUT', '/api/escalas/$id8', token: admin, json: {'tipo': 'louvor', 'funcao': 'Violão', 'membros': ['nao-existe']})).$1, 400);
      await chamar('PUT', '/api/escalas/${dom1['id']}', token: admin, json: {'tipo': 'pastoral', 'funcao': 'Pregação', 'membros': [pr]});
      final abertura = await musica('Abertura', tom: 'G');
      await chamar('PUT', '/api/escalas/${dom1['id']}', token: admin,
          json: {'musicas': [{'repertorioId': abertura, 'tom': 'G'}], 'tema': 'Graça'});

      nov = await mes('2026-11');
      final avisosLouvor = nov['avisos']['louvor'] as List;
      expect(avisosLouvor.first['titulo'], 'Bruno Reis em duas funções no dia 08/11');
      expect(avisosLouvor.last['tipo'], 'vazias');
      expect(nov['whatsapp']['pastoral'], contains('*Dom 01/11 · 19h* (Santa Ceia)\nPregação: Pr. Souza\nTema: Graça'));
      expect(nov['whatsapp']['louvor'], contains('Músicas: Abertura (G)'));

      // Indisponibilidade aparece como aviso na pessoa.
      final (stInd, ind) = await chamar('POST', '/api/escalas/indisponibilidades', token: admin,
          json: {'membroId': bruno, 'de': '2026-11-07', 'ate': '2026-11-09', 'motivo': 'viagem'});
      expect(stInd, 201);
      expect(culto(await mes('2026-11'), '2026-11-08')['louvor']['Violão'].single['aviso'], 'Indisponível');
      expect((await mes('2026-11'))['indisponibilidades'].single['nome'], 'Bruno Reis');
      await chamar('DELETE', '/api/escalas/indisponibilidades/${ind['id']}', token: admin);
      expect((await mes('2026-11'))['indisponibilidades'], isEmpty);

      // Culto extra; mesmo dia e hora não duplica; excluir.
      final (stExtra, extra) = await chamar('POST', '/api/escalas', token: admin,
          json: {'data': '2026-11-20', 'hora': '19h30', 'nome': 'Vigília'});
      expect(stExtra, 201);
      expect(extra['horaTexto'], '19h30');
      expect((await chamar('POST', '/api/escalas', token: admin, json: {'data': '2026-11-20', 'hora': '19:30'})).$1, 409);
      expect((await chamar('DELETE', '/api/escalas/${extra['id']}', token: admin)).$1, 200);
    });

    test('repetir o mês anterior preenche só as funções vazias, pelo mesmo culto da semana', () async {
      await chamar('PUT', '/api/admin/configuracoes', token: admin, json: {'siteCultos': 'Domingo — 19h\nQuarta — 20h'});
      final ana = await membro('Ana Lima', ministerios: ['Louvor']);
      final rui = await membro('Rui Melo', ministerios: ['Louvor']);
      await chamar('POST', '/api/escalas/gerar', token: admin, json: {'mes': '2026-10'});
      final out = await mes('2026-10');
      // 1º domingo de outubro (04) e 2ª quarta (14).
      await chamar('PUT', '/api/escalas/${culto(out, '2026-10-04')['id']}', token: admin, json: {'tipo': 'louvor', 'funcao': 'Teclado', 'membros': [ana]});
      await chamar('PUT', '/api/escalas/${culto(out, '2026-10-14')['id']}', token: admin, json: {'tipo': 'louvor', 'funcao': 'Bateria', 'membros': [rui]});

      expect((await chamar('POST', '/api/escalas/repetir', token: admin, json: {'mes': '2026-11', 'tipo': 'louvor'})).$1, 400);
      await chamar('POST', '/api/escalas/gerar', token: admin, json: {'mes': '2026-11'});
      // O 1º domingo de novembro já tem tecladista: não é trocado.
      final nov = await mes('2026-11');
      await chamar('PUT', '/api/escalas/${culto(nov, '2026-11-01')['id']}', token: admin, json: {'tipo': 'louvor', 'funcao': 'Teclado', 'membros': [rui]});

      final (st, r) = await chamar('POST', '/api/escalas/repetir', token: admin, json: {'mes': '2026-11', 'tipo': 'louvor'});
      expect(st, 200);
      expect(r['preenchidas'], 1);
      final depois = await mes('2026-11');
      expect(culto(depois, '2026-11-01')['louvor']['Teclado'].single['nome'], 'Rui Melo');
      expect(culto(depois, '2026-11-11')['louvor']['Bateria'].single['nome'], 'Rui Melo'); // 2ª quarta
      expect(culto(depois, '2026-11-04')['louvor']['Bateria'], isEmpty);
    });

    test('Comissão do Louvor monta só o louvor; Mídia só vê; tablet vê o próximo culto', () async {
      await chamar('PUT', '/api/admin/configuracoes', token: admin, json: {'siteCultos': 'Domingo — 19h'});
      await chamar('POST', '/api/escalas/gerar', token: admin, json: {'mes': '2026-11'});
      final bruno = await membro('Bruno Reis', ministerios: ['Louvor']);
      final lider = await criarUsuario('lider.louvor', Perfil.comissaoLouvor);
      final secretaria = await criarUsuario('secretaria.escala', Perfil.secretaria);
      final midia = await criarUsuario('midia', Perfil.midia);
      final id = culto(await mes('2026-11'), '2026-11-01')['id'];

      expect((await chamar('PUT', '/api/escalas/$id', token: lider, json: {'tipo': 'louvor', 'funcao': 'Violão', 'membros': [bruno]})).$1, 200);
      final abertura = await musica('Abertura');
      expect((await chamar('PUT', '/api/escalas/$id', token: secretaria,
          json: {'musicas': [{'repertorioId': abertura}]})).$1, 403);
      expect((await chamar('PUT', '/api/escalas/$id', token: secretaria,
          json: {'tipo': 'louvor', 'funcao': 'Ministro', 'membros': [bruno]})).$1, 403);
      expect((await chamar('PUT', '/api/escalas/$id', token: secretaria,
          json: {'tipo': 'pastoral', 'funcao': 'Pregação', 'membros': [bruno]})).$1, 403);
      expect((await chamar('POST', '/api/repertorio', token: secretaria,
          json: {'titulo': 'Bloqueada'})).$1, 403);
      expect((await chamar('PUT', '/api/escalas/$id', token: lider, json: {'musicas': [{'repertorioId': abertura}]})).$1, 200);
      expect((await chamar('PUT', '/api/escalas/$id', token: lider, json: {'tipo': 'pastoral', 'funcao': 'Pregação', 'membros': [bruno]})).$1, 403);
      expect((await chamar('PUT', '/api/escalas/$id', token: lider, json: {'ceia': false})).$1, 403);
      expect((await chamar('POST', '/api/escalas', token: lider, json: {'data': '2026-11-20', 'hora': '19h'})).$1, 403);
      expect((await chamar('POST', '/api/escalas/gerar', token: lider, json: {'mes': '2026-12'})).$1, 403);
      expect((await mes('2026-12'))['cultos'], isEmpty);
      expect((await chamar('DELETE', '/api/escalas/$id', token: lider)).$1, 403);
      expect((await chamar('GET', '/api/membros', token: lider)).$1, 403);
      expect((await mes('2026-11', token: lider))['pode'], {'pastoral': false, 'louvor': true});

      final visto = await mes('2026-11', token: midia);
      expect(visto['pessoas'], isEmpty); // nomes do cadastro só para quem monta escala
      expect(culto(visto, '2026-11-01')['louvor']['Violão'].single['nome'], 'Bruno Reis');
      expect((await chamar('PUT', '/api/escalas/$id', token: midia, json: {'musicas': []})).$1, 403);
      expect((await chamar('POST', '/api/escalas/gerar', token: midia, json: {'mes': '2026-12'})).$1, 403);

      // Quarta 28/10 sem culto: o tablet recebe o próximo (domingo 01/11).
      final (_, hoje) = await chamar('GET', '/api/escalas/hoje', token: midia);
      expect(hoje['hoje'], isFalse);
      expect(hoje['cultos'].single['rotulo'], 'Dom 01/11');
      expect(hoje['cultos'].single['musicas'].single['titulo'], 'Abertura');
    });

    test('consulta todos os avisos ativos com autor e envio; cancelar remove da lista', () async {
      final bruno = await membro('Bruno Reis', ministerios: ['Louvor']);
      final pastor = await criarUsuario('pastor.aviso', Perfil.pastor);
      final secretaria = await criarUsuario('secretaria.aviso', Perfil.secretaria);
      final midia = await criarUsuario('midia.aviso', Perfil.midia);
      expect((await chamar('POST', '/api/escalas/indisponibilidades', token: secretaria,
          json: {'membroId': bruno, 'de': '2027-01-05'})).$1, 403);
      final (st, criado) = await chamar('POST', '/api/escalas/indisponibilidades', token: pastor,
          json: {'membroId': bruno, 'de': '2027-01-05', 'ate': '2027-01-07', 'motivo': 'viagem',
            'enviadoPor': 'nome-falso', 'enviadoEm': '1999-01-01'});
      expect(st, 201);
      expect(criado['enviadoPor'], 'Usuário pastor.aviso');
      expect(criado['enviadoEm'], startsWith('2026-10-28T'));
      await store.salvar('indisponibilidades', {'id': 'legado', 'membroId': bruno,
        'de': '2025-01-01', 'ate': '2025-01-02'});
      expect((await chamar('GET', '/api/escalas/indisponibilidades')).$1, 401);
      expect((await chamar('GET', '/api/escalas/indisponibilidades', token: midia)).$1, 200);
      final (stLista, lista) = await chamar('GET', '/api/escalas/indisponibilidades', token: secretaria);
      expect(stLista, 200);
      expect(lista, hasLength(2));
      expect(lista.first, containsPair('nome', 'Bruno Reis'));
      expect(lista.first, containsPair('enviadoPor', 'Usuário pastor.aviso'));
      expect(lista.last['enviadoEm'], isNull);
      expect(lista.last['enviadoPor'], isNull);
      expect((await chamar('DELETE', '/api/escalas/indisponibilidades/${criado['id']}', token: midia)).$1, 403);
      expect((await chamar('DELETE', '/api/escalas/indisponibilidades/${criado['id']}', token: secretaria)).$1, 403);
      expect((await chamar('DELETE', '/api/escalas/indisponibilidades/${criado['id']}', token: pastor)).$1, 200);
      expect((await chamar('GET', '/api/escalas/indisponibilidades', token: secretaria)).$2, hasLength(1));
    });

    test('baixa PDF autenticado dos dois formatos sem cultos vazios', () async {
      await chamar('PUT', '/api/admin/configuracoes', token: admin, json: {'siteCultos': 'Domingo — 19h'});
      await chamar('POST', '/api/escalas/gerar', token: admin, json: {'mes': '2026-11'});
      final cultoId = culto(await mes('2026-11'), '2026-11-01')['id'];
      final abertura = await musica('Abertura', tom: 'G');
      await chamar('PUT', '/api/escalas/$cultoId', token: admin,
          json: {'musicas': [{'repertorioId': abertura}]});
      const basePdf = '/api/escalas/pdf?mes=2026-11&tipo=louvor&formato=';
      expect((await chamar('GET', '${basePdf}paisagem')).$1, 401);
      expect((await chamar('GET', '${basePdf}paisagem', token: admin)).$1, 400);
      expect((await chamar('GET', '${basePdf}outro', token: admin)).$1, 400);
      expect((await chamar('GET', '/api/escalas/pdf?mes=invalido&tipo=louvor&formato=retrato', token: admin)).$1, 400);
      final bruno = await membro('Bruno Reis', ministerios: ['Louvor']);
      await chamar('PUT', '/api/escalas/$cultoId', token: admin,
          json: {'tipo': 'louvor', 'funcao': 'Vocal', 'membros': [bruno]});
      for (final formato in ['paisagem', 'retrato']) {
        final r = await handler(Request('GET', Uri.parse('http://x$basePdf$formato'),
            headers: {'authorization': 'Bearer $admin'}));
        expect(r.statusCode, 200);
        expect(r.headers['content-type'], 'application/pdf');
        expect(r.headers['content-disposition'], contains('attachment; filename="escala-louvor-2026-11-$formato.pdf"'));
        final bytes = await r.read().expand((chunk) => chunk).toList();
        expect(bytes.length, greaterThan(1000));
        expect(latin1.decode(bytes.take(5).toList()), '%PDF-');
      }
      expect((await chamar('GET', '/api/escalas/pdf?mes=2026-11&tipo=pastoral&formato=retrato', token: admin)).$1, 400);
    });

    test('Minha escala: login vinculado, isolamento, secretaria e QR comum', () async {
      await chamar('PUT', '/api/admin/configuracoes', token: admin, json: {'siteCultos': 'Domingo — 19h\nQuarta — 20h'});
      await chamar('POST', '/api/escalas/gerar', token: admin, json: {'mes': '2026-11'});
      final bruno = await membro('Bruno Reis', ministerios: ['Louvor']);
      final ana = await membro('Ana Lima', ministerios: ['Louvor']);
      final nov = await mes('2026-11');
      await chamar('PUT', '/api/escalas/${culto(nov, '2026-11-01')['id']}', token: admin, json: {'tipo': 'louvor', 'funcao': 'Violão', 'membros': [bruno]});
      final abertura = await musica('Abertura', tom: 'G');
      await chamar('PUT', '/api/repertorio/$abertura', token: admin,
          json: {'referencia': 'https://youtu.be/dQw4w9WgXcQ?t=10'});
      await chamar('PUT', '/api/escalas/${culto(nov, '2026-11-01')['id']}', token: admin, json: {'musicas': [{'repertorioId': abertura, 'tom': 'G'}]});
      await chamar('PUT', '/api/escalas/${culto(nov, '2026-11-04')['id']}', token: admin, json: {'tipo': 'louvor', 'funcao': 'Vocal', 'membros': [ana]});

      expect((await chamar('POST', '/api/escalas/link/$bruno', token: admin)).$1, 404);
      expect((await chamar('POST', '/api/public/minha-escala', json: {'token': 'x' * 30})).$1, 404);
      expect((await chamar('GET', '/api/minha-escala')).$1, 401);
      final secretaria = await criarUsuario('secretaria1', Perfil.secretaria);
      expect((await chamar('GET', '/api/admin/usuarios', token: secretaria)).$1, 403);
      final (st, criado) = await chamar('POST', '/api/acessos-escala', token: secretaria,
          json: {'membroId': bruno, 'nome': 'Bruno Reis', 'login': 'bruno.reis'});
      expect(st, 201);
      final (_, login) = await chamar('POST', '/api/login', json: {'usuario': 'bruno.reis', 'senha': criado['senhaTemporaria']});
      final acesso = login['token'] as String;
      expect((await chamar('GET', '/api/escalas', token: acesso)).$1, 403);
      expect((await chamar('GET', '/api/minha-escala', token: secretaria)).$1, 403);
      expect((await chamar('POST', '/api/acessos-escala', token: secretaria,
          json: {'membroId': bruno, 'nome': 'Outro', 'login': 'outro1'})).$1, 400);
      final (stMinha, minha) = await chamar('GET', '/api/minha-escala', token: acesso);
      expect(stMinha, 200);
      expect(minha['nome'], 'Bruno');
      expect((minha['cultos'] as List).map((c) => c['data']), ['2026-11-01']);
      expect(minha['cultos'].single['funcoes'], [{'tipo': 'louvor', 'funcao': 'Violão'}]);
      expect(minha['cultos'].single['musicas'].single, {
        'repertorioId': abertura, 'titulo': 'Abertura', 'tom': 'G',
        'youtube': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      });

      expect((await chamar('POST', '/api/minha-escala/indisponivel', token: acesso, json: {'de': '2026-10-01'})).$1, 400);
      final (stInd, ind) = await chamar('POST', '/api/minha-escala/indisponivel', token: acesso,
          json: {'membroId': ana, 'de': '2026-11-15', 'ate': '2026-11-16', 'motivo': 'viagem'});
      expect(stInd, 201);
      expect(ind['membroId'], bruno);
      expect(ind['enviadoPor'], 'Bruno Reis');
      expect(ind['enviadoEm'], startsWith('2026-10-28T'));
      expect((await chamar('GET', '/api/escalas/indisponibilidades', token: acesso)).$1, 403);
      expect((await chamar('GET', '/api/minha-escala', token: acesso)).$2['indisponibilidades'].single['motivo'], 'viagem');
      // A indisponibilidade de outra pessoa não pode ser removida por esta conta.
      final (_, daAna) = await chamar('POST', '/api/escalas/indisponibilidades', token: admin, json: {'membroId': ana, 'de': '2026-11-20'});
      expect((await chamar('POST', '/api/minha-escala/indisponivel/remover', token: acesso, json: {'id': daAna['id']})).$1, 404);
      expect((await chamar('POST', '/api/minha-escala/indisponivel/remover', token: acesso, json: {'id': ind['id']})).$1, 200);
      final qr = await handler(Request('GET', Uri.parse('http://x/qr-minha-escala.png')));
      expect(qr.statusCode, 200);
      expect(qr.headers['content-type'], 'image/png');
      expect((await chamar('POST', '/api/acessos-escala/vincular', token: acesso,
          json: {'usuarioId': criado['usuario']['id'], 'membroId': ana})).$1, 403);
      expect((await chamar('POST', '/api/acessos-escala/${criado['usuario']['id']}/senha', token: secretaria)).$1, 200);
      expect((await chamar('GET', '/api/minha-escala', token: acesso)).$1, 401);
      // Pastor existente pode ser vinculado sem criar segunda conta.
      final pastor = await criarUsuario('pastor1', Perfil.pastor);
      final pr = await membro('Pr. João', funcao: 'Pastor');
      await chamar('PUT', '/api/escalas/${culto(nov, '2026-11-01')['id']}', token: admin,
          json: {'tipo': 'pastoral', 'funcao': 'Pregação', 'membros': [pr]});
      final usuarios = (await chamar('GET', '/api/acessos-escala', token: secretaria)).$2['usuarios'] as List;
      final pastorId = usuarios.firstWhere((u) => u['login'] == 'pastor1')['id'];
      expect((await chamar('POST', '/api/acessos-escala/vincular', token: secretaria,
          json: {'usuarioId': pastorId, 'membroId': pr})).$1, 200);
      final (stPastor, minhaPastoral) = await chamar('GET', '/api/minha-escala', token: pastor);
      expect(stPastor, 200);
      expect(minhaPastoral['cultos'].single['musicas'].single['youtube'], 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      await chamar('PUT', '/api/repertorio/$abertura', token: admin,
          json: {'referencia': 'https://youtube.com.evil.test/watch?v=dQw4w9WgXcQ'});
      expect((await chamar('GET', '/api/minha-escala', token: pastor)).$2['cultos'].single['musicas'].single.containsKey('youtube'), false);
      expect((await chamar('POST', '/api/acessos-escala/$pastorId/senha', token: secretaria)).$1, 404);
    });

    test('ministro escolhe músicas apenas no próprio culto, sem editar pessoas ou repertório', () async {
      await chamar('PUT', '/api/admin/configuracoes', token: admin, json: {'siteCultos': 'Domingo — 19h'});
      await chamar('POST', '/api/escalas/gerar', token: admin, json: {'mes': '2026-11'});
      final cultos = await mes('2026-11');
      final primeiro = culto(cultos, '2026-11-01')['id'] as String;
      final segundo = culto(cultos, '2026-11-08')['id'] as String;
      final pessoa = await membro('Ana Ministra', ministerios: ['Louvor']);
      final outra = await membro('Outra Ministra', ministerios: ['Louvor']);
      await chamar('PUT', '/api/escalas/$primeiro', token: admin,
          json: {'tipo': 'louvor', 'funcao': 'Ministro', 'membros': [pessoa]});
      await chamar('PUT', '/api/escalas/$segundo', token: admin,
          json: {'tipo': 'louvor', 'funcao': 'Ministro', 'membros': [outra]});
      final cancion = await musica('Canção', tom: 'G');
      final ministro = await criarUsuario('ana.ministra', Perfil.ministro);
      final integrante = await criarUsuario('outro.integrante', Perfil.integrante);
      final usuarios = (await chamar('GET', '/api/acessos-escala', token: admin)).$2['usuarios'] as List;
      final usuarioId = usuarios.firstWhere((u) => u['login'] == 'ana.ministra')['id'];
      expect((await chamar('POST', '/api/acessos-escala/vincular', token: admin,
          json: {'usuarioId': usuarioId, 'membroId': pessoa})).$1, 200);
      final minha = (await chamar('GET', '/api/minha-escala', token: ministro)).$2 as Map;
      expect(minha['cultos'].single['podeEscolherMusicas'], true);
      expect(minha['repertorio'], isNotEmpty);
      expect((await chamar('PUT', '/api/minha-escala/cultos/$primeiro/musicas', token: ministro,
          json: {'musicas': [{'repertorioId': cancion, 'tom': 'D'}]})).$1, 200);
      expect((await chamar('GET', '/api/minha-escala', token: ministro)).$2['cultos'].single['musicas'].single['tom'], 'D');
      expect((await chamar('PUT', '/api/minha-escala/cultos/$segundo/musicas', token: ministro,
          json: {'musicas': []})).$1, 403);
      expect((await chamar('PUT', '/api/minha-escala/cultos/$primeiro/musicas', token: ministro,
          json: {'musicas': [{'repertorioId': 'inexistente'}]})).$1, 400);
      expect((await chamar('PUT', '/api/minha-escala/cultos/$primeiro/musicas', token: ministro,
          json: {'musicas': [], 'louvor': {}})).$1, 400);
      expect((await chamar('PUT', '/api/minha-escala/cultos/$primeiro/musicas', token: integrante,
          json: {'musicas': []})).$1, 403);
      expect((await chamar('PUT', '/api/escalas/$primeiro', token: ministro,
          json: {'musicas': []})).$1, 403);
      expect((await chamar('POST', '/api/repertorio', token: ministro,
          json: {'titulo': 'Nova'})).$1, 403);
      await chamar('PUT', '/api/escalas/$primeiro', token: admin,
          json: {'tipo': 'louvor', 'funcao': 'Ministro', 'membros': [outra]});
      expect((await chamar('PUT', '/api/minha-escala/cultos/$primeiro/musicas', token: ministro,
          json: {'musicas': []})).$1, 403);
      expect(culto(await mes('2026-11'), '2026-11-01')['musicas'].single['tom'], 'D');
    });

    test('Louvor vê somente a própria escala e músicas, sem poder alterar dados', () async {
      await chamar('PUT', '/api/admin/configuracoes', token: admin, json: {'siteCultos': 'Domingo — 19h'});
      await chamar('POST', '/api/escalas/gerar', token: admin, json: {'mes': '2026-11'});
      final idCulto = culto(await mes('2026-11'), '2026-11-01')['id'] as String;
      final bruno = await membro('Bruno', ministerios: ['Louvor']);
      final ana = await membro('Ana', ministerios: ['Louvor']);
      final abertura = await musica('Abertura');
      await chamar('PUT', '/api/escalas/$idCulto', token: admin,
          json: {'tipo': 'louvor', 'funcao': 'Vocal', 'membros': [bruno]});
      await chamar('PUT', '/api/escalas/$idCulto', token: admin,
          json: {'musicas': [{'repertorioId': abertura}]});
      final (stCriacao, criado) = await chamar('POST', '/api/admin/usuarios', token: admin,
          json: {'nome': 'Bruno', 'login': 'bruno.louvor', 'perfil': 'louvor'});
      expect(stCriacao, 201);
      final (_, login) = await chamar('POST', '/api/login',
          json: {'usuario': 'bruno.louvor', 'senha': criado['senhaTemporaria']});
      final acesso = login['token'] as String;
      expect((await chamar('GET', '/api/minha-escala', token: acesso)).$1, 403); // falta vínculo
      expect((await chamar('POST', '/api/acessos-escala/vincular', token: admin,
          json: {'usuarioId': criado['usuario']['id'], 'membroId': bruno})).$1, 200);
      final (stMinha, minha) = await chamar('GET', '/api/minha-escala', token: acesso);
      expect(stMinha, 200);
      expect(minha['cultos'].single['musicas'].single['titulo'], 'Abertura');
      expect(minha['cultos'].single['podeEscolherMusicas'], false);
      expect(minha['indisponibilidades'], isEmpty);
      expect(minha['podeAvisarIndisponibilidade'], false);
      expect(minha.containsKey('repertorio'), false);
      expect((await chamar('GET', '/api/escalas', token: acesso)).$1, 403);
      expect((await chamar('GET', '/api/repertorio', token: acesso)).$1, 403);
      expect((await chamar('PUT', '/api/escalas/$idCulto', token: acesso,
          json: {'musicas': []})).$1, 403);
      expect((await chamar('PUT', '/api/minha-escala/cultos/$idCulto/musicas', token: acesso,
          json: {'musicas': []})).$1, 403);
      expect((await chamar('POST', '/api/minha-escala/indisponivel', token: acesso,
          json: {'de': '2026-11-05', 'membroId': ana})).$1, 403);
      expect((await chamar('POST', '/api/minha-escala/indisponivel/remover', token: acesso,
          json: {'id': 'qualquer'})).$1, 403);
    });

    test('repertório: prévia, importação sem sobrescrever, edição e músicas vinculadas na escala', () async {
      const csv = 'Louvor,Cantor,Status,Tom Diakonia,Observações\n'
          'Santo pra sempre,Marine Friesen,Ok,"F\nComeça com Bb",Teste\n'
          'Em análise,Outro cantor,Pendente,D,Nota';
      final (stPreview, previa) = await chamar('POST', '/api/repertorio/importar/previa', token: admin, json: {'csv': csv});
      expect(stPreview, 200);
      expect(previa['novas'], 2);
      expect(previa['musicas'][0]['tomDiakonia'], 'F\nComeça com Bb');

      final (stImport, importado) = await chamar('POST', '/api/repertorio/importar', token: admin, json: {'csv': csv});
      expect(stImport, 200);
      expect(importado['importadas'], 2);
      final lista = (await chamar('GET', '/api/repertorio', token: admin)).$2 as List;
      final ativo = lista.firstWhere((m) => m['titulo'] == 'Santo pra sempre') as Map;
      final inativo = lista.firstWhere((m) => m['titulo'] == 'Em análise') as Map;
      expect(ativo['ativo'], true);
      expect(inativo['ativo'], false);
      expect(ativo['tomDiakonia'], 'F\nComeça com Bb');

      expect((await chamar('PUT', '/api/repertorio/${ativo['id']}', token: admin,
          json: {...ativo, 'tomDiakonia': 'G'})).$1, 200);
      expect((await chamar('POST', '/api/repertorio/importar', token: admin, json: {'csv': csv})).$2['importadas'], 0);
      expect(((await chamar('GET', '/api/repertorio', token: admin)).$2 as List).first['tomDiakonia'], 'G');

      await chamar('PUT', '/api/admin/configuracoes', token: admin, json: {'siteCultos': 'Domingo — 19h'});
      await chamar('POST', '/api/escalas/gerar', token: admin, json: {'mes': '2026-11'});
      final id = culto(await mes('2026-11'), '2026-11-01')['id'];
      expect((await chamar('PUT', '/api/escalas/$id', token: admin,
          json: {'musicas': [{'titulo': 'Inventada', 'tom': 'G'}]})).$1, 400);
      expect((await chamar('PUT', '/api/escalas/$id', token: admin,
          json: {'musicas': [{'repertorioId': inativo['id'], 'titulo': 'Em análise', 'tom': 'D'}]})).$1, 400);
      final (_, padrao) = await chamar('PUT', '/api/escalas/$id', token: admin,
          json: {'musicas': [{'repertorioId': ativo['id']}]});
      expect(padrao['musicas'].single['tom'], 'G');
      final (stCulto, editado) = await chamar('PUT', '/api/escalas/$id', token: admin,
          json: {'musicas': [{'repertorioId': ativo['id'], 'titulo': 'Santo pra sempre', 'tom': 'A'}]});
      expect(stCulto, 200);
      expect(editado['musicas'].single['tom'], 'A');
      expect(editado['musicas'].single['repertorioId'], ativo['id']);
      expect((await chamar('PUT', '/api/repertorio/${ativo['id']}', token: admin,
          json: {...ativo, 'ativo': false})).$1, 200);
      expect(culto(await mes('2026-11'), '2026-11-01')['musicas'].single['tom'], 'A');
      expect((await chamar('PUT', '/api/escalas/$id', token: admin,
          json: {'musicas': [{'repertorioId': ativo['id'], 'tom': 'A'}]})).$1, 200);
    });

    test('status editado controla disponibilidade sem alterar registros antigos automaticamente', () async {
      final (st, criada) = await chamar('POST', '/api/repertorio', token: admin,
          json: {'titulo': 'Nova canção', 'cantor': 'Banda', 'status': 'Em análise', 'tomSelecionado': 'A#m', 'ativo': true});
      expect(st, 201);
      expect(criada['ativo'], false);
      expect(criada['tomPadrao'], isNull); // A sugestão é calculada no modelo, não gravada na resposta.
      final id = criada['id'];
      expect((await chamar('PUT', '/api/repertorio/$id', token: admin, json: {'status': 'OK'})).$2['ativo'], true);
      expect((await chamar('PUT', '/api/repertorio/$id', token: admin, json: {'status': 'Outro'})).$1, 400);
      final (_, previa) = await chamar('POST', '/api/repertorio/importar/previa', token: admin,
          json: {'csv': 'Louvor,Cantor,Status\nLegada,Outro,Pendente'});
      expect(previa['musicas'].single['ativo'], false);
      expect(previa['musicas'].single['status'], 'Pendente');
    });

    test('Comissão do Louvor mantém repertório, Mídia só consulta', () async {
      final lider = await criarUsuario('lider.repertorio', Perfil.comissaoLouvor);
      final midia = await criarUsuario('midia.repertorio', Perfil.midia);
      final (st, criada) = await chamar('POST', '/api/repertorio', token: lider,
          json: {'titulo': 'Nova música', 'cantor': 'Cantor', 'tomDiakonia': 'C'});
      expect(st, 201);
      expect((await chamar('GET', '/api/repertorio', token: midia)).$1, 200);
      expect((await chamar('POST', '/api/repertorio', token: midia,
          json: {'titulo': 'Outra', 'cantor': 'Outro'})).$1, 403);
      expect((await chamar('PUT', '/api/repertorio/${criada['id']}', token: midia,
          json: {'titulo': 'Outra', 'cantor': 'Outro'})).$1, 403);
    });

    test('músicas antigas são preservadas e podem ser vinculadas sem alterar o tom', () async {
      await store.salvar('escalas', {
        'id': 'antigo', 'data': '2026-11-01', 'hora': '19:00', 'nome': 'Culto',
        'pastoral': <String, dynamic>{}, 'louvor': <String, dynamic>{},
        'musicas': [{'titulo': 'Canção antiga', 'tom': 'D'}],
      });
      expect(culto(await mes('2026-11'), '2026-11-01')['musicas'].single['titulo'], 'Canção antiga');
      expect((await chamar('PUT', '/api/escalas/antigo', token: admin,
          json: {'musicas': [{'titulo': 'Canção antiga', 'tom': 'D'}]})).$1, 200);
      final id = await musica('Canção antiga', tom: 'G');
      final (st, c) = await chamar('PUT', '/api/escalas/antigo', token: admin,
          json: {'musicas': [{'repertorioId': id, 'tom': 'D'}]});
      expect(st, 200);
      expect(c['musicas'].single, {'titulo': 'Canção antiga', 'tom': 'D', 'repertorioId': id});
    });

    test('backup e restauração preservam o repertório', () async {
      final id = await musica('Bondade de Deus', tom: 'D');
      final zip = await backup.gerarZip();
      await store.substituir('repertorio', []);
      expect(store.listar('repertorio'), isEmpty);
      final restauracao = Restauracao(store: store, backup: backup,
          pastaDados: store.pasta, pastaCartazes: p.join(tmp.path, 'cartazes'));
      await restauracao.restaurar(zip);
      expect(store.buscar('repertorio', id)?['titulo'], 'Bondade de Deus');
    });
  });
}
