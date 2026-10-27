import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'auth.dart';
import 'store.dart';

/// Tablet pareado para falar direto com o agente na rede da igreja (sem passar pela internet).
class TabletLocal {
  TabletLocal({required this.id, required this.hash, required this.usuario, required this.aparelho, required this.criadoEm});

  final String id;

  /// SHA-256 do token (o token em si só o tablet guarda).
  final String hash;

  /// Id da conta que pareou ([Auth.idPrincipal] para a conta principal).
  final String usuario;
  final String aparelho;
  final DateTime criadoEm;

  factory TabletLocal.fromJson(Map<String, dynamic> j) => TabletLocal(
        id: j['id'] as String,
        hash: j['hash'] as String,
        usuario: j['usuario'] as String? ?? Auth.idPrincipal,
        aparelho: j['aparelho'] as String? ?? '',
        criadoEm: DateTime.tryParse(j['criadoEm'] as String? ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'hash': hash, 'usuario': usuario, 'aparelho': aparelho, 'criadoEm': criadoEm.toIso8601String()};
}

/// Hash guardado no servidor e no agente para conferir o token do tablet.
String hashTokenLocal(String token) => sha256.convert(utf8.encode(token)).toString();

/// Tablets pareados em data/tablets-locais.json. Fica fora do backup, como as sessões.
class TabletsLocais {
  TabletsLocais(String pastaDados) : _arquivo = File(p.join(pastaDados, 'tablets-locais.json'));

  final File _arquivo;
  final List<TabletLocal> _lista = [];
  Future<void> _fila = Future.value();

  static const maximo = 30;

  List<TabletLocal> get lista => List.unmodifiable(_lista);

  Future<void> carregar() async {
    if (!await _arquivo.exists()) return;
    final j = jsonDecode(await _arquivo.readAsString()) as List;
    _lista
      ..clear()
      ..addAll([for (final t in j) TabletLocal.fromJson(Map<String, dynamic>.from(t as Map))]);
  }

  TabletLocal? buscar(String id) => _lista.where((t) => t.id == id).firstOrNull;

  /// Cria o pareamento e retorna o token (mostrado uma única vez, ao tablet).
  Future<({TabletLocal tablet, String token})> parear({required String usuario, required String aparelho}) async {
    final nome = aparelho.trim().replaceAll(RegExp(r'[\r\n\t]'), ' ');
    if (nome.length > 60) throw const FormatException('Nome do aparelho muito longo.');
    if (_lista.length >= maximo) throw const FormatException('Limite de $maximo tablets pareados. Remova algum em Administração.');
    final token = gerarSegredo(32);
    final t = TabletLocal(
        id: novoId(), hash: hashTokenLocal(token), usuario: usuario, aparelho: nome.isEmpty ? 'Tablet' : nome, criadoEm: DateTime.now());
    _lista.add(t);
    await _salvar();
    return (tablet: t, token: token);
  }

  Future<bool> remover(String id) async {
    final antes = _lista.length;
    _lista.removeWhere((t) => t.id == id);
    if (_lista.length == antes) return false;
    await _salvar();
    return true;
  }

  Future<void> removerDoUsuario(String usuario) async {
    final antes = _lista.length;
    _lista.removeWhere((t) => t.usuario == usuario);
    if (_lista.length != antes) await _salvar();
  }

  Future<void> _salvar() {
    final conteudo = const JsonEncoder.withIndent('  ').convert([for (final t in _lista) t.toJson()]);
    return _fila = _fila.then((_) async {
      await _arquivo.parent.create(recursive: true);
      final tmp = File('${_arquivo.path}.tmp');
      await tmp.writeAsString(conteudo, flush: true);
      if (!Platform.isWindows) await Process.run('chmod', ['600', tmp.path]);
      await tmp.rename(_arquivo.path);
    });
  }
}
