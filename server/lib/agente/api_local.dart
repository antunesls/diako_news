import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../holyrics.dart';
import 'agente.dart';

/// Atalho dos tablets pareados até o Holyrics, pela rede da igreja (sem passar pela internet).
/// Aceita só as mesmas ações que o servidor repassa; o token do tablet vem do pareamento.
///
/// GET /ping → {"ok", "versao", "tablet"} · POST /holyrics/<acao> → JSON cru do Holyrics.
class ApiLocal {
  ApiLocal(this.agente, {this.endereco});

  final Agente agente;

  /// Padrão: todas as interfaces (os tablets estão na rede da igreja).
  final InternetAddress? endereco;
  HttpServer? _servidor;
  final _falhas = <String, List<DateTime>>{};

  static const maximoFalhas = 10;
  static const janelaFalhas = Duration(minutes: 5);
  static const tamanhoMaximo = 512 * 1024;

  int? get porta => _servidor?.port;

  Future<void> iniciar() async {
    _servidor = await HttpServer.bind(endereco ?? InternetAddress.anyIPv4, agente.config.apiLocalPorta);
    _servidor!.listen(_atender);
  }

  Future<void> parar() async {
    await _servidor?.close(force: true);
  }

  /// Muitas tentativas com token errado do mesmo IP: recusa por um tempo (adivinhar token).
  bool _bloqueado(String ip) {
    final agora = DateTime.now();
    final lista = _falhas[ip]?..removeWhere((t) => agora.difference(t) >= janelaFalhas);
    return lista != null && lista.length >= maximoFalhas;
  }

  void _falhou(String ip) => _falhas.putIfAbsent(ip, () => []).add(DateTime.now());

  Future<void> _atender(HttpRequest req) async {
    final res = req.response;
    res.headers.set('Cache-Control', 'no-store');
    res.headers.set('X-Content-Type-Options', 'nosniff');
    final ip = req.connectionInfo?.remoteAddress.address ?? '?';
    try {
      if (_bloqueado(ip)) return _json(res, 429, {'erro': 'Muitas tentativas. Aguarde alguns minutos.'});
      final h = req.headers.value(HttpHeaders.authorizationHeader) ?? '';
      final tablet = h.startsWith('Bearer ') ? agente.tabletDoToken(h.substring(7).trim()) : null;
      if (tablet == null) {
        _falhou(ip);
        return _json(res, 401, {'erro': 'Tablet não pareado com este PC.'});
      }
      final partes = req.uri.pathSegments;
      if (req.method == 'GET' && req.uri.path == '/ping') {
        return _json(res, 200, {'ok': true, 'versao': agente.versao, 'tablet': tablet['nome']});
      }
      if (req.method == 'POST' && partes.length == 2 && partes.first == 'holyrics') {
        final acao = partes[1];
        if (!acoesPermitidas.contains(acao)) return _json(res, 403, {'erro': 'Ação não permitida: $acao'});
        final corpo = await _lerCorpo(req);
        if (corpo == null) return _json(res, 400, {'erro': 'Corpo inválido.'});
        final r = await agente.chamarLocal(tablet, acao, corpo);
        res.statusCode = r.status;
        res.headers.contentType = ContentType.json;
        res.write(r.corpo);
        return;
      }
      return _json(res, 404, {'erro': 'Não encontrado.'});
    } catch (_) {
      return _json(res, 400, {'erro': 'Requisição inválida.'});
    } finally {
      await res.close();
    }
  }

  /// JSON de objeto até [tamanhoMaximo], ou null.
  static Future<String?> _lerCorpo(HttpRequest req) async {
    final b = BytesBuilder(copy: false);
    await for (final parte in req) {
      b.add(parte);
      if (b.length > tamanhoMaximo) return null;
    }
    final texto = b.isEmpty ? '{}' : utf8.decode(b.takeBytes());
    try {
      return jsonDecode(texto) is Map ? texto : null;
    } on FormatException {
      return null;
    }
  }

  static void _json(HttpResponse res, int status, Map<String, dynamic> dados) {
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(dados));
  }
}
