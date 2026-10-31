import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'cartazes.dart';
import 'configuracoes.dart';
import 'galeria.dart';
import 'qr_oracao.dart';

/// Artes de fundo dos QR projetados (oração, mensagens, PIX), em data/artes-qr/. O QR é encaixado
/// pelo servidor em cima (comporQr); a arte em si nunca tem o código.
class ArtesQr {
  ArtesQr(String pastaDados) : pasta = p.join(pastaDados, 'artes-qr');

  final String pasta;

  static const largura = 1920, altura = 1080;

  /// Nomes gerados pelo servidor: "<qr>-<hex>.png" (a arte, sem o QR) e "<qr>-foto-<hex>.jpg" (a foto
  /// de fundo do editor automático, para reabrir e editar). O nome muda a cada envio.
  static bool nomeValido(String nome) =>
      RegExp(r'^(oracao|mensagens|pix)-([0-9a-f]{20}\.png|foto-[0-9a-f]{20}\.jpg)$').hasMatch(nome);

  File? arquivo(String nome) => nomeValido(nome) ? File(p.join(pasta, nome)) : null;

  /// Ajusta a imagem a 1920x1080 (corta o que sobra, sem distorcer), tira o EXIF e grava: a arte em
  /// PNG (texto nítido), a [foto] do editor em JPG. Lança [FormatException] com a mensagem para o usuário.
  Future<String> salvar(String qr, Uint8List bytes, {bool foto = false}) async {
    if (!qrsComArte.contains(qr)) throw const FormatException('QR desconhecido.');
    if (bytes.isEmpty) throw const FormatException('Arquivo vazio.');
    if (bytes.length > Galeria.tamanhoMaximo) throw const FormatException('Imagem maior que 15 MB.');
    if (Cartazes.tipoImagem(bytes) == null) throw const FormatException('Envie uma imagem JPG ou PNG.');
    final saida = await Isolate.run(() => normalizarArte(bytes, jpg: foto));
    await Directory(pasta).create(recursive: true);
    final rng = Random.secure();
    final hex = List.generate(10, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final nome = foto ? '$qr-foto-$hex.jpg' : '$qr-$hex.png';
    await File(p.join(pasta, nome)).writeAsBytes(saida, flush: true);
    return nome;
  }

  Future<void> excluir(String nome) async {
    final f = arquivo(nome);
    if (f != null && await f.exists()) await f.delete();
  }

  /// A arte de [qr] pronta para comporQr, ou null no modo padrão. Arte sumida ou ilegível: null
  /// (o QR sai no padrão) e um aviso no log; o culto nunca fica sem QR.
  Future<ArteDoQr?> carregar(Configuracoes cfg, String qr) async {
    final a = cfg.arteQr(qr);
    if (a.modo == 'padrao') return null;
    final f = arquivo(a.fundo);
    try {
      if (f == null || !await f.exists()) throw const FileSystemException('arquivo não encontrado');
      final fundo = img.decodePng(await f.readAsBytes());
      if (fundo == null || fundo.width != largura || fundo.height != altura) {
        throw const FormatException('arte ilegível');
      }
      return (fundo: fundo, posicao: a.posicao, tamanho: a.tamanho);
    } catch (e) {
      stderr.writeln('Arte do QR "$qr" indisponível ($e); usando o QR padrão.');
      return null;
    }
  }
}

/// PNG (ou JPG) 1920x1080 da arte: corta para preencher a tela, fundo branco onde houver transparência.
Uint8List normalizarArte(Uint8List bytes, {bool jpg = false}) {
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (decoder == null || info == null) throw const FormatException('Não foi possível ler a imagem.');
  if (info.width * info.height > Galeria.pixelsMaximos) {
    throw const FormatException('Imagem com resolução alta demais. Reduza o tamanho e envie de novo.');
  }
  var arte = decoder.decode(bytes);
  if (arte == null) throw const FormatException('Não foi possível ler a imagem.');
  arte = img.bakeOrientation(arte);
  final escala = max(ArtesQr.largura / arte.width, ArtesQr.altura / arte.height);
  final w = max(ArtesQr.largura, (arte.width * escala).ceil()), h = max(ArtesQr.altura, (arte.height * escala).ceil());
  final ajustada = img.copyResize(arte, width: w, height: h, interpolation: img.Interpolation.average);
  final cortada = img.copyCrop(ajustada,
      x: (w - ArtesQr.largura) ~/ 2, y: (h - ArtesQr.altura) ~/ 2, width: ArtesQr.largura, height: ArtesQr.altura);
  // Transparência vira branco; a saída é sempre RGB 1920x1080.
  final tela = img.Image(width: ArtesQr.largura, height: ArtesQr.altura);
  img.fill(tela, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(tela, cortada);
  return jpg ? img.encodeJpg(tela, quality: 88) : img.encodePng(tela);
}

/// Refaz os três QR projetados (com a arte de cada um, se houver) na pasta de cartazes, de onde
/// o Holyrics os abre e o agente os copia para o PC da igreja.
Future<void> gravarQrsProjetados(String pastaCartazes, Configuracoes cfg, ArtesQr artes) async {
  await gravarQr(pastaCartazes, cfg.urlOracao, arte: await artes.carregar(cfg, 'oracao'));
  await gravarQrMensagens(pastaCartazes, cfg.urlMensagens, arte: await artes.carregar(cfg, 'mensagens'));
  await gravarQrPix(pastaCartazes,
      chave: cfg.sitePixChave, nome: cfg.sitePixNome, cidade: cfg.sitePixCidade, arte: await artes.carregar(cfg, 'pix'));
}
