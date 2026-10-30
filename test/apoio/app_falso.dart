import 'dart:convert';
import 'dart:io';

import 'package:diako_core/diako_core.dart';
import 'package:diako_news/app_scope.dart';
import 'package:diako_news/data/agenda_repo.dart';
import 'package:diako_news/data/conta_repo.dart';
import 'package:diako_news/data/escala_repo.dart';
import 'package:diako_news/data/mensagem_repo.dart';
import 'package:diako_news/data/motivo_repo.dart';
import 'package:diako_news/data/palavra_repo.dart';
import 'package:diako_news/data/recado_repo.dart';
import 'package:diako_news/data/settings.dart';
import 'package:diako_news/data/visita_repo.dart';
import 'package:diako_news/holyrics/agente_local.dart';
import 'package:diako_news/holyrics/holyrics_client.dart';
import 'package:diako_news/holyrics/status_controller.dart';
import 'package:diako_news/sync/server_api.dart';
import 'package:diako_news/sync/tempo_real.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Servidor DiakoNews falso com um domingo típico: escala com Santa Ceia daqui a 30 min,
/// recados, motivos, visitantes de hoje e um evento na agenda. Holyrics sempre aceita.
class ServidorFalso {
  ServidorFalso(this.agora);

  final DateTime agora;

  /// Ações recebidas pelo Holyrics, na ordem (ex: "ShowQuickPresentation"), com o corpo de cada uma.
  final holyrics = <String>[];
  final corpos = <Map<String, dynamic>>[];

  /// Palavra pronta de hoje (null = o pastor não preparou texto).
  Palavra? palavra;

  late final hoje = diaIso(agora);

  late final recados = [
    Recado(id: 'r1', titulo: 'Aniversariantes da semana', texto: 'Ana Paula (30/10), Jorge (31/10), Débora (2/11)', categoria: Categoria.aniversario, fixo: true),
    Recado(id: 'r2', titulo: 'Retiro de Jovens 2026', texto: 'De 14 a 16/11 no Sítio Boa Esperança. Inscrições com a Larissa até 7/11.', categoria: Categoria.evento, ordem: 1),
    Recado(id: 'r3', titulo: 'Campanha do Quilo', texto: 'Traga 1 kg de alimento não perecível. Doações vão para 18 famílias do bairro.', ordem: 2),
    Recado(id: 'r4', titulo: 'Ensaio geral do louvor', texto: 'Sábado às 16h00. Todos os escalados para a Santa Ceia.', categoria: Categoria.evento, ordem: 3),
    Recado(id: 'r5', titulo: 'Escola Bíblica Dominical', texto: 'Nova classe de casais começa domingo às 9h00, na sala 3.', ordem: 4),
  ];

  late final motivos = [
    Motivo(id: 'm1', para: 'Sr. Antônio', motivo: 'Cirurgia do joelho na terça', status: StatusMotivo.aguardando),
    Motivo(id: 'm2', para: 'Família Duarte', motivo: 'Consolo pelo falecimento da avó'),
    Motivo(id: 'm3', para: 'Rafael', motivo: 'Emprego novo'),
    Motivo(id: 'm4', para: 'Igreja', motivo: 'Retiro de jovens'),
    Motivo(id: 'm5', para: 'Márcia', motivo: 'Saúde e recuperação'),
    Motivo(id: 'm6', para: 'Lúcia', motivo: 'Curada da pneumonia', status: StatusMotivo.atendido, atendidoEm: agora.subtract(const Duration(days: 3)), testemunho: 'Recebeu alta no sábado.'),
  ];

  Visita _visita(String id, String nome, {bool mencionar = true}) => Visita(
        id: id,
        membroId: 'p-$id',
        nome: nome,
        data: hoje,
        criadoEm: agora.subtract(const Duration(minutes: 10)),
        origem: OrigemVisita.recepcao,
        mencionar: mencionar,
      );

  late final visitas = [_visita('v1', 'Família Oliveira'), _visita('v2', 'Renata Campos'), _visita('v3', 'Caio Torres', mencionar: false)];

