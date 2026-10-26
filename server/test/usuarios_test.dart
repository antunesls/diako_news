import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
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
  test('rotas da API e a permissão exigida', () {
    expect(permissaoDaRota('GET', 'api/eu'), Permissao.sessao);
    expect(permissaoDaRota('GET', 'ws'), Permissao.sessao);
    expect(permissaoDaRota('GET', 'api/motivos'), Permissao.motivosVer);
    expect(permissaoDaRota('POST', 'api/motivos/x/aprovar'), Permissao.motivosEditar);
    expect(permissaoDaRota('PUT', 'api/mensagens/x'), Permissao.mensagens);
    expect(permissaoDaRota('GET', 'api/agenda'), Permissao.agendaVer);
    expect(permissaoDaRota('POST', 'api/agenda/eventos'), Permissao.agendaEditar);
    expect(permissaoDaRota('POST', 'api/holyrics/ShowImage'), Permissao.projetar);
    expect(permissaoDaRota('GET', 'api/admin/usuarios'), Permissao.usuarios);
    expect(permissaoDaRota('GET', 'api/backups'), Permissao.admin);
    expect(permissaoDaRota('GET', 'api/rota-nova-sem-regra'), Permissao.admin); // padrão: negar
  });

  group('servidor', () {
    late Directory tmp;
    late Store store;
    late Handler handler;
    late Usuarios usuarios;
    late Auth auth;
    late String admin;
    late String pastaDados;

    Future<(int, dynamic)> chamar(String metodo, String caminho, {String? token, Object? json}) async {
      final r = await handler(Request(metodo, Uri.parse('http://x$caminho'),
          headers: {if (token != null) 'authorization': 'Bearer $token', 'content-type': 'application/json'},
          body: json == null ? null : jsonEncode(json)));
      final texto = await r.readAsString();
      return (r.statusCode, texto.startsWith('{') || texto.startsWith('[') ? jsonDecode(texto) : texto);
    }

    Future<String?> entrar(String usuario, String senha) async {
      final (st, j) = await chamar('POST', '/api/login', json: {'usuario': usuario, 'senha': senha});
      return st == 200 ? j['token'] as String : null;
    }

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('diako_usuarios');
      final config = Config.lerJson('{"senhaAdmin":"senha-principal"}', pastaBase: tmp.path);
      pastaDados = config.pastaDados;
      store = Store(config.pastaDados);
      await store.carregar();
      final cfg = await Configuracoes.carregar(config, urlDetectada: 'http://192.168.0.10:8080');
      usuarios = Usuarios(config.pastaDados);
      auth = Auth(conferirSenha: cfg.conferirSenha, pastaDados: config.pastaDados, usuarios: usuarios);
      final web = Directory(p.join(tmp.path, 'web'))..createSync();
      handler = Servidor(
        store: store,
        auth: auth,
        holyrics: HolyricsDireto(
            host: 'h', porta: 1, token: 't', cliente: MockClient((_) async => http.Response('{"status":"ok"}', 200))),
        cartazes: Cartazes(config.pastaCartazes),
        backup: Backup(pastaDados: config.pastaDados, configuracoes: cfg.publicas),
        pastaWeb: web.path,
        urlOracao: cfg.urlOracao,
        cartazesNoHolyrics: false,
        historico: Historico(config.pastaDados),
        cfg: cfg,
      ).handler;
      admin = (await entrar('', 'senha-principal'))!;
    });
    tearDown(() async {
      await store.fechar();
      await tmp.delete(recursive: true);
    });

    /// Cria o usuário pelo /admin e já entra com a senha temporária.
    Future<(String id, String token)> criar(String login, Perfil perfil) async {
      final (st, j) = await chamar('POST', '/api/admin/usuarios',
          token: admin, json: {'nome': 'Pessoa $login', 'login': login, 'perfil': perfil.name});
      expect(st, 201, reason: '$j');
      final token = await entrar(login, j['senhaTemporaria'] as String);
      return (j['usuario']['id'] as String, token!);
    }

    test('login: conta principal com e sem "admin", usuário, senha errada e desativado', () async {
      expect(await entrar('admin', 'senha-principal'), isNotNull);
      expect(await entrar('', 'errada'), isNull);
      final (id, token) = await criar('maria.silva', Perfil.secretaria);
      expect(await entrar('MARIA.SILVA', 'errada'), isNull);
      final (_, eu) = await chamar('GET', '/api/eu', token: token);
      expect(eu['nome'], 'Pessoa maria.silva');
      expect(eu['perfil'], 'secretaria');
      expect(eu['permissoes'], contains('mensagens'));
      expect(eu['permissoes'], isNot(contains('admin')));
      expect(id, isNotEmpty);
    });

    // Teste separado: o servidor aceita só 5 tentativas de login por minuto do mesmo IP.
    test('desativar derruba a sessão e impede novo login; logins reservados e repetidos', () async {
      final (id, token) = await criar('maria.silva', Perfil.secretaria);
      await chamar('PUT', '/api/admin/usuarios/$id', token: admin, json: {'ativo': false});
      expect((await chamar('GET', '/api/eu', token: token)).$1, 401);
      final (_, senha) = await chamar('POST', '/api/admin/usuarios/$id/senha', token: admin);
      expect(await entrar('maria.silva', senha['senhaTemporaria'] as String), isNull);

      // Não dá para criar "admin" nem repetir login.
      expect((await chamar('POST', '/api/admin/usuarios', token: admin, json: {'nome': 'X', 'login': 'admin', 'perfil': 'pastor'})).$1, 400);
      expect((await chamar('POST', '/api/admin/usuarios', token: admin, json: {'nome': 'X', 'login': 'maria.silva', 'perfil': 'pastor'})).$1, 400);
    });

    test('cada perfil só acessa o que a matriz permite', () async {
      final (_, pastor) = await criar('pastor', Perfil.pastor);
      final (_, secretaria) = await criar('secretaria', Perfil.secretaria);
      final (_, midia) = await criar('midia', Perfil.midia);
      final (_, telao) = await criar('telao', Perfil.telao);
      final quem = {'pastor': pastor, 'secretaria': secretaria, 'midia': midia, 'telao': telao, 'admin': admin};

      // rota -> perfis que podem
      final matriz = <(String, String), Set<String>>{
        ('GET', '/api/estado'): {'admin', 'pastor', 'secretaria', 'midia', 'telao'},
        ('GET', '/api/motivos'): {'admin', 'pastor', 'secretaria', 'midia', 'telao'},
        ('GET', '/api/mensagens'): {'admin', 'pastor', 'secretaria'},
        ('GET', '/api/recados'): {'admin', 'pastor', 'secretaria', 'midia', 'telao'},
        ('GET', '/api/membros'): {'admin', 'pastor', 'secretaria'},
        ('GET', '/api/galeria'): {'admin', 'pastor', 'midia'},
        ('GET', '/api/resumo-semanal'): {'admin', 'pastor', 'secretaria'},
        ('POST', '/api/holyrics/ShowImage'): {'admin', 'pastor', 'midia', 'telao'},
        ('GET', '/api/admin/configuracoes'): {'admin'},
        ('GET', '/api/admin/usuarios'): {'admin'},
        ('GET', '/api/backups'): {'admin'},
      };
      for (final e in matriz.entries) {
        for (final perfil in quem.keys) {
          final (st, _) = await chamar(e.key.$1, e.key.$2, token: quem[perfil], json: e.key.$1 == 'POST' ? {'file': 'x'} : null);
          expect(st == 403, !e.value.contains(perfil), reason: '${e.key} como $perfil: HTTP $st');
        }
      }
    });

    test('pedidos particulares e nome de quem pediu: só pastor e administrador', () async {
      final (_, pastor) = await criar('pastor', Perfil.pastor);
      final (_, secretaria) = await criar('secretaria', Perfil.secretaria);
      await chamar('POST', '/api/public/pedidos',
          json: {'motivo': 'Cirurgia', 'para': 'Dona Lúcia', 'tipo': 'saude', 'enviadoPor': 'Marcos', 'publico': true});
      await chamar('POST', '/api/public/pedidos', json: {'motivo': 'Assunto particular', 'tipo': 'familia', 'enviadoPor': 'Ana'});

      for (final t in [admin, pastor]) {
        final (_, lista) = await chamar('GET', '/api/motivos', token: t);
        expect((lista as List).length, 2);
        expect(lista.map((m) => m['enviadoPor']), containsAll(['Marcos', 'Ana']));
      }
      final (_, visivel) = await chamar('GET', '/api/motivos', token: secretaria);
      expect((visivel as List).single['motivo'], 'Cirurgia');
      expect(visivel.single['enviadoPor'], '');
      expect(jsonEncode(visivel), isNot(contains('Ana')));

      // Secretaria aprova o público (fica registrado quem aprovou) sem apagar quem enviou...
      final publico = visivel.single['id'];
      expect((await chamar('POST', '/api/motivos/$publico/aprovar', token: secretaria)).$1, 200);
      expect((await chamar('PUT', '/api/motivos/$publico', token: secretaria, json: {...visivel.single, 'motivo': 'Cirurgia na quinta'})).$1, 200);
      final salvo = store.buscar('motivos', publico as String)!;
      expect(salvo['enviadoPor'], 'Marcos');
      expect(salvo['aprovadoPor'], 'Pessoa secretaria');

      // ...mas não mexe no particular.
      final particular = store.listar('motivos').firstWhere((m) => m['publico'] == false)['id'];
      expect((await chamar('POST', '/api/motivos/$particular/aprovar', token: secretaria)).$1, 403);
      expect((await chamar('DELETE', '/api/motivos/$particular', token: secretaria)).$1, 403);
      expect((await chamar('POST', '/api/motivos/$particular/aprovar', token: pastor)).$1, 200);
    });

    test('trocar perfil derruba a sessão; trocar a própria senha', () async {
      final (id, token) = await criar('joao', Perfil.midia);
      await chamar('PUT', '/api/admin/usuarios/$id', token: admin, json: {'perfil': 'pastor'});
      expect((await chamar('GET', '/api/eu', token: token)).$1, 401);

      final (_, senha) = await chamar('POST', '/api/admin/usuarios/$id/senha', token: admin);
      final novo = (await entrar('joao', senha['senhaTemporaria'] as String))!;
      expect((await chamar('POST', '/api/eu/senha', token: novo, json: {'atual': 'errada', 'nova': 'outra-senha-boa'})).$1, 403);
      expect((await chamar('POST', '/api/eu/senha', token: novo, json: {'atual': senha['senhaTemporaria'], 'nova': 'outra-senha-boa'})).$1, 200);
      expect(await entrar('joao', 'outra-senha-boa'), isNotNull);
    });

    test('quem projetou fica no histórico', () async {
      final (_, midia) = await criar('midia', Perfil.midia);
      await chamar('POST', '/api/holyrics/ShowImage', token: midia, json: {'file': 'Diako/retiro.jpg'});
      final (_, hist) = await chamar('GET', '/api/historico', token: admin);
      expect((hist as List).first['usuario'], 'Pessoa midia');
    });

    test('senhas só como hash; usuários fora do backup; sessões antigas migradas', () async {
      await criar('ana', Perfil.secretaria);
      final arquivo = File(p.join(pastaDados, 'usuarios.json')).readAsStringSync();
      expect(arquivo, contains('senhaHash'));
      final (_, lista) = await chamar('GET', '/api/admin/usuarios', token: admin);
      expect(jsonEncode(lista), isNot(contains('senhaHash')));

      final r = await handler(Request('GET', Uri.parse('http://x/api/backups/agora/download'), headers: {'authorization': 'Bearer $admin'}));
      final zip = ZipDecoder().decodeBytes(await r.read().expand((b) => b).toList());
      expect(zip.files.map((f) => f.name), isNot(contains(contains('usuarios'))));

      // sessoes.json no formato antigo (token -> data): vira sessão da conta principal.
      final antigo = Directory(p.join(tmp.path, 'antigo'))..createSync();
      File(p.join(antigo.path, 'sessoes.json'))
          .writeAsStringSync(jsonEncode({'tok-antigo': DateTime.now().add(const Duration(days: 5)).toIso8601String()}));
      final a = Auth(senha: 'x', pastaDados: antigo.path);
      await a.carregar();
      expect(a.contaDe('tok-antigo')?.ehPrincipal, isTrue);
    });
  });
}
