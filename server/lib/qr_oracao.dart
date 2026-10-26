import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:qr/qr.dart';

const arquivoQr = 'qr-oracao.png';
const arquivoQrMensagens = 'qr-mensagens.png';

/// PNG 1920x1080 de fundo branco com o QR code de [url] centralizado,
/// pronto para o Holyrics projetar com ShowImage.
Uint8List gerarPngQr(String url, {String? rotulo}) {
  final qr = QrImage(QrCode(payload: QrPayload.fromString(url), errorCorrectLevel: QrErrorCorrectLevel.medium));
  const largura = 1920, altura = 1080;
  final margem = 4; // zona silenciosa exigida pelo padrão, em módulos
  final total = qr.moduleCount + margem * 2;
  final escala = (altura * (rotulo == null ? 0.85 : 0.70) / total).floor();
  final lado = total * escala;
  final x0 = (largura - lado) ~/ 2, y0 = (altura - lado) ~/ 2 + (rotulo == null ? 0 : 40);

  final imagem = img.Image(width: largura, height: altura);
  img.fill(imagem, color: img.ColorRgb8(255, 255, 255));
  final preto = img.ColorRgb8(0, 0, 0);
  for (var linha = 0; linha < qr.moduleCount; linha++) {
    for (var coluna = 0; coluna < qr.moduleCount; coluna++) {
      if (!qr.isDark(linha, coluna)) continue;
      final x = x0 + (coluna + margem) * escala, y = y0 + (linha + margem) * escala;
      img.fillRect(imagem, x1: x, y1: y, x2: x + escala - 1, y2: y + escala - 1, color: preto);
    }
  }
  if (rotulo != null) img.drawString(imagem, rotulo, font: img.arial48, y: 70, color: preto);
  return img.encodePng(imagem);
}

/// Grava o PNG do QR na pasta de cartazes (subpasta "Diako" do Holyrics).
Future<File> gravarQr(String pasta, String url) async {
  await Directory(pasta).create(recursive: true);
  final f = File(p.join(pasta, arquivoQr));
  await f.writeAsBytes(gerarPngQr(url));
  return f;
}

/// QR independente para a caixa de mensagens, na mesma pasta sincronizada ao Holyrics.
Future<File> gravarQrMensagens(String pasta, String url) async {
  await Directory(pasta).create(recursive: true);
  final f = File(p.join(pasta, arquivoQrMensagens));
  await f.writeAsBytes(gerarPngQr(url, rotulo: 'DUVIDAS, SUGESTOES E CRITICAS'));
  return f;
}
