import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

/// Login por senha única do administrador, com sessões persistidas em data/sessoes.json
/// (o tablet não precisa logar de novo quando o servidor reinicia).
class Auth {
  Auth({required this.senha, required String pastaDados}) : _arquivo = File(p.join(pastaDados, 'sessoes.json'));

  final String senha;
  final File _arquivo;
  final Map<String, DateTime> _sessoes = {};
  final _tentativas = LimiteTaxa(maximo: 5, janela: const Duration(minutes: 1));

  static const validade = Duration(days: 90);

  Future<void> carregar() async {
    if (!await _arquivo.exists()) return;
    final j = jsonDecode(await _arquivo.readAsString()) as Map<String, dynamic>;
    final agora = DateTime.now();
    j.forEach((token, expira) {
      final d = DateTime.tryParse(expira as String);
      if (d != null && d.isAfter(agora)) _sessoes[token] = d;
    });
  }

  /// Retorna o token de sessão, ou null se a senha estiver errada.
  /// Lança [LimiteExcedido] após muitas tentativas do mesmo IP.
  Future<String?> login(String senhaInformada, String ip) async {
    if (!_tentativas.permitir(ip)) throw LimiteExcedido();
    if (!_iguais(senhaInformada, senha)) return null;
    final bytes = List<int>.generate(32, (_) => _rng.nextInt(256));
    final token = base64Url.encode(bytes).replaceAll('=', '');
    _sessoes[token] = DateTime.now().add(validade);
    await _salvar();
    return token;
  }

  Future<void> logout(String token) async {
    if (_sessoes.remove(token) != null) await _salvar();
  }

  bool valido(String? token) {
    if (token == null) return false;
    final expira = _sessoes[token];
    return expira != null && expira.isAfter(DateTime.now());
  }

  /// Token do cabeçalho "Authorization: Bearer ..." ou do parâmetro ?token= (WebSocket).
  static String? tokenDe(Request req) {
    final h = req.headers['authorization'];
    if (h != null && h.startsWith('Bearer ')) return h.substring(7).trim();
    return req.url.queryParameters['token'];
  }

  Middleware middleware(bool Function(Request) publica) => (inner) => (req) {
        if (publica(req) || valido(tokenDe(req))) return inner(req);
        return Response(401, body: jsonEncode({'erro': 'Faça login.'}), headers: jsonHeaders);
      };

  Future<void> _salvar() async {
    final tmp = File('${_arquivo.path}.tmp');
    await tmp.writeAsString(jsonEncode(_sessoes.map((k, v) => MapEntry(k, v.toIso8601String()))));
    await tmp.rename(_arquivo.path);
  }

  // Comparação em tempo constante.
  static bool _iguais(String a, String b) {
    final x = utf8.encode(a), y = utf8.encode(b);
    var diff = x.length ^ y.length;
    for (var i = 0; i < min(x.length, y.length); i++) {
      diff |= x[i] ^ y[i];
    }
    return diff == 0;
  }
}

final _rng = Random.secure();

const jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

class LimiteExcedido implements Exception {}

/// Limita quantas ações cada chave (IP) faz numa janela de tempo.
class LimiteTaxa {
  LimiteTaxa({required this.maximo, required this.janela, DateTime Function()? relogio})
      : _agora = relogio ?? DateTime.now;

  final int maximo;
  final Duration janela;
  final DateTime Function() _agora;
  final Map<String, List<DateTime>> _registros = {};

  bool permitir(String chave) {
    final agora = _agora();
    final lista = _registros.putIfAbsent(chave, () => [])..removeWhere((t) => agora.difference(t) >= janela);
    if (lista.length >= maximo) return false;
    lista.add(agora);
    return true;
  }
}

/// IP de quem fez a requisição.
String ipDe(Request req) {
  final info = req.context['shelf.io.connection_info'];
  return info is HttpConnectionInfo ? info.remoteAddress.address : 'desconhecido';
}
