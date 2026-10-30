import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pointycastle/export.dart';

/// Cópia do backup que vai para o PC da igreja: só sai do servidor cifrada (ChaCha20-Poly1305), com a
/// chave derivada da senha do backup (PBKDF2-HMAC-SHA256). Quem pegar o arquivo, a pasta ou a
/// chave do agente não consegue ler; para restaurar, a senha é digitada no /admin.
///
/// Formato: "DIAKOBK1" + iterações (4 bytes) + sal (16) + nonce (12) + dados cifrados + tag (16).
/// O cabeçalho entra como dado autenticado: alterar qualquer byte faz a abertura falhar.
const extensaoCifrado = '.cifrado';
const _magico = 'DIAKOBK1';
const _tamCabecalho = 8 + 4 + 16 + 12;
const iteracoesPbkdf2 = 600000;
const _iteracoesMaximas = 5000000;
const senhaBackupMinima = 12;

final _rng = Random.secure();
Uint8List _aleatorios(int n) => Uint8List.fromList([for (var i = 0; i < n; i++) _rng.nextInt(256)]);

Uint8List derivarChaveBackup(String senha, Uint8List sal, int iteracoes) {
  final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(Pbkdf2Parameters(sal, iteracoes, 32));
  return kdf.process(Uint8List.fromList(utf8.encode(senha)));
}

/// ChaCha20-Poly1305 (RFC 8439). Ao abrir, a tag errada lança erro. Usa processBytes/doFinal:
/// o atalho process() da pointycastle 4.0.0 devolve zeros e não confere a tag.
Uint8List chacha20Poly1305(bool cifrar, Uint8List chave, Uint8List nonce, Uint8List aad, Uint8List dados) {
  final c = ChaCha20Poly1305(ChaCha7539Engine(), Poly1305())
    ..init(cifrar, AEADParameters(KeyParameter(chave), 128, nonce, aad));
  final saida = Uint8List(c.getOutputSize(dados.length));
  var n = c.processBytes(dados, 0, dados.length, saida, 0);
  n += c.doFinal(saida, n);
  return n == saida.length ? saida : saida.sublist(0, n);
}

/// O arquivo começa com o cabeçalho de um backup cifrado.
bool pareceBackupCifrado(List<int> bytes) =>
    bytes.length >= _magico.length && ascii.decode(bytes.sublist(0, _magico.length), allowInvalid: true) == _magico;

Uint8List cifrarBackup(Uint8List dados, {required Uint8List chave, required Uint8List sal, required int iteracoes}) {
  final cabecalho = BytesBuilder()
    ..add(ascii.encode(_magico))
    ..add((ByteData(4)..setUint32(0, iteracoes)).buffer.asUint8List())
    ..add(sal)
    ..add(_aleatorios(12));
  final cab = cabecalho.toBytes();
  return (BytesBuilder(copy: false)
        ..add(cab)
        ..add(chacha20Poly1305(true, chave, cab.sublist(28), cab, dados)))
      .toBytes();
}

/// Abre um backup cifrado com a [senha]. Senha errada ou arquivo alterado: [FormatException].
Uint8List decifrarBackup(Uint8List arquivo, String senha) {
  if (!pareceBackupCifrado(arquivo) || arquivo.length < _tamCabecalho + 16) {
    throw const FormatException('Este arquivo não é um backup cifrado do DiakoHub.');
  }
  final cab = arquivo.sublist(0, _tamCabecalho);
  final iteracoes = ByteData.sublistView(cab, 8, 12).getUint32(0);
  if (iteracoes < 1 || iteracoes > _iteracoesMaximas) throw const FormatException('Backup cifrado inválido.');
  final chave = derivarChaveBackup(senha, cab.sublist(12, 28), iteracoes);
  try {
    return chacha20Poly1305(false, chave, cab.sublist(28), cab, arquivo.sublist(_tamCabecalho));
  } catch (_) {
    // A tag não confere: senha errada ou algum byte alterado.
    throw const FormatException('Senha do backup errada ou arquivo corrompido.');
  }
}

/// [decifrarBackup] em outro isolate (a derivação da chave leva cerca de um segundo).
Future<Uint8List> decifrarBackupEmSegundoPlano(Uint8List arquivo, String senha) =>
    Isolate.run(() => decifrarBackup(arquivo, senha));

