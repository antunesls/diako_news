import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../auth.dart' show iguaisSeguro;
import '../cartazes.dart';
import '../config.dart';
import '../historico.dart';
import '../holyrics.dart';
import '../store.dart' show novoId;
import '../tablets_locais.dart' show hashTokenLocal;

/// Configuração do agente (agente.json, ao lado do diako_agente.exe).
class AgenteConfig {
  AgenteConfig({
    required this.servidor,
    required this.chaveAgente,
    this.holyricsHost = '127.0.0.1',
    this.holyricsPorta = 8091,
    required this.holyricsToken,
    required this.pastaImagensHolyrics,
    this.monitorPorta = 8096,
    this.monitorHash = '',
    this.monitorSal = '',
    this.apiLocalPorta = 8097,
  });

  /// Endereço do servidor na internet, ex: https://diako.minhaigreja.com.br
  final String servidor;
  final String chaveAgente;
  final String holyricsHost;
  final int holyricsPorta;
  final String holyricsToken;
  final String pastaImagensHolyrics;
  final int monitorPorta;
  final String monitorHash;
  final String monitorSal;

  /// Porta em que os tablets pareados falam direto com o agente na rede da igreja; 0 desliga.
  final int apiLocalPorta;

  /// Subpasta gerenciada pelo agente dentro da biblioteca de imagens do Holyrics.
  String get pastaCartazes => p.join(pastaImagensHolyrics, Config.subpastaHolyrics);

  Uri get uriWs {
    final u = Uri.parse(servidor);
    return u.replace(
      scheme: u.scheme == 'https' ? 'wss' : 'ws',
      path: '/agente/ws',
      queryParameters: {'chave': chaveAgente},
    );
  }

  static AgenteConfig lerJson(String texto) {
    if (texto.startsWith('﻿')) texto = texto.substring(1);
    final j = jsonDecode(texto) as Map<String, dynamic>;
    final h = (j['holyrics'] as Map?)?.cast<String, dynamic>() ?? const {};
    final monitor = (j['monitor'] as Map?)?.cast<String, dynamic>() ?? const {};
    final servidor = (j['servidor'] as String? ?? '').trim().replaceAll(RegExp(r'/+$'), '');
    final chave = (j['chaveAgente'] as String? ?? '').trim();
    final pasta = (j['pastaImagensHolyrics'] as String? ?? '').trim();
    final url = Uri.tryParse(servidor);
    if (url == null || !{'http', 'https'}.contains(url.scheme) || url.host.isEmpty ||
        url.userInfo.isNotEmpty || url.hasQuery || url.hasFragment || url.path.isNotEmpty && url.path != '/') {
      throw const FormatException('Defina "servidor" sem usuário, senha ou parâmetros (ex: https://diako.minhaigreja.com.br).');
    }
    if (chave.isEmpty) throw const FormatException('Defina "chaveAgente" (mostrada na instalação do servidor).');
    if (pasta.isEmpty) throw const FormatException('Defina "pastaImagensHolyrics" (pasta de imagens do Holyrics).');
    final monitorPorta = (monitor['porta'] as num?)?.toInt() ?? 8096;
    if (monitorPorta < 1 || monitorPorta > 65535) throw const FormatException('Porta do monitor inválida.');
    final apiLocal = (j['apiLocal'] as Map?)?.cast<String, dynamic>() ?? const {};
    final apiLocalPorta = (apiLocal['porta'] as num?)?.toInt() ?? 8097;
    if (apiLocalPorta < 0 || apiLocalPorta > 65535 || apiLocalPorta == monitorPorta) {
      throw const FormatException('Porta da API local inválida (use 0 para desligar).');
    }
    return AgenteConfig(
      servidor: servidor,
      chaveAgente: chave,
      holyricsHost: h['host'] as String? ?? '127.0.0.1',
      holyricsPorta: (h['porta'] as num?)?.toInt() ?? 8091,
      holyricsToken: h['token'] as String? ?? '',
      pastaImagensHolyrics: pasta,
      monitorPorta: monitorPorta,
      monitorHash: monitor['hash'] as String? ?? '',
      monitorSal: monitor['sal'] as String? ?? '',
      apiLocalPorta: apiLocalPorta,
    );
  }
}

