import 'dart:convert';
import 'dart:io';

import 'package:diako_server/agente/agente.dart';
import 'package:diako_server/agente/monitor.dart';
import 'package:diako_server/auth.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  late MonitorAgente monitor;
  late http.Client cliente;
  late Uri base;
  late String cookie;
  late String csrf;
  late List<String> acoes;
  Map<String, dynamic>? apresentacao;
  bool falharLeitura = false;

  setUp(() async {
    acoes = [];
    apresentacao = null;
    falharLeitura = false;
    final hash = gerarHashSenha('senha-do-monitor-123');
    final holyrics = MockClient((req) async {
      final acao = req.url.pathSegments.last;
      acoes.add(acao);
      if (acao == 'GetCurrentPresentation' && falharLeitura) {
        return http.Response(jsonEncode({'status': 'error', 'error': 'invalid token'}), 200);
      }
      Object? data;
      switch (acao) {
        case 'GetCurrentPresentation': data = apresentacao;
        case 'GetCPInfo': data = {'show': false};
        case 'GetThemes': data = [{'id': '7', 'name': 'Avisos'}];
        case 'GetThumbnail': data = [{'id': '7', 'type': 'theme', 'image': 'iVBORw0KGgo='}];
        case 'ShowQuickPresentation':
          apresentacao = {'type': 'quick_presentation', 'id': 'ensaio-1', 'slide_number': 1};
        case 'ActionNextQuickPresentation':
          apresentacao?['slide_number'] = 2;
        case 'ActionPreviousQuickPresentation':
          apresentacao?['slide_number'] = 1;
      }
      return http.Response(jsonEncode({'status': 'ok', 'data': data}), 200);
    });
    final agent = Agente(AgenteConfig(servidor: 'https://exemplo.org', chaveAgente: 'secreta',
        holyricsToken: 'token-secreto', pastaImagensHolyrics: Directory.systemTemp.path,
        monitorPorta: 0, monitorHash: hash.hash, monitorSal: hash.sal), clienteHolyrics: holyrics);
    monitor = MonitorAgente(agent);
    await monitor.iniciar();
    base = Uri.parse('http://127.0.0.1:${monitor.porta}');
    cliente = http.Client();
    cookie = '';
    csrf = '';
  });

  tearDown(() async { cliente.close(); await monitor.parar(); });

  Future<http.Response> post(String rota, Object corpo, {bool autenticado = true, String? origem}) =>
      cliente.post(base.resolve(rota), headers: {
        'Origin': origem ?? base.origin, 'Content-Type': 'application/json',
        if (autenticado) 'Cookie': cookie,
        if (autenticado) 'X-CSRF-Token': csrf,
      }, body: jsonEncode(corpo));

  Future<void> login() async {
    final r = await post('/api/login', {'senha': 'senha-do-monitor-123'}, autenticado: false);
    expect(r.statusCode, 200);
    cookie = r.headers['set-cookie']!.split(';').first;
    csrf = jsonDecode(r.body)['csrf'] as String;
  }

  test('sessão obrigatória, senha independente, origem e CSRF', () async {
    expect((await cliente.get(base.resolve('/api/estado'))).statusCode, 401);
    expect((await post('/api/login', {'senha': 'incorreta'}, autenticado: false)).statusCode, 401);
    await login();
    final estado = await cliente.get(base.resolve('/api/estado'), headers: {'Cookie': cookie});
    expect(estado.statusCode, 200);
    expect(estado.body, isNot(contains('token-secreto')));
    expect(estado.body, isNot(contains('secreta')));
    expect((await post('/api/diagnostico', {'acao': 'GetCPInfo'}, origem: 'http://outro.site')).statusCode, 403);
    csrf = 'incorreto';
    expect((await post('/api/diagnostico', {'acao': 'GetCPInfo'})).statusCode, 403);
    expect(acoes, isEmpty);
  });

  test('limita tentativas de senha e bloqueia Host não local', () async {
    final externo = await cliente.get(base.resolve('/api/estado'), headers: {'Host': 'site.externo'});
    expect(externo.statusCode, 403);
    for (var i = 0; i < 5; i++) {
      expect((await post('/api/login', {'senha': 'errada'}, autenticado: false)).statusCode, 401);
    }
    expect((await post('/api/login', {'senha': 'senha-do-monitor-123'}, autenticado: false)).statusCode, 429);
  });

  test('monitor sem senha própria não inicia', () async {
    final desligado = MonitorAgente(Agente(AgenteConfig(servidor: 'https://exemplo.org',
        chaveAgente: 'chave', holyricsToken: 'token', pastaImagensHolyrics: Directory.systemTemp.path,
        monitorPorta: 0)));
    await expectLater(desligado.iniciar(), throwsStateError);
    expect(desligado.porta, isNull);
  });

  test('diagnósticos de leitura, catálogo com preview e logs sem credenciais', () async {
    await login();
    final d = await post('/api/diagnostico', {'acao': 'GetCPInfo'});
    expect(jsonDecode(d.body)['ok'], true);
    final temas = await cliente.get(base.resolve('/api/temas'), headers: {'Cookie': cookie});
    expect((jsonDecode(temas.body)['temas'] as List).single['thumbnail'], 'iVBORw0KGgo=');
    expect(jsonDecode(temas.body)['miniaturasDisponiveis'], true);
    expect(acoes, containsAll(['GetCPInfo', 'GetThemes', 'GetThumbnail']));
    expect(acoes, isNot(contains('ShowQuickPresentation')));
    final logs = await cliente.get(base.resolve('/api/logs'), headers: {'Cookie': cookie});
    expect(logs.body, isNot(contains('token-secreto')));
  });

  test('ensaio bloqueado se tela ocupada; confirmação por etapa e identidade', () async {
    await login();
    expect((await post('/api/ensaio', {'etapa': 'iniciar'})).statusCode, 400);
    apresentacao = {'id': 'culto', 'type': 'song'};
    expect((await post('/api/ensaio', {'etapa': 'iniciar', 'confirmacao': 'SIM'})).statusCode, 409);
    expect(acoes, isNot(contains('ShowQuickPresentation')));
    apresentacao = null;
    expect((await post('/api/ensaio', {'etapa': 'iniciar', 'confirmacao': 'SIM'})).statusCode, 200);
    apresentacao = {'id': 'outro', 'type': 'quick_presentation'};
    expect((await post('/api/ensaio', {'etapa': 'proximo', 'confirmacao': 'SIM'})).statusCode, 409);
    expect(acoes, isNot(contains('ActionNextQuickPresentation')));
  });

  test('falha ao ler o telão bloqueia toda projeção', () async {
    await login();
    falharLeitura = true;
    expect((await post('/api/ensaio', {'etapa': 'iniciar', 'confirmacao': 'SIM'})).statusCode, 409);
    expect(acoes, isNot(contains('ShowQuickPresentation')));
  });

  test('navegação do ensaio confirma mudança do slide sem fechar apresentação', () async {
    await login();
    expect((await post('/api/ensaio', {'etapa': 'iniciar', 'confirmacao': 'SIM'})).statusCode, 200);
    final seguinte = await post('/api/ensaio', {'etapa': 'proximo', 'confirmacao': 'SIM'});
    expect(jsonDecode(seguinte.body)['slide'], 2);
    final anterior = await post('/api/ensaio', {'etapa': 'anterior', 'confirmacao': 'SIM'});
    expect(jsonDecode(anterior.body)['slide'], 1);
    expect(acoes, isNot(contains('CloseCurrentPresentation')));
  });
}
