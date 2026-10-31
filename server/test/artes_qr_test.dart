import 'dart:io';
import 'dart:typed_data';

import 'package:diako_server/artes_qr.dart';
import 'package:diako_server/config.dart';
import 'package:diako_server/configuracoes.dart';
import 'package:diako_server/pagina_inicial.dart';
import 'package:diako_server/qr_oracao.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';
import 'package:zxing2/qrcode.dart';

/// Lê o QR de um PNG como uma câmera leria (sem saber onde ele está).
String lerQr(Uint8List png) {
  final im = img.decodePng(png)!;
  final pixels = Int32List(im.width * im.height);
  var i = 0;
  for (final px in im) {
    pixels[i++] = 0xFF000000 | (px.r.toInt() << 16) | (px.g.toInt() << 8) | px.b.toInt();
  }
  return QRCodeReader().decode(BinaryBitmap(HybridBinarizer(RGBLuminanceSource(im.width, im.height, pixels)))).text;
}

/// Arte de teste "difícil": listras escuras e claras, como uma foto cheia de contraste.
img.Image arteListrada() {
  final a = img.Image(width: 1920, height: 1080);
  for (var x = 0; x < 1920; x += 40) {
    img.fillRect(a, x1: x, y1: 0, x2: x + 19, y2: 1079, color: img.ColorRgb8(10, 10, 40));
    img.fillRect(a, x1: x + 20, y1: 0, x2: x + 39, y2: 1079, color: img.ColorRgb8(240, 200, 60));
  }
  return a;
}

void main() {
  const url = 'https://diako.minhaigreja.com.br/oracao';

  group('comporQr', () {
    final arte = arteListrada();
    for (final posicao in posicoesQr) {
      for (final tamanho in tamanhosQr) {
        test('$posicao $tamanho: lê a URL e fica dentro da tela, longe da borda', () {
          final png = comporQr((fundo: arte, posicao: posicao, tamanho: tamanho), url);
          final final_ = img.decodePng(png)!;
          expect([final_.width, final_.height], [1920, 1080]);
          expect(lerQr(png), url);
          final r = retanguloCartaoQr(posicao, tamanho, modulos: 33);
          expect(r.x, greaterThanOrEqualTo(60));
          expect(r.y, greaterThanOrEqualTo(60));
          expect(r.x + r.lado, lessThanOrEqualTo(1920 - 60));
          expect(r.y + r.lado, lessThanOrEqualTo(1080 - 60));
          // O código (sem a zona silenciosa) nunca fica menor que ~30% da altura.
          expect(r.lado * 33 / 41, greaterThanOrEqualTo(1080 * 0.30));
        });
      }
    }

    test('mesma geometria da prévia do /admin (tabela igual em test/arte_qr_test.js)', () {
      const tabela = [
        ['esquerda-meio', 'P', 96, 318, 444],
        ['esquerda-meio', 'G', 96, 170, 740],
        ['centro-baixo', 'P', 738, 540, 444],
        ['centro-baixo', 'G', 590, 244, 740],
        ['direita-meio', 'P', 1380, 318, 444],
        ['direita-meio', 'G', 1084, 170, 740],
      ];
      for (final [posicao as String, tamanho as String, x, y, lado] in tabela) {
        final r = retanguloCartaoQr(posicao, tamanho, modulos: 29);
        expect([r.x, r.y, r.lado], [x, y, lado], reason: '$posicao $tamanho');
      }
    });

    test('a arte não é alterada fora do cartão', () {
      final png = comporQr((fundo: arte, posicao: 'direita-meio', tamanho: 'M'), url);
      final final_ = img.decodePng(png)!;
      expect(final_.getPixel(5, 5), arte.getPixel(5, 5));
      expect(final_.getPixel(25, 1000), arte.getPixel(25, 1000));
    });

    test('PIX: o payload longo também é lido', () {
      final pix = payloadPix(chave: 'tesouraria@igrejadiakonia.org.br', nome: 'Igreja Diakonia Tulipas', cidade: 'Jundiai');
      for (final tamanho in tamanhosQr) {
        expect(lerQr(comporQr((fundo: arte, posicao: 'centro-baixo', tamanho: tamanho), pix)), pix);
      }
    });
  });

  test('normalizarArte: qualquer proporção vira 1920x1080 cortando, sem distorcer', () {
    final retrato = img.Image(width: 600, height: 1200);
    img.fill(retrato, color: img.ColorRgb8(200, 0, 0));
    img.fillRect(retrato, x1: 0, y1: 0, x2: 599, y2: 99, color: img.ColorRgb8(0, 0, 200)); // topo: some no corte
    final saida = img.decodePng(normalizarArte(img.encodePng(retrato)))!;
    expect([saida.width, saida.height], [1920, 1080]);
    expect(saida.getPixel(960, 540).r, greaterThan(150));
    expect(saida.getPixel(960, 2).b, lessThan(100), reason: 'o topo azul foi cortado');
    expect(() => normalizarArte(Uint8List.fromList([1, 2, 3])), throwsFormatException);
  });

  group('ArtesQr', () {
    late Directory pasta;
    setUp(() async => pasta = await Directory.systemTemp.createTemp('artes_qr'));
    tearDown(() => pasta.delete(recursive: true));

    test('nomes aceitos e arte sumida cai no QR padrão', () async {
      final artes = ArtesQr(pasta.path);
      expect(ArtesQr.nomeValido('oracao-0123456789abcdef0123.png'), isTrue);
      expect(ArtesQr.nomeValido('../config.json'), isFalse);
      expect(ArtesQr.nomeValido('palco-0123456789abcdef0123.png'), isFalse);
      expect(() => artes.salvar('palco', Uint8List.fromList(img.encodePng(arteListrada()))), throwsFormatException);

      final nome = await artes.salvar('oracao', Uint8List.fromList(img.encodePng(arteListrada())));
      expect(ArtesQr.nomeValido(nome), isTrue);

      final config = Config.lerJson('{"senhaAdmin":"teste123"}', pastaBase: pasta.path);
      final cfg = await Configuracoes.carregar(config, urlDetectada: 'http://192.168.0.10:8080');
      expect(await artes.carregar(cfg, 'oracao'), isNull, reason: 'modo padrão');
      await cfg.definirArteQr('oracao', modo: 'arte', fundo: nome);
      expect(await artes.carregar(cfg, 'oracao'), isNotNull);
      await artes.excluir(nome);
      expect(await artes.carregar(cfg, 'oracao'), isNull, reason: 'arquivo sumiu: QR padrão, nunca sem QR');
    });
  });
}
