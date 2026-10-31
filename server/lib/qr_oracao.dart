import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:qr/qr.dart';

import 'pagina_inicial.dart';

const arquivoQr = 'qr-oracao.png';
const arquivoQrMensagens = 'qr-mensagens.png';

/// Arte de fundo de um QR (montada no /admin ou enviada pronta) e onde o QR entra nela.
typedef ArteDoQr = ({img.Image fundo, String posicao, String tamanho});

/// Posições prontas do QR na arte: horizontal-vertical.
const posicoesQr = {
  'esquerda-meio', 'centro-meio', 'direita-meio', 'esquerda-baixo', 'centro-baixo', 'direita-baixo',
};
const tamanhosQr = {'P', 'M', 'G'};

/// Lado do cartão do QR em fração da altura da tela.
const _ladoCartao = {'P': 0.44, 'M': 0.56, 'G': 0.70};

/// Distância do cartão até a borda da tela, em px (nunca encosta).
const margemCartaoQr = 96;

/// Onde fica o cartão branco do QR numa tela de [largura]x[altura] (o mesmo cálculo da prévia do
/// /admin, em server/web/arte-qr.js).
({int x, int y, int lado}) retanguloCartaoQr(String posicao, String tamanho,
    {int largura = 1920, int altura = 1080, int modulos = 25}) {
  final alvo = (altura * (_ladoCartao[tamanho] ?? _ladoCartao['M']!)).round();
  // Módulos inteiros: o QR fica nítido. A zona silenciosa (4 módulos de cada lado) é o próprio cartão.
  final escala = max(1, alvo ~/ (modulos + 8));
  final lado = escala * (modulos + 8);
  final partes = posicao.split('-');
  final x = switch (partes.first) {
    'esquerda' => margemCartaoQr,
    'direita' => largura - margemCartaoQr - lado,
    _ => (largura - lado) ~/ 2,
  };
  final y = partes.length > 1 && partes[1] == 'baixo' ? altura - margemCartaoQr - lado : (altura - lado) ~/ 2;
  return (x: x, y: y, lado: lado);
}

/// A arte com o QR de [conteudo] num cartão branco arredondado, com sombra leve: o contraste para a
/// câmera não depende das cores da arte. A arte já vem em 1920x1080 (ArtesQr.salvar).
Uint8List comporQr(ArteDoQr arte, String conteudo) {
  final qr = QrImage(QrCode.fromData(data: conteudo, errorCorrectLevel: QrErrorCorrectLevel.Q));
  final tela = img.Image.from(arte.fundo);
  final r = retanguloCartaoQr(arte.posicao, arte.tamanho,
      largura: tela.width, altura: tela.height, modulos: qr.moduleCount);
  final escala = r.lado ~/ (qr.moduleCount + 8);
  final raio = escala * 2; // menor que a zona silenciosa: o arredondado nunca corta o QR

  // Sombra: camadas pretas translúcidas, cada vez maiores.
  for (var i = 4; i >= 1; i--) {
    final d = i * 6;
    img.fillRect(tela,
        x1: r.x - d, y1: r.y - d + 8, x2: r.x + r.lado + d, y2: r.y + r.lado + d + 8,
        radius: raio + d, color: img.ColorRgba8(0, 0, 0, 18));
  }
  img.fillRect(tela,
      x1: r.x, y1: r.y, x2: r.x + r.lado - 1, y2: r.y + r.lado - 1, radius: raio, color: img.ColorRgb8(255, 255, 255));
  final preto = img.ColorRgb8(0, 0, 0);
  for (var linha = 0; linha < qr.moduleCount; linha++) {
    for (var coluna = 0; coluna < qr.moduleCount; coluna++) {
      if (!qr.isDark(linha, coluna)) continue;
      final x = r.x + (coluna + 4) * escala, y = r.y + (linha + 4) * escala;
      img.fillRect(tela, x1: x, y1: y, x2: x + escala - 1, y2: y + escala - 1, color: preto);
    }
  }
  return img.encodePng(tela);
}

/// PNG 1920x1080 com o QR code de [url], pronto para o Holyrics projetar com ShowImage. Sem
/// [arte], o padrão: fundo branco e o QR centralizado (com [rotulo] em cima, se houver).
Uint8List gerarPngQr(String url, {String? rotulo, ArteDoQr? arte}) {
  if (arte != null) return comporQr(arte, url);
  final qr = QrImage(QrCode.fromData(data: url, errorCorrectLevel: QrErrorCorrectLevel.M));
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
Future<File> gravarQr(String pasta, String url, {ArteDoQr? arte}) async {
  await Directory(pasta).create(recursive: true);
  final f = File(p.join(pasta, arquivoQr));
  await f.writeAsBytes(gerarPngQr(url, arte: arte));
  return f;
}

/// QR independente para a caixa de mensagens, na mesma pasta sincronizada ao Holyrics.
Future<File> gravarQrMensagens(String pasta, String url, {ArteDoQr? arte}) async {
  await Directory(pasta).create(recursive: true);
  final f = File(p.join(pasta, arquivoQrMensagens));
  await f.writeAsBytes(gerarPngQr(url, rotulo: 'DUVIDAS, SUGESTOES E CRITICAS', arte: arte));
  return f;
}

const arquivoQrPix = 'qr-pix.png';

/// QR gerados pelo servidor: não são cartazes (não aparecem na lista nem vão para o backup),
/// mas o agente os copia para a pasta de imagens do Holyrics.
bool ehArquivoDeQr(String nome) => nome == arquivoQr || nome == arquivoQrMensagens || nome == arquivoQrPix;

/// QR do PIX (com a chave escrita) para o momento das ofertas no culto. Sem chave, nome e
/// cidade, apaga o antigo e retorna null.
Future<File?> gravarQrPix(String pasta,
    {required String chave, required String nome, required String cidade, ArteDoQr? arte}) async {
  final f = File(p.join(pasta, arquivoQrPix));
  if (chave.trim().isEmpty || nome.trim().isEmpty || cidade.trim().isEmpty) {
    if (await f.exists()) await f.delete();
    return null;
  }
  await Directory(pasta).create(recursive: true);
  await f.writeAsBytes(gerarPngQr(payloadPix(chave: chave, nome: nome, cidade: cidade),
      rotulo: 'PIX: ${formatarChavePix(chave)}', arte: arte));
  return f;
}
