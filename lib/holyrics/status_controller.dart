import 'dart:async';

import 'package:flutter/foundation.dart';

import '../sync/server_api.dart';
import 'holyrics_client.dart';

enum Conexao { verificando, conectado, desconectado }

/// Consulta o Holyrics (pelo servidor) periodicamente para saber se está conectado e o que está no ar.
class StatusController extends ChangeNotifier {
  StatusController(this._client);

  final HolyricsClient _client;
  Timer? _timer;

  Conexao conexao = Conexao.verificando;
  String? erro;
  Apresentacao? atual;

  // Estado das telas F9/F10 controlado pelo app.
  bool telaVazia = false;
  bool telaPreta = false;

  void iniciar() {
    _timer?.cancel();
    atualizar();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => atualizar());
  }

  Future<void> atualizar() async {
    try {
      atual = await _client.apresentacaoAtual();
      conexao = Conexao.conectado;
      erro = null;
    } on ErroAmigavel catch (e) {
      conexao = Conexao.desconectado;
      erro = e.message;
      atual = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
