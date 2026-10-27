import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../sync/server_api.dart';

/// Porta padrão da API local do agente (agente.json › apiLocal.porta).
const portaAgenteLocal = 8097;

/// Completa o IP digitado: "192.168.0.20" → "http://192.168.0.20:8097".
String normalizarAgenteLocal(String entrada) {
  var s = entrada.trim();
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.isEmpty) return s;
  if (!s.contains('://')) s = 'http://$s';
  final uri = Uri.tryParse(s);
  if (uri == null || uri.host.isEmpty) return s;
  return (uri.hasPort ? uri : uri.replace(port: portaAgenteLocal)).replace(path: '').toString();
}

/// Atalho até o Holyrics pelo agente do PC da igreja, na mesma rede do tablet. O app tenta
/// por aqui primeiro e, se o PC não responder, usa a internet (servidor), como antes.
class AgenteLocal extends ChangeNotifier {
  AgenteLocal(this._config, {http.Client? httpClient, DateTime Function()? relogio})
      : _http = httpClient ?? IOClient(HttpClient()..connectionTimeout = conexao),
        _agora = relogio ?? DateTime.now;

  final ({String base, String token}) Function() _config;
  final http.Client _http;
  final DateTime Function() _agora;

  /// Fora da rede da igreja o PC não responde: espera pouco para conectar...
  static const conexao = Duration(milliseconds: 1500);

  /// ...e o resto do tempo é do Holyrics (o agente espera até 5 s por ele).
  static const timeout = Duration(seconds: 7);

  /// Depois de uma falha, vai direto pela internet por este tempo antes de tentar de novo.
  static const pausa = Duration(seconds: 30);

  DateTime? _pausadoAte;

  /// Caminho e tempo do último comando ("rede local" ou "internet"), para conferir o ganho.
  String? ultimoCaminho;
  int? ultimoMs;

  /// O agente recusou o token (pareamento removido no /admin): precisa parear de novo.
  bool recusado = false;

  bool get configurado {
    final c = _config();
    return c.base.isNotEmpty && c.token.isNotEmpty;
  }

  /// JSON do Holyrics pela rede local, ou null quando não deu (o app então usa a internet).
  Future<Map<String, dynamic>?> holyrics(String acao, Map<String, dynamic> corpo) async {
    final c = _config();
    if (c.base.isEmpty || c.token.isEmpty) return null;
    final pausado = _pausadoAte;
    if (pausado != null && _agora().isBefore(pausado)) return null;
    try {
      final r = await _http
          .post(Uri.parse('${c.base}/holyrics/$acao'),
              headers: {'Authorization': 'Bearer ${c.token}', 'Content-Type': 'application/json; charset=utf-8'},
              body: utf8.encode(jsonEncode(corpo)))
          .timeout(timeout);
      if (r.statusCode == 401) {
        recusado = true;
        notifyListeners();
      }
      if (r.statusCode != 200) return _falhou();
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is! Map) return _falhou();
      _pausadoAte = null;
      if (recusado) {
        recusado = false;
        notifyListeners();
      }
      return Map<String, dynamic>.from(j);
    } catch (_) {
      return _falhou();
    }
  }

  Map<String, dynamic>? _falhou() {
    _pausadoAte = _agora().add(pausa);
    return null;
  }

  /// Anota por onde foi o último comando e quanto demorou.
  void registrar(String caminho, int ms) {
    ultimoCaminho = caminho;
    ultimoMs = ms;
    notifyListeners();
  }

  /// Confere se o agente responde e aceita o token. Retorna o tempo de resposta em ms.
  Future<int> testar({String? base, String? token}) async {
    final c = _config();
    final inicio = Stopwatch()..start();
    final http.Response r;
    try {
      r = await _http
          .get(Uri.parse('${base ?? c.base}/ping'), headers: {'Authorization': 'Bearer ${token ?? c.token}'})
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      throw ServidorException('O PC da igreja não respondeu. Confira o IP, se o tablet está no mesmo Wi-Fi e se o '
          'agente está atualizado e com a rede do Windows como "Privada".');
    }
    if (r.statusCode == 401) {
      throw ServidorException('O PC da igreja ainda não reconhece este tablet. Ele precisa estar conectado à internet '
          'para receber o pareamento; tente de novo em instantes.', status: 401);
    }
    if (r.statusCode != 200) throw ServidorException('O PC da igreja respondeu erro ${r.statusCode}.');
    _pausadoAte = null;
    recusado = false;
    notifyListeners();
    return inicio.elapsedMilliseconds;
  }

  /// Volta a tentar a rede local já no próximo comando (ex: depois de parear).
  void reiniciar() {
    _pausadoAte = null;
    recusado = false;
    notifyListeners();
  }
}
