import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../cartazes.dart';
import '../config.dart';
import '../holyrics.dart';

/// Configuração do agente (agente.json, ao lado do diako_agente.exe).
class AgenteConfig {
  AgenteConfig({
    required this.servidor,
    required this.chaveAgente,
    this.holyricsHost = '127.0.0.1',
    this.holyricsPorta = 8091,
    required this.holyricsToken,
    required this.pastaImagensHolyrics,
  });

  /// Endereço do servidor na internet, ex: https://diako.minhaigreja.com.br
  final String servidor;
  final String chaveAgente;
  final String holyricsHost;
  final int holyricsPorta;
  final String holyricsToken;
  final String pastaImagensHolyrics;

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
    final servidor = (j['servidor'] as String? ?? '').trim().replaceAll(RegExp(r'/+$'), '');
    final chave = (j['chaveAgente'] as String? ?? '').trim();
    final pasta = (j['pastaImagensHolyrics'] as String? ?? '').trim();
    if (!servidor.startsWith('http')) throw const FormatException('Defina "servidor" (ex: https://diako.minhaigreja.com.br).');
    if (chave.isEmpty) throw const FormatException('Defina "chaveAgente" (mostrada na instalação do servidor).');
    if (pasta.isEmpty) throw const FormatException('Defina "pastaImagensHolyrics" (pasta de imagens do Holyrics).');
    return AgenteConfig(
      servidor: servidor,
      chaveAgente: chave,
      holyricsHost: h['host'] as String? ?? '127.0.0.1',
      holyricsPorta: (h['porta'] as num?)?.toInt() ?? 8091,
      holyricsToken: h['token'] as String? ?? '',
      pastaImagensHolyrics: pasta,
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
  Agente(this.config, {this.versao = 'dev', http.Client? cliente, http.Client? clienteHolyrics, void Function(String)? log})
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

  WebSocketChannel? _canal;
  Timer? _timerSync;
  bool _parado = false;
  bool _sincronizando = false;
  Duration _espera = const Duration(seconds: 2);

  late final _sync = SincronizadorCartazes(pasta: config.pastaCartazes, baixar: _baixarCartaz);

  /// Conecta e reconecta para sempre (até [parar]).
  Future<void> rodar() async {
    _timerSync = Timer.periodic(const Duration(minutes: 10), (_) => sincronizar());
    while (!_parado) {
      await _conectarUmaVez();
      if (_parado) break;
      _log('Reconectando em ${_espera.inSeconds}s...');
      await Future.delayed(_espera);
      _espera = Duration(seconds: (_espera.inSeconds * 2).clamp(2, 60));
    }
  }

  Future<void> _conectarUmaVez() async {
    try {
      final canal = IOWebSocketChannel.connect(config.uriWs, pingInterval: const Duration(seconds: 25));
      await canal.ready;
      _canal = canal;
      _espera = const Duration(seconds: 2);
      _log('Conectado a ${config.servidor}.');
      canal.sink.add(jsonEncode({'tipo': 'ola', 'versao': versao}));
      unawaited(sincronizar());
      await for (final msg in canal.stream) {
        unawaited(_tratar(msg as String));
      }
      _log('Conexão encerrada pelo servidor (${canal.closeCode ?? '-'} ${canal.closeReason ?? ''}).');
    } catch (e) {
      _log('Sem conexão com o servidor: ${_resumo(e)}');
    } finally {
      _canal = null;
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
        if (acao != 'GetCurrentPresentation' && acao != 'GetCPInfo') _log('Holyrics: $acao');
      case 'sincronizar':
        await sincronizar();
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
      if (resultado.baixados.isNotEmpty || resultado.apagados.isNotEmpty) _log('Cartazes: $resultado.');
    } catch (e) {
      _log('Falha ao sincronizar cartazes: ${_resumo(e)}');
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
    await _canal?.sink.close();
  }

  static String _resumo(Object e) => e.toString().split('\n').first;
}
