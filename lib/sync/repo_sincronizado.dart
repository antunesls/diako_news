import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'server_api.dart';

/// Lista que vem do servidor, com uma cópia local para continuar mostrando
/// os dados quando o servidor estiver fora do ar. Alterações só com conexão.
abstract class RepoSincronizado<T> extends ChangeNotifier {
  RepoSincronizado({required this.colecao, required this.api, required Future<File> Function() cache}) : _cache = cache;

  final String colecao;
  final ServerApi api;
  final Future<File> Function() _cache;

  List<T> _itens = [];
  bool _online = false;
  String? _erro;

  T fromJson(Map<String, dynamic> j);
  Map<String, dynamic> toJson(T item);
  String idDe(T item);

  List<T> get todos => List.unmodifiable(_itens);

  /// true quando a última sincronização com o servidor funcionou.
  bool get online => _online;
  String? get erro => _erro;

  Future<void> carregar() async {
    try {
      final f = await _cache();
      if (await f.exists()) {
        final lista = jsonDecode(await f.readAsString()) as List;
        _itens = [for (final e in lista) fromJson(Map<String, dynamic>.from(e as Map))];
        notifyListeners();
      }
    } catch (_) {
      // Cache corrompido: ignora e espera o servidor.
    }
    await sincronizar();
  }

  /// Busca a lista do servidor. Sem conexão, mantém a cópia local.
  Future<void> sincronizar() async {
    try {
      final lista = await api.listar(colecao);
      _itens = lista.map(fromJson).toList();
      _online = true;
      _erro = null;
      await _gravarCache();
    } on ErroAmigavel catch (e) {
      _online = false;
      _erro = e.message;
    }
    notifyListeners();
  }

  Future<T> criar(T item) async {
    final salvo = fromJson(await api.criar(colecao, toJson(item)));
    _itens = [..._itens, salvo];
    await _aplicado();
    return salvo;
  }

  Future<T> atualizar(T item) async {
    final salvo = fromJson(await api.atualizar(colecao, idDe(item), toJson(item)));
    substituir(salvo);
    await _aplicado();
    return salvo;
  }

  Future<void> excluir(String id) async {
    await api.excluir(colecao, id);
    _itens = _itens.where((x) => idDe(x) != id).toList();
    await _aplicado();
  }

  @protected
  void substituir(T salvo) {
    _itens = [for (final x in _itens) idDe(x) == idDe(salvo) ? salvo : x];
  }

  @protected
  Future<void> aplicado() => _aplicado();

  Future<void> _aplicado() async {
    _online = true;
    _erro = null;
    await _gravarCache();
    notifyListeners();
  }

  Future<void> _gravarCache() async {
    try {
      final f = await _cache();
      await f.writeAsString(jsonEncode(_itens.map(toJson).toList()));
    } catch (_) {
      // Sem cache local não é grave: o servidor continua sendo a fonte.
    }
  }
}
