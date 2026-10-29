import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'auth.dart';
import 'permissoes.dart';
import 'store.dart';

/// Pessoa com acesso ao painel/app (a conta principal "admin" não fica aqui: é a senha do /admin).
class Usuario {
  Usuario({
    required this.id,
    required this.nome,
    required this.login,
    required this.perfil,
    this.senhaHash = '',
    this.senhaSal = '',
    this.ativo = true,
    required this.criadoEm,
    this.ultimoAcesso,
    this.membroId,
  });

  final String id;
  String nome;
  final String login;
  Perfil perfil;
  String senhaHash;
  String senhaSal;
  bool ativo;
  final DateTime criadoEm;
  DateTime? ultimoAcesso;
  String? membroId;

  factory Usuario.fromJson(Map<String, dynamic> j) => Usuario(
        id: j['id'] as String,
        nome: j['nome'] as String? ?? '',
        login: j['login'] as String,
        perfil: Perfil.porNome(j['perfil'] as String? ?? '') ?? Perfil.telao,
        senhaHash: j['senhaHash'] as String? ?? '',
        senhaSal: j['senhaSal'] as String? ?? '',
        ativo: j['ativo'] as bool? ?? true,
        criadoEm: DateTime.tryParse(j['criadoEm'] as String? ?? '') ?? DateTime.now(),
        ultimoAcesso: DateTime.tryParse(j['ultimoAcesso'] as String? ?? ''),
        membroId: j['membroId'] as String?,
      );

  /// [comSenha] só para gravar no disco; o painel nunca recebe o hash.
  Map<String, dynamic> toJson({bool comSenha = false}) => {
        'id': id,
        'nome': nome,
        'login': login,
        'perfil': perfil.id,
        'perfilNome': perfil.nome,
        'ativo': ativo,
        'criadoEm': criadoEm.toIso8601String(),
        'ultimoAcesso': ultimoAcesso?.toIso8601String(),
        'membroId': membroId,
        if (comSenha) ...{'senhaHash': senhaHash, 'senhaSal': senhaSal},
      };
}

/// Usuários em data/usuarios.json. Fica fora do backup (guarda os hashes das senhas).
class Usuarios {
  Usuarios(String pastaDados) : _arquivo = File(p.join(pastaDados, 'usuarios.json'));

  final File _arquivo;
  final List<Usuario> _lista = [];
  Future<void> _fila = Future.value();

  static const maximo = 100;
  static final _formatoLogin = RegExp(r'^[a-z0-9][a-z0-9._-]{2,29}$');

  List<Usuario> get lista => List.unmodifiable(_lista);

  Future<void> carregar() async {
    if (!await _arquivo.exists()) return;
    final j = jsonDecode(await _arquivo.readAsString()) as List;
    _lista
      ..clear()
      ..addAll([for (final u in j) Usuario.fromJson(Map<String, dynamic>.from(u as Map))]);
  }

  Usuario? buscar(String id) => _lista.where((u) => u.id == id).firstOrNull;
  Usuario? porLogin(String login) => _lista.where((u) => u.login == login.trim().toLowerCase()).firstOrNull;
  Usuario? porMembro(String id) => _lista.where((u) => u.membroId == id).firstOrNull;

  Future<Usuario> vincular(String usuarioId, String membroId) async {
    final u = buscar(usuarioId);
    if (u == null) throw const FormatException('Usuário não encontrado.');
    final outro = porMembro(membroId);
    if (outro != null && outro.id != usuarioId) {
      throw const FormatException('Este membro já tem uma conta vinculada.');
    }
    u.membroId = membroId;
    await _salvar();
    return u;
  }

  /// Usuário ativo com esta senha, ou null. Registra o último acesso.
  Future<Usuario?> autenticar(String login, String senha) async {
    final u = porLogin(login);
    if (u == null || !u.ativo || !conferirHashSenha(senha, hash: u.senhaHash, sal: u.senhaSal)) return null;
    u.ultimoAcesso = DateTime.now();
    await _salvar();
    return u;
  }

  /// Cria o usuário com a senha dada. Lança [FormatException] com a mensagem para o painel.
  Future<Usuario> criar({required String nome, required String login, required Perfil perfil, required String senha, String? membroId}) async {
    final l = login.trim().toLowerCase();
    if (_lista.length >= maximo) throw const FormatException('Limite de $maximo usuários atingido.');
    _validarNome(nome);
    if (!_formatoLogin.hasMatch(l)) {
      throw const FormatException('Usuário inválido: use de 3 a 30 letras minúsculas, números, ponto, hífen ou _ (ex.: maria.silva).');
    }
    if (l == Auth.idPrincipal) throw const FormatException('"admin" é reservado para a conta principal.');
    if (porLogin(l) != null) throw const FormatException('Já existe um usuário com esse nome de acesso.');
    if (membroId != null && porMembro(membroId) != null) throw const FormatException('Este membro já tem uma conta vinculada.');
    final h = gerarHashSenha(senha);
    final u = Usuario(
        id: novoId(), nome: nome.trim(), login: l, perfil: perfil, senhaHash: h.hash, senhaSal: h.sal,
        membroId: membroId, criadoEm: DateTime.now());
    _lista.add(u);
    await _salvar();
    return u;
  }

  Future<Usuario> atualizar(String id, {String? nome, Perfil? perfil, bool? ativo}) async {
    final u = buscar(id);
    if (u == null) throw const FormatException('Usuário não encontrado.');
    if (nome != null) {
      _validarNome(nome);
      u.nome = nome.trim();
    }
    if (perfil != null) u.perfil = perfil;
    if (ativo != null) u.ativo = ativo;
    await _salvar();
    return u;
  }

  Future<void> definirSenha(String id, String senha) async {
    final u = buscar(id);
    if (u == null) throw const FormatException('Usuário não encontrado.');
    final h = gerarHashSenha(senha);
    u
      ..senhaHash = h.hash
      ..senhaSal = h.sal;
    await _salvar();
  }

  bool conferirSenha(String id, String senha) {
    final u = buscar(id);
    return u != null && conferirHashSenha(senha, hash: u.senhaHash, sal: u.senhaSal);
  }

  Future<bool> excluir(String id) async {
    final antes = _lista.length;
    _lista.removeWhere((u) => u.id == id);
    if (_lista.length == antes) return false;
    await _salvar();
    return true;
  }

  static void _validarNome(String nome) {
    if (nome.trim().isEmpty) throw const FormatException('Informe o nome da pessoa.');
    if (nome.trim().length > 60) throw const FormatException('Nome muito longo.');
  }

  Future<void> _salvar() {
    final conteudo = const JsonEncoder.withIndent('  ').convert([for (final u in _lista) u.toJson(comSenha: true)]);
    return _fila = _fila.then((_) async {
      await _arquivo.parent.create(recursive: true);
      final tmp = File('${_arquivo.path}.tmp');
      await tmp.writeAsString(conteudo, flush: true);
      if (!Platform.isWindows) await Process.run('chmod', ['600', tmp.path]);
      await tmp.rename(_arquivo.path);
    });
  }
}
