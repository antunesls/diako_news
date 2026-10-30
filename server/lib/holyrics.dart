import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Ações da API do Holyrics que o tablet pode pedir pelo servidor.
const acoesPermitidas = {
  'GetCPInfo',
  'GetCurrentPresentation',
  'ShowQuickPresentation',
  'ShowImage',
  // Versículo da Palavra no telão (Modo Culto), por ids LLCCCVVV.
  'ShowVerse',
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
  'GetThumbnail',
};

/// Resposta do Holyrics ou do próprio servidor quando o Holyrics não responde.
class RespostaHolyrics {
  RespostaHolyrics(this.status, this.corpo);
  final int status;
  final String corpo;
}

/// Caminho até o Holyrics: direto (mesma rede) ou pelo agente instalado no PC da igreja.
abstract class PonteHolyrics {
  Future<RespostaHolyrics> chamar(String acao, String corpoJson);

  /// true se o Holyrics respondeu "ok" ao GetCPInfo.
  Future<bool> conectado() async {
    final r = await chamar('GetCPInfo', '{}');
    try {
      return (jsonDecode(r.corpo) as Map)['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }
}

/// Resposta de erro no mesmo formato do Holyrics, para o app tratar igual.
RespostaHolyrics erroHolyrics(String msg) => RespostaHolyrics(200, jsonEncode({'status': 'error', 'error': msg}));

/// Chama a API Server do Holyrics por HTTP (servidor ou agente na mesma rede do Holyrics).
class HolyricsDireto extends PonteHolyrics {
  HolyricsDireto({required this.host, required this.porta, required this.token, http.Client? cliente})
      : _http = cliente ?? http.Client();

  String host;
  int porta;
  String token;
  final http.Client _http;

  /// Aplica novos dados de conexão (alterados pela página de administração).
  void atualizar({required String host, required int porta, required String token}) {
    this.host = host;
    this.porta = porta;
    this.token = token;
  }

  static const timeout = Duration(seconds: 5);

  bool get configurado => token.isNotEmpty;

  @override
  Future<RespostaHolyrics> chamar(String acao, String corpoJson) async {
    if (!configurado) {
      return _erro('Configure o token do Holyrics no config.json.');
    }
    if (acao == 'ShowQuickPresentation') corpoJson = _apresentacaoEstilizada(corpoJson);
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

  /// O Holyrics só interpreta <b> quando o texto começa com <styled>.
  /// Vale tanto para um slide quanto para cada item da sequência enviada pelo agente.
  static String _apresentacaoEstilizada(String corpoJson) {
    try {
      final dados = jsonDecode(corpoJson);
      if (dados is! Map) return corpoJson;
      var alterado = false;
      void estilizar(Map slide) {
        final texto = slide['text'];
        if (texto is String && texto.contains('<b>') && !texto.startsWith('<styled>')) {
          slide['text'] = '<styled>$texto';
          alterado = true;
        }
      }
      estilizar(dados);
      if (dados['slides'] case final List slides) {
        for (final slide in slides) {
          if (slide is Map) estilizar(slide);
        }
      }
      return alterado ? jsonEncode(dados) : corpoJson;
    } on FormatException {
      return corpoJson;
    }
  }

  RespostaHolyrics _erro(String msg) => erroHolyrics(msg);
}
