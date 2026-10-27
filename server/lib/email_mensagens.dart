import 'package:diako_core/diako_core.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

import 'configuracoes.dart';

SmtpServer _servidor(Configuracoes cfg) => SmtpServer(
      cfg.smtpHost,
      port: cfg.smtpPorta,
      username: cfg.smtpUsuario.isEmpty ? null : cfg.smtpUsuario,
      password: cfg.smtpUsuario.isEmpty ? null : cfg.smtpSenha,
      ssl: cfg.smtpSsl,
      allowInsecure: false,
    );

Future<void> enviarEmailMensagem(
    Configuracoes cfg, Mensagem mensagem, String urlPainel) async {
  final tipo = switch (mensagem.tipo) {
    'duvida' => 'dúvida',
    'sugestao' => 'sugestão',
    _ => 'crítica',
  };
  await send(
      Message()
        ..from = Address(cfg.smtpRemetente)
        ..recipients.add(cfg.smtpDestinatario)
        ..subject = 'DiakoNews: nova $tipo na caixa de mensagens'
        ..text =
            'Chegou uma nova $tipo. Abra o painel protegido para ler: $urlPainel',
      _servidor(cfg));
}

Future<void> enviarEmailTeste(Configuracoes cfg) async {
  await send(
      Message()
        ..from = Address(cfg.smtpRemetente)
        ..recipients.add(cfg.smtpDestinatario)
        ..subject = 'DiakoNews: teste de e-mail'
        ..text =
            'A configuração de avisos da caixa de mensagens está funcionando.',
      _servidor(cfg));
}

/// Aviso de que o backup automático falhou. Sem detalhes do erro nem caminhos: só o link do /admin.
Future<void> enviarEmailFalhaBackup(Configuracoes cfg, DateTime quando, String urlAdmin) async {
  String dois(int n) => n.toString().padLeft(2, '0');
  final data = '${dois(quando.day)}/${dois(quando.month)}/${quando.year} às ${dois(quando.hour)}:${dois(quando.minute)}';
  await send(
      Message()
        ..from = Address(cfg.smtpRemetente)
        ..recipients.add(cfg.smtpDestinatario)
        ..subject = 'DiakoNews: o backup automático falhou'
        ..text = 'O backup automático de $data não foi gravado. O servidor tenta de novo a cada hora.\n'
            'Abra a administração para gravar um backup e conferir: $urlAdmin',
      _servidor(cfg));
}
