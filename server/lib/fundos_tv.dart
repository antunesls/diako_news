import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'cartazes.dart';
import 'galeria.dart';

/// Imagens de fundo das TVs (mural de informações e boas-vindas), em data/fundos-tv/.
/// Qual imagem cada TV usa fica nas configurações (muralFundoImagem, boasVindasFundoImagem).
class FundosTv {
  FundosTv(String pastaDados) : pasta = p.join(pastaDados, 'fundos-tv');

  final String pasta;

  /// Telas que aceitam fundo: o nome na URL (?tela=) e o prefixo das chaves nas configurações.
  static const telas = {'mural': 'mural', 'boas-vindas': 'boasVindas'};

  /// Nomes gerados pelo servidor: "<tela>-<hex>.jpg". O nome muda a cada envio (cache longo).
  static bool nomeValido(String nome) => RegExp(r'^(mural|boas-vindas)-[0-9a-f]{20}\.jpg$').hasMatch(nome);

  File? arquivo(String nome) => nomeValido(nome) ? File(p.join(pasta, nome)) : null;

  bool existe(String nome) => arquivo(nome)?.existsSync() ?? false;

  /// Reduz para 1920 px, tira o EXIF e grava. Lança [FormatException] com a mensagem para o usuário.
  Future<String> salvar(String tela, Uint8List bytes) async {
    if (!telas.containsKey(tela)) throw const FormatException('TV desconhecida.');
    if (bytes.isEmpty) throw const FormatException('Arquivo vazio.');
    if (bytes.length > Galeria.tamanhoMaximo) throw const FormatException('Imagem maior que 15 MB.');
    if (Cartazes.tipoImagem(bytes) == null) throw const FormatException('Envie uma imagem JPG ou PNG.');
    final r = await Isolate.run(() => processarFoto(bytes));
    await Directory(pasta).create(recursive: true);
    final rng = Random.secure();
    final nome = '$tela-${List.generate(10, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}.jpg';
    await File(p.join(pasta, nome)).writeAsBytes(r.foto, flush: true);
    return nome;
  }

  Future<void> excluir(String nome) async {
    final f = arquivo(nome);
    if (f != null && await f.exists()) await f.delete();
  }
}
