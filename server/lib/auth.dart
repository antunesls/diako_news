import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

import 'permissoes.dart';
import 'usuarios.dart';

/// Quem está usando o painel/app nesta requisição.
class Conta {
  const Conta({required this.id, required this.nome, required this.login, required this.perfil});

  /// A conta principal: a senha do painel definida na instalação (config.json / /admin).
  static const principal =
      Conta(id: Auth.idPrincipal, nome: 'Administrador', login: Auth.idPrincipal, perfil: Perfil.administrador);

  final String id;
  final String nome;
  final String login;
  final Perfil perfil;

  bool get ehPrincipal => id == Auth.idPrincipal;
  bool pode(Permissao p) => perfil.pode(p);
}

class _Sessao {
  _Sessao(this.expira, this.usuario);
  final DateTime expira;

  /// Id do usuário ([Auth.idPrincipal] para a conta principal).
  final String usuario;
}

/// Login por usuário e senha (ou só a senha principal, que entra como "admin"), com sessões
/// persistidas em data/sessoes.json (o tablet não precisa logar de novo quando o servidor reinicia).
class Auth {
  /// Use [senha] (fixa) ou [conferirSenha] (ex: Configuracoes.conferirSenha, que permite trocar pelo painel).
  Auth({String? senha, bool Function(String)? conferirSenha, required String pastaDados, this.usuarios})
      : _conferir = conferirSenha ?? ((s) => iguaisSeguro(s, senha ?? '')),
        _arquivo = File(p.join(pastaDados, 'sessoes.json'));

  static const idPrincipal = 'admin';

  /// Usuários individuais (sem eles, só a conta principal entra).
  final Usuarios? usuarios;
  final bool Function(String) _conferir;
  final File _arquivo;
  final Map<String, _Sessao> _sessoes = {};
  final _tentativas = LimiteTaxa(maximo: 5, janela: const Duration(minutes: 1));
  final _tentativasPorLogin = LimiteTaxa(maximo: 10, janela: const Duration(minutes: 15));

  static const validade = Duration(days: 90);

  Future<void> carregar() async {
    if (!await _arquivo.exists()) return;
    final j = jsonDecode(await _arquivo.readAsString()) as Map<String, dynamic>;
    final agora = DateTime.now();
    j.forEach((token, valor) {
      // Formato antigo (token -> data): sessões da senha única, que agora é a conta principal.
      final d = DateTime.tryParse((valor is Map ? valor['expira'] : valor) as String? ?? '');
      final usuario = valor is Map ? valor['usuario'] as String? ?? idPrincipal : idPrincipal;
      if (d != null && d.isAfter(agora)) _sessoes[token] = _Sessao(d, usuario);
    });
  }

  /// Retorna o token de sessão, ou null se o usuário ou a senha estiverem errados.
  /// [usuario] vazio (ou "admin") entra com a senha principal.
  /// Lança [LimiteExcedido] após muitas tentativas do mesmo IP ou do mesmo usuário.
  Future<String?> login(String senhaInformada, String ip, {String usuario = ''}) async {
    if (!_tentativas.permitir(ip)) throw LimiteExcedido();
    final login = usuario.trim().toLowerCase();
    if (!_tentativasPorLogin.permitir(login.isEmpty ? idPrincipal : login)) throw LimiteExcedido();
    String? id;
    if (login.isEmpty || login == idPrincipal) {
      if (_conferir(senhaInformada)) id = idPrincipal;
    } else {
      id = (await usuarios?.autenticar(login, senhaInformada))?.id;
    }
    if (id == null) return null;
    final bytes = List<int>.generate(32, (_) => _rng.nextInt(256));
    final token = base64Url.encode(bytes).replaceAll('=', '');
    _sessoes[token] = _Sessao(DateTime.now().add(validade), id);
    await _salvar();
    return token;
  }

  Future<void> logout(String token) async {
    if (_sessoes.remove(token) != null) await _salvar();
  }

  /// Aparelhos conectados (sessões válidas).
  int get quantidade => _sessoes.values.where((s) => s.expira.isAfter(DateTime.now())).length;

  /// Desconecta todos os aparelhos, menos a sessão [manter] (quem pediu). Retorna quantos saíram.
  Future<int> encerrarOutras(String? manter) async {
    final antes = _sessoes.length;
    _sessoes.removeWhere((t, _) => t != manter);
    await _salvar();
    return antes - _sessoes.length;
  }

  /// Desconecta os aparelhos de um usuário (perfil trocado, senha redefinida, desativado, excluído).
  Future<int> encerrarDoUsuario(String id, {String? manter}) async {
    final antes = _sessoes.length;
    _sessoes.removeWhere((t, s) => s.usuario == id && t != manter);
    if (_sessoes.length != antes) await _salvar();
    return antes - _sessoes.length;
  }

