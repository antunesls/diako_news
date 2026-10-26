import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_scope.dart';
import 'data/agenda_repo.dart';
import 'data/mensagem_repo.dart';
import 'data/motivo_repo.dart';
import 'data/recado_repo.dart';
import 'data/settings.dart';
import 'holyrics/holyrics_client.dart';
import 'holyrics/status_controller.dart';
import 'sync/server_api.dart';
import 'sync/tempo_real.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  final settings = AppSettings(await SharedPreferences.getInstance());
  final api = ServerApi(() => ServidorConfig(base: settings.servidor, sessao: settings.sessao));

  // Cópias locais (cache) para mostrar os dados mesmo sem conexão com o servidor.
  Future<File> arquivo(String nome) async => File('${(await getApplicationDocumentsDirectory()).path}/$nome');
  final repo = RecadoRepo(api: api, cache: () => arquivo('cache_recados.json'));
  final motivos = MotivoRepo(api: api, cache: () => arquivo('cache_motivos.json'));
  final agenda = AgendaRepo(api: api, cache: () => arquivo('cache_agenda.json'));
  final mensagens = MensagemRepo(api: api, cache: () => arquivo('cache_mensagens.json'));
  // Sem await: a tela abre na hora com o cache e atualiza quando o servidor responder.
  unawaited(repo.carregar());
  unawaited(motivos.carregar());
  unawaited(agenda.carregar());
  unawaited(mensagens.carregar());

  final client = HolyricsClient(api);
  final status = StatusController(client)..iniciar();

  final tempoReal = TempoReal(
    api,
    aoMudar: (tipo) {
      if (tipo == 'recados' || tipo == 'membros') repo.sincronizar();
      if (tipo == 'motivos') motivos.sincronizar();
      if (tipo == 'agenda') agenda.sincronizar();
      if (tipo == 'mensagens') mensagens.sincronizar();
    },
    aoReconectar: () {
      repo.sincronizar();
      motivos.sincronizar();
      agenda.sincronizar();
      mensagens.sincronizar();
    },
  );
  if (settings.configurado) tempoReal.iniciar();

  runApp(AppScope(
    repo: repo,
    motivos: motivos,
    agenda: agenda,
    mensagens: mensagens,
    settings: settings,
    api: api,
    client: client,
    status: status,
    tempoReal: tempoReal,
    child: const DiakoNewsApp(),
  ));
}

class DiakoNewsApp extends StatelessWidget {
  const DiakoNewsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Diako News',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF5C6BC0),
        visualDensity: VisualDensity.comfortable,
      ),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const HomePage(),
    );
  }
}
