# Caixa de mensagens Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task.

**Goal:** receber dúvidas, sugestões e críticas por QR em formulário público, administrar no painel e tablet, e avisar por SMTP sem divulgar o conteúdo.

**Architecture:** coleção JSON `mensagens` no Store existente, rotas públicas protegidas por honeypot/limite e rotas administrativas autenticadas; QR PNG distinto sincronizado ao Holyrics/agente e exibido no mural. Notificação SMTP desacoplada do salvamento, com estado de falha visível e nova tentativa manual.

**Tech Stack:** Dart/Shelf, diako_core, Flutter, HTML/JS, JSON, `package:test`/`flutter test`.

---

**Objetivo:** receber dúvidas, sugestões e críticas por QR em formulário público, administrar no painel e tablet, e avisar por SMTP sem divulgar o conteúdo.

**Arquitetura:** coleção JSON `mensagens` no Store existente, rotas públicas protegidas por honeypot/limite e rotas administrativas autenticadas; QR PNG distinto sincronizado ao Holyrics/agente e exibido no mural. Notificação SMTP desacoplada do salvamento, com estado de falha visível e nova tentativa manual. Configurações SMTP editadas em `/admin`, com senha excluída das respostas e backups.

**Stack:** Dart/Shelf, diako_core, Flutter, HTML/JS, JSON e testes `package:test`/`flutter test`.

## Mapa de contexto

| Área | Arquivos de alteração | Referência/teste |
|---|---|---|
| Dados e API | `server/lib/store.dart`, `server/lib/app.dart`, `packages/diako_core/lib/src/mensagem.dart`, `packages/diako_core/lib/diako_core.dart` | `server/test/server_test.dart`, `packages/diako_core/test/` |
| E-mail/configuração | `server/lib/configuracoes.dart`, `server/lib/email_mensagens.dart`, `server/pubspec.yaml`, `server/web/admin.html`, `server/web/admin.js` | `server/test/admin_test.dart`; senha não sai do servidor nem entra no backup |
| QR/mural | `server/lib/qr_oracao.dart`, `server/bin/diako_server.dart`, `server/lib/backup.dart`, `packages/diako_core/lib/src/mural.dart`, `server/web/mural.html` | QR de oração existente; sincronização do agente |
| Formulário/painel | `server/web/mensagens.html`, `server/web/painel.html`, `server/web/painel.js` | `server/web/oracao.html`, rotas e DOM do painel |
| Tablet | `lib/sync/server_api.dart`, `lib/data/mensagem_repo.dart`, `lib/app_scope.dart`, `lib/main.dart`, `lib/ui/home_page.dart`, `lib/ui/mensagem_panel.dart` | repositório de motivos, abas e eventos WebSocket |
| Docs | `README.md`, `server/LEIA-ME.md` | instalação local e hospedada |

**Riscos:** arquivos da agenda têm mudanças locais não commitadas; preservá-los. Coleção nova precisa entrar no backup/restauração. URL pública muda os dois QRs. SMTP pode falhar: não perder envio; limitar tentativas e não revelar dados privados no mural/e-mail. Sem SDK instalado no PATH, a verificação automatizada pode depender de instalação posterior.

## Tarefas

1. **Modelo e armazenamento.** Escrever testes para tipo/status/validação e persistência; observar falha; criar modelo compartilhado e incluir `mensagens` em `Store.colecoes`; rodar testes. Status: `nova`, `emAnalise`, `resolvida`; conteúdo até 2000 caracteres, nome 80, contato 120.
2. **API pública/protegida.** Testar envio anônimo/identificado, entrada inválida, honeypot, limite, login obrigatório, mudanças de status sem alteração de conteúdo e resumo da contagem; implementar `/api/public/mensagens`, `/api/mensagens` e `/api/mensagens/<id>`.
3. **QR e mural.** Testar QR distinto, criação/atualização após mudança de URL, restauração e presença de slide sem dados privados; adicionar `/mensagens`, `/qr-mensagens.png`, `qrMensagens` em `/api/estado`, geração no boot e atualização, exclusão dos PNGs regeneráveis do backup e slide novo.
4. **SMTP.** Testar validação de configuração, ocultação de senha e envio simulado com falha/retentativa; adicionar configuração de host/porta/TLS/usuário/senha/remetente/destinatário e teste no admin. Após persistir mensagem, tentar aviso contendo apenas tipo/link; marcar estado de entrega; permitir nova tentativa autenticada. Falha nunca reverte mensagem nem retorna erro de envio ao visitante.
5. **Web.** Criar formulário responsivo; adicionar aba de mensagens, filtros/status e link/QR/ação de projeção; administrar SMTP em `/admin`. Não renderizar texto de usuário como HTML.
6. **Tablet.** Testar decodificação/repositório, sincronização e status; acrescentar aba com lista, badge e atualização. Manter cache em leitura quando offline, sem permitir mudanças de status offline.
7. **Validação e documentação.** Executar `dart test` no `server` e `packages/diako_core`, `flutter test` e `flutter analyze` na raiz; verificar `git diff --check` e alterações de usuário; documentar configuração SMTP e fluxo de QR no README.

**Critérios de aceite:** QR de mensagens abre formulário distinto; mensagem enviada é persistida e visível apenas autenticado no painel/tablet; estados sincronizam; mural e telão só mostram QR e chamada; aviso SMTP não contém texto/contato; falhas ficam recuperáveis; backup inclui mensagens mas não senha; pedidos de oração continuam independentes.

## Execução e verificação

- Implementadas as tarefas 1–7 no diretório existente, preservando as mudanças locais de agenda. Não fazer commit misturando trabalho pré-existente.
- Testes do servidor e `diako_core`: executar `dart test` nas respectivas pastas; análise estática: `dart analyze` em ambas.
- JavaScript: `node --check server/web/painel.js` e `node --check server/web/admin.js`.
- O teste e a análise do app Flutter dependem da instalação do Flutter SDK (não disponível no ambiente atual). Testar `flutter test` e `flutter analyze` antes de publicar o APK.
- Um SMTP real exige credenciais do administrador; testar envio com o botão em `/admin#email` antes de divulgar o QR.
