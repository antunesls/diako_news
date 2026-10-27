import 'package:flutter/material.dart';

import 'data/agenda_repo.dart';
import 'data/conta_repo.dart';
import 'data/mensagem_repo.dart';
import 'data/motivo_repo.dart';
import 'data/recado_repo.dart';
import 'data/settings.dart';
import 'data/visita_repo.dart';
import 'holyrics/agente_local.dart';
import 'holyrics/holyrics_client.dart';
import 'holyrics/status_controller.dart';
import 'sync/server_api.dart';
import 'sync/tempo_real.dart';

/// Disponibiliza os serviços do app para toda a árvore de widgets.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.repo,
    required this.motivos,
    required this.agenda,
    required this.mensagens,
    required this.visitas,
    required this.conta,
    required this.settings,
    required this.api,
    required this.client,
    required this.agenteLocal,
    required this.status,
    required this.tempoReal,
    required super.child,
  });

  final RecadoRepo repo;
  final MotivoRepo motivos;
  final AgendaRepo agenda;
  final MensagemRepo mensagens;
  final VisitaRepo visitas;

  /// Perfil de quem está logado (o que mostrar e permitir).
  final ContaRepo conta;
  final AppSettings settings;
  final ServerApi api;
  final HolyricsClient client;

  /// Atalho pela rede da igreja até o agente (Configurações › PC da igreja).
  final AgenteLocal agenteLocal;
  final StatusController status;
  final TempoReal tempoReal;

  static AppScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  /// Busca tudo de novo no servidor (após login ou reconexão), só o que o perfil pode ver.
  Future<void> sincronizarTudo() async {
    await conta.sincronizar();
    await Future.wait([
      if (conta.pode('recados')) repo.sincronizar(),
      if (conta.pode('motivosVer')) motivos.sincronizar(),
      if (conta.pode('agendaVer')) agenda.sincronizar(),
      if (conta.pode('mensagens')) mensagens.sincronizar(),
      if (conta.pode('visitantes')) visitas.sincronizar(),
      status.atualizar(),
    ]);
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}

/// Executa uma ação (servidor ou Holyrics) e mostra o resultado em um SnackBar.
Future<bool> executar(BuildContext context, Future<void> Function() acao, {String? sucesso}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await acao();
    if (sucesso != null) {
      messenger.showSnackBar(SnackBar(content: Text(sucesso), duration: const Duration(seconds: 2)));
    }
    return true;
  } on ErroAmigavel catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade700));
    return false;
  }
}
