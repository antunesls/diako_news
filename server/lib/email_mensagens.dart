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
        ..subject = 'Diako News: nova $tipo na caixa de mensagens'
        ..text =
            'Chegou uma nova $tipo. Abra o painel protegido para ler: $urlPainel',
      _servidor(cfg));
}

Future<void> enviarEmailTeste(Configuracoes cfg) async {
  await send(
      Message()
        ..from = Address(cfg.smtpRemetente)
        ..recipients.add(cfg.smtpDestinatario)
        ..subject = 'Diako News: teste de e-mail'
        ..text =
            'A configuração de avisos da caixa de mensagens está funcionando.',
      _servidor(cfg));
}
