import 'dart:async';
import 'dart:convert';

import 'package:diako_core/diako_core.dart';
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

/// Completa o endereço digitado:
/// - com esquema (http:// ou https://): mantém como está;
/// - IP, "localhost", nome sem domínio ou com porta: http:// (+ :8080 se faltar a porta);
/// - domínio (ex: diako.minhaigreja.com.br): https://, sem porta.
String normalizarServidor(String entrada) {
  var s = entrada.trim();
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.isEmpty || s.contains('://')) return s;
  final uri = Uri.tryParse('http://$s');
  if (uri == null) return 'http://$s';
  final host = uri.host;
  final ehRedeLocal = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host) || host == 'localhost' || !host.contains('.');
  if (uri.hasPort) return 'http://$s';
  if (ehRedeLocal) return uri.replace(port: 8080).toString();
  return 'https://$s';
}

class Cartaz {
  Cartaz({required this.nome, required this.holyrics, required this.url});
  final String nome;

  /// Caminho usado no ShowImage do Holyrics (ex: "Diako/retiro.jpg").
  final String holyrics;

  /// Endereço completo da imagem no servidor (para miniaturas).
  final String url;
}

/// Cliente REST do servidor DiakoHub.
class ServerApi {
  ServerApi(this._config, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final ServidorConfig Function() _config;
  final http.Client _http;

  static const timeout = Duration(seconds: 8);

  String get base => _config().base;

  /// Troca a senha por um token de sessão.
  /// [usuario] vazio entra com a senha principal da igreja.
  Future<String> login(String base, String senha, {String usuario = ''}) async {
    final j = await _enviar('POST', base, '/api/login', null, json: {'usuario': usuario.trim(), 'senha': senha});
    return (j as Map)['token'] as String;
  }

  /// Quem está logado: nome, perfil e permissões.
  Future<Map<String, dynamic>> eu() async => Map<String, dynamic>.from(await _req('GET', '/api/eu') as Map);

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

  /// Escala de hoje (ou do próximo culto em até 7 dias): {hoje, cultos: [...]}.
  /// A Palavra pronta de hoje para o culto: {palavra: {...} ou null}.
  Future<Map<String, dynamic>> palavraDeHoje({String culto = ''}) async => Map<String, dynamic>.from(
      await _req('GET', '/api/palavras/hoje${culto.isEmpty ? '' : '?culto=${Uri.encodeQueryComponent(culto)}'}') as Map);

  Future<Map<String, dynamic>> escalaHoje() async => Map<String, dynamic>.from(await _req('GET', '/api/escalas/hoje') as Map);

  Future<Map<String, dynamic>> marcarVisitaMencionada(String id, {bool desfazer = false}) async =>
      Map<String, dynamic>.from(await _req('POST', '/api/visitas/${Uri.encodeComponent(id)}/mencionada',
          json: {if (desfazer) 'desfazer': true}) as Map);

  /// Retorna o JSON do Holyrics ({"status": "ok"} quando projetou).
  Future<Map<String, dynamic>> projetarBoasVindas({List<String>? ids}) async =>
      Map<String, dynamic>.from(await _req('POST', '/api/projetar/boas-vindas', json: {if (ids != null) 'ids': ids}) as Map);

  /// Próximos eventos do Google Agenda (lidos pelo servidor).
  Future<AgendaServidor> agenda({int dias = 30}) async {
    final j = Map<String, dynamic>.from(await _req('GET', '/api/agenda?dias=$dias') as Map);
    return AgendaServidor(
      configurada: j['configurada'] == true,
      editavel: j['editavel'] == true,
      erro: j['erro'] as String?,
      atualizado: DateTime.tryParse(j['atualizado'] as String? ?? ''),
      eventos: [for (final e in (j['eventos'] as List? ?? const [])) Evento.fromJson(Map<String, dynamic>.from(e as Map))],
    );
  }

  /// Cria um evento no Google Agenda (pelo servidor, com a conta de serviço).
  Future<Evento> criarEvento(Map<String, dynamic> dados) async =>
      Evento.fromJson(Map<String, dynamic>.from(await _req('POST', '/api/agenda/eventos', json: dados, tempo: _tempoGoogle) as Map));

  Future<Evento> atualizarEvento(String id, Map<String, dynamic> dados) async => Evento.fromJson(Map<String, dynamic>.from(
      await _req('PUT', '/api/agenda/eventos/${Uri.encodeComponent(id)}', json: dados, tempo: _tempoGoogle) as Map));

  Future<void> excluirEvento(String id) =>
      _req('DELETE', '/api/agenda/eventos/${Uri.encodeComponent(id)}', tempo: _tempoGoogle);

  /// O servidor conversa com o Google antes de responder.
  static const _tempoGoogle = Duration(seconds: 30);

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

  /// Pareia este tablet com o agente do PC da igreja: {id, token, agenteConectado}. Precisa de internet.
  Future<Map<String, dynamic>> parearAgenteLocal(String aparelho) async =>
      Map<String, dynamic>.from(await _req('POST', '/api/agente-local/parear', json: {'aparelho': aparelho}) as Map);

  Future<void> desparearAgenteLocal(String id) => _req('DELETE', '/api/agente-local/${Uri.encodeComponent(id)}');

  /// Catálogo de temas e miniaturas do backend; pode estar desatualizado quando o Holyrics estiver offline.
  Future<Map<String, dynamic>> temas() async =>
      Map<String, dynamic>.from(await _req('GET', '/api/temas', tempo: const Duration(seconds: 75)) as Map);

  Uri wsUri() {
    final c = _config();
    final u = Uri.parse(c.base);
    return u.replace(scheme: u.scheme == 'https' ? 'wss' : 'ws', path: '/ws', queryParameters: {'token': c.sessao});
  }

  Future<dynamic> _req(String metodo, String caminho, {Object? json, List<int>? bytes, Duration tempo = timeout}) {
    final c = _config();
    if (c.base.isEmpty || c.sessao.isEmpty) {
      throw ServidorException('Configure o endereço do servidor e entre com a senha nas Configurações.');
    }
    return _enviar(metodo, c.base, caminho, c.sessao, json: json, bytes: bytes, tempo: tempo);
  }

  Future<dynamic> _enviar(String metodo, String base, String caminho, String? sessao,
      {Object? json, List<int>? bytes, Duration tempo = timeout}) async {
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
      resp = await http.Response.fromStream(await _http.send(req).timeout(tempo));
    } on TimeoutException {
      throw ServidorException('O servidor não respondeu. Verifique a internet do tablet e se o servidor está no ar.');
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

/// Resposta de GET /api/agenda.
class AgendaServidor {
  AgendaServidor({required this.configurada, required this.eventos, this.editavel = false, this.erro, this.atualizado});
  final bool configurada;

  /// O servidor pode criar e alterar eventos (conta de serviço do Google ligada).
  final bool editavel;
  final List<Evento> eventos;

  /// Problema na última atualização do servidor com o Google (os eventos são da última cópia boa).
  final String? erro;
  final DateTime? atualizado;
}
