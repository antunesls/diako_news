import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'cartazes.dart';
import 'galeria.dart' show processarFoto;

/// Fotos do cadastro de membros, gravadas em data/fotos-membros/. Diferente da galeria
/// do site, **não** são públicas: o servidor só entrega atrás de login (Permissao.membros).
/// O nome do arquivo fica no campo "foto" do membro; a miniatura é "<nome>-m.jpg".
class FotosMembros {
  FotosMembros(String pastaDados) : pasta = p.join(pastaDados, 'fotos-membros');

  final String pasta;

  static const tamanhoMaximo = 15 * 1024 * 1024;
  static const larguraMaxima = 1280;
  static const larguraMiniatura = 320;

  /// Acima disso a foto nem é aberta (memória do servidor).
  static const pixelsMaximos = 40 * 1000 * 1000;

  /// Nomes gerados pelo servidor: "<hex>.jpg" (foto) e "<hex>-m.jpg" (miniatura).
  static bool nomeValido(String nome) => RegExp(r'^[0-9a-f]{20}(-m)?\.jpg$').hasMatch(nome);

  File? arquivo(String nome) => nomeValido(nome) ? File(p.join(pasta, nome)) : null;

  /// Processa e grava a foto (em pé, sem EXIF, no máximo [larguraMaxima] px).
  /// Lança [FormatException] com a mensagem para o usuário.
  Future<({String arquivo, String miniatura})> salvar(Uint8List bytes) async {
    if (bytes.isEmpty) throw const FormatException('Arquivo vazio.');
    if (bytes.length > tamanhoMaximo) throw const FormatException('Foto maior que 15 MB.');
    if (Cartazes.tipoImagem(bytes) == null) throw const FormatException('Envie uma foto JPG ou PNG.');
    final r = await Isolate.run(() => processarFotoMembro(bytes));
    await Directory(pasta).create(recursive: true);
    final rng = Random.secure();
    final base = List.generate(10, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final arquivo = '$base.jpg', miniatura = '$base-m.jpg';
    await File(p.join(pasta, arquivo)).writeAsBytes(r.foto, flush: true);
    await File(p.join(pasta, miniatura)).writeAsBytes(r.miniatura, flush: true);
    return (arquivo: arquivo, miniatura: miniatura);
  }

  Future<void> excluir(Iterable<String> nomes) async {
    for (final nome in nomes) {
      final f = arquivo(nome);
      if (f != null && await f.exists()) await f.delete();
    }
  }
}

/// Mesmo processamento da galeria, com as larguras do cadastro de membros.
/// Roda em isolate: tem que ficar fora da classe para capturar corretamente.
({Uint8List foto, Uint8List miniatura, int largura, int altura}) processarFotoMembro(Uint8List bytes) {
  final r = processarFoto(bytes,
      larguraMaxima: FotosMembros.larguraMaxima, larguraMiniatura: FotosMembros.larguraMiniatura);
  return (foto: r.foto, miniatura: r.miniatura, largura: r.largura, altura: r.altura);
}
