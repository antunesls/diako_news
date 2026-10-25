import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Erro com mensagem pronta para mostrar ao usuário.
abstract class ErroAmigavel implements Exception {
  String get message;
  @override
  String toString() => message;
}

class ServidorException extends ErroAmigavel {
  ServidorException(this.message, {this.status});
  @override
  final String message;
  final int? status;
  bool get naoAutorizado => status == 401;
}

class ServidorConfig {
  const ServidorConfig({required this.base, required this.sessao});

  /// Ex: http://192.168.0.10:8080
  final String base;
  final String sessao;
}

/// "192.168.0.10" -> "http://192.168.0.10:8080"; remove a barra final.
String normalizarServidor(String entrada) {
  var s = entrada.trim();
  if (s.isEmpty) return '';
  if (!s.contains('://')) s = 'http://$s';
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  final uri = Uri.tryParse(s);
  if (uri != null && !uri.hasPort) s = uri.replace(port: 8080).toString();
  return s;
}

class Cartaz {
  Cartaz({required this.nome, required this.holyrics, required this.url});
  final String nome;

  /// Caminho usado no ShowImage do Holyrics (ex: "Diako/retiro.jpg").
  final String holyrics;

  /// Endereço completo da imagem no servidor (para miniaturas).
  final String url;
}

/// Cliente REST do servidor Diako News.
class ServerApi {
  ServerApi(this._config, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final ServidorConfig Function() _config;
  final http.Client _http;

  static const timeout = Duration(seconds: 8);

  String get base => _config().base;

  /// Troca a senha por um token de sessão.
  Future<String> login(String base, String senha) async {
    final j = await _enviar('POST', base, '/api/login', null, json: {'senha': senha});
    return (j as Map)['token'] as String;
  }

  Future<List<Map<String, dynamic>>> listar(String colecao) async {
    final j = await _req('GET', '/api/$colecao');
    return [for (final e in j as List) Map<String, dynamic>.from(e as Map)];
  }

  Future<Map<String, dynamic>> criar(String colecao, Map<String, dynamic> dados) async =>
      Map<String, dynamic>.from(await _req('POST', '/api/$colecao', json: dados) as Map);

  Future<Map<String, dynamic>> atualizar(String colecao, String id, Map<String, dynamic> dados) async =>
      Map<String, dynamic>.from(await _req('PUT', '/api/$colecao/${Uri.encodeComponent(id)}', json: dados) as Map);

  Future<void> excluir(String colecao, String id) => _req('DELETE', '/api/$colecao/${Uri.encodeComponent(id)}');

  Future<void> ordenarRecados(List<String> ids) => _req('PUT', '/api/recados/ordem', json: ids);

  Future<Map<String, dynamic>> aprovarMotivo(String id) async =>
      Map<String, dynamic>.from(await _req('POST', '/api/motivos/${Uri.encodeComponent(id)}/aprovar') as Map);

  Future<Map<String, dynamic>> estado() async => Map<String, dynamic>.from(await _req('GET', '/api/estado') as Map);

  Future<List<Cartaz>> cartazes() async {
    final j = await _req('GET', '/api/cartazes') as List;
    return [
      for (final c in j.cast<Map>())
        Cartaz(nome: c['nome'] as String, holyrics: c['holyrics'] as String, url: '$base${c['url']}'),
    ];
  }

  /// Envia uma imagem e retorna o caminho para o Holyrics.
  Future<String> enviarCartaz(String nome, List<int> bytes) async {
    final j = await _req('POST', '/api/cartazes?nome=${Uri.encodeQueryComponent(nome)}', bytes: bytes);
    return (j as Map)['holyrics'] as String;
  }

  /// Repassa uma ação ao Holyrics pelo servidor. Retorna o JSON cru do Holyrics.
  Future<Map<String, dynamic>> holyrics(String acao, Map<String, dynamic> corpo) async =>
      Map<String, dynamic>.from(await _req('POST', '/api/holyrics/$acao', json: corpo) as Map);

  Uri wsUri() {
    final c = _config();
    final u = Uri.parse(c.base);
    return u.replace(scheme: u.scheme == 'https' ? 'wss' : 'ws', path: '/ws', queryParameters: {'token': c.sessao});
  }

  Future<dynamic> _req(String metodo, String caminho, {Object? json, List<int>? bytes}) {
    final c = _config();
    if (c.base.isEmpty || c.sessao.isEmpty) {
      throw ServidorException('Configure o endereço do servidor e entre com a senha nas Configurações.');
    }
    return _enviar(metodo, c.base, caminho, c.sessao, json: json, bytes: bytes);
  }

  Future<dynamic> _enviar(String metodo, String base, String caminho, String? sessao,
      {Object? json, List<int>? bytes}) async {
    final req = http.Request(metodo, Uri.parse('$base$caminho'));
    if (sessao != null) req.headers['Authorization'] = 'Bearer $sessao';
    if (json != null) {
      req.headers['Content-Type'] = 'application/json; charset=utf-8';
      req.bodyBytes = utf8.encode(jsonEncode(json));
    } else if (bytes != null) {
      req.headers['Content-Type'] = 'application/octet-stream';
      req.bodyBytes = bytes;
    }
    final http.Response resp;
    try {
      resp = await http.Response.fromStream(await _http.send(req).timeout(timeout));
    } on TimeoutException {
      throw ServidorException('O servidor não respondeu. O PC do Holyrics está ligado e na mesma rede?');
    } catch (_) {
      throw ServidorException('Não foi possível conectar ao servidor em $base.');
    }
    dynamic corpo;
    try {
      corpo = resp.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(resp.bodyBytes));
    } on FormatException {
      corpo = null;
    }
    if (resp.statusCode >= 400) {
      final msg = corpo is Map && corpo['erro'] is String ? corpo['erro'] as String : 'Erro ${resp.statusCode} no servidor.';
      throw ServidorException(resp.statusCode == 401 && sessao != null ? 'Sessão expirada. Entre de novo nas Configurações.' : msg,
          status: resp.statusCode);
    }
    return corpo;
  }
}
