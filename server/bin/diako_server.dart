import 'dart:io';

import 'package:diako_server/app.dart';
import 'package:diako_server/auth.dart';
import 'package:diako_server/backup.dart';
import 'package:diako_server/cartazes.dart';
import 'package:diako_server/config.dart';
import 'package:diako_server/historico.dart';
import 'package:diako_server/holyrics.dart';
import 'package:diako_server/qr_oracao.dart';
import 'package:diako_server/store.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart' as io;

/// Versão definida na compilação (dart compile exe -DVERSAO=1.2.0).
const versao = String.fromEnvironment('VERSAO', defaultValue: 'dev');

/// Uso: diako_server [caminho/do/config.json]
/// Sem argumento, procura config.json ao lado do executável (ou na pasta atual com `dart run`).
Future<void> main(List<String> args) async {
  final arquivoConfig = args.isNotEmpty ? args.first : _configPadrao();
  final Config config;
  try {
    config = await Config.carregar(arquivoConfig);
  } on Exception catch (e) {
    stderr.writeln('Erro na configuração: $e');
    exitCode = 1;
    return;
  }

  final store = Store(config.pastaDados);
  await store.carregar();
  final auth = Auth(senha: config.senhaAdmin, pastaDados: config.pastaDados);
  await auth.carregar();

  final ip = await ipLocal() ?? '127.0.0.1';
  final base = config.urlPublica.isNotEmpty ? config.urlPublica : 'http://$ip:${config.porta}';
  final urlOracao = '$base/oracao';
  await gravarQr(config.pastaCartazes, urlOracao);

  final backup = Backup(
    pastaDados: config.pastaDados,
    pastaDestino: config.pastaBackup,
    horario: config.horaBackup,
    configSemSegredos: {
      'porta': config.porta,
      'holyrics': {'host': config.holyricsHost, 'porta': config.holyricsPorta},
      'pastaImagensHolyrics': config.pastaImagensHolyrics,
      'pastaBackup': config.pastaBackup,
      'horaBackup': config.horaBackup,
      'urlPublica': config.urlPublica,
    },
  )..agendar();

  final servidor = Servidor(
    store: store,
    auth: auth,
    holyrics: HolyricsProxy(host: config.holyricsHost, porta: config.holyricsPorta, token: config.holyricsToken),
    cartazes: Cartazes(config.pastaCartazes),
    backup: backup,
    pastaWeb: config.pastaWeb,
    urlOracao: urlOracao,
    cartazesNoHolyrics: config.pastaImagensHolyrics.isNotEmpty,
    historico: Historico(config.pastaDados),
    versao: versao,
  );

  final http = await io.serve(servidor.handler, InternetAddress.anyIPv4, config.porta);
  stdout.writeln('''
Diako News $versao rodando.
  Painel:              $base/painel
  Pedidos de oração:   $urlOracao
  Mural (TV):          $base/mural
  No tablet, use o endereço: $base
  Cartazes e QR em:    ${config.pastaCartazes}
  Backup:              ${backup.configurado ? '${config.pastaBackup} às ${config.horaBackup}' : 'desativado (defina pastaBackup)'}
''');
  if (config.holyricsToken.isEmpty) {
    stdout.writeln('Atenção: token do Holyrics vazio. Os comandos de projeção não vão funcionar.');
  }

  ProcessSignal.sigint.watch().listen((_) async {
    backup.parar();
    await http.close();
    await store.fechar();
    exit(0);
  });
}

String _configPadrao() {
  final exe = Platform.resolvedExecutable;
  // Rodando como .exe compilado: config.json fica ao lado. Com `dart run`: pasta atual.
  final pasta = p.basenameWithoutExtension(exe).toLowerCase() == 'dart' ? Directory.current.path : p.dirname(exe);
  return p.join(pasta, 'config.json');
}
