import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:diako_server/app.dart';
import 'package:diako_server/auth.dart';
import 'package:diako_server/backup.dart';
import 'package:diako_server/cartazes.dart';
import 'package:diako_server/config.dart';
import 'package:diako_server/configuracoes.dart';
import 'package:diako_server/galeria.dart';
import 'package:diako_server/historico.dart';
import 'package:diako_server/holyrics.dart';
import 'package:diako_server/store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// JPEG de teste; [orientacao] 6 = celular deitado (precisa girar 90°).
Uint8List jpeg(int largura, int altura, {int? orientacao, String? camera}) {
  final imagem = img.Image(width: largura, height: altura);
  img.fill(imagem, color: img.ColorRgb8(30, 95, 91));
  if (orientacao != null) imagem.exif.imageIfd.orientation = orientacao;
  if (camera != null) imagem.exif.imageIfd.make = camera;
  return img.encodeJpg(imagem);
}

void main() {
  test('processamento: gira a foto do celular, reduz e remove o EXIF', () {
    final grande = processarFoto(jpeg(4000, 2000));
    expect((grande.largura, grande.altura), (1920, 960));

    final original = jpeg(1200, 800, orientacao: 6, camera: 'CameraSecreta');
    expect(latin1.decode(original, allowInvalid: true), contains('CameraSecreta'));
    final deitada = processarFoto(original);
    expect((deitada.largura, deitada.altura), (800, 1200)); // de pé
    expect(latin1.decode(deitada.foto, allowInvalid: true), isNot(contains('CameraSecreta')));
    expect(latin1.decode(deitada.foto, allowInvalid: true), isNot(contains('Exif')));
    expect(img.decodeJpg(deitada.miniatura)!.width, Galeria.larguraMiniatura);

    // PNG com transparência vira JPEG com fundo branco.
    final png = img.Image(width: 10, height: 10, numChannels: 4);
    final r = processarFoto(img.encodePng(png));
    expect(img.decodeJpg(r.foto)!.getPixel(0, 0).r, greaterThan(240));
  });

  test('nomes de arquivo aceitos', () {
    expect(Galeria.nomeValido('0123456789abcdef0123.jpg'), isTrue);
    expect(Galeria.nomeValido('0123456789abcdef0123-m.jpg'), isTrue);
    expect(Galeria.nomeValido('../galeria.json'), isFalse);
    expect(Galeria.nomeValido('foto.jpg'), isFalse);
  });

  group('servidor', () {
    late Directory tmp;
    late Store store;
    late Handler handler;
    late String token;
    late String pastaDados;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('diako_galeria');
      final config = Config.lerJson('{"senhaAdmin":"senha-teste"}', pastaBase: tmp.path);
      pastaDados = config.pastaDados;
      store = Store(config.pastaDados);
      await store.carregar();
      final cfg = await Configuracoes.carregar(config, urlDetectada: 'http://192.168.0.10:8080');
      final auth = Auth(conferirSenha: cfg.conferirSenha, pastaDados: config.pastaDados);
      final backup = Backup(pastaDados: config.pastaDados, configuracoes: cfg.publicas);
      final web = Directory(p.join(tmp.path, 'web'))..createSync();
      handler = Servidor(
        store: store,
        auth: auth,
        holyrics: HolyricsDireto(host: 'h', porta: 1, token: 't', cliente: MockClient((_) async => http.Response('{}', 200))),
        cartazes: Cartazes(config.pastaCartazes),
        backup: backup,
        pastaWeb: web.path,
        urlOracao: cfg.urlOracao,
        cartazesNoHolyrics: false,
        historico: Historico(config.pastaDados),
        cfg: cfg,
        restauracao: Restauracao(
            store: store, backup: backup, pastaDados: config.pastaDados, pastaCartazes: config.pastaCartazes),
      ).handler;
      final r = await handler(Request('POST', Uri.parse('http://x/api/login'), body: jsonEncode({'senha': 'senha-teste'})));
      token = (jsonDecode(await r.readAsString()) as Map)['token'] as String;
    });
    tearDown(() async {
      await store.fechar();
      await tmp.delete(recursive: true);
    });

    Future<(int, dynamic)> chamar(String metodo, String caminho, {Object? json, List<int>? bytes, bool login = true}) async {
      final r = await handler(Request(metodo, Uri.parse('http://x$caminho'),
          headers: {if (login) 'authorization': 'Bearer $token', if (json != null) 'content-type': 'application/json'},
          body: bytes ?? (json == null ? null : jsonEncode(json))));
      final corpo = await r.read().expand((b) => b).toList();
      final texto = utf8.decode(corpo, allowMalformed: true);
      return (r.statusCode, texto.startsWith('{') || texto.startsWith('[') ? jsonDecode(texto) : corpo);
    }

    Future<List> galeriaPublica() async => (await chamar('GET', '/api/public/inicio', login: false)).$2['galeria'] as List;

    test('enviar, legendar, ordenar, ocultar, desligar e excluir', () async {
      expect((await chamar('POST', '/api/galeria', bytes: jpeg(800, 600), login: false)).$1, 401);
      expect((await chamar('POST', '/api/galeria', bytes: utf8.encode('não é imagem'))).$1, 400);

      var (st, a) = await chamar('POST', '/api/galeria?legenda=Culto%20de%20jovens', bytes: jpeg(2400, 1600));
      expect(st, 201);
      expect(a['legenda'], 'Culto de jovens');
      expect(a['largura'], 1920);
      final (_, b) = await chamar('POST', '/api/galeria', bytes: jpeg(800, 600));

      // A foto é pública; caminhos fora da pasta não.
      final (stFoto, foto) = await chamar('GET', a['url'] as String, login: false);
      expect(stFoto, 200);
      expect(img.decodeJpg(Uint8List.fromList(foto as List<int>))!.width, 1920);
      expect((await chamar('GET', '/galeria/..%2Fgaleria.json', login: false)).$1, 404);

      expect((await galeriaPublica()).map((f) => f['legenda']), ['Culto de jovens', '']);

      expect((await chamar('PUT', '/api/galeria/${b['id']}', json: {'link': 'http://x'})).$1, 400);
      expect((await chamar('PUT', '/api/galeria/${b['id']}', json: {'legenda': 'Batismo', 'link': 'https://instagram.com/p/1'})).$1, 200);
      await chamar('PUT', '/api/galeria/ordem', json: [b['id'], a['id']]);
      var publica = await galeriaPublica();
      expect(publica.map((f) => f['legenda']), ['Batismo', 'Culto de jovens']); // a primeira é a capa
      expect(publica.first['link'], 'https://instagram.com/p/1');

      await chamar('PUT', '/api/galeria/${a['id']}', json: {'ativo': false});
      expect((await galeriaPublica()).map((f) => f['legenda']), ['Batismo']);
      final (_, lista) = await chamar('GET', '/api/galeria');
      expect((lista as List).length, 2); // o painel vê também as ocultas

      await chamar('PUT', '/api/admin/configuracoes', json: {'siteGaleria': false});
      expect(await galeriaPublica(), isEmpty);
      await chamar('PUT', '/api/admin/configuracoes', json: {'siteGaleria': true});

      (st, _) = await chamar('DELETE', '/api/galeria/${a['id']}');
      expect(st, 200);
      expect(File(p.join(pastaDados, 'galeria', a['arquivo'] as String)).existsSync(), isFalse);
      expect(File(p.join(pastaDados, 'galeria', a['miniatura'] as String)).existsSync(), isFalse);
    });

    test('backup leva e restaura as fotos', () async {
      final (_, a) = await chamar('POST', '/api/galeria?legenda=Retiro', bytes: jpeg(800, 600));
      final (_, zipBytes) = await chamar('GET', '/api/backups/agora/download');
      final zip = ZipDecoder().decodeBytes(zipBytes as List<int>);
      expect(zip.findFile('galeria/${a['arquivo']}'), isNotNull);
      expect(zip.findFile('galeria/${a['miniatura']}'), isNotNull);
      expect(zip.findFile('data/galeria.json'), isNotNull);

      await chamar('DELETE', '/api/galeria/${a['id']}');
      expect(await galeriaPublica(), isEmpty);
      final (st, r) = await chamar('POST', '/api/backups/restaurar', bytes: zipBytes);
      expect(st, 200, reason: '$r');
      expect((await galeriaPublica()).single['legenda'], 'Retiro');
      expect((await chamar('GET', '/galeria/${a['arquivo']}', login: false)).$1, 200);
    });
  });
}
