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

  /// Mensagem na TV do palco. Com nada no ar, o Holyrics esconde as telas (inclusive a do palco):
  /// antes entra um slide em branco no [tema] (no telão, só o fundo do tema), para a mensagem
  /// aparecer. Sem F9 aqui: o Holyrics abre o slide de forma assíncrona e um F9 logo em seguida
  /// falha com "No presentation available".
  /// Com [papelDeParede], o telão mostra o papel de parede do Holyrics (F8) por cima do slide em
  /// branco; o F8 só vale depois que o Holyrics abre o slide, por isso a espera. Falhar aqui
  /// (servidor ou agente sem SetF8) não segura a mensagem: o telão fica no fundo do tema.
  Future<void> mensagemPalco(String texto, {String? tema, bool papelDeParede = false}) async {
    if (await _client.apresentacaoAtual() == null) {
      await _client.projetarTexto(' ', tema: tema);
      if (papelDeParede) {
        try {
          for (var i = 0; i < 20 && await _client.apresentacaoAtual() == null; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 150));
          }
          await _client.papelDeParede(true);
        } catch (_) {}
      }
    }
    await _client.mensagemPalco(texto);
    await atualizar();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
