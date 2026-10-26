import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// Coleções de documentos JSON gravadas em data/<nome>.json.
/// Cada gravação é atômica (arquivo temporário + rename) e incrementa a versão
/// da coleção, avisando quem escuta [mudancas].
class Store {
  Store(this.pasta);

  final String pasta;
  final Map<String, List<Map<String, dynamic>>> _colecoes = {};
  final Map<String, int> _versoes = {};
  final _mudancas = StreamController<String>.broadcast();

  // Serializa as gravações para não intercalar escritas do mesmo arquivo.
  Future<void> _fila = Future.value();

  static const colecoes = ['recados', 'motivos', 'membros', 'mensagens', 'galeria', 'visitas'];

  Stream<String> get mudancas => _mudancas.stream;
  Map<String, int> get versoes => Map.unmodifiable(_versoes);

  Future<void> carregar() async {
    await Directory(pasta).create(recursive: true);
    for (final nome in colecoes) {
      final f = File(p.join(pasta, '$nome.json'));
      final lista = await f.exists() ? jsonDecode(await f.readAsString()) as List : const [];
      _colecoes[nome] = [for (final e in lista) Map<String, dynamic>.from(e as Map)];
      _versoes[nome] = 0;
    }
  }

  List<Map<String, dynamic>> listar(String colecao) => List.unmodifiable(_colecoes[colecao]!);

  Map<String, dynamic>? buscar(String colecao, String id) =>
      _colecoes[colecao]!.where((d) => d['id'] == id).firstOrNull;

  /// Insere ou substitui pelo campo "id".
  Future<void> salvar(String colecao, Map<String, dynamic> doc) {
    final lista = _colecoes[colecao]!;
    final i = lista.indexWhere((d) => d['id'] == doc['id']);
    if (i >= 0) {
      lista[i] = doc;
    } else {
      lista.add(doc);
    }
    return _persistir(colecao);
  }

  Future<void> salvarVarios(String colecao, List<Map<String, dynamic>> docs) {
    final lista = _colecoes[colecao]!;
    for (final doc in docs) {
      final i = lista.indexWhere((d) => d['id'] == doc['id']);
      if (i >= 0) {
        lista[i] = doc;
      } else {
        lista.add(doc);
      }
    }
    return _persistir(colecao);
  }

  /// Retorna false se o documento não existia.
  Future<bool> excluir(String colecao, String id) async {
    final lista = _colecoes[colecao]!;
    final antes = lista.length;
    lista.removeWhere((d) => d['id'] == id);
    if (lista.length == antes) return false;
    await _persistir(colecao);
    return true;
  }

  Future<void> _persistir(String colecao) {
    _versoes[colecao] = (_versoes[colecao] ?? 0) + 1;
    final conteudo = const JsonEncoder.withIndent('  ').convert(_colecoes[colecao]);
    final destino = p.join(pasta, '$colecao.json');
    _fila = _fila.then((_) async {
      final tmp = File('$destino.tmp');
      await tmp.writeAsString(conteudo, flush: true);
      await tmp.rename(destino);
    });
    _mudancas.add(colecao);
    return _fila;
  }

  /// Troca a coleção inteira (restauração de backup).
  Future<void> substituir(String colecao, List<Map<String, dynamic>> docs) {
    _colecoes[colecao] = [for (final d in docs) Map<String, dynamic>.from(d)];
    return _persistir(colecao);
  }

  /// Avisa uma mudança que não é de coleção (ex: "cartazes").
  void avisar(String tipo) => _mudancas.add(tipo);

  Future<void> fechar() async {
    await _fila;
    await _mudancas.close();
  }
}

/// Id curto, ordenável pelo tempo e com parte aleatória.
String novoId() {
  final tempo = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final aleatorio = _rng.nextInt(1 << 32).toRadixString(36).padLeft(7, '0');
  return '$tempo$aleatorio';
}

final _rng = Random.secure();