/// Resultado de uma sincronização de cartazes.
class ResultadoSync {
  final baixados = <String>[];
  final apagados = <String>[];
  @override
  String toString() => '${baixados.length} baixado(s), ${apagados.length} apagado(s)';
}

/// Mantém a pasta local igual à lista de cartazes do servidor.
/// Só toca em arquivos de imagem dentro da própria pasta (nunca fora dela).
class SincronizadorCartazes {
  SincronizadorCartazes({required this.pasta, required this.baixar});

  final String pasta;

  /// Baixa o conteúdo de um arquivo pelo nome.
  final Future<List<int>> Function(String nome) baixar;

  static bool nomeValido(String nome) => Cartazes.nomeValido(nome);

  /// [remotos]: [{nome, tamanho, modificado}] vindos do servidor.
  Future<ResultadoSync> sincronizar(List<Map<String, dynamic>> remotos) async {
    final r = ResultadoSync();
    final dir = Directory(pasta);
    await dir.create(recursive: true);

    final esperados = <String>{};
    for (final item in remotos) {
      final nome = item['nome'] as String? ?? '';
      if (!nomeValido(nome)) continue;
      esperados.add(nome);
      final modificado = DateTime.tryParse(item['modificado'] as String? ?? '');
      final local = File(p.join(pasta, nome));
      if (await local.exists()) {
        final s = await local.stat();
        final mesmaData = modificado == null || s.modified.toUtc().difference(modificado).inSeconds.abs() < 2;
        if (s.size == item['tamanho'] && mesmaData) continue;
      }
      final bytes = await baixar(nome);
      final tmp = File('${local.path}.baixando');
      await tmp.writeAsBytes(bytes, flush: true);
      if (await local.exists()) await local.delete();
      await tmp.rename(local.path);
      if (modificado != null) await local.setLastModified(modificado);
      r.baixados.add(nome);
    }

    await for (final e in dir.list()) {
      if (e is! File) continue;
      final nome = p.basename(e.path);
      if (nomeValido(nome) && !esperados.contains(nome)) {
        await e.delete();
        r.apagados.add(nome);
      }
    }
    return r;
  }
}

/// Agente que roda no PC da igreja: liga o servidor da internet ao Holyrics local.
class Agente {
  /// [cliente] fala com o servidor; [clienteHolyrics] com o Holyrics local (separados para testes).
  /// [pastaDados] guarda a lista de tablets e a fila do histórico (sem ela, ficam só na memória).
  Agente(this.config,
      {this.versao = 'dev', this.pastaDados, http.Client? cliente, http.Client? clienteHolyrics, void Function(String)? log})
      : _http = cliente ?? http.Client(),
        _log = log ?? ((m) => stdout.writeln('[${DateTime.now().toIso8601String().substring(0, 19)}] $m')),
        _holyrics = HolyricsDireto(
          host: config.holyricsHost,
          porta: config.holyricsPorta,
          token: config.holyricsToken,
          cliente: clienteHolyrics,
        );

  final AgenteConfig config;
  final String versao;
  final http.Client _http;
  final void Function(String) _log;
  final HolyricsDireto _holyrics;
  final String? pastaDados;

  /// Tablets pareados ({id, hash, nome}), recebidos do servidor e guardados em tablets.json.
  List<Map<String, String>> _tablets = [];

  /// Projeções feitas pela rede local que o servidor ainda não confirmou (historico-pendente.json).
  final List<Map<String, dynamic>> _historicoPendente = [];
  static const maximoPendentes = 1000;
  int chamadasLocais = 0;
  DateTime? ultimaLocalEm;
  int? ultimaLocalMs;

  WebSocketChannel? _canal;
  Timer? _timerSync;
  Timer? _timerHolyrics;
  bool _parado = false;
  bool _sincronizando = false;
  Duration _espera = const Duration(seconds: 2);
  bool backendConectado = false;
  DateTime? conectadoEm;
  DateTime? ultimaMensagem;
  DateTime? ultimaSincronizacao;
  String? erroSincronizacao;
  int reconexoes = 0;
  String? erroBackend;
  int cartazesRemotos = 0;
  int cartazesBaixados = 0;
  int cartazesApagados = 0;
  bool? holyricsConectado;
  DateTime? holyricsVerificadoEm;
  int? holyricsLatenciaMs;
  final List<Map<String, String>> eventos = [];