  late final culto = {
    'id': 'c1',
    'data': hoje,
    'hora': _hhmm(agora.add(const Duration(minutes: 30))),
    'rotulo': 'Dom 02/11',
    'horaTexto': '19h',
    'nome': 'Culto da família',
    'ceia': true,
    'tema': 'Em memória de mim',
    'funcoes': {
      'pastoral': ['Direção', 'Pregação', 'Oração e ofertas', 'Santa Ceia'],
      'louvor': ['Ministro', 'Vocal', 'Teclado', 'Violão', 'Bateria', 'Técnico de som'],
    },
    'pastoral': {
      'Direção': [{'nome': 'Pra. Elaine'}],
      'Pregação': [{'nome': 'Pr. Marcos'}],
      'Oração e ofertas': [{'nome': 'Diác. Paulo'}],
      'Santa Ceia': [{'nome': 'Pr. Marcos'}, {'nome': 'Diác. Paulo'}],
    },
    'louvor': {
      'Ministro': [{'nome': 'Lucas'}],
      'Vocal': [{'nome': 'Júlia'}, {'nome': 'Thaís'}],
      'Teclado': [{'nome': 'Pedro'}],
      'Violão': [{'nome': 'André'}],
      'Bateria': [{'nome': 'Bruno'}],
      'Técnico de som': [{'nome': 'Sérgio'}],
    },
    'musicas': [
      {'titulo': 'Bondade de Deus', 'tom': 'G'},
      {'titulo': 'Grande é o Senhor', 'tom': 'D'},
      {'titulo': 'Ousado Amor', 'tom': 'A'},
      {'titulo': 'Tu és Santo', 'tom': 'E'},
    ],
  };

  late final evento = Evento(
    id: 'e1',
    titulo: 'Retiro de Jovens',
    inicio: DateTime(agora.year, agora.month, agora.day).add(const Duration(days: 12, hours: 8)),
    fim: DateTime(agora.year, agora.month, agora.day).add(const Duration(days: 14, hours: 18)),
    local: 'Sítio Boa Esperança',
  );

  http.Client get cliente => MockClient((req) async {
        final caminho = req.url.path;
        final Object? resposta = switch (caminho) {
          '/api/recados' => [for (final r in recados) r.toJson()],
          '/api/motivos' => [for (final m in motivos) m.toJson()],
          '/api/visitas' => [for (final v in visitas) v.toJson()],
          '/api/mensagens' => const [],
          '/api/agenda' => {'configurada': true, 'eventos': [evento.toJson()]},
          '/api/escalas/hoje' => {'hoje': true, 'cultos': [culto]},
          '/api/palavras/hoje' => {'palavra': palavra == null ? null : PalavraDoCulto.de(palavra!).toJson()},
          '/api/estado' => {'qrHolyrics': 'DiakoNews/qr.png', 'qrMensagensHolyrics': 'DiakoNews/qr-mensagens.png', 'qrPixHolyrics': 'DiakoNews/qr-pix.png'},
          '/api/projetar/boas-vindas' => {'status': 'ok'},
          _ when caminho.startsWith('/api/holyrics/') => () {
              holyrics.add(caminho.substring('/api/holyrics/'.length));
              corpos.add(req.body.isEmpty ? {} : Map<String, dynamic>.from(jsonDecode(req.body) as Map));
              return {'status': 'ok', 'data': null};
            }(),
          _ => null,
        };
        if (resposta == null) return http.Response('{"erro":"não encontrado"}', 404);
        return http.Response.bytes(utf8.encode(jsonEncode(resposta)), 200);
      });
}

/// Monta o AppScope de verdade sobre o [ServidorFalso], já sincronizado. Rodar dentro de `tester.runAsync`.
Future<AppScope> montarApp(ServidorFalso servidor, Directory pasta, Widget home) async {
  SharedPreferences.setMockInitialValues({'servidor': 'http://srv:8080', 'sessao': 's'});
  final settings = AppSettings(await SharedPreferences.getInstance());
  final api = ServerApi(() => ServidorConfig(base: settings.servidor, sessao: settings.sessao), httpClient: servidor.cliente);
  Future<File> arquivo(String nome) async => File('${pasta.path}/$nome');
  final repo = RecadoRepo(api: api, cache: () => arquivo('recados.json'));
  final motivos = MotivoRepo(api: api, cache: () => arquivo('motivos.json'));
  final agenda = AgendaRepo(api: api, cache: () => arquivo('agenda.json'));
  final escalas = EscalaRepo(api: api, cache: () => arquivo('escala.json'));
  final mensagens = MensagemRepo(api: api, cache: () => arquivo('mensagens.json'));
  final visitas = VisitaRepo(api: api, cache: () => arquivo('visitas.json'));
  final conta = ContaRepo(api: api, cache: () => arquivo('conta.json'));
  final palavra = PalavraRepo(api: api, cache: () => arquivo('palavra.json'));
  await Future.wait([repo.sincronizar(), motivos.sincronizar(), agenda.sincronizar(), escalas.sincronizar(), mensagens.sincronizar(), visitas.sincronizar(), palavra.sincronizar()]);
  final client = HolyricsClient(api, local: AgenteLocal(() => (base: '', token: '')));
  final status = StatusController(client);
  await status.atualizar();
  return AppScope(
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
    agenteLocal: AgenteLocal(() => (base: '', token: '')),
    status: status,
    tempoReal: TempoReal(api, aoMudar: (_) {}, aoReconectar: () {}),
    child: MaterialApp(
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
      home: home,
    ),
  );
}
