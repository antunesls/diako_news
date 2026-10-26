import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'holyrics.dart';

/// Ponte com o Holyrics quando o servidor está na internet: os comandos vão pelo
/// WebSocket do agente instalado no PC da igreja, que os repassa ao Holyrics local.
///
/// Mensagens servidor → agente: {"tipo":"holyrics","id","acao","corpo"} e {"tipo":"sincronizar"}.
/// Mensagens agente → servidor: {"tipo":"resposta","id","status","corpo"} e {"tipo":"ola","versao"}.
class HolyricsViaAgente extends PonteHolyrics {
  HolyricsViaAgente({this.timeout = const Duration(seconds: 8), DateTime Function()? relogio})
      : _agora = relogio ?? DateTime.now;

  final Duration timeout;
  final DateTime Function() _agora;

  WebSocketChannel? _canal;
  final Map<String, Completer<RespostaHolyrics>> _pendentes = {};
  int _sequencia = 0;

  /// Última mensagem recebida do agente.
  DateTime? vistoEm;
  String? versaoAgente;

  bool get agenteConectado => _canal != null;

  /// Registra a conexão do agente. Uma conexão nova substitui a anterior.
  void conectar(WebSocketChannel canal) {
    final anterior = _canal;
    _canal = canal;
    vistoEm = _agora();
    anterior?.sink.close(4000, 'Substituído por uma nova conexão');
    canal.stream.listen(
      (msg) => _receber(msg),
      onDone: () => _desconectou(canal),
      onError: (_) => _desconectou(canal),
    );
  }

  /// Derruba a conexão atual (ex: depois de trocar a chave do agente).
  void desconectar() {
    final canal = _canal;
    if (canal == null) return;
    _desconectou(canal);
    canal.sink.close(4001, 'Chave do agente alterada');
  }

  /// Pede ao agente para sincronizar os cartazes (ex: depois de um upload).
  void pedirSincronizacao() => _enviar({'tipo': 'sincronizar'});

  @override
  Future<RespostaHolyrics> chamar(String acao, String corpoJson) {
    if (_canal == null) {
      return Future.value(erroHolyrics('O PC da igreja (agente DiakoNews) está desconectado.'));
    }
    final id = '${++_sequencia}';
    final completer = Completer<RespostaHolyrics>();
    _pendentes[id] = completer;
    _enviar({'tipo': 'holyrics', 'id': id, 'acao': acao, 'corpo': corpoJson});
    return completer.future.timeout(timeout, onTimeout: () {
      _pendentes.remove(id);
      return erroHolyrics('O PC da igreja não respondeu a tempo.');
    });
  }

  void _receber(dynamic msg) {
    vistoEm = _agora();
    final Map j;
    try {
      j = jsonDecode(msg as String) as Map;
    } catch (_) {
      return;
    }
    switch (j['tipo']) {
      case 'resposta':
        final c = _pendentes.remove(j['id']);
        c?.complete(RespostaHolyrics((j['status'] as num?)?.toInt() ?? 200, j['corpo'] as String? ?? ''));
      case 'ola':
        versaoAgente = j['versao'] as String?;
    }
  }

  void _desconectou(WebSocketChannel canal) {
    if (!identical(_canal, canal)) return;
    _canal = null;
    for (final c in _pendentes.values) {
      c.complete(erroHolyrics('A conexão com o PC da igreja caiu.'));
    }
    _pendentes.clear();
  }

  void _enviar(Map<String, dynamic> msg) => _canal?.sink.add(jsonEncode(msg));
}
