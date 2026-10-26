import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Registro do que foi projetado, uma linha JSON por evento em data/historico.jsonl.
class Historico {
  Historico(String pastaDados, {DateTime Function()? relogio})
      : arquivo = File(p.join(pastaDados, 'historico.jsonl')),
        _agora = relogio ?? DateTime.now;

  final File arquivo;
  final DateTime Function() _agora;
  Future<void> _fila = Future.value();

  /// Ações que entram no histórico.
  static const acoes = {'ShowQuickPresentation', 'ShowImage', 'ShowCountdown', 'SetTextCP', 'StartCountdownCP'};

  /// Registra a ação se ela for de projeção. [corpo] é o JSON enviado ao Holyrics; [usuario] é
  /// o nome de quem projetou (vazio em registros antigos).
  Future<void> registrar(String acao, String corpo, {String usuario = ''}) {
    if (!acoes.contains(acao)) return Future.value();
    final descricao = descrever(acao, corpo);
    if (descricao == null) return Future.value();
    final linha = jsonEncode({
      'quando': _agora().toIso8601String(),
      'acao': acao,
      'descricao': descricao,
      if (usuario.isNotEmpty) 'usuario': usuario,
    });
    _fila = _fila.then((_) => arquivo.writeAsString('$linha\n', mode: FileMode.append, flush: true));
    return _fila;
  }

  /// Eventos mais recentes primeiro.
  Future<List<Map<String, dynamic>>> listar({int limite = 300}) async {
    await _fila;
    if (!await arquivo.exists()) return [];
    final linhas = await arquivo.readAsLines();
    final eventos = <Map<String, dynamic>>[];
    for (final l in linhas.reversed) {
      if (eventos.length >= limite) break;
      try {
        eventos.add(Map<String, dynamic>.from(jsonDecode(l) as Map));
      } catch (_) {
        // Linha incompleta (ex: queda de energia): ignora.
      }
    }
    return eventos;
  }

  /// Texto curto para o histórico, ou null quando não vale registrar (ex: ocultar mensagem do palco).
  static String? descrever(String acao, String corpo) {
    Map<String, dynamic> j;
    try {
      j = corpo.trim().isEmpty ? {} : Map<String, dynamic>.from(jsonDecode(corpo) as Map);
    } catch (_) {
      j = {};
    }
    String limpar(String? t) => (t ?? '').replaceAll(RegExp(r'<[^>]+>'), '').trim();
    String primeiraLinha(String? t) => limpar(t).split('\n').first.trim();

    switch (acao) {
      case 'ShowQuickPresentation':
        final slides = j['slides'];
        if (slides is List && slides.isNotEmpty) {
          final titulo = primeiraLinha((slides.first as Map)['text'] as String?);
          return slides.length == 1 ? titulo : '$titulo (${slides.length} slides)';
        }
        return primeiraLinha(j['text'] as String?);
      case 'ShowImage':
        return 'Imagem: ${j['file'] ?? ''}';
      case 'ShowCountdown':
        return 'Contagem no telão: ${j['time'] ?? ''}${j['exact_time'] == true ? ' (horário)' : ''}';
      case 'StartCountdownCP':
        return 'Contagem no palco: ${j['minutes'] ?? 0} min';
      case 'SetTextCP':
        if (j['show'] != true || limpar(j['text'] as String?).isEmpty) return null;
        return 'Palco: ${limpar(j['text'] as String?)}';
    }
    return null;
  }
}
