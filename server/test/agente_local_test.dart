import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:diako_server/agente/agente.dart';
import 'package:diako_server/agente/api_local.dart';
import 'package:diako_server/agente_hub.dart';
import 'package:diako_server/app.dart';
import 'package:diako_server/auth.dart';
import 'package:diako_server/backup.dart';
import 'package:diako_server/cartazes.dart';
import 'package:diako_server/historico.dart';
import 'package:diako_server/store.dart';
import 'package:diako_server/tablets_locais.dart';
import 'package:diako_server/usuarios.dart';
import 'package:diako_server/permissoes.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart' as io;
import 'package:test/test.dart';

const senha = 'senha-forte-123';
const chaveAgente = 'chave-do-agente-com-mais-de-24-caracteres';

Future<void> ate(bool Function() cond, {Duration limite = const Duration(seconds: 5)}) async {
  final fim = DateTime.now().add(limite);
  while (!cond()) {
    if (DateTime.now().isAfter(fim)) throw TimeoutException('condição não atingida');
    await Future.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  group('tablet falando direto com o agente na rede local', () {
    late Directory tmp;
    late Store store;
    late HttpServer http_;
    late HolyricsViaAgente hub;
    late Historico historico;
    late Usuarios usuarios;
    late String base;
    late List<http.Request> chamadasHolyrics;
    late Agente agente;
    late ApiLocal apiLocal;
    late String local;
    late String sessao;

    Agente novoAgente(String servidor) => Agente(
          AgenteConfig(
            servidor: servidor,
            chaveAgente: chaveAgente,
            holyricsToken: 'tk',
            pastaImagensHolyrics: p.join(tmp.path, 'igreja', 'imagens'),
            apiLocalPorta: 0,
          ),
          pastaDados: p.join(tmp.path, 'igreja', 'agente'),
          clienteHolyrics: MockClient((req) async {
            chamadasHolyrics.add(req);
            return http.Response(jsonEncode({'status': 'ok'}), 200);
          }),
          log: (_) {},
        );

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('diako_local');
      final dados = p.join(tmp.path, 'servidor', 'data');
      final web = Directory(p.join(tmp.path, 'servidor', 'web'))..createSync(recursive: true);
      store = Store(dados);
      await store.carregar();
      usuarios = Usuarios(dados);
      final auth = Auth(senha: senha, pastaDados: dados, usuarios: usuarios);
      hub = HolyricsViaAgente();
      historico = Historico(dados);
      final servidor = Servidor(
        store: store,
        auth: auth,
        holyrics: hub,
        cartazes: Cartazes(p.join(dados, 'cartazes')),
        backup: Backup(pastaDados: dados),
        pastaWeb: web.path,
        urlOracao: 'https://exemplo.org/oracao',
        cartazesNoHolyrics: false,
        historico: historico,
        agente: hub,
        chaveAgente: chaveAgente,
      );
      http_ = await io.serve(servidor.handler, InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${http_.port}';

      chamadasHolyrics = [];
      agente = novoAgente(base);
      unawaited(agente.rodar());
      await ate(() => hub.agenteConectado);
      // Porta 0 na configuração desliga a API no programa; no teste ela sobe numa porta livre.
      apiLocal = ApiLocal(agente, endereco: InternetAddress.loopbackIPv4);
      await apiLocal.iniciar();
      local = 'http://127.0.0.1:${apiLocal.porta}';

      final r = await http.post(Uri.parse('$base/api/login'), body: jsonEncode({'senha': senha}));
      sessao = (jsonDecode(r.body) as Map)['token'] as String;
    });

    tearDown(() async {
      await apiLocal.parar();
      await agente.parar();
      await http_.close(force: true);
      await store.fechar();
      // O agente pode estar terminando de gravar tablets.json (Windows não apaga arquivo aberto).
      for (var i = 0;; i++) {
        try {
          await tmp.delete(recursive: true);
          break;
        } on FileSystemException {
          if (i == 20) rethrow;
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }
    });

    Map<String, String> comSessao([String? t]) =>
        {'Authorization': 'Bearer ${t ?? sessao}', 'Content-Type': 'application/json'};

    Future<Map> parear([String? t]) async {
      final r = await http.post(Uri.parse('$base/api/agente-local/parear'),
          headers: comSessao(t), body: jsonEncode({'aparelho': 'Tablet do púlpito'}));
      expect(r.statusCode, 201, reason: r.body);
      return jsonDecode(r.body) as Map;
    }

    test('pareia com a sessão, projeta pela rede local e o histórico chega ao servidor', () async {
      final par = await parear();
      final token = par['token'] as String;
      expect(File(p.join(tmp.path, 'servidor', 'data', 'tablets-locais.json')).readAsStringSync(), isNot(contains(token)));
      await ate(() => agente.tabletDoToken(token) != null);
      expect(File(p.join(tmp.path, 'igreja', 'agente', 'tablets.json')).readAsStringSync(), isNot(contains(token)));

      final ping = await http.get(Uri.parse('$local/ping'), headers: {'Authorization': 'Bearer $token'});
      expect(ping.statusCode, 200);
      expect((jsonDecode(ping.body) as Map)['tablet'], 'Administrador (Tablet do púlpito)');

      final r = await http.post(Uri.parse('$local/holyrics/ShowQuickPresentation'),
          headers: {'Authorization': 'Bearer $token'}, body: jsonEncode({'text': 'Culto de domingo'}));
      expect(jsonDecode(r.body), {'status': 'ok'});
      expect(chamadasHolyrics.single.url.path, '/api/ShowQuickPresentation');

      await ate(() => agente.estado['historicoPendente'] == 0 && File(historico.arquivo.path).existsSync());
      final eventos = await historico.listar();
      expect(eventos.single['descricao'], 'Culto de domingo');
      expect(eventos.single['usuario'], 'Administrador');
      expect(eventos.single['via'], 'rede local');
    });

    test('recusa token errado, ação fora da lista e corpo que não é objeto', () async {
      final token = (await parear())['token'] as String;
      await ate(() => agente.tabletDoToken(token) != null);
      final errado = await http.post(Uri.parse('$local/holyrics/ShowImage'), headers: {'Authorization': 'Bearer xyz'});
      expect(errado.statusCode, 401);
      final sem = await http.get(Uri.parse('$local/ping'));
      expect(sem.statusCode, 401);
      final acao = await http.post(Uri.parse('$local/holyrics/SetVolume'), headers: {'Authorization': 'Bearer $token'});
      expect(acao.statusCode, 403);
      final corpo = await http.post(Uri.parse('$local/holyrics/ShowImage'),
          headers: {'Authorization': 'Bearer $token'}, body: '[1]');
      expect(corpo.statusCode, 400);
      expect(chamadasHolyrics, isEmpty);
    });

    test('muitas tentativas com token errado bloqueiam o IP', () async {
      for (var i = 0; i < ApiLocal.maximoFalhas; i++) {
        await http.get(Uri.parse('$local/ping'), headers: {'Authorization': 'Bearer chute-$i'});
      }
      expect((await http.get(Uri.parse('$local/ping'))).statusCode, 429);
    });

    test('remover no /admin, desativar a conta ou tirar "projetar" corta o acesso local', () async {
      final u = await usuarios.criar(nome: 'Ana', login: 'ana', perfil: Perfil.telao, senha: 'senha-da-ana-1');
      final login = await http.post(Uri.parse('$base/api/login'),
          body: jsonEncode({'usuario': 'ana', 'senha': 'senha-da-ana-1'}));
      final sessaoAna = (jsonDecode(login.body) as Map)['token'] as String;
      final par = await parear(sessaoAna);
      final token = par['token'] as String;
      await ate(() => agente.tabletDoToken(token) != null);

      // Recepção não tem "projetar": o tablet sai da lista do agente.
      await http.put(Uri.parse('$base/api/admin/usuarios/${u.id}'), headers: comSessao(), body: jsonEncode({'perfil': 'recepcao'}));
      await ate(() => agente.tabletDoToken(token) == null);
      await http.put(Uri.parse('$base/api/admin/usuarios/${u.id}'), headers: comSessao(), body: jsonEncode({'perfil': 'telao'}));
      await ate(() => agente.tabletDoToken(token) != null);

      final lista = jsonDecode((await http.get(Uri.parse('$base/api/admin/tablets-locais'), headers: comSessao())).body) as Map;
      expect((lista['tablets'] as List).single, containsPair('conta', 'Ana'));
      expect(jsonEncode(lista), isNot(contains('hash')));

      await http.delete(Uri.parse('$base/api/admin/tablets-locais/${par['id']}'), headers: comSessao());
      await ate(() => agente.tabletDoToken(token) == null);
      expect((await http.get(Uri.parse('$local/ping'), headers: {'Authorization': 'Bearer $token'})).statusCode, 401);
    });

    test('perfil sem "projetar" não pareia; pareamento de outra conta não é removido pelo tablet', () async {
      await usuarios.criar(nome: 'Rec', login: 'rec', perfil: Perfil.recepcao, senha: 'senha-da-rec-1');
      await usuarios.criar(nome: 'Bia', login: 'bia', perfil: Perfil.midia, senha: 'senha-da-bia-1');
      Future<String> entrar(String u, String s) async => (jsonDecode((await http.post(Uri.parse('$base/api/login'),
          body: jsonEncode({'usuario': u, 'senha': s}))).body) as Map)['token'] as String;
      final rec = await entrar('rec', 'senha-da-rec-1');
      final r = await http.post(Uri.parse('$base/api/agente-local/parear'), headers: comSessao(rec), body: '{}');
      expect(r.statusCode, 403);

      final par = await parear();
      final bia = await entrar('bia', 'senha-da-bia-1');
      final d = await http.delete(Uri.parse('$base/api/agente-local/${par['id']}'), headers: comSessao(bia));
      expect(d.statusCode, 403);
      final meu = await http.delete(Uri.parse('$base/api/agente-local/${par['id']}'), headers: comSessao());
      expect(meu.statusCode, 200);
    });

    test('sem internet: tablets e histórico ficam em disco e o histórico sobe quando volta', () async {
      final token = (await parear())['token'] as String;
      await ate(() => agente.tabletDoToken(token) != null);
      await apiLocal.parar();
      await agente.parar();
      await ate(() => !hub.agenteConectado);

      // PC reiniciado sem internet: o agente novo lê a lista do disco.
      final offline = novoAgente('http://127.0.0.1:1');
      await offline.carregarDados();
      final api = ApiLocal(offline, endereco: InternetAddress.loopbackIPv4);
      await api.iniciar();
      final r = await http.post(Uri.parse('http://127.0.0.1:${api.porta}/holyrics/ShowImage'),
          headers: {'Authorization': 'Bearer $token'}, body: jsonEncode({'file': 'Diako/retiro.png'}));
      expect(jsonDecode(r.body), {'status': 'ok'});
      expect(offline.estado['historicoPendente'], 1);
      await api.parar();

      // Internet de volta: outro processo do agente envia a fila.
      agente = novoAgente(base);
      await agente.carregarDados();
      expect(agente.estado['historicoPendente'], 1);
      unawaited(agente.rodar());
      await ate(() => agente.estado['historicoPendente'] == 0);
      expect((await historico.listar()).single['descricao'], 'Imagem: Diako/retiro.png');
      apiLocal = ApiLocal(agente, endereco: InternetAddress.loopbackIPv4);
      await apiLocal.iniciar();
    });
  });

  test('hashTokenLocal não revela o token', () {
    expect(hashTokenLocal('abc'), hasLength(64));
    expect(hashTokenLocal('abc'), isNot(contains('abc')));
  });
}
