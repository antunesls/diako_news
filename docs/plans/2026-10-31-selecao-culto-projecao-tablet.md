# Seleção de culto e chave global de projeção — plano de implementação

**Objetivo:** permitir operar no tablet qualquer culto da escala de hoje ou futuro, escolher a Palavra pronta da data e ensaiar sem enviar comandos ao Holyrics.

**Arquitetura:** o servidor expõe a lista futura de cultos e as Palavras prontas por data, sem revelar rascunhos. O tablet mantém o culto e a Palavra escolhidos só em memória nesta sessão. Um estado de projeção global (ligado ao iniciar) impede comandos de escrita ao Holyrics na camada de transporte; no Modo Culto, avançar sem projetar continua atualizando apenas o estado local.

**Stack:** Dart/Shelf, Flutter, diako_core; testes Dart e widget tests.

## Requisitos

- R1: seleção automática do culto de hoje e opção manual para qualquer culto cadastrado de hoje em diante; cultos passados não entram.
- R2: permitir operar telão e TV do palco de um culto futuro; contagem usa a data/hora escolhida; recados, orações e boas-vindas continuam com dados atuais.
- R3: listar Palavras prontas da data selecionada e permitir escolher entre elas no tablet; sem Palavra pronta, manter roteiro sem leitura. Não expor rascunhos.
- R4: escolhas manuais não sobrevivem ao fechamento do app; ao trocar de culto iniciado, confirmar e reiniciar progresso. O progresso restaurável precisa ser identificado pelo culto, sem atribuir um passo a outro culto.
- R5: chave de projeção para todo o app, ligada por padrão em cada abertura; desligada impede escritas ao Holyrics nas duas telas, mas mantém consultas e permite navegação local no Modo Culto. Fora dele, comandos de projeção mostram indisponibilidade.
- R6: religar sincroniza imediatamente o passo atual do Modo Culto e o trecho da Palavra se houver; falha de sincronização deve ser mostrada e não declarada como sucesso. Não fazer deploy nem release nesta tarefa.

## Tarefas (TDD: teste vermelho → implementação mínima → teste verde)

1. **API de cultos futuros** — `server/lib/app.dart`, `server/test/escalas_test.dart`, `lib/sync/server_api.dart`, `lib/data/escala_repo.dart`: acrescentar endpoint de leitura para cultos da escala com data >= hoje, reutilizando a serialização e o modelo de roteiro de `/api/escalas/hoje`; manter endpoint existente e cache. Testar ordenação, dois horários no mesmo dia, datas futuras e permissões.
2. **API de Palavras por data** — `server/lib/app.dart`, `server/test/palavras_test.dart`, `lib/sync/server_api.dart`, `lib/data/palavra_repo.dart`: aceitar dia ISO validado e retornar lista mínima de Palavras prontas dessa data, com ID; escolher por ID ao carregar, fallback à mais recente apenas sem escolha manual. Testar duas prontas, rascunho oculto, dia inválido e ausência de Palavra.
3. **Seleção no Modo Culto** — `lib/data/modo_culto.dart`, `lib/ui/modo_culto_page.dart`, `test/modo_culto_test.dart`, `test/telas_tablet_test.dart`: autoescolher hoje; selecionar por ID culto futuro; escolher Palavra por ID; confirmar troca durante operação; reiniciar progresso; voltar ao automático; horários e rótulos da data escolhida. Testar que o estado salvo de outro culto não é restaurado como se fosse o atual.
4. **Intertravamento global** — `lib/holyrics/holyrics_client.dart`, `lib/main.dart`, `lib/app_scope.dart`, `lib/ui/home_page.dart`, `lib/ui/modo_culto_page.dart`, `test/holyrics_client_test.dart`, `test/telas_tablet_test.dart`: estado em memória inicialmente ligado, chave visível e acessível de todas as telas; distinguir ações de leitura e escrita na camada de transporte; bloquear todas as escritas, inclusive caminhos via servidor; exibir aviso nos controles externos.
5. **Ensaio e sincronização** — `lib/data/modo_culto.dart`, `lib/ui/modo_culto_page.dart`, testes do controlador e widget: ao avançar desligado, atualizar somente o roteiro local e contadores; religar executa o passo atual e restaura a leitura no palco quando houver. Validar erro, projeção desligada durante execução e que religar sem passo não altera as telas.
6. **Verificação final** — rodar `dart test`/`dart analyze` em `packages/diako_core` e `server`, `flutter test`, `flutter analyze` e revisão do diff. Preservar `docs/plans/2026-10-30-freeshow-diako.md` e `palavra-modelo.txt` não relacionados, sem commit/deploy/release automáticos.

## Riscos e decisões

- A listagem de cultos atual só retorna hoje ou o próximo dia até sete dias; uma rota separada evita mudar os clientes existentes.
- A Palavra ainda não é vinculada no editor web a um culto: a seleção explícita no tablet substitui a ambiguidade quando há duas na mesma data.
- O app tem outras rotas de projeção além do cliente Holyrics direto (ex.: boas-vindas via servidor); essas ações também precisam de guarda para que o bloqueio seja realmente global.
- Contagens de hora exata em dias futuros podem depender do Holyrics; validar ou avisar quando o comando não puder expressar a data, sem exibir contagem errada.
