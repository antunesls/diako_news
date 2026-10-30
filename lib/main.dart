import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_scope.dart';
import 'data/agenda_repo.dart';
import 'data/escala_repo.dart';
import 'data/conta_repo.dart';
import 'data/mensagem_repo.dart';
import 'data/motivo_repo.dart';
import 'data/palavra_repo.dart';
import 'data/recado_repo.dart';
import 'data/settings.dart';
import 'data/visita_repo.dart';
import 'holyrics/agente_local.dart';
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
  final escalas = EscalaRepo(api: api, cache: () => arquivo('cache_escala.json'));
  final mensagens = MensagemRepo(api: api, cache: () => arquivo('cache_mensagens.json'));
  final visitas = VisitaRepo(api: api, cache: () => arquivo('cache_visitas.json'));
  final palavra = PalavraRepo(api: api, cache: () => arquivo('cache_palavra.json'));
  final conta = ContaRepo(api: api, cache: () => arquivo('cache_conta.json'));
  // O perfil primeiro (cache), para só buscar o que ele pode ver.
  await conta.carregar();
  unawaited(conta.sincronizar());
  // Sem await: a tela abre na hora com o cache e atualiza quando o servidor responder.
  if (conta.pode('recados')) unawaited(repo.carregar());
  if (conta.pode('motivosVer')) unawaited(motivos.carregar());
  if (conta.pode('agendaVer')) unawaited(agenda.carregar());
  if (conta.pode('escalasVer')) unawaited(escalas.carregar());
  if (conta.pode('mensagens')) unawaited(mensagens.carregar());
  if (conta.pode('visitantes')) unawaited(visitas.carregar());
  if (conta.pode('projetar')) unawaited(palavra.carregar());

  final agenteLocal = AgenteLocal(() => (base: settings.agenteLocal, token: settings.agenteLocalToken));
  final client = HolyricsClient(api, local: agenteLocal);
  final status = StatusController(client)..iniciar();

  final tempoReal = TempoReal(
    api,
    aoMudar: (tipo) {
      if ((tipo == 'recados' || tipo == 'membros') && conta.pode('recados')) repo.sincronizar();
      if (tipo == 'motivos' && conta.pode('motivosVer')) motivos.sincronizar();
      if (tipo == 'agenda' && conta.pode('agendaVer')) agenda.sincronizar();
      if ((tipo == 'escalas' || tipo == 'membros') && conta.pode('escalasVer')) escalas.sincronizar();
      if (tipo == 'mensagens' && conta.pode('mensagens')) mensagens.sincronizar();
      if (tipo == 'visitas' && conta.pode('visitantes')) visitas.sincronizar();
      if (tipo == 'palavras' && conta.pode('projetar')) palavra.sincronizar();
    },
    aoReconectar: () async {
      await conta.sincronizar();
      if (conta.pode('recados')) repo.sincronizar();
      if (conta.pode('motivosVer')) motivos.sincronizar();
      if (conta.pode('agendaVer')) agenda.sincronizar();
      if (conta.pode('escalasVer')) escalas.sincronizar();
      if (conta.pode('mensagens')) mensagens.sincronizar();
      if (conta.pode('visitantes')) visitas.sincronizar();
      if (conta.pode('projetar')) palavra.sincronizar();
    },
  );
  if (settings.configurado) tempoReal.iniciar();

  runApp(AppScope(
    repo: repo,
    motivos: motivos,
    agenda: agenda,
    escalas: escalas,
    palavra: palavra,
    mensagens: mensagens,
    visitas: visitas,
    conta: conta,
    settings: settings,
    api: api,
    client: client,
    agenteLocal: agenteLocal,
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
      title: 'DiakoNews',
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