  void registrar(String categoria, String mensagem, {String nivel = 'info'}) {
    // Histórico estruturado; proteção adicional contra inclusão acidental de credenciais.
    var seguro = mensagem.replaceAll(RegExp(r'[\r\n\t]'), ' ');
    for (final segredo in [config.chaveAgente, config.holyricsToken]) {
      if (segredo.isNotEmpty) {
        seguro = seguro.replaceAll(segredo, '[oculto]').replaceAll(Uri.encodeComponent(segredo), '[oculto]');
      }
    }
    seguro = seguro.replaceAll(RegExp(r'(token|chave|dtoken)=([^&\s]+)', caseSensitive: false), '[oculto]');
    eventos.add({'quando': DateTime.now().toIso8601String(), 'tipo': categoria,
      'nivel': nivel == 'erro' ? 'erro' : 'info', 'mensagem': seguro.length > 250 ? seguro.substring(0, 250) : seguro});
    if (eventos.length > 200) eventos.removeAt(0);
  }

  Map<String, dynamic> get estado => {
        'versao': versao,
        'servidor': config.servidor,
        'backendConectado': backendConectado,
        'conectadoEm': conectadoEm?.toIso8601String(),
        'ultimaMensagem': ultimaMensagem?.toIso8601String(),
        'reconexoes': reconexoes,
        'erroBackend': erroBackend,
        'holyricsHost': config.holyricsHost,
        'holyricsPorta': config.holyricsPorta,
        'holyricsConfigurado': config.holyricsToken.isNotEmpty,
        'holyricsConectado': holyricsConectado,
        'holyricsVerificadoEm': holyricsVerificadoEm?.toIso8601String(),
        'holyricsLatenciaMs': holyricsLatenciaMs,
        'pastaCartazes': config.pastaCartazes,
        'sincronizando': _sincronizando,
        'ultimaSincronizacao': ultimaSincronizacao?.toIso8601String(),
        'erroSincronizacao': erroSincronizacao,
        'cartazesRemotos': cartazesRemotos,
        'cartazesBaixados': cartazesBaixados,
        'cartazesApagados': cartazesApagados,
        'apiLocalPorta': config.apiLocalPorta,
        'tabletsPareados': [for (final t in _tablets) t['nome']],
        'chamadasLocais': chamadasLocais,
        'ultimaLocalEm': ultimaLocalEm?.toIso8601String(),
        'ultimaLocalMs': ultimaLocalMs,
        'historicoPendente': _historicoPendente.length,
      };

  // ---------- Tablets na rede local ----------

  File? _arquivo(String nome) => pastaDados == null ? null : File(p.join(pastaDados!, nome));

  /// Lê a lista de tablets e a fila do histórico gravadas antes (o PC pode reiniciar sem internet).
  Future<void> carregarDados() async {
    try {
      final t = _arquivo('tablets.json');
      if (t != null && await t.exists()) _tablets = _lerTablets(jsonDecode(await t.readAsString()));
      final h = _arquivo('historico-pendente.json');
      if (h != null && await h.exists()) {
        _historicoPendente.addAll([for (final e in jsonDecode(await h.readAsString()) as List) Map<String, dynamic>.from(e as Map)]);
      }
    } catch (_) {
      registrar('local', 'Arquivo de tablets ou do histórico pendente ilegível; aguardando o servidor', nivel: 'erro');
    }
  }

  static List<Map<String, String>> _lerTablets(Object? lista) => [
        for (final t in (lista as List? ?? const []))
          if (t is Map && t['id'] is String && t['hash'] is String)
            {'id': t['id'] as String, 'hash': t['hash'] as String, 'nome': t['nome'] as String? ?? ''},
      ];

