import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:diako_server/backup_cifrado.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final zip = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, ...utf8.encode('dados da igreja: CPF 111.444.777-35')]);
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('diako_cifrado'));
  tearDown(() => tmp.delete(recursive: true));

  test('ChaCha20-Poly1305 confere com o vetor de teste da RFC 8439 (2.8.2)', () {
    Uint8List hex(String s) => Uint8List.fromList(
        [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);
    final chave = Uint8List.fromList([for (var i = 0x80; i <= 0x9f; i++) i]);
    final nonce = hex('070000004041424344454647');
    final aad = hex('50515253c0c1c2c3c4c5c6c7');
    final texto = Uint8List.fromList(utf8.encode("Ladies and Gentlemen of the class of '99: If I could offer you only one "
        'tip for the future, sunscreen would be it.'));
    final cifrado = chacha20Poly1305(true, chave, nonce, aad, texto);
    expect(cifrado.sublist(0, 16), hex('d31a8d34648e60db7b86afbc53ef7ec2'));
    expect(cifrado.sublist(cifrado.length - 16), hex('1ae10b594f09e26a7e902ecbd0600691'));
    expect(chacha20Poly1305(false, chave, nonce, aad, cifrado), texto);
    // PBKDF2-HMAC-SHA256("password", "salt", 1 iteração, 32 bytes): vetor conhecido.
    expect(derivarChaveBackup('password', Uint8List.fromList(utf8.encode('salt')), 1),
        hex('120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b'));
  });

  test('cifra e abre com a senha; o conteúdo não aparece no arquivo', () async {
    final senha = SenhaBackup(tmp.path, iteracoes: 1000);
    await senha.definir('uma senha bem longa');
    final cifrado = senha.cifrar(zip);
    expect(pareceBackupCifrado(cifrado), isTrue);
    expect(latin1.decode(cifrado), isNot(contains('111.444')));
    expect(decifrarBackup(cifrado, 'uma senha bem longa'), zip);
    // Cada cópia tem um nonce novo.
    expect(senha.cifrar(zip), isNot(cifrado));
    // Em outro isolate, com o mesmo resultado e o mesmo erro.
    final emSegundoPlano = await senha.cifrarEmSegundoPlano(zip);
    expect(await decifrarBackupEmSegundoPlano(emSegundoPlano, 'uma senha bem longa'), zip);
    await expectLater(decifrarBackupEmSegundoPlano(emSegundoPlano, 'senha errada aqui'), throwsFormatException);
  });

  test('senha errada ou arquivo alterado não abrem', () async {
    final senha = SenhaBackup(tmp.path, iteracoes: 1000);
    await senha.definir('uma senha bem longa');
    final cifrado = senha.cifrar(zip);
    expect(() => decifrarBackup(cifrado, 'outra senha qualquer'), throwsFormatException);
    final alterado = Uint8List.fromList(cifrado)..[cifrado.length - 1] ^= 1;
    expect(() => decifrarBackup(alterado, 'uma senha bem longa'), throwsFormatException);
    final cabecalhoAlterado = Uint8List.fromList(cifrado)..[20] ^= 1; // sal
    expect(() => decifrarBackup(cabecalhoAlterado, 'uma senha bem longa'), throwsFormatException);
    expect(() => decifrarBackup(zip, 'uma senha bem longa'), throwsFormatException);
  });

  test('definir várias vezes ao mesmo tempo (clique repetido): todas terminam e a última vale', () async {
    final senha = SenhaBackup(tmp.path, iteracoes: 1000);
    await Future.wait([
      senha.definir('primeira senha longa'),
      senha.definir('segunda senha longa'),
      senha.definir('terceira senha longa'),
      senha.remover(),
      senha.definir('quarta senha bem longa'),
    ]);
    final recarregada = SenhaBackup(tmp.path);
    await recarregada.carregar();
    // O que está em memória é o mesmo que está gravado.
    expect(decifrarBackup(recarregada.cifrar(zip), 'quarta senha bem longa'), zip);
    expect(decifrarBackup(senha.cifrar(zip), 'quarta senha bem longa'), zip);
    expect(Directory(tmp.path).listSync().map((e) => p.basename(e.path)), ['backup-senha.json']);
  });

  test('guarda só sal e chave derivada; recarrega; remover desliga', () async {
    final senha = SenhaBackup(tmp.path, iteracoes: 1000);
    expect(senha.definida, isFalse);
    expect(() => senha.cifrar(zip), throwsStateError);
    await expectLater(senha.definir('curta'), throwsFormatException);
    await senha.definir('uma senha bem longa');
    final gravado = File(p.join(tmp.path, 'backup-senha.json')).readAsStringSync();
    expect(gravado, isNot(contains('uma senha')));

    final outra = SenhaBackup(tmp.path);
    await outra.carregar();
    expect(outra.definida, isTrue);
    expect(outra.definidaEm, isNotNull);
    expect(decifrarBackup(outra.cifrar(zip), 'uma senha bem longa'), zip);

    await outra.remover();
    expect(outra.definida, isFalse);
    expect(File(p.join(tmp.path, 'backup-senha.json')).existsSync(), isFalse);
  });
}
