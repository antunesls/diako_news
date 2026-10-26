import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'cartazes.dart';
import 'galeria.dart' show processarFoto;

/// Termo de autorização usado enquanto a igreja não escreve o seu no /admin.
/// É um modelo para revisar (de preferência com alguém da área jurídica).
String termoLgpdPadrao(String igreja) => '''
Autorizo a $igreja a guardar e usar os meus dados pessoais informados no cadastro de membros: nome, data de nascimento, sexo, estado civil, foto, telefone, WhatsApp, e-mail, endereço, CPF, RG, contato de emergência, vínculos de família e informações da minha vida na igreja (como data de chegada, batismo, membresia, ministérios e função).

Sei que estas informações revelam a minha participação na igreja e, por isso, são dados sensíveis pela Lei Geral de Proteção de Dados (Lei 13.709/2018).

Os dados serão usados apenas para: manter o cadastro de membros e visitantes; entrar em contato comigo sobre a vida da igreja (avisos, visitas e cuidado pastoral); organizar ministérios e escalas; e lembrar o meu aniversário. O meu nome e o dia do aniversário podem aparecer no telão e no mural de avisos da igreja.

Os dados ficam no sistema da igreja, com acesso restrito à secretaria e à liderança pastoral, e não serão vendidos nem repassados a terceiros, a não ser por obrigação legal.

Posso, a qualquer momento e sem custo, pedir para ver, corrigir ou apagar os meus dados, e revogar esta autorização falando com a secretaria da igreja. A revogação não afeta o que foi feito antes dela.

Quando a pessoa cadastrada tem menos de 18 anos, quem autoriza é o pai, a mãe ou o responsável legal.''';

/// Termos assinados (foto ou PDF) gravados em data/termos-lgpd/. Como as fotos do
/// cadastro, nunca são públicos: o servidor só entrega atrás de login (Permissao.membros).
class TermosAssinados {
  TermosAssinados(String pastaDados) : pasta = p.join(pastaDados, 'termos-lgpd');

  final String pasta;

  static const tamanhoMaximo = 15 * 1024 * 1024;

  /// Foto do papel assinado: larga o bastante para ler as letras miúdas.
  static const larguraMaxima = 2000;

  /// Nomes gerados pelo servidor: "<hex>.jpg" ou "<hex>.pdf".
  static bool nomeValido(String nome) => RegExp(r'^[0-9a-f]{20}\.(jpg|pdf)$').hasMatch(nome);

  File? arquivo(String nome) => nomeValido(nome) ? File(p.join(pasta, nome)) : null;

  static String tipo(String nome) => nome.endsWith('.pdf') ? 'application/pdf' : 'image/jpeg';

  static bool ehPdf(Uint8List bytes) =>
      bytes.length > 5 && utf8.decode(bytes.sublist(0, 5), allowMalformed: true) == '%PDF-';

  /// Grava o termo. Foto: em pé e sem EXIF (o celular grava a localização). PDF: como veio.
  /// Lança [FormatException] com a mensagem para o usuário.
  Future<String> salvar(Uint8List bytes) async {
    if (bytes.isEmpty) throw const FormatException('Arquivo vazio.');
    if (bytes.length > tamanhoMaximo) throw const FormatException('Arquivo maior que 15 MB.');
    final Uint8List conteudo;
    final String extensao;
    if (ehPdf(bytes)) {
      conteudo = bytes;
      extensao = 'pdf';
    } else if (Cartazes.tipoImagem(bytes) != null) {
      conteudo = await Isolate.run(() => processarTermo(bytes));
      extensao = 'jpg';
    } else {
      throw const FormatException('Envie a foto (JPG ou PNG) ou o PDF do termo assinado.');
    }
    await Directory(pasta).create(recursive: true);
    final rng = Random.secure();
    final nome = '${List.generate(10, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}.$extensao';
    await File(p.join(pasta, nome)).writeAsBytes(conteudo, flush: true);
    return nome;
  }

  Future<void> excluir(String? nome) async {
    if (nome == null) return;
    final f = arquivo(nome);
    if (f != null && await f.exists()) await f.delete();
  }
}

/// Roda em isolate: fora da classe para capturar corretamente.
Uint8List processarTermo(Uint8List bytes) =>
    processarFoto(bytes, larguraMaxima: TermosAssinados.larguraMaxima, larguraMiniatura: 320).foto;

/// Token do link de autorização: 32 bytes aleatórios (vai só na URL; guardamos o hash).
String novoTokenLgpd() {
  final rng = Random.secure();
  return base64Url.encode(List.generate(32, (_) => rng.nextInt(256))).replaceAll('=', '');
}

String hashTokenLgpd(String token) => sha256.convert(utf8.encode(token)).toString();
