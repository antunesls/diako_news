import 'dart:convert';
import 'dart:io';

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
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late Store store;
  late Handler handler;
  late String token;
  late int avisos;
  var falharEmail = false;

  Future<Response> chamar(String metodo, String path,
          {Map<String, dynamic>? dados, bool login = false}) =>
      Future.sync(() => handler(
            Request(metodo, Uri.parse('http://localhost$path'),
                headers: {
                  if (login) 'authorization': 'Bearer $token',
                  'content-type': 'application/json'
                },
                body: dados == null ? null : jsonEncode(dados)),
          ));
  Future<dynamic> json(Response r) async => jsonDecode(await r.readAsString());

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('diako_mensagens_');
    store = Store(p.join(tmp.path, 'data'));
    await store.carregar();
    final auth = Auth(senha: 'senha-forte', pastaDados: store.pasta);
    await auth.carregar();
    final web = Directory(p.join(tmp.path, 'web'))..createSync();
    File(p.join(web.path, 'mensagens.html'))
        .writeAsStringSync('<h1>Caixa de mensagens</h1>');
    avisos = 0;
    falharEmail = false;
    handler = Servidor(
      store: store,
      auth: auth,
      holyrics: HolyricsDireto(
          host: 'localhost',
          porta: 8091,
          token: 'x',
          cliente:
              MockClient((_) async => http.Response('{"status":"ok"}', 200))),
      cartazes: Cartazes(p.join(tmp.path, 'imagens')),
      backup: Backup(pastaDados: store.pasta),
      pastaWeb: web.path,
      urlOracao: 'http://localhost/oracao',
      cartazesNoHolyrics: true,
      historico: Historico(store.pasta),
      enviarAvisoMensagem: (mensagem, url) async {
        avisos++;
        if (falharEmail) throw const SocketException('SMTP indisponível');
      },
    ).handler;
    token = (await json(await chamar('POST', '/api/login',
        dados: {'senha': 'senha-forte'})))['token'] as String;
  });

  tearDown(() async {
    await store.fechar();
    await tmp.delete(recursive: true);
  });

  test('formulário público salva sem identificação e a caixa exige login',
      () async {
    expect((await chamar('GET', '/mensagens')).statusCode, 200);
    expect((await chamar('GET', '/api/mensagens')).statusCode, 401);
    final resposta = await chamar('POST', '/api/public/mensagens',
        dados: {'tipo': 'critica', 'texto': '  Melhorar a recepção  '});
    expect(resposta.statusCode, 201);
    final lista =
        await json(await chamar('GET', '/api/mensagens', login: true)) as List;
    expect(lista.single['texto'], 'Melhorar a recepção');
    expect(lista.single['status'], 'nova');
    expect(lista.single['nome'], '');
    expect(
        (await json(
            await chamar('GET', '/api/estado', login: true)))['mensagensNovas'],
        1);
    expect(avisos, 1);
  });

  test('rejeita conteúdo inválido e ignora armadilha de robôs', () async {
    for (final dados in [
      {'tipo': 'outro', 'texto': 'Oi'},
      {'tipo': 'duvida', 'texto': ' '},
      {'tipo': 'sugestao', 'texto': 'x' * 2001},
      {'tipo': 'critica', 'texto': 'Oi', 'contato': 'x' * 121},
    ]) {
      expect(
          (await chamar('POST', '/api/public/mensagens', dados: dados))
              .statusCode,
          400);
    }
    expect(
        (await chamar('POST', '/api/public/mensagens', dados: {
          'tipo': 'duvida',
          'texto': 'Spam',
          'website': 'bot',
        }))
            .statusCode,
        200);
    expect(
        (await json(await chamar('GET', '/api/mensagens', login: true))
            as List),
        isEmpty);
  });

  test('limita envios públicos por IP sem afetar a caixa autenticada',
      () async {
    for (var i = 0; i < 5; i++) {
      expect(
          (await chamar('POST', '/api/public/mensagens',
                  dados: {'tipo': 'duvida', 'texto': 'Dúvida $i'}))
              .statusCode,
          201);
    }
    expect(
        (await chamar('POST', '/api/public/mensagens',
                dados: {'tipo': 'duvida', 'texto': 'Mais uma'}))
            .statusCode,
        429);
    expect(
        (await json(await chamar('GET', '/api/mensagens', login: true)) as List)
            .length,
        5);
  });

  test('status muda sem aceitar edição do texto; mensagens persistem em backup',
      () async {
    await chamar('POST', '/api/public/mensagens',
        dados: {'tipo': 'duvida', 'texto': 'Horários?'});
    final item =
        (await json(await chamar('GET', '/api/mensagens', login: true)) as List)
            .single;
    final id = item['id'];
    expect(
        (await chamar('PUT', '/api/mensagens/$id',
                dados: {'status': 'invalido'}, login: true))
            .statusCode,
        400);
    expect(
        (await chamar('PUT', '/api/mensagens/$id',
                dados: {'status': 'emAnalise', 'texto': 'Alterado'},
                login: true))
            .statusCode,
        400);
    final r = await chamar('PUT', '/api/mensagens/$id',
        dados: {'status': 'emAnalise'}, login: true);
    expect((await json(r))['status'], 'emAnalise');
    expect(
        (await json(
            await chamar('GET', '/api/estado', login: true)))['mensagensNovas'],
        0);
    final zip = await Backup(pastaDados: store.pasta).gerarZip();
    final salvo = ZipDecoder().decodeBytes(zip).findFile('data/mensagens.json');
    expect(salvo, isNotNull);
    expect(utf8.decode(salvo!.content), contains('Horários?'));
    expect(await File(p.join(store.pasta, 'mensagens.json')).exists(), isTrue);
    final outraInstancia = Store(store.pasta);
    await outraInstancia.carregar();
    expect(outraInstancia.listar('mensagens').single['status'], 'emAnalise');
    await outraInstancia.fechar();
  });

  test(
      'falha no SMTP não perde mensagem e nova tentativa autenticada atualiza aviso',
      () async {
    falharEmail = true;
    expect(
        (await chamar('POST', '/api/public/mensagens',
                dados: {'tipo': 'sugestao', 'texto': 'Mais bancos'}))
            .statusCode,
        201);
    final item =
        (await json(await chamar('GET', '/api/mensagens', login: true)) as List)
            .single;
    expect(item['avisoEmail'], 'falhou');
    expect(
        (await chamar('POST', '/api/mensagens/${item['id']}/avisar'))
            .statusCode,
        401);
    falharEmail = false;
    final r = await chamar('POST', '/api/mensagens/${item['id']}/avisar',
        login: true);
    expect((await json(r))['avisoEmail'], 'enviado');
    expect(avisos, 2);
  });

  test('QR de mensagens não pode ser apagado pela API de cartazes', () async {
    final pasta = p.join(tmp.path, 'imagens');
    await gravarQrMensagens(pasta, 'http://localhost/mensagens');
    expect(
        (await json(await chamar('GET', '/api/cartazes', login: true)) as List),
        isEmpty);
    expect(
        (await chamar('DELETE', '/api/cartazes/qr-mensagens.png', login: true))
            .statusCode,
        404);
    expect(await File(p.join(pasta, arquivoQrMensagens)).exists(), isTrue);
  });

  test('QR projetado identifica a caixa de mensagens', () async {
    final pasta = p.join(tmp.path, 'imagens');
    final arquivo =
        await gravarQrMensagens(pasta, 'http://localhost/mensagens');
    final imagem = img.decodePng(await arquivo.readAsBytes())!;
    var tintaNoTitulo = false;
    for (var y = 60; y < 130; y++) {
      for (var x = 350; x < 1570; x++) {
        if (imagem.getPixel(x, y).r < 128) tintaNoTitulo = true;
      }
    }
    expect(tintaNoTitulo, isTrue);
  });
}
