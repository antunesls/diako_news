import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'cartazes.dart';

/// Fotos do carrossel da página inicial, gravadas em data/galeria/ (separadas dos cartazes do
/// telão: não vão para o Holyrics nem para o agente). Os dados de cada foto (legenda, ordem,
/// visível) ficam na coleção "galeria" do Store.
class Galeria {
  Galeria(String pastaDados) : pasta = p.join(pastaDados, 'galeria');

  final String pasta;

  static const tamanhoMaximo = 15 * 1024 * 1024;
  static const maximoFotos = 30;
  static const larguraMaxima = 1920;
  static const larguraMiniatura = 480;

  /// Acima disso a foto nem é aberta (memória do servidor).
  static const pixelsMaximos = 40 * 1000 * 1000;

  /// Nomes gerados pelo servidor: "<hex>.jpg" (foto) e "<hex>-m.jpg" (miniatura).
  static bool nomeValido(String nome) => RegExp(r'^[0-9a-f]{20}(-m)?\.jpg$').hasMatch(nome);

  File? arquivo(String nome) => nomeValido(nome) ? File(p.join(pasta, nome)) : null;

  /// Processa e grava a foto. Lança [FormatException] com a mensagem para o usuário.
  Future<({String arquivo, String miniatura, int largura, int altura})> salvar(Uint8List bytes) async {
    if (bytes.isEmpty) throw const FormatException('Arquivo vazio.');
    if (bytes.length > tamanhoMaximo) throw const FormatException('Foto maior que 15 MB.');
    if (Cartazes.tipoImagem(bytes) == null) throw const FormatException('Envie uma foto JPG ou PNG.');
    final r = await Isolate.run(() => processarFoto(bytes));
    await Directory(pasta).create(recursive: true);
    final rng = Random.secure();
    final base = List.generate(10, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final arquivo = '$base.jpg', miniatura = '$base-m.jpg';
    await File(p.join(pasta, arquivo)).writeAsBytes(r.foto, flush: true);
    await File(p.join(pasta, miniatura)).writeAsBytes(r.miniatura, flush: true);
    return (arquivo: arquivo, miniatura: miniatura, largura: r.largura, altura: r.altura);
  }

  Future<void> excluir(Iterable<String> nomes) async {
    for (final nome in nomes) {
      final f = arquivo(nome);
      if (f != null && await f.exists()) await f.delete();
    }
  }
}

/// Deixa a foto de pé (orientação do celular), reduz para no máximo [Galeria.larguraMaxima] px e
/// regrava em JPEG sem os metadados EXIF (que podem trazer a localização GPS de onde foi tirada).
({Uint8List foto, Uint8List miniatura, int largura, int altura}) processarFoto(Uint8List bytes) {
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (decoder == null || info == null) throw const FormatException('Não foi possível ler a imagem.');
  if (info.width * info.height > Galeria.pixelsMaximos) {
    throw const FormatException('Foto com resolução alta demais. Reduza o tamanho e envie de novo.');
  }
  var foto = decoder.decode(bytes);
  if (foto == null) throw const FormatException('Não foi possível ler a imagem.');
  foto = img.bakeOrientation(foto);
  if (foto.hasAlpha) {
    // PNG com transparência: fundo branco (o JPEG não tem transparência).
    final fundo = img.Image(width: foto.width, height: foto.height);
    img.fill(fundo, color: img.ColorRgb8(255, 255, 255));
    foto = img.compositeImage(fundo, foto);
  }
  if (foto.width > Galeria.larguraMaxima) {
    foto = img.copyResize(foto, width: Galeria.larguraMaxima, interpolation: img.Interpolation.average);
  }
  final miniatura = img.copyResize(foto, width: Galeria.larguraMiniatura, interpolation: img.Interpolation.average);
  foto.exif = img.ExifData();
  miniatura.exif = img.ExifData();
  return (
    foto: img.encodeJpg(foto, quality: 82),
    miniatura: img.encodeJpg(miniatura, quality: 78),
    largura: foto.width,
    altura: foto.height,
  );
}