  /// Confere a senha principal sem criar sessão (ex: para trocar a senha).
  bool conferir(String senha) => _conferir(senha);

  /// Conta dona do token, ou null (token inválido, vencido ou usuário desativado/excluído).
  Conta? contaDe(String? token) {
    final s = token == null ? null : _sessoes[token];
    if (s == null || !s.expira.isAfter(DateTime.now())) return null;
    if (s.usuario == idPrincipal) return Conta.principal;
    final u = usuarios?.buscar(s.usuario);
    if (u == null || !u.ativo) return null;
    return Conta(id: u.id, nome: u.nome, login: u.login, perfil: u.perfil);
  }

  bool valido(String? token) => contaDe(token) != null;

  /// Conta guardada na requisição pelo [middleware] (null em rotas públicas).
  static Conta? contaDa(Request req) => req.context[_chaveConta] as Conta?;
  static const _chaveConta = 'diako.conta';

  /// Token do cabeçalho "Authorization: Bearer ..." ou do parâmetro ?token= (WebSocket).
  static String? tokenDe(Request req) {
    final h = req.headers['authorization'];
    if (h != null && h.startsWith('Bearer ')) return h.substring(7).trim();
    return req.url.queryParameters['token'];
  }

  Middleware middleware(bool Function(Request) publica) => (inner) => (req) {
        if (publica(req)) return inner(req);
        final conta = contaDe(tokenDe(req));
        if (conta != null) return inner(req.change(context: {_chaveConta: conta}));
        return Response(401, body: jsonEncode({'erro': 'Faça login.'}), headers: jsonHeaders);
      };

  Future<void> _salvar() async {
    final tmp = File('${_arquivo.path}.tmp');
    await tmp.writeAsString(jsonEncode(
        _sessoes.map((k, s) => MapEntry(k, {'expira': s.expira.toIso8601String(), 'usuario': s.usuario}))));
    await tmp.rename(_arquivo.path);
  }
}

// ---------- Senhas (PBKDF2) ----------

/// Gera sal e hash (base64) para guardar uma senha.
({String hash, String sal}) gerarHashSenha(String senha) {
  final sal = List<int>.generate(16, (_) => _rng.nextInt(256));
  return (hash: base64.encode(derivarSenha(senha, sal)), sal: base64.encode(sal));
}

bool conferirHashSenha(String senha, {required String hash, required String sal}) {
  if (hash.isEmpty || sal.isEmpty) return false;
  return iguaisSeguro(base64.encode(derivarSenha(senha, base64.decode(sal))), hash);
}

/// PBKDF2-HMAC-SHA256 (um bloco de 32 bytes).
List<int> derivarSenha(String senha, List<int> sal, {int iteracoes = 100000}) {
  final hmac = Hmac(sha256, utf8.encode(senha));
  var u = hmac.convert([...sal, 0, 0, 0, 1]).bytes;
  final t = List<int>.from(u);
  for (var i = 1; i < iteracoes; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < t.length; j++) {
      t[j] ^= u[j];
    }
  }
  return t;
}

/// Senha temporária fácil de ditar (sem letras e números parecidos).
String gerarSenhaTemporaria([int tamanho = 10]) {
  const letras = 'abcdefghjkmnpqrstuvwxyz23456789';
  return List.generate(tamanho, (_) => letras[_rng.nextInt(letras.length)]).join();
}

/// Compara segredos em tempo constante.
bool iguaisSeguro(String a, String b) {
  final x = utf8.encode(a), y = utf8.encode(b);
  var diff = x.length ^ y.length;
  for (var i = 0; i < min(x.length, y.length); i++) {
    diff |= x[i] ^ y[i];
  }
  return diff == 0;
}

/// Gera um segredo aleatório em base64url (ex: chave do agente e do mural).
String gerarSegredo([int bytes = 24]) =>
    base64Url.encode(List<int>.generate(bytes, (_) => _rng.nextInt(256))).replaceAll('=', '');

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

/// IP de quem fez a requisição. Atrás de um proxy reverso (Caddy) de confiança,
/// usa o primeiro endereço do X-Forwarded-For, que é o do visitante.
String ipDe(Request req, {bool confiarProxy = false}) {
  if (confiarProxy) {
    final xff = req.headers['x-forwarded-for'];
    if (xff != null && xff.trim().isNotEmpty) return xff.split(',').first.trim();
  }
  final info = req.context['shelf.io.connection_info'];
  return info is HttpConnectionInfo ? info.remoteAddress.address : 'desconhecido';
}
