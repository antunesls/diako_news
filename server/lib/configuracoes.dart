import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'auth.dart';
import 'config.dart';

/// Configurações que o administrador altera pelo painel (/admin), gravadas em data/configuracoes.json.
/// Os valores do config.json valem como padrão até a primeira alteração pelo painel.
class Configuracoes {
  Configuracoes._(this._arquivo, this._valores, this._senhaInicial, {required this.urlDetectada});

  final File _arquivo;
  final Map<String, dynamic> _valores;

  /// senhaAdmin do config.json, usada enquanto a senha não for trocada pelo painel.
  final String _senhaInicial;

  /// Endereço detectado na rede (http://IP:porta), usado quando urlPublica está vazio.
  final String urlDetectada;

  static const nomeIgrejaPadrao = 'Igreja Diakonia Tulipas';

  /// Campos que nunca saem do servidor nem vão para o backup.
  static const _segredos = {'senhaHash', 'senhaSal', 'chaveAgente', 'holyricsToken'};

  static Future<Configuracoes> carregar(Config config, {required String urlDetectada}) async {
    final arquivo = File(p.join(config.pastaDados, 'configuracoes.json'));
    final valores = <String, dynamic>{
      'nomeIgreja': nomeIgrejaPadrao,
      'urlPublica': config.urlPublica,
      'pedidoTitulo': 'Pedido de oração',
      'pedidoIntro': 'Conte para nós como podemos orar por você. O pastor recebe todos os pedidos.',
      'pedidoObrigado': 'Estaremos orando por você.',
      'chaveMural': config.chaveMural,
      'chaveAgente': config.chaveAgente,
      'holyricsHost': config.holyricsHost,
      'holyricsPorta': config.holyricsPorta,
      'holyricsToken': config.holyricsToken,
      'motivosPorSlide': 4,
      'segundosPorSlide': 10,
      'diasRespondidas': 30,
      'temaPadrao': '',
      'horaBackup': config.horaBackup,
      'backupsManter': 30,
    };
    if (await arquivo.exists()) {
      var texto = await arquivo.readAsString();
      if (texto.startsWith('﻿')) texto = texto.substring(1);
      valores.addAll(Map<String, dynamic>.from(jsonDecode(texto) as Map));
    }
    return Configuracoes._(arquivo, valores, config.senhaAdmin, urlDetectada: urlDetectada);
  }

  String _s(String k) => _valores[k] as String? ?? '';
  int _i(String k, int padrao) => (_valores[k] as num?)?.toInt() ?? padrao;

  String get nomeIgreja => _s('nomeIgreja').isEmpty ? nomeIgrejaPadrao : _s('nomeIgreja');
  String get urlPublica => _s('urlPublica');

  /// Endereço base do site: o público configurado ou o detectado na rede.
  String get urlBase => urlPublica.isNotEmpty ? urlPublica : urlDetectada;
  String get urlOracao => '$urlBase/oracao';
  String get pedidoTitulo => _s('pedidoTitulo');
  String get pedidoIntro => _s('pedidoIntro');
  String get pedidoObrigado => _s('pedidoObrigado');
  String get chaveMural => _s('chaveMural');
  String get chaveAgente => _s('chaveAgente');
  String get holyricsHost => _s('holyricsHost').isEmpty ? '127.0.0.1' : _s('holyricsHost');
  int get holyricsPorta => _i('holyricsPorta', 8091);
  String get holyricsToken => _s('holyricsToken');
  int get motivosPorSlide => _i('motivosPorSlide', 4);
  int get segundosPorSlide => _i('segundosPorSlide', 10);
  int get diasRespondidas => _i('diasRespondidas', 30);
  String get temaPadrao => _s('temaPadrao');
  String get horaBackup => _s('horaBackup').isEmpty ? '03:00' : _s('horaBackup');
  int get backupsManter => _i('backupsManter', 30);

  /// Configurações sem segredos (para o painel e para o backup).
  Map<String, dynamic> publicas() => {
        for (final e in _valores.entries)
          if (!_segredos.contains(e.key)) e.key: e.value,
        'holyricsTokenDefinido': holyricsToken.isNotEmpty,
      };

