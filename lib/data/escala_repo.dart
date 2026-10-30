import 'dart:convert';
import 'dart:io';

import 'package:diako_core/diako_core.dart';
import 'package:flutter/foundation.dart';

import '../sync/server_api.dart';

/// Um culto como o tablet mostra: quem serve em cada função (nomes já resolvidos pelo servidor) e as músicas.
class CultoDoDia {
  CultoDoDia({
    required this.id,
    required this.data,
    required this.hora,
    required this.rotulo,
    required this.horaTexto,
    required this.nome,
    required this.ceia,
    required this.tema,
    required this.pastoral,
    required this.louvor,
    required this.musicas,
  });

  final String id;
  final String data;

  /// hh:mm (vazio em cópias salvas antes desta versão).
  final String hora;

  /// "Dom 01/11"
  final String rotulo;

  /// "19h"
  final String horaTexto;
  final String nome;
  final bool ceia;
  final String tema;

  /// Função → nomes, na ordem das funções do culto (função vazia fica com lista vazia).
  final Map<String, List<String>> pastoral;
  final Map<String, List<String>> louvor;
  final List<Musica> musicas;

  static Map<String, List<String>> _funcoes(Map<String, dynamic> j, String tipo) {
    final funcoes = [for (final f in ((j['funcoes'] as Map?)?[tipo] as List? ?? const [])) f as String];
    final pessoas = Map<String, dynamic>.from(j[tipo] as Map? ?? const {});
    return {
      for (final f in funcoes) f: [for (final p in (pessoas[f] as List? ?? const [])) (p as Map)['nome'] as String],
    };
  }

  factory CultoDoDia.fromJson(Map<String, dynamic> j) => CultoDoDia(
        id: j['id'] as String? ?? '',
        data: j['data'] as String,
        hora: j['hora'] as String? ?? '',
        rotulo: j['rotulo'] as String? ?? '',
        horaTexto: j['horaTexto'] as String? ?? '',
        nome: j['nome'] as String? ?? 'Culto',
        ceia: j['ceia'] == true,
        tema: j['tema'] as String? ?? '',
        pastoral: _funcoes(j, 'pastoral'),
        louvor: _funcoes(j, 'louvor'),
        musicas: [for (final m in (j['musicas'] as List? ?? const [])) Musica.fromJson(Map<String, dynamic>.from(m as Map))],
      );
}

/// Escala de hoje (ou do próximo culto, em até 7 dias), com cópia local para usar sem conexão.
class EscalaRepo extends ChangeNotifier {
  EscalaRepo({required this.api, required Future<File> Function() cache}) : _cache = cache;

  final ServerApi api;
  final Future<File> Function() _cache;

  List<CultoDoDia> _cultos = [];
  bool _hoje = false;
  bool _online = false;
  String? _erro;

  /// Cultos de hoje; sem culto hoje, os do próximo dia com culto.
  List<CultoDoDia> get cultos => _cultos;

  /// Os [cultos] são de hoje (senão, são do próximo dia com culto).
  bool get hoje => _hoje;
  bool get online => _online;
  String? get erro => _erro;

  Future<void> carregar() async {
    try {
      final f = await _cache();
      if (await f.exists()) {
        _ler(Map<String, dynamic>.from(jsonDecode(await f.readAsString()) as Map));
        notifyListeners();
      }
    } catch (_) {
      // Cache corrompido: espera o servidor.
    }
    await sincronizar();
  }

  void _ler(Map<String, dynamic> j) {
    _hoje = j['hoje'] == true;
    _cultos = [for (final c in (j['cultos'] as List? ?? const [])) CultoDoDia.fromJson(Map<String, dynamic>.from(c as Map))];
  }

  Future<void> sincronizar() async {
    try {
      final j = await api.escalaHoje();
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
