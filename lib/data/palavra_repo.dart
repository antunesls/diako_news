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

  /// A Palavra de hoje; null se não há uma pronta (ou a cópia é de outro dia).
  PalavraDoCulto? get palavra => _dia == diaIso(_agora()) ? _palavra : null;
  bool get online => _online;
  String? get erro => _erro;

  /// Culto da escala de hoje, para escolher entre duas Palavras no mesmo dia.
  String culto = '';

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
      final j = {...await api.palavraDeHoje(culto: culto), 'dia': diaIso(_agora())};
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
