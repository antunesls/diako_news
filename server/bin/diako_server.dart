import 'dart:io';

import 'package:diako_server/agenda.dart';
import 'package:diako_server/agenda_google_api.dart';
import 'package:diako_server/agente_hub.dart';
import 'package:diako_server/app.dart';
import 'package:diako_server/auth.dart';
import 'package:diako_server/backup.dart';
import 'package:diako_server/backup_cifrado.dart';
import 'package:diako_server/cartazes.dart';
import 'package:diako_server/config.dart';
import 'package:diako_server/configuracoes.dart';
import 'package:diako_server/email_mensagens.dart';
import 'package:diako_server/historico.dart';
import 'package:diako_server/holyrics.dart';
import 'package:diako_server/qr_oracao.dart';
import 'package:diako_server/store.dart';
import 'package:diako_server/tablets_locais.dart';
import 'package:diako_server/usuarios.dart';
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

  // Configurações editáveis pelo painel (/admin); o config.json vale como padrão.
  final ip = await ipLocal() ?? '127.0.0.1';
  final cfg = await Configuracoes.carregar(config, urlDetectada: 'http://$ip:${config.porta}');
  // Usuários por pessoa (perfis Pastor, Secretaria, Mídia...); a senha do config.json/admin é a conta "admin".
  final usuarios = Usuarios(config.pastaDados);
  await usuarios.carregar();
  final auth = Auth(conferirSenha: cfg.conferirSenha, pastaDados: config.pastaDados, usuarios: usuarios);
  await auth.carregar();

  final base = cfg.urlBase;
  await gravarQr(config.pastaCartazes, cfg.urlOracao);
  await gravarQrMensagens(config.pastaCartazes, cfg.urlMensagens);
  await gravarQrPix(config.pastaCartazes, chave: cfg.sitePixChave, nome: cfg.sitePixNome, cidade: cfg.sitePixCidade);

  final backup = Backup(
    pastaDados: config.pastaDados,
    pastaDestino: config.pastaBackup,
    pastaCartazes: config.pastaCartazes,
    horario: () => cfg.horaBackup,
    manter: () => cfg.backupsManter,
    configuracoes: cfg.publicas,
  )
    ..aoFalhar = (quando) async {
      if (cfg.smtpConfigurado) await enviarEmailFalhaBackup(cfg, quando, '${cfg.urlBase}/admin#backup');
    }
    ..agendar();

  // Senha da cópia cifrada do backup no PC da igreja (data/backup-senha.json, fora dos backups).
  final senhaBackup = SenhaBackup(config.pastaDados);
  await senhaBackup.carregar();

  final modoAgente = config.modoHolyrics == ModoHolyrics.agente;
  final agente = modoAgente ? HolyricsViaAgente() : null;
  final tabletsLocais = TabletsLocais(config.pastaDados);
  await tabletsLocais.carregar();
  final online = modoAgente || config.confiarProxy;

  // Agenda do Google: baixa a cada 15 min e avisa o painel/app quando muda. Com a chave de uma
  // conta de serviço, lê e altera pela API (criar/editar/excluir eventos pelo painel e pelo tablet).
  final contaGoogle = ContaServicoGoogle(config.pastaDados);
  await contaGoogle.carregar();
  final agenda = AgendaGoogle(
    pastaDados: config.pastaDados,
    url: () => cfg.agendaUrl,
    conta: contaGoogle,
    calendarioId: () => cfg.agendaCalendarioId,
    aoMudar: () => store.avisar('agenda'),
  );
  await agenda.carregar();
  agenda.iniciar();

  final servidor = Servidor(
    store: store,
    auth: auth,
    agenda: agenda,
    holyrics: agente ?? HolyricsDireto(host: cfg.holyricsHost, porta: cfg.holyricsPorta, token: cfg.holyricsToken),
    cartazes: Cartazes(config.pastaCartazes),
    backup: backup,
    pastaWeb: config.pastaWeb,
    urlOracao: cfg.urlOracao,
    cartazesNoHolyrics: config.pastaImagensHolyrics.isNotEmpty,
    historico: Historico(config.pastaDados),
    versao: versao,
    agente: agente,
    tabletsLocais: tabletsLocais,
    senhaBackup: senhaBackup,
    confiarProxy: config.confiarProxy,
    cfg: cfg,
    senhaMinima: online ? 10 : 6,
    restauracao: Restauracao(
      store: store,
      backup: backup,
      pastaDados: config.pastaDados,
      pastaCartazes: config.pastaCartazes,
      aplicarConfiguracoes: (dados) async {
        await cfg.restaurarPublicas(dados);
        await gravarQr(config.pastaCartazes, cfg.urlOracao);
        await gravarQrMensagens(config.pastaCartazes, cfg.urlMensagens);
        await gravarQrPix(config.pastaCartazes, chave: cfg.sitePixChave, nome: cfg.sitePixNome, cidade: cfg.sitePixCidade);
        store.avisar('cartazes');
      },
    ),
  );

  final http = await io.serve(servidor.handler, config.endereco, config.porta);
  final mural = cfg.chaveMural.isEmpty ? '$base/mural' : '$base/mural?chave=${cfg.chaveMural}';
  stdout.writeln('''
DiakoHub $versao rodando em ${config.endereco}:${config.porta}.
  Painel:              $base/painel
  Pedidos de oração:   ${cfg.urlOracao}
  Caixa de mensagens:  ${cfg.urlMensagens}
  Mural (TV):          $mural
  No tablet, use o endereço: $base
  Holyrics:            ${modoAgente ? 'pelo agente no PC da igreja (aguardando conexão)' : 'direto em ${cfg.holyricsHost}:${cfg.holyricsPorta}'}
  Cartazes e QR em:    ${config.pastaCartazes}
  Backup:              ${backup.pastaDestino} às ${cfg.horaBackup}
  Administração:       $base/admin
''');
  if (!modoAgente && cfg.holyricsToken.isEmpty) {
    stdout.writeln('Atenção: token do Holyrics vazio. Os comandos de projeção não vão funcionar.');
  }

  Future<void> encerrar() async {
    backup.parar();
    agenda.parar();
    await http.close();
    await store.fechar();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen((_) => encerrar());
  // systemd para o serviço com SIGTERM (não existe no Windows).
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen((_) => encerrar());
}

String _configPadrao() {
  final exe = Platform.resolvedExecutable;
  // Rodando como .exe compilado: config.json fica ao lado. Com `dart run`: pasta atual.
  final pasta = p.basenameWithoutExtension(exe).toLowerCase() == 'dart' ? Directory.current.path : p.dirname(exe);
  return p.join(pasta, 'config.json');
}
