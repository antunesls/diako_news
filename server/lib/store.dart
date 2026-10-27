import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// Coleções de documentos JSON gravadas em data/<nome>.json.
/// Cada gravação é atômica (arquivo temporário + rename). Só depois de gravada a
/// mudança aparece em [listar]/[buscar], incrementa a versão e é avisada em [mudancas];
/// se a gravação falhar, nada muda e o erro vai só para quem pediu aquela operação.
/// Enquanto uma gravação está em andamento, as leituras mostram o último estado gravado.
class Store {
  Store(this.pasta, {Future<void> Function(String caminho, String conteudo)? gravar})
      : _gravar = gravar ?? gravarArquivo;

  final String pasta;
  final Future<void> Function(String caminho, String conteudo) _gravar;
  final Map<String, List<Map<String, dynamic>>> _colecoes = {};
  final Map<String, int> _versoes = {};
  final _mudancas = StreamController<String>.broadcast();

  // Serializa as operações inteiras (ler o estado, gravar, publicar), na ordem pedida.
  Future<void> _fila = Future.value();

  static const colecoes = ['recados', 'motivos', 'membros', 'mensagens', 'galeria', 'visitas', 'escalas',
    'indisponibilidades', 'linksEscala', 'repertorio'];

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
  Future<void> salvar(String colecao, Map<String, dynamic> doc) => salvarVarios(colecao, [doc]);

  Future<void> salvarVarios(String colecao, List<Map<String, dynamic>> docs) => _alterar(colecao, (lista) {
        for (final doc in docs) {
          final i = lista.indexWhere((d) => d['id'] == doc['id']);
          if (i >= 0) {
            lista[i] = doc;
          } else {
            lista.add(doc);
          }
        }
        return true;
      });

  /// Retorna false se o documento não existia.
  Future<bool> excluir(String colecao, String id) => _alterar(colecao, (lista) {
        final antes = lista.length;
        lista.removeWhere((d) => d['id'] == id);
        return lista.length != antes;
      });

  /// Troca a coleção inteira (restauração de backup).
  Future<void> substituir(String colecao, List<Map<String, dynamic>> docs) => _alterar(colecao, (lista) {
        lista
          ..clear()
          ..addAll([for (final d in docs) Map<String, dynamic>.from(d)]);
        return true;
      });

  /// Na vez da fila: aplica [mudar] numa cópia do último estado gravado; se ela
  /// retornar true, grava a cópia e só então a publica.
  Future<bool> _alterar(String colecao, bool Function(List<Map<String, dynamic>> lista) mudar) {
    final operacao = _fila.then((_) async {
      final lista = [..._colecoes[colecao]!];
      if (!mudar(lista)) return false;
      await _gravar(p.join(pasta, '$colecao.json'), const JsonEncoder.withIndent('  ').convert(lista));
      _colecoes[colecao] = lista;
      _versoes[colecao] = (_versoes[colecao] ?? 0) + 1;
      _mudancas.add(colecao);
      return true;
    });
    // Uma falha não trava a fila: o erro vai só para quem pediu esta operação.
    _fila = operacao.then((_) {}, onError: (_) {});
    return operacao;
  }

  /// Gravação padrão: arquivo temporário e rename (quem lê vê o arquivo antigo ou o novo).
  static Future<void> gravarArquivo(String caminho, String conteudo) async {
    final tmp = File('$caminho.tmp');
    try {
      await tmp.writeAsString(conteudo, flush: true);
      await tmp.rename(caminho);
    } catch (_) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
    }
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
