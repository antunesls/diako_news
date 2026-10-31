import 'dart:convert';
import 'dart:io';

import 'package:diako_core/diako_core.dart';
import 'package:flutter/foundation.dart';

import '../sync/server_api.dart';

/// A Palavra pronta de hoje (preparada no painel), com cópia local: a leitura no culto
/// continua mesmo se a conexão com o servidor cair.
class PalavraRepo extends ChangeNotifier {
  PalavraRepo({required this.api, required Future<File> Function() cache, DateTime Function()? relogio})
      : _cache = cache,
        _agora = relogio ?? DateTime.now;

  final ServerApi api;
  final Future<File> Function() _cache;
  final DateTime Function() _agora;

  PalavraDoCulto? _palavra;
  String _dia = '';
  bool _online = false;
  String? _erro;

  /// A Palavra de hoje (ou da data escolhida); null se não há uma pronta para ela.
  PalavraDoCulto? get palavra => _dia == (data.isEmpty ? diaIso(_agora()) : data) ? _palavra : null;
  bool get online => _online;
  String? get erro => _erro;

  /// Culto da escala, para escolher entre duas Palavras no mesmo dia.
  String culto = '';

  /// Data e Palavra escolhidas no tablet (só nesta sessão; vazias = seleção automática).
  String data = '';
  String id = '';

  /// Palavras prontas da data escolhida (título e id, para o seletor).
  List<({String id, String titulo})> opcoes = [];

  /// Esquece a escolha manual (ao sair do Modo Culto, a Palavra volta a ser a de hoje).
  void limparEscolha() {
    culto = '';
    data = '';
    id = '';
    _dia = '';
    _palavra = null;
  }

  /// Busca as Palavras prontas do dia, sem o texto (é só para escolher).
  Future<void> buscarOpcoes(String dia) async {
    try {
      final j = await api.palavraDeHoje(data: dia, listar: true);
      opcoes = [
        for (final p in j['palavras'] as List? ?? const []) (id: (p as Map)['id'] as String, titulo: p['titulo'] as String),
      ];
      notifyListeners();
    } on ErroAmigavel catch (e) {
      _erro = e.message;
      notifyListeners();
    }
  }

  Future<void> carregar() async {
    try {
      final f = await _cache();
      if (await f.exists()) {
        _ler(Map<String, dynamic>.from(jsonDecode(await f.readAsString()) as Map));
        notifyListeners();
      }
    } catch (_) {
      // Cópia ilegível: espera o servidor.
    }
    await sincronizar();
  }

  void _ler(Map<String, dynamic> j) {
    _dia = j['dia'] as String? ?? '';
    final p = j['palavra'];
    _palavra = p is Map ? PalavraDoCulto.fromJson(Map<String, dynamic>.from(p)) : null;
  }

  Future<void> sincronizar() async {
    try {
      final j = {...await api.palavraDeHoje(culto: culto, data: data, id: id), 'dia': data.isEmpty ? diaIso(_agora()) : data};
      _ler(j);
      _online = true;
      _erro = null;
      try {
        await (await _cache()).writeAsString(jsonEncode(j));
      } catch (_) {}
    } on ErroAmigavel catch (e) {
      _online = false;
      _erro = e.message;
    }
    notifyListeners();
  }
}
