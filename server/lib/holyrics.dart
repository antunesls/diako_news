import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Ações da API do Holyrics que o tablet pode pedir pelo servidor.
const acoesPermitidas = {
  'GetCPInfo',
  'GetCurrentPresentation',
  'ShowQuickPresentation',
  'ShowImage',
  'ActionNext',
  'ActionPrevious',
  'ActionNextQuickPresentation',
  'ActionPreviousQuickPresentation',
  'CloseCurrentPresentation',
  'SetF9',
  'SetF10',
  'SetTextCP',
  'StartCountdownCP',
  'StopCountdownCP',
  'ShowCountdown',
  'GetThemes',
};

/// Resposta do Holyrics ou do próprio servidor quando o Holyrics não responde.
class RespostaHolyrics {
  RespostaHolyrics(this.status, this.corpo);
  final int status;
  final String corpo;
}

/// Encaminha chamadas para a API Server do Holyrics na mesma máquina.
class HolyricsProxy {
  HolyricsProxy({required this.host, required this.porta, required this.token, http.Client? cliente})
      : _http = cliente ?? http.Client();

  final String host;
  final int porta;
  final String token;
  final http.Client _http;

  static const timeout = Duration(seconds: 5);

  bool get configurado => token.isNotEmpty;

  Future<RespostaHolyrics> chamar(String acao, String corpoJson) async {
    if (!configurado) {
      return _erro('Configure o token do Holyrics no config.json do servidor.');
    }
    final uri = Uri(scheme: 'http', host: host, port: porta, path: '/api/$acao', queryParameters: {'token': token});
    try {
      final r = await _http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: corpoJson.isEmpty ? '{}' : corpoJson)
          .timeout(timeout);
      if (r.statusCode != 200) return _erro('Holyrics respondeu HTTP ${r.statusCode}.');
      return RespostaHolyrics(200, utf8.decode(r.bodyBytes));
    } on TimeoutException {
      return _erro('Holyrics não respondeu. Ele está aberto?');
    } catch (_) {
      return _erro('Não foi possível conectar ao Holyrics em $host:$porta. Verifique se a API Server está ativa.');
    }
  }

  /// true se o Holyrics respondeu "ok" ao GetCPInfo.
  Future<bool> conectado() async {
    final r = await chamar('GetCPInfo', '{}');
    try {
      return (jsonDecode(r.corpo) as Map)['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  // Mesmo formato do Holyrics, para o app tratar igual.
  RespostaHolyrics _erro(String msg) => RespostaHolyrics(200, jsonEncode({'status': 'error', 'error': msg}));
}
