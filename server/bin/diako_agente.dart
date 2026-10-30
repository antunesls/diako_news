import 'dart:convert';
import 'dart:io';

import 'package:diako_server/agente/agente.dart';
import 'package:diako_server/agente/api_local.dart';
import 'package:diako_server/agente/monitor.dart';
import 'package:diako_server/auth.dart' show gerarHashSenha;
import 'package:path/path.dart' as p;

/// Versão definida na compilação (dart compile exe -DVERSAO=1.2.0).
const versao = String.fromEnvironment('VERSAO', defaultValue: 'dev');

/// Agente do PC da igreja: liga o servidor DiakoHub da internet ao Holyrics local.
/// Uso: diako_agente [caminho/do/agente.json]
Future<void> main(List<String> args) async {
  final definirSenha = args.isNotEmpty && args.first == '--definir-senha';
  final arquivo = definirSenha ? (args.length > 1 ? args[1] : _configPadrao())
      : (args.isNotEmpty ? args.first : _configPadrao());
  if (definirSenha) {
    try {
      final config = File(arquivo);
      var texto = await config.readAsString();
      if (texto.startsWith('\uFEFF')) texto = texto.substring(1);
      final original = jsonDecode(texto) as Map<String, dynamic>;
      if (!stdin.hasTerminal) throw const FormatException('Abra um terminal interativo para definir a senha.');
      stdout.write('Nova senha do monitor (mínimo 12 caracteres): ');
      late final String senha;
      try {
        stdin.echoMode = false;
        senha = stdin.readLineSync() ?? '';
      } finally {
        stdin.echoMode = true;
      }
      stdout.writeln();
      if (senha.length < 12) throw const FormatException('A senha precisa ter pelo menos 12 caracteres.');
      final hash = gerarHashSenha(senha);
      final monitor = Map<String, dynamic>.from((original['monitor'] as Map?) ?? {});
      monitor['hash'] = hash.hash;
      monitor['sal'] = hash.sal;
      original['monitor'] = monitor;
      final tmp = File('$arquivo.tmp');
      await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(original));
      await tmp.rename(arquivo);
      stdout.writeln('Senha definida. Guarde-a: ela não pode ser recuperada do arquivo.');
    } catch (e) {
      stderr.writeln('Não foi possível definir a senha do monitor: $e');
      exitCode = 1;
    }
    return;
  }
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
Agente DiakoHub $versao
  Servidor:  ${config.servidor}
  Holyrics:  ${config.holyricsHost}:${config.holyricsPorta}
  Cartazes:  ${config.pastaCartazes}
''');
  final agente = Agente(config, versao: versao, pastaDados: p.dirname(p.absolute(arquivo)));
  await agente.carregarDados();
  final monitor = MonitorAgente(agente);
  try {
    await monitor.iniciar();
    stdout.writeln('Monitor local: http://127.0.0.1:${monitor.porta}');
  } catch (_) {
    stderr.writeln('Monitor indisponível: confira senha configurada e porta local. O agente continuará ativo.');
  }
  final apiLocal = ApiLocal(agente);
  if (config.apiLocalPorta > 0) {
    try {
      await apiLocal.iniciar();
      stdout.writeln('Tablets na rede local: porta ${apiLocal.porta}');
    } catch (_) {
      stderr.writeln('Porta ${config.apiLocalPorta} ocupada: os tablets usarão só a internet.');
    }
  }
  ProcessSignal.sigint.watch().listen((_) async {
    await apiLocal.parar();
    await monitor.parar();
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