  Future<void> _gravar(String nome, Object dados) async {
    final f = _arquivo(nome);
    if (f == null) return;
    try {
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(dados), flush: true);
      await tmp.rename(f.path);
    } catch (_) {
      registrar('local', 'Não foi possível gravar $nome', nivel: 'erro');
    }
  }

  /// Tablet dono do token, ou null. Compara só hashes (o agente nunca guarda o token).
  Map<String, String>? tabletDoToken(String token) {
    if (token.isEmpty) return null;
    final hash = hashTokenLocal(token);
    Map<String, String>? achado;
    for (final t in _tablets) {
      if (iguaisSeguro(t['hash']!, hash)) achado = t;
    }
    return achado;
  }

  /// Comando vindo direto de um tablet pareado. Projeções entram na fila do histórico do servidor.
  Future<RespostaHolyrics> chamarLocal(Map<String, String> tablet, String acao, String corpo) async {
    final inicio = DateTime.now();
    final r = await _holyrics.chamar(acao, corpo);
    chamadasLocais++;
    ultimaLocalEm = DateTime.now();
    ultimaLocalMs = ultimaLocalEm!.difference(inicio).inMilliseconds;
    if (!{'GetCurrentPresentation', 'GetCPInfo', 'GetThumbnail', 'GetThemes'}.contains(acao)) {
      registrar('local', '$acao (${tablet['nome']}, ${ultimaLocalMs}ms)');
    }
    if (Historico.acoes.contains(acao) && _respostaOk(r.corpo)) {
      _historicoPendente.add({'id': novoId(), 'quando': inicio.toUtc().toIso8601String(), 'acao': acao,
        'corpo': corpo, 'tablet': tablet['id']});
      if (_historicoPendente.length > maximoPendentes) _historicoPendente.removeAt(0);
      await _gravar('historico-pendente.json', _historicoPendente);
      _enviarHistorico();
    }
    return r;
  }

  static bool _respostaOk(String corpo) {
    try {
      return (jsonDecode(corpo) as Map)['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  void _enviarHistorico() {
    if (_canal == null || _historicoPendente.isEmpty) return;
    _canal!.sink.add(jsonEncode({'tipo': 'historico', 'eventos': _historicoPendente.take(100).toList()}));
  }

  Future<RespostaHolyrics> consultarHolyrics(String acao, [String corpo = '{}']) {
    if (!{'GetCPInfo', 'GetCurrentPresentation', 'GetThemes', 'GetThumbnail',
      'ShowQuickPresentation', 'ActionNextQuickPresentation', 'ActionPreviousQuickPresentation'}.contains(acao)) {
      throw ArgumentError.value(acao, 'acao', 'Ação não permitida pelo monitor');
    }
    return _holyrics.chamar(acao, corpo);
  }

  late final _sync = SincronizadorCartazes(pasta: config.pastaCartazes, baixar: _baixarCartaz);

  /// Conecta e reconecta para sempre (até [parar]).
  Future<void> rodar() async {
    _timerSync = Timer.periodic(const Duration(minutes: 10), (_) => sincronizar());
    _timerHolyrics = Timer.periodic(const Duration(seconds: 30), (_) => unawaited(verificarHolyrics()));
    while (!_parado) {
      await _conectarUmaVez();
      if (_parado) break;
      _log('Reconectando em ${_espera.inSeconds}s...');
      await Future.delayed(_espera);
      _espera = Duration(seconds: (_espera.inSeconds * 2).clamp(2, 60));
    }
  }

  Future<void> verificarHolyrics() async {
    final inicio = DateTime.now();
    final conectado = await _holyrics.conectado();
    if (holyricsConectado != conectado) registrar('holyrics', conectado ? 'Conectado' : 'Sem resposta do Holyrics',
        nivel: conectado ? 'info' : 'erro');
    holyricsConectado = conectado;
    holyricsVerificadoEm = DateTime.now();
    holyricsLatenciaMs = holyricsVerificadoEm!.difference(inicio).inMilliseconds;
  }

  Future<void> _conectarUmaVez() async {
    try {
      final canal = IOWebSocketChannel.connect(config.uriWs, pingInterval: const Duration(seconds: 25));
      await canal.ready;
      _canal = canal;
      backendConectado = true;
      erroBackend = null;
      conectadoEm = DateTime.now();
      ultimaMensagem = conectadoEm;
      registrar('backend', 'Conectado');
      _espera = const Duration(seconds: 2);
      _log('Conectado a ${config.servidor}.');
      canal.sink.add(jsonEncode({'tipo': 'ola', 'versao': versao}));
      _enviarHistorico();
      unawaited(sincronizar());
      await for (final msg in canal.stream) {
        ultimaMensagem = DateTime.now();
        unawaited(_tratar(msg as String));
      }
      _log('Conexão encerrada pelo servidor (${canal.closeCode ?? '-'}).');
      erroBackend = 'Conexão encerrada (código ${canal.closeCode ?? '-'})';
      registrar('backend', 'Conexão encerrada');
    } catch (e) {
      erroBackend = e is SocketException ? 'Rede ou DNS indisponível' :
          e is WebSocketException ? 'WebSocket recusado; confira chave e URL' : 'Falha na conexão; confira chave e URL';
      registrar('backend', 'Falha de conexão (verifique endereço, rede e chave)', nivel: 'erro');
      _log('Sem conexão com o servidor (verifique endereço, rede e chave).');
    } finally {
      _canal = null;
      backendConectado = false;
      if (!_parado) reconexoes++;
    }
  }

  Future<void> _tratar(String msg) async {
    final Map j;
    try {
      j = jsonDecode(msg) as Map;
    } catch (_) {
      return;
    }
    switch (j['tipo']) {
      case 'holyrics':
        final acao = j['acao'] as String? ?? '';
        final r = await _holyrics.chamar(acao, j['corpo'] as String? ?? '{}');
        _canal?.sink.add(jsonEncode({'tipo': 'resposta', 'id': j['id'], 'status': r.status, 'corpo': r.corpo}));
        if (!{'GetCurrentPresentation', 'GetCPInfo', 'GetThumbnail', 'GetThemes'}.contains(acao)) {
          if (acoesPermitidas.contains(acao)) _log('Holyrics: $acao');
          registrar('holyrics', acoesPermitidas.contains(acao) ? acao : 'Ação não reconhecida');
        }
      case 'sincronizar':
        await sincronizar();
      case 'tablets':
        _tablets = _lerTablets(j['lista']);
        registrar('local', '${_tablets.length} tablet(s) pareado(s)');
        await _gravar('tablets.json', _tablets);
      case 'historico-ok':
        final ids = {for (final id in (j['ids'] as List? ?? const [])) '$id'};
        final antes = _historicoPendente.length;
        _historicoPendente.removeWhere((e) => ids.contains(e['id']));
        if (_historicoPendente.length != antes) {
          await _gravar('historico-pendente.json', _historicoPendente);
          _enviarHistorico(); // próximo lote, se houver
        }
    }
  }

  /// Copia os cartazes do servidor para a pasta de imagens do Holyrics.
  Future<void> sincronizar() async {
    if (_sincronizando) return;
    _sincronizando = true;
    try {
      final uri = Uri.parse('${config.servidor}/agente/cartazes').replace(queryParameters: {'chave': config.chaveAgente});
      final r = await _http.get(uri).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw HttpException('HTTP ${r.statusCode}');
      final lista = [for (final e in jsonDecode(utf8.decode(r.bodyBytes)) as List) Map<String, dynamic>.from(e as Map)];
      final resultado = await _sync.sincronizar(lista);
      ultimaSincronizacao = DateTime.now();
      erroSincronizacao = null;
      cartazesRemotos = lista.length;
      cartazesBaixados = resultado.baixados.length;
      cartazesApagados = resultado.apagados.length;
      registrar('cartazes', 'Sincronização concluída: $resultado');
      if (resultado.baixados.isNotEmpty || resultado.apagados.isNotEmpty) _log('Cartazes: $resultado.');
    } catch (_) {
      erroSincronizacao = 'Verifique conexão com o backend e acesso à pasta de cartazes.';
      registrar('cartazes', 'Falha ao sincronizar cartazes', nivel: 'erro');
      _log('Falha ao sincronizar cartazes. $erroSincronizacao');
    } finally {
      _sincronizando = false;
    }
  }

  Future<List<int>> _baixarCartaz(String nome) async {
    final uri = Uri.parse('${config.servidor}/agente/cartazes/${Uri.encodeComponent(nome)}')
        .replace(queryParameters: {'chave': config.chaveAgente});
    final r = await _http.get(uri).timeout(const Duration(minutes: 2));
    if (r.statusCode != 200) throw HttpException('HTTP ${r.statusCode} ao baixar $nome');
    return r.bodyBytes;
  }

  Future<void> parar() async {
    _parado = true;
    _timerSync?.cancel();
    _timerHolyrics?.cancel();
    await _canal?.sink.close();
  }

}
