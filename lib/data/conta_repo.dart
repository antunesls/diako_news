import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../sync/server_api.dart';

/// Quem está logado no tablet e o que o perfil permite (vem de GET /api/eu).
/// Os nomes das permissões são os do servidor (server/lib/permissoes.dart), ex.: "projetar".
class ContaRepo extends ChangeNotifier {
  ContaRepo({required this.api, required Future<File> Function() cache}) : _cache = cache;

  final ServerApi api;
  final Future<File> Function() _cache;

  Set<String> _permissoes = {};
  String _nome = '';
  String _perfil = '';
  bool _conhecida = false;

  String get nome => _nome;
  String get perfil => _perfil;

  /// Enquanto não sabe o perfil (sem cache e sem servidor, ou servidor antigo), libera tudo:
  /// o servidor recusa o que não for permitido.
  bool pode(String permissao) => !_conhecida || _permissoes.contains(permissao);

  Future<void> carregar() async {
    try {
      final f = await _cache();
      if (await f.exists()) _aplicar(Map<String, dynamic>.from(jsonDecode(await f.readAsString()) as Map));
    } catch (_) {
      // Cache corrompido: espera o servidor.
    }
  }

  Future<void> sincronizar() async {
    try {
      final j = await api.eu();
      _aplicar(j);
      try {
        await (await _cache()).writeAsString(jsonEncode(j));
      } catch (_) {}
    } on ServidorException catch (e) {
      // Servidor de antes dos perfis (sem /api/eu): tudo liberado, como era.
      if (e.status == 404) {
        _conhecida = false;
        notifyListeners();
      }
    } on ErroAmigavel {
      // Sem conexão ou sem login: mantém o que já sabia.
    }
  }

  /// Ao sair: esquece o perfil anterior.
  Future<void> limpar() async {
    _permissoes = {};
    _nome = '';
    _perfil = '';
    _conhecida = false;
    try {
      final f = await _cache();
      if (await f.exists()) await f.delete();
    } catch (_) {}
    notifyListeners();
  }

  void _aplicar(Map<String, dynamic> j) {
    _permissoes = {for (final p in (j['permissoes'] as List? ?? const [])) p as String};
    _nome = j['nome'] as String? ?? '';
    _perfil = j['perfilNome'] as String? ?? '';
    _conhecida = true;
    notifyListeners();
  }
}