// Funções de nível superior: um closure criado dentro de um método levaria o objeto junto
// para o outro isolate (e a fila de SenhaBackup não pode ser enviada).
Future<Uint8List> _derivarEmSegundoPlano(String senha, Uint8List sal, int iteracoes) =>
    Isolate.run(() => derivarChaveBackup(senha, sal, iteracoes));

Future<Uint8List> _cifrarEmSegundoPlano(Uint8List zip, Uint8List chave, Uint8List sal, int iteracoes) =>
    Isolate.run(() => cifrarBackup(zip, chave: chave, sal: sal, iteracoes: iteracoes));

/// Senha do backup (data/backup-senha.json). Guarda só o sal e a chave derivada, nunca a senha;
/// o arquivo não entra nos backups. Sem senha definida, a cópia no PC da igreja fica desligada.
class SenhaBackup {
  SenhaBackup(this.pastaDados, {DateTime Function()? relogio, this.iteracoes = iteracoesPbkdf2})
      : _agora = relogio ?? DateTime.now;

  final String pastaDados;
  final int iteracoes;
  final DateTime Function() _agora;
  Uint8List? _chave;
  Uint8List? _sal;
  int _iteracoesChave = iteracoesPbkdf2;
  DateTime? definidaEm;

  File get _arquivo => File(p.join(pastaDados, 'backup-senha.json'));
  bool get definida => _chave != null;

  Future<void> carregar() async {
    try {
      if (!await _arquivo.exists()) return;
      final j = jsonDecode(await _arquivo.readAsString()) as Map<String, dynamic>;
      _sal = base64Decode(j['sal'] as String);
      _chave = base64Decode(j['chave'] as String);
      _iteracoesChave = (j['iteracoes'] as num).toInt();
      definidaEm = DateTime.tryParse(j['definidaEm'] as String? ?? '');
    } catch (_) {
      _chave = _sal = null;
    }
  }

  /// Uma operação por vez (dois cliques em "Definir senha" não gravam o mesmo arquivo temporário),
  /// na ordem pedida: no fim, memória e arquivo têm a mesma senha.
  Future<void> _fila = Future.value();

  Future<void> _naVez(Future<void> Function() acao) {
    final r = _fila.then((_) => acao());
    _fila = r.then((_) {}, onError: (_) {});
    return r;
  }

  Future<void> definir(String senha) {
    if (senha.length < senhaBackupMinima) {
      return Future.error(FormatException('A senha do backup precisa ter pelo menos $senhaBackupMinima caracteres.'));
    }
    return _naVez(() async {
      final sal = _aleatorios(16);
      final n = iteracoes;
      // A derivação leva alguns segundos: em outro isolate, para não travar as outras requisições.
      final chave = await _derivarEmSegundoPlano(senha, sal, n);
      final quando = _agora();
      await _arquivo.parent.create(recursive: true);
      final tmp = File('${_arquivo.path}.tmp');
      await tmp.writeAsString(jsonEncode({
        'sal': base64Encode(sal),
        'chave': base64Encode(chave),
        'iteracoes': n,
        'definidaEm': quando.toIso8601String(),
      }), flush: true);
      await tmp.rename(_arquivo.path);
      _sal = sal;
      _chave = chave;
      _iteracoesChave = n;
      definidaEm = quando;
    });
  }

  Future<void> remover() => _naVez(() async {
        if (await _arquivo.exists()) await _arquivo.delete();
        _chave = _sal = null;
        definidaEm = null;
      });

  Uint8List cifrar(Uint8List zip) {
    final chave = _chave;
    if (chave == null) throw StateError('Senha do backup não definida.');
    return cifrarBackup(zip, chave: chave, sal: _sal!, iteracoes: _iteracoesChave);
  }

  /// [cifrar] em outro isolate: um backup grande não trava as outras requisições.
  Future<Uint8List> cifrarEmSegundoPlano(Uint8List zip) {
    final chave = _chave;
    if (chave == null) throw StateError('Senha do backup não definida.');
    return _cifrarEmSegundoPlano(zip, chave, _sal!, _iteracoesChave);
  }
}
