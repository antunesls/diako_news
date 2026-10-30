import 'dart:convert';
import 'dart:io';

import 'package:diako_core/diako_core.dart' show livrosBiblia;
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
  static const acoes = {'ShowQuickPresentation', 'ShowImage', 'ShowVerse', 'ShowCountdown', 'SetTextCP', 'StartCountdownCP'};

  /// Registra a ação se ela for de projeção. [corpo] é o JSON enviado ao Holyrics; [usuario] é
  /// o nome de quem projetou (vazio em registros antigos). [quando] vem do agente quando a projeção
  /// foi feita pela rede local e chegou depois; [via] marca esse caminho ("rede local").
  Future<void> registrar(String acao, String corpo, {String usuario = '', DateTime? quando, String via = ''}) {
    if (!acoes.contains(acao)) return Future.value();
    final descricao = descrever(acao, corpo);
    if (descricao == null) return Future.value();
    final linha = jsonEncode({
      'quando': (quando ?? _agora()).toIso8601String(),
      'acao': acao,
      'descricao': descricao,
      if (usuario.isNotEmpty) 'usuario': usuario,
      if (via.isNotEmpty) 'via': via,
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
      case 'ShowVerse':
        return 'Versículo: ${_referenciaDosIds([for (final i in j['ids'] as List? ?? const []) '$i'])}';
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

  /// "1 Coríntios 11.23-24" a partir dos ids LLCCCVVV do Holyrics.
  static String _referenciaDosIds(List<String> ids) {
    final validos = [for (final i in ids) if (RegExp(r'^\d{8}$').hasMatch(i)) i];
    if (validos.isEmpty) return ids.join(', ');
    final livro = int.parse(validos.first.substring(0, 2));
    final nome = livro >= 1 && livro <= livrosBiblia.length ? livrosBiblia[livro - 1].nome : 'Livro $livro';
    final capitulo = int.parse(validos.first.substring(2, 5));
    final de = int.parse(validos.first.substring(5));
    final ate = int.parse(validos.last.substring(5));
    return '$nome $capitulo.$de${ate != de ? '-$ate' : ''}';
  }
}
