# Monitor do agente e catálogo de temas — plano de implementação

> **For Claude:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task.

**Goal:** Exibir monitor local permanente do agente, diagnósticos, logs seguros e ensaio guiado, além de nomes e miniaturas dos temas Holyrics no DiakoNews.

**Architecture:** O agente existente continua sendo o único WebSocket com o backend. Um servidor HTTP vinculado somente a 127.0.0.1 consulta seu estado em memória. O monitor autentica com senha independente armazenada como PBKDF2, usa cookies de sessão HttpOnly/SameSite e CSRF, e nunca devolve segredos. A API Holyrics fornece temas via `GetThemes` e miniaturas via `GetThumbnail` (base64), buscadas sob demanda pelo backend através da ponte existente; não projetam conteúdo.

**Tech Stack:** Dart 3.5, dart:io, package:http, package:test, HTML/CSS/JS embarcado no executável, PowerShell de instalação.

---

### Task 1: Estado e trilha de eventos do agente

**Files:** `server/lib/agente/agente.dart`, `server/test/agente_test.dart`.

1. Criar testes para conexão, desconexão, sucesso/falha da sincronização e limites/redação do histórico.
2. Rodar `dart test test/agente_test.dart` (esperado: falha antes da implementação).
3. Registrar estado em memória, timestamps, contadores e eventos redigidos, sem texto bruto de exceções contendo chave ou token.
4. Rodar os testes novamente (esperado: sucesso).

### Task 2: Servidor web local autenticado

**Files:** `server/lib/agente/monitor.dart`, `server/bin/diako_agente.dart`, `server/agente.example.json`, `server/test/monitor_test.dart`.

1. Testar ausência de sessão, senha incorreta, limitação de tentativas, sessão expirada, CSRF e rejeição de Host/Origin externo.
2. Implementar inicialização fail-closed somente com senha própria configurada por hash+sal; bind obrigatório em `InternetAddress.loopbackIPv4`, sem afetar o loop WebSocket em caso de falha de bind.
3. Expor `/`, `/api/estado`, `/api/logs`, `/api/diagnostico`, `/api/temas`, `/api/ensaio` com dados limitados e mensagens redigidas.
4. Testar parser, HTTP e integração por `dart test`.

### Task 3: Diagnósticos e ensaio guiado

**Files:** `server/lib/agente/monitor.dart`, `server/test/monitor_test.dart`.

1. Testar leituras (`GetCPInfo`, `GetCurrentPresentation`, `GetThemes`), pasta de cartazes e sincronização; registrar resultados com orientações.
2. Testar bloqueio do ensaio com telão ocupado, cancelamento, token CSRF, sequência de confirmação por etapa e mudança inesperada da apresentação.
3. Implementar texto de teste com dois slides, próximo/anterior apenas da apresentação criada pelo ensaio; nunca fechar ou restaurar apresentação de terceiros.

### Task 4: Catálogo de temas com miniaturas

**Files:** `server/lib/holyrics.dart`, `server/lib/app.dart`, `server/lib/permissoes.dart`, `server/web/admin.html`, `server/web/admin.js`, `lib/sync/server_api.dart`, `lib/ui/settings_page.dart`, `server/test/server_test.dart`.

1. Testar permissão da ação `GetThumbnail`, IDs inválidos, base64 inválido, resposta limitada, backend indisponível e uso de token de administrador no catálogo.
2. Construir `/api/temas` autenticado: buscar `GetThemes`, buscar miniaturas em lotes por `ids`, filtrar tamanho/formato e devolver `id`, `name`, miniatura opcional. Cache curto em memória com data da atualização e aviso de stale; não confundir preview com projeção real.
3. No painel admin, manter o campo manual como fallback e acrescentar cards com miniaturas e botão atualizar. No tablet, trocar a lista textual por cards com miniaturas consultados no backend. Preservar valor anterior quando desconectado.

### Task 5: Instalação, documentação e verificação

**Files:** `server/instalar.ps1`, `server/LEIA-ME.md`, `server/agente.example.json`.

1. Oferecer definição interativa da senha própria do monitor sem parâmetro de linha de comando; guardar só hash e sal e manter o valor em upgrades.
2. Documentar URL local, porta configurável, permissões GetThemes/GetThumbnail, significado de estado stale e riscos do ensaio.
3. Executar `dart format`, `dart analyze`, `dart test`, verificação de bind local e `git diff --check`. Caso Dart não esteja disponível, relatar explicitamente a limitação e não afirmar que os testes passaram.

**Safety:** somente leitura por padrão; cada ação ativa exige confirmação; o ensaio nunca substitui apresentação existente; log e relatórios nunca incluem chave, token, URL de credenciais ou payload pessoal. Não executar projeção real automaticamente.

**Limitações operacionais:** a conferência de telão livre e o comando de projetar são chamadas separadas à API Holyrics; se outro operador iniciar uma apresentação exatamente entre elas, não há transação atômica na API que impeça a corrida. O ensaio é para janela de manutenção com coordenação humana. O monitor mantém eventos recentes em memória; o log histórico do processo permanece apenas no PC, fora do navegador.

**Aceite manual no PC da igreja:** (1) depois de instalar o pacote, abrir `http://127.0.0.1:8096` e entrar com a senha própria; (2) verificar que o backend e Holyrics mostram "conectado" somente quando realmente conectados; (3) executar diagnósticos de leitura e buscar miniaturas no monitor, no `/admin` e no tablet; (4) confirmar que o endereço não responde de outro computador; (5) somente em janela livre, iniciar ensaio e confirmar próximo/anterior com `SIM` a cada etapa; (6) interromper caso outra apresentação apareça. Nunca enviar um token no chat nem executar ensaio automaticamente nos testes de integração.
