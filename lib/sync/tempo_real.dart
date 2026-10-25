import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'server_api.dart';

/// Mantém um WebSocket com o servidor e chama [aoMudar] com o tipo alterado
/// ("recados", "motivos", "membros", "cartazes"). Reconecta sozinho.
class TempoReal extends ChangeNotifier {
  TempoReal(this._api, {required this.aoMudar, required this.aoReconectar});

  final ServerApi _api;
  final void Function(String tipo) aoMudar;

  /// Chamado a cada conexão nova, para buscar o que mudou enquanto estava fora.
  final VoidCallback aoReconectar;

  WebSocketChannel? _canal;
  StreamSubscription? _sub;
  Timer? _retentar;
  bool _conectado = false;
  bool _parado = true;

  bool get conectado => _conectado;

  void iniciar() {
    _parado = false;
    _conectar();
  }

  /// Fecha e abre de novo (ex: depois de trocar o servidor ou a senha).
  void reiniciar() {
    _fechar();
    iniciar();
  }

  Future<void> _conectar() async {
    if (_parado) return;
    try {
      final canal = WebSocketChannel.connect(_api.wsUri());
      await canal.ready;
      _canal = canal;
      _definir(true);
      aoReconectar();
      _sub = canal.stream.listen(
        (msg) {
          try {
            final tipo = (jsonDecode(msg as String) as Map)['tipo'];
            if (tipo is String) aoMudar(tipo);
          } catch (_) {}
        },
        onDone: _caiu,
        onError: (_) => _caiu(),
      );
    } catch (_) {
      _caiu();
    }
  }

  void _caiu() {
    _definir(false);
    _sub?.cancel();
    _sub = null;
    _canal = null;
    if (_parado) return;
    _retentar?.cancel();
    _retentar = Timer(const Duration(seconds: 5), _conectar);
  }

  void _definir(bool v) {
    if (_conectado == v) return;
    _conectado = v;
    notifyListeners();
  }

  void _fechar() {
    _parado = true;
    _retentar?.cancel();
    _sub?.cancel();
    _canal?.sink.close();
    _canal = null;
    _definir(false);
  }

  @override
  void dispose() {
    _fechar();
    super.dispose();
  }
}