  /// Aplica alterações vindas do painel, validando cada campo. Lança [FormatException].
  Future<void> atualizar(Map<String, dynamic> mudancas) async {
    final novos = <String, dynamic>{};
    String texto(String k, int max, {bool vazio = true}) {
      final v = (mudancas[k] as String? ?? '').trim();
      if (!vazio && v.isEmpty) throw FormatException('Preencha "$k".');
      if (v.length > max) throw FormatException('"$k" muito longo.');
      return v;
    }

    int inteiro(String k, int min, int max) {
      final v = mudancas[k];
      final n = v is num ? v.toInt() : int.tryParse('$v');
      if (n == null || n < min || n > max) throw FormatException('"$k" deve ser entre $min e $max.');
      return n;
    }

    for (final k in mudancas.keys) {
      switch (k) {
        case 'nomeIgreja':
          novos[k] = texto(k, 80, vazio: false);
        case 'urlPublica':
          final v = texto(k, 200).replaceAll(RegExp(r'/+$'), '');
          if (v.isNotEmpty && !RegExp(r'^https?://[^\s/]+$').hasMatch(v)) {
            throw const FormatException('Endereço público inválido. Use algo como https://diako.minhaigreja.com.br');
          }
          novos[k] = v;
        case 'pedidoTitulo':
          novos[k] = texto(k, 80, vazio: false);
        case 'pedidoIntro' || 'pedidoObrigado':
          novos[k] = texto(k, 300);
        case 'temaPadrao':
          novos[k] = texto(k, 80);
        case 'holyricsHost':
          novos[k] = texto(k, 100, vazio: false);
        case 'holyricsPorta':
          novos[k] = inteiro(k, 1, 65535);
        case 'holyricsToken':
          // Vazio mantém o token atual (o painel nunca recebe o valor).
          final v = texto(k, 200);
          if (v.isNotEmpty) novos[k] = v;
        case 'motivosPorSlide':
          novos[k] = inteiro(k, 1, 8);
        case 'segundosPorSlide':
          novos[k] = inteiro(k, 3, 120);
        case 'diasRespondidas':
          novos[k] = inteiro(k, 1, 365);
        case 'backupsManter':
          novos[k] = inteiro(k, 1, 365);
        case 'horaBackup':
          final v = texto(k, 5, vazio: false);
          if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(v)) throw const FormatException('Horário inválido (use HH:MM).');
          novos[k] = v;
        default:
          throw FormatException('Campo desconhecido: $k');
      }
    }
    _valores.addAll(novos);
    await _salvar();
  }

  /// Restaura configurações públicas de um backup (ignora segredos e campos desconhecidos).
  Future<void> restaurarPublicas(Map<String, dynamic> dados) async {
    final permitidos = {
      'nomeIgreja', 'urlPublica', 'pedidoTitulo', 'pedidoIntro', 'pedidoObrigado', 'chaveMural',
      'holyricsHost', 'holyricsPorta', 'motivosPorSlide', 'segundosPorSlide', 'diasRespondidas',
      'temaPadrao', 'horaBackup', 'backupsManter',
    };
    for (final e in dados.entries) {
      if (permitidos.contains(e.key)) _valores[e.key] = e.value;
    }
    await _salvar();
  }

  /// Nova chave do mural ('' desativa a proteção).
  Future<String> novaChaveMural({bool desativar = false}) async {
    _valores['chaveMural'] = desativar ? '' : gerarSegredo(15);
    await _salvar();
    return chaveMural;
  }

  /// Nova chave do agente (o agente.json do PC da igreja precisa ser atualizado).
  Future<String> novaChaveAgente() async {
    _valores['chaveAgente'] = gerarSegredo(30);
    await _salvar();
    return chaveAgente;
  }

  // ---------- Senha ----------

  bool conferirSenha(String senha) {
    final hash = _s('senhaHash'), sal = _s('senhaSal');
    if (hash.isEmpty || sal.isEmpty) return iguaisSeguro(senha, _senhaInicial);
    return iguaisSeguro(base64.encode(_derivar(senha, base64.decode(sal))), hash);
  }

  Future<void> trocarSenha(String nova, {required int minimo}) async {
    if (nova.trim().length < minimo) throw FormatException('A senha precisa ter pelo menos $minimo caracteres.');
    final sal = List<int>.generate(16, (_) => _rng.nextInt(256));
    _valores['senhaSal'] = base64.encode(sal);
    _valores['senhaHash'] = base64.encode(_derivar(nova.trim(), sal));
    await _salvar();
  }

  /// PBKDF2-HMAC-SHA256 (um bloco de 32 bytes).
  static List<int> _derivar(String senha, List<int> sal, {int iteracoes = 100000}) {
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

  Future<void> _salvar() async {
    await _arquivo.parent.create(recursive: true);
    final tmp = File('${_arquivo.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(_valores), flush: true);
    await tmp.rename(_arquivo.path);
  }
}

final _rng = Random.secure();
