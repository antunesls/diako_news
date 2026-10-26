import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:diako_core/diako_core.dart';
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
  test('rotas das visitas na matriz de permissões', () {
    expect(permissaoDaRota('GET', 'api/visitas'), Permissao.visitantes);
    expect(permissaoDaRota('POST', 'api/visitas'), Permissao.visitantesCadastrar);
    expect(permissaoDaRota('POST', 'api/visitas/x/mencionada'), Permissao.visitantes);
    expect(permissaoDaRota('PUT', 'api/visitas/x/contato'), Permissao.membros);
    expect(permissaoDaRota('POST', 'api/projetar/boas-vindas'), Permissao.projetar);
    expect(Perfil.recepcao.permissoes, {Permissao.sessao, Permissao.visitantes, Permissao.visitantesCadastrar});
  });

  group('servidor', () {
    late Directory tmp;
    late Store store;
    late Handler handler;
    late String admin;
    late Restauracao restauracao;
    String? ultimoHolyrics;
    var holyricsOk = true;

    Future<(int, dynamic)> chamar(String metodo, String caminho, {String? token, Object? json, List<int>? bytes}) async {
      final r = await handler(Request(metodo, Uri.parse('http://x$caminho'),
          headers: {if (token != null) 'authorization': 'Bearer $token', 'content-type': 'application/json'},
          body: bytes ?? (json == null ? null : jsonEncode(json))));
      final corpo = await r.read().expand((b) => b).toList();
      final texto = utf8.decode(corpo, allowMalformed: true);
      return (r.statusCode, texto.startsWith('{') || texto.startsWith('[') ? jsonDecode(texto) : corpo);
    }

    Future<String> criarUsuario(String login, Perfil perfil) async {
      final (_, j) = await chamar('POST', '/api/admin/usuarios',
          token: admin, json: {'nome': 'Obreiro $login', 'login': login, 'perfil': perfil.name});
      final (_, l) = await chamar('POST', '/api/login', json: {'usuario': login, 'senha': j['senhaTemporaria']});
      return l['token'] as String;
    }

    Future<List> visitas() async => (await chamar('GET', '/api/visitas?desde=2000-01-01', token: admin)).$2 as List;
    Future<List> membros() async => (await chamar('GET', '/api/membros', token: admin)).$2 as List;
    Map porNome(List lista, String nome) => lista.firstWhere((m) => m['nome'] == nome) as Map;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('diako_visitas');
      final config = Config.lerJson('{"senhaAdmin":"senha-principal"}', pastaBase: tmp.path);
      store = Store(config.pastaDados);
      await store.carregar();
      final cfg = await Configuracoes.carregar(config, urlDetectada: 'http://192.168.0.10:8080');
      final usuarios = Usuarios(config.pastaDados);
      final auth = Auth(conferirSenha: cfg.conferirSenha, pastaDados: config.pastaDados, usuarios: usuarios);
      final backup = Backup(pastaDados: config.pastaDados, configuracoes: cfg.publicas);
      restauracao = Restauracao(store: store, backup: backup, pastaDados: config.pastaDados, pastaCartazes: config.pastaCartazes);
      ultimoHolyrics = null;
      holyricsOk = true;
      handler = Servidor(
        store: store,
        auth: auth,
        holyrics: HolyricsDireto(
          host: 'h', porta: 1, token: 't',
          cliente: MockClient((r) async {
            ultimoHolyrics = r.body;
            return http.Response(holyricsOk ? '{"status":"ok"}' : '{"status":"error"}', 200);
          }),
        ),
        cartazes: Cartazes(config.pastaCartazes),
        backup: backup,
        pastaWeb: (Directory(p.join(tmp.path, 'web'))..createSync()).path,
        urlOracao: cfg.urlOracao,
        cartazesNoHolyrics: false,
        historico: Historico(config.pastaDados),
        cfg: cfg,
        restauracao: restauracao,
      ).handler;
      final (_, l) = await chamar('POST', '/api/login', json: {'senha': 'senha-principal'});
      admin = l['token'] as String;
    });
    tearDown(() async {
      await store.fechar();
      await tmp.delete(recursive: true);
    });

    test('obreiro cadastra família: vínculos, LGPD, pedido de oração; não vê o resto', () async {
      final obreiro = await criarUsuario('joao.recepcao', Perfil.recepcao);
      final anoFilho = DateTime.now().year - 8;
      final (st, r) = await chamar('POST', '/api/visitas', token: obreiro, json: {
        'pessoas': [
          {'nome': 'Rita Alves', 'aniversario': '07/08/1990', 'telefone': '(11) 91234-5678'},
          {'nome': 'Paulo Alves', 'aniversario': '10/02/1988', 'parentesco': 'conjuge'},
          {'nome': 'Lia Alves', 'aniversario': '03/03/$anoFilho', 'parentesco': 'filho'},
        ],
        'comoConheceu': 'Amigos',
        'mencionar': true,
        'interesses': ['visitaPastoral'],
        'pedidoOracao': 'Pela saúde da minha mãe',
        'autorizo': true,
      });
      expect(st, 201, reason: '$r');
      expect((r['pessoas'] as List).map((p) => p['primeiraVez']), [true, true, true]);

      final ms = await membros();
      final rita = porNome(ms, 'Rita Alves'), paulo = porNome(ms, 'Paulo Alves'), lia = porNome(ms, 'Lia Alves');
      expect(rita['status'], 'visitante');
      expect(rita['whatsapp'], '(11) 91234-5678');
      expect(rita['conjugeId'], paulo['id']);
      expect(paulo['conjugeId'], rita['id']);
      expect(lia['paisIds'], unorderedEquals([rita['id'], paulo['id']]));
      // LGPD: a titular autorizou; a filha menor pela mãe (responsável); o marido adulto não marcou.
      expect(rita['consentimentoVia'], 'recepcao');
      expect(rita['consentimentoRegistro']['por'], 'Obreiro joao.recepcao');
      expect(lia['consentimentoRegistro']['responsavel'], 'Rita Alves');
      expect(paulo.containsKey('consentimentoEm'), isFalse);

      final vs = await visitas();
      expect(vs, hasLength(3));
      expect(vs.map((v) => v['grupoId']).toSet(), hasLength(1));
      final vRita = porNome(vs, 'Rita Alves');
      expect(vRita['origem'], 'recepcao');
      expect(vRita['registradoPor'], 'Obreiro joao.recepcao');
      expect(vRita['interesses'], unorderedEquals(['visitaPastoral', 'oracao']));
      expect(vRita['mencionar'], isTrue);

      // O pedido vai para a aprovação, particular.
      final (_, motivos) = await chamar('GET', '/api/motivos', token: admin);
      final pedido = (motivos as List).single as Map;
      expect(pedido['status'], 'aguardando');
      expect(pedido['publico'], isFalse);
      expect(pedido['enviadoPor'], 'Rita Alves (visitante)');

      // O obreiro vê as visitas (sem anotações de contato), mas não o cadastro nem os pedidos.
      final (sv, dele) = await chamar('GET', '/api/visitas', token: obreiro);
      expect(sv, 200);
      expect((dele as List).first.containsKey('contato'), isFalse);
      expect((await chamar('GET', '/api/membros', token: obreiro)).$1, 403);
      expect((await chamar('GET', '/api/motivos', token: obreiro)).$1, 403);
      expect((await chamar('PUT', '/api/visitas/${vRita['id']}/contato', token: obreiro, json: {'status': 'contatado'})).$1, 403);
    });

    test('quem volta é ligado ao mesmo cadastro; repetido no mesmo dia não duplica', () async {
      final corpo = {
        'pessoas': [{'nome': 'Rita Alves', 'aniversario': '07/08', 'telefone': '11 91234-5678'}],
        'mencionar': false, 'autorizo': true,
      };
      await chamar('POST', '/api/visitas', token: admin, json: corpo);
      // Visita de outro dia, no passado, para simular "voltou".
      final v = (await visitas()).single as Map;
      await store.salvar('visitas', {...v, 'data': '2026-01-04'});

      final (_, r) = await chamar('POST', '/api/visitas', token: admin,
          json: {...corpo, 'pessoas': [{'nome': 'rita  ALVES', 'aniversario': '07/08', 'telefone': '(11) 91234-5678'}]});
      expect((r['pessoas'] as List).single['primeiraVez'], isFalse);
      expect(await membros(), hasLength(1));
      // De novo hoje (clique duplo): nenhuma visita a mais.
      await chamar('POST', '/api/visitas', token: admin, json: corpo);
      final vs = await visitas();
      expect(vs, hasLength(2));
      expect(vs.where((v) => v['primeiraVez'] == false), hasLength(1));
    });

    test('validações: pergunta do púlpito, LGPD no QR, menor sem responsável, data', () async {
      final base = {'pessoas': [{'nome': 'Ana', 'aniversario': '05/03'}], 'autorizo': true};
      expect((await chamar('POST', '/api/public/visitante', json: base)).$1, 400); // sem "mencionar"
      expect((await chamar('POST', '/api/public/visitante', json: {...base, 'mencionar': true, 'autorizo': false})).$1, 400);
      final menor = {'pessoas': [{'nome': 'Léo', 'aniversario': '01/01/${DateTime.now().year - 12}'}], 'mencionar': true, 'autorizo': true};
      expect((await chamar('POST', '/api/public/visitante', json: menor)).$1, 400);
      expect((await chamar('POST', '/api/public/visitante', json: {...menor, 'responsavel': 'Pai do Léo'})).$1, 201);
      expect((await chamar('POST', '/api/public/visitante',
          json: {...base, 'mencionar': true, 'pessoas': [{'nome': 'X', 'aniversario': '31/02'}]})).$1, 400);
      // Painel: a secretaria pode cadastrar sem a autorização na hora (pede o link depois).
      final (st, _) = await chamar('POST', '/api/visitas', token: admin,
          json: {'pessoas': [{'nome': 'Bia', 'aniversario': '02/02'}], 'mencionar': false});
      expect(st, 201);
      expect(porNome(await membros(), 'Bia').containsKey('consentimentoEm'), isFalse);
      expect(porNome(await visitas(), 'Bia')['origem'], 'painel');
    });

    test('boas-vindas: telão só com quem autorizou, dá baixa; TV de boas-vindas e mural', () async {
      Future<void> cadastrar(String nome, bool mencionar) => chamar('POST', '/api/visitas', token: admin, json: {
            'pessoas': [{'nome': nome, 'aniversario': '01/01'}], 'mencionar': mencionar, 'autorizo': true,
          });
      await cadastrar('Rita', true);
      await cadastrar('Caio', true);
      await cadastrar('Léo', false);

      // TV de boas-vindas: nomes de quem autorizou, na ordem de chegada, e o QR.
      final (_, tv) = await chamar('GET', '/api/public/mural?tela=boas-vindas');
      expect(tv['nomes'], ['Rita', 'Caio']);
      expect(tv['qr'], '/qr-visitante.png');
      // Mural principal: sem boas-vindas, a não ser que o /admin ligue.
      List titulos(Map j) => [for (final s in j['slides'] as List) s['titulo']];
      expect(titulos((await chamar('GET', '/api/public/mural')).$2 as Map), isNot(contains('Sejam bem-vindos!')));
      // (o token vai junto: salvar no /admin reaplica a conexão do Holyrics)
      await chamar('PUT', '/api/admin/configuracoes', token: admin, json: {'muralBoasVindas': true, 'holyricsToken': 't'});
      expect(titulos((await chamar('GET', '/api/public/mural')).$2 as Map), contains('Sejam bem-vindos!'));

      // Holyrics fora do ar: nada recebe baixa.
      holyricsOk = false;
      await chamar('POST', '/api/projetar/boas-vindas', token: admin);
      expect((await visitas()).where((v) => v['mencionadaEm'] != null), isEmpty);
      holyricsOk = true;
      final (st, _) = await chamar('POST', '/api/projetar/boas-vindas', token: admin);
      expect(st, 200);
      expect(ultimoHolyrics, contains('Sejam bem-vindos!'));
      expect(ultimoHolyrics, contains('Rita'));
      expect(ultimoHolyrics, isNot(contains('Léo')));
      final vs = await visitas();
      expect(porNome(vs, 'Rita')['mencionadaEm'], isNotNull);
      expect(porNome(vs, 'Léo')['mencionadaEm'], isNull);
      // Ninguém mais pendente.
      expect((await chamar('POST', '/api/projetar/boas-vindas', token: admin)).$1, 400);

      // Baixa manual e desfazer.
      final leo = porNome(vs, 'Caio');
      await chamar('POST', '/api/visitas/${leo['id']}/mencionada', token: admin, json: {'desfazer': true});
      expect(porNome(await visitas(), 'Caio')['mencionadaEm'], isNull);
    });

    test('acompanhamento pós-visita e backup', () async {
      await chamar('POST', '/api/visitas', token: admin,
          json: {'pessoas': [{'nome': 'Rita', 'aniversario': '01/01'}], 'mencionar': true, 'autorizo': true});
      final v = (await visitas()).single as Map;
      expect(v['contato'], 'aContatar');
      expect((await chamar('PUT', '/api/visitas/${v['id']}/contato', token: admin, json: {'status': 'xpto'})).$1, 400);
      final (_, c) = await chamar('PUT', '/api/visitas/${v['id']}/contato', token: admin,
          json: {'status': 'contatado', 'nota': 'Ligou na terça, quer visita'});
      expect(c['contato'], 'contatado');
      expect(c['contatoPor'], isNotNull);
      expect(c['contatoNota'], 'Ligou na terça, quer visita');

      final (_, zip) = await chamar('GET', '/api/backups/agora/download', token: admin);
      expect(ZipDecoder().decodeBytes(zip as List<int>).findFile('data/visitas.json'), isNotNull);

      // Excluir a pessoa leva as visitas junto.
      final rita = (await membros()).single as Map;
      await chamar('DELETE', '/api/membros/${rita['id']}', token: admin);
      expect(await visitas(), isEmpty);
      final r = await restauracao.restaurar(zip);
      expect(r.colecoes['visitas'], 1);
      expect(Visita.fromJson(Map<String, dynamic>.from(store.listar('visitas').single)).contato, StatusContato.contatado);
    });
  });
}
