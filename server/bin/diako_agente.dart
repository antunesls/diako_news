import 'dart:io';

import 'package:diako_server/agente/agente.dart';
import 'package:path/path.dart' as p;

/// Versão definida na compilação (dart compile exe -DVERSAO=1.2.0).
const versao = String.fromEnvironment('VERSAO', defaultValue: 'dev');

/// Agente do PC da igreja: liga o servidor DiakoNews da internet ao Holyrics local.
/// Uso: diako_agente [caminho/do/agente.json]
Future<void> main(List<String> args) async {
  final arquivo = args.isNotEmpty ? args.first : _configPadrao();
  final AgenteConfig config;
  try {
    final f = File(arquivo);
    if (!await f.exists()) {
      throw FileSystemException('agente.json não encontrado. Copie agente.example.json para agente.json e preencha.', arquivo);
    }
    config = AgenteConfig.lerJson(await f.readAsString());
  } on Exception catch (e) {
    stderr.writeln('Erro na configuração: $e');
    exitCode = 1;
    return;
  }

  stdout.writeln('''
Agente DiakoNews $versao
  Servidor:  ${config.servidor}
  Holyrics:  ${config.holyricsHost}:${config.holyricsPorta}
  Cartazes:  ${config.pastaCartazes}
''');
  final agente = Agente(config, versao: versao);
  ProcessSignal.sigint.watch().listen((_) async {
    await agente.parar();
    exit(0);
  });
  await agente.rodar();
}

String _configPadrao() {
  final exe = Platform.resolvedExecutable;
  final pasta = p.basenameWithoutExtension(exe).toLowerCase() == 'dart' ? Directory.current.path : p.dirname(exe);
  return p.join(pasta, 'agente.json');
}
