import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'qr_oracao.dart';

/// Imagens enviadas pelo site ou pelo tablet, gravadas na pasta de imagens do Holyrics.
class Cartazes {
  Cartazes(this.pasta);

  final String pasta;

  static const tamanhoMaximo = 10 * 1024 * 1024;
  static const extensoes = {'.jpg', '.jpeg', '.png'};

  /// Nome simples de imagem, sem pastas nem caminhos (seguro para gravar na pasta de cartazes).
  static bool nomeValido(String nome) =>
      nome.isNotEmpty &&
      nome == p.basename(nome) &&
      !nome.startsWith('.') &&
      !nome.contains('\\') &&
      !nome.contains('/') &&
      extensoes.contains(p.extension(nome).toLowerCase());

  Future<List<({String nome, int tamanho, DateTime modificado})>> listar() async {
    final dir = Directory(pasta);
    if (!await dir.exists()) return [];
    final lista = <({String nome, int tamanho, DateTime modificado})>[];
    await for (final e in dir.list()) {
      if (e is! File) continue;
      final nome = p.basename(e.path);
      if (nome == arquivoQr || nome == arquivoQrMensagens || !extensoes.contains(p.extension(nome).toLowerCase())) continue;
      final s = await e.stat();
      lista.add((nome: nome, tamanho: s.size, modificado: s.modified));
    }
    lista.sort((a, b) => b.modificado.compareTo(a.modificado));
    return lista;
  }

  /// Grava a imagem e retorna o nome final (único). Lança [FormatException] se inválida.
  Future<String> salvar(String nomeOriginal, Uint8List bytes) async {
    if (bytes.isEmpty) throw const FormatException('Arquivo vazio.');
    if (bytes.length > tamanhoMaximo) throw const FormatException('Imagem maior que 10 MB.');
    final tipo = tipoImagem(bytes);
    if (tipo == null) throw const FormatException('Envie uma imagem JPG ou PNG.');

    var base = nomeSeguro(p.basenameWithoutExtension(nomeOriginal));
    if (base.isEmpty) base = 'cartaz';
    await Directory(pasta).create(recursive: true);
    var nome = '$base.$tipo';
    for (var i = 2; await File(p.join(pasta, nome)).exists(); i++) {
      nome = '$base-$i.$tipo';
    }
    await File(p.join(pasta, nome)).writeAsBytes(bytes, flush: true);
    return nome;
  }

  Future<bool> excluir(String nome) async {
    final f = arquivo(nome);
    if (f == null || !await f.exists()) return false;
    await f.delete();
    return true;
  }

  /// Arquivo pelo nome, recusando caminhos fora da pasta.
  File? arquivo(String nome) {
    if (nome != p.basename(nome) || nome.startsWith('.') || nome == arquivoQr || nome == arquivoQrMensagens) return null;
    if (!extensoes.contains(p.extension(nome).toLowerCase())) return null;
    return File(p.join(pasta, nome));
  }

  /// Confere a assinatura do arquivo, sem confiar na extensão enviada ('jpg', 'png' ou null).
  static String? tipoImagem(Uint8List b) {
    if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'jpg';
    if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'png';
    return null;
  }
}

/// "Retiro de Casais 2026!" -> "retiro-de-casais-2026"
String nomeSeguro(String nome) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const para = 'aaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final c in nome.toLowerCase().split('')) {
    final i = de.indexOf(c);
    b.write(i >= 0 ? para[i] : c);
  }
  final limpo = b.toString().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return limpo.length > 60 ? limpo.substring(0, 60) : limpo;
}
