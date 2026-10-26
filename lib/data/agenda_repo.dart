import 'dart:convert';
import 'dart:io';

import 'package:diako_core/diako_core.dart';
import 'package:flutter/foundation.dart';

import '../sync/server_api.dart';

/// Próximos eventos do Google Agenda (só leitura), com cópia local para usar sem conexão.
class AgendaRepo extends ChangeNotifier {
  AgendaRepo({required this.api, required Future<File> Function() cache, DateTime Function()? relogio})
      : _cache = cache,
        _agora = relogio ?? DateTime.now;

  final ServerApi api;
  final Future<File> Function() _cache;
  final DateTime Function() _agora;

  List<Evento> _eventos = [];
  bool _configurada = false;
  bool _online = false;
  String? _erro;
  DateTime? _atualizado;

  /// Eventos que ainda não terminaram, em ordem.
  List<Evento> get eventos => [for (final e in _eventos) if (e.fim.isAfter(_agora())) e];
  bool get configurada => _configurada;
  bool get online => _online;

  /// Erro de conexão com o servidor ou do servidor com o Google.
  String? get erro => _erro;
  DateTime? get atualizado => _atualizado;

  /// O próximo evento que ainda não começou (ou está acontecendo).
  Evento? get proximo => eventos.firstOrNull;

  Future<void> carregar() async {
    try {
      final f = await _cache();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        _configurada = j['configurada'] == true;
        _eventos = [for (final e in j['eventos'] as List) Evento.fromJson(Map<String, dynamic>.from(e as Map))];
        notifyListeners();
      }
    } catch (_) {
      // Cache corrompido: espera o servidor.
    }
    await sincronizar();
  }

  Future<void> sincronizar() async {
    try {
      final r = await api.agenda(dias: 30);
      _eventos = r.eventos;
      _configurada = r.configurada;
      _erro = r.erro;
      _atualizado = r.atualizado;
      _online = true;
      try {
        final f = await _cache();
        await f.writeAsString(jsonEncode({'configurada': _configurada, 'eventos': [for (final e in _eventos) e.toJson()]}));
      } catch (_) {}
    } on ErroAmigavel catch (e) {
      _online = false;
      _erro = e.message;
    }
    notifyListeners();
  }
}
