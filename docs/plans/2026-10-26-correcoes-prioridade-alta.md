# Correções de prioridade alta — plano de implementação

**Objetivo:** limitar a exposição do histórico de visitas, impedir a divulgação de aniversariantes sem autorização vigente e garantir que falhas de persistência não deixem o servidor anunciando dados não gravados.

**Arquitetura:** autorização e filtro de publicação no servidor/pacote compartilhado; `Store` confirma a gravação antes de alterar o estado observado e emitir notificações. Preservar as APIs e o formato dos JSON existentes. Implementar com testes de regressão antes das correções.

**Stack:** Dart 3, Shelf, `diako_core`, `package:test`, Flutter para regressão do consumidor. Este plano não inclui a proposta de operação do culto, avaliada separadamente.

## Decisões e critérios globais

- Visitantes: o perfil `recepcao` só recebe visitas da data corrente do servidor, independentemente de `desde`; `pastor`, `secretaria` e `administrador` preservam consultas históricas. Confirmar explicitamente o período permitido para `telao` antes de alterar seu comportamento: o tablet hoje usa a API de visitas para exibir o dia.
- Aniversariantes: só publicar quem estiver ativo, tiver `consentimentoEm` válido e não tiver `consentimentoRevogado`. Sem autorização registrada, inclusive nos dados legados, não publicar. A ficha permanece acessível a usuários autorizados para regularização.
- Persistência: sucesso de `salvar`, `salvarVarios`, `excluir` e `substituir` significa estado persistido e observável; uma falha não perde a capacidade de fazer novas gravações. Não trocar todo o armazenamento por banco de dados nesta correção.
- Não divulgar dados reais nos testes. Não converter um erro de gravação em resposta HTTP de sucesso. Revisar também as rotas que fazem mais de uma gravação; atomicidade entre coleções é um trabalho adicional e não deve ser alegada por este plano.

## 1. Restringir histórico no perfil Recepção

**Arquivos:** `server/lib/app.dart` (`_listarVisitas`), `server/test/visitas_test.dart`, `server/LEIA-ME.md` se a regra descrita precisar de ajuste.

1. Em `server/test/visitas_test.dart`, adicionar teste de API com visitas de hoje e de ontem, autenticado como `recepcao`: `GET /api/visitas`, `?desde=2000-01-01` e `?desde=<ontem>` retornam somente hoje; a mesma consulta como `secretaria` ou `admin` retorna o histórico permitido.
2. Executar `dart test test/visitas_test.dart` em `server/`; confirmar que o novo teste falha na versão atual.
3. Em `_listarVisitas`, obter `Auth.contaDa(req)`, definir o limite inferior como `_hoje()` para `Perfil.recepcao` e ignorar valores anteriores de `desde`. Evitar que valores futuros ou malformados ampliem a janela; para os demais perfis, preservar o comportamento atual. A filtragem deve ocorrer **antes** de serializar a resposta.
4. Executar novamente o teste específico, seguido de `dart analyze --fatal-infos` e `dart test` em `server/`.

**Aceite:** nenhum token de Recepção obtém visitas de dias anteriores por alteração direta da URL; os perfis com acesso histórico mantêm sua funcionalidade. A interface `/recepcao` continua mostrando as visitas de hoje.

## 2. Respeitar autorização nas divulgações de aniversário

**Arquivos:** `packages/diako_core/lib/src/aniversariantes.dart`, `packages/diako_core/test/core_test.dart`, `packages/diako_core/test/ideias_test.dart` ou teste de resumo existente, `server/test/membros_test.dart`, `server/LEIA-ME.md`, `README.md`.

1. Criar testes no `diako_core` com quatro pessoas aniversariando na semana: autorizada, sem autorização, revogada e inativa. Verificar que `aniversariantesDaSemana`/`recadoAniversariantes` incluem apenas a autorizada e que nenhuma divulgação automática é criada se ninguém for elegível. Ajustar os testes anteriores de aniversário para registrar autorização explícita nas pessoas que devem aparecer.
2. Criar teste de `montarResumoSemanal` que não contenha o nome de quem não autorizou; criar teste de integração no servidor para a resposta do mural e de `/api/resumo-semanal`. Manter a pessoa sem consentimento na listagem protegida de membros.
3. Executar `dart test` em `packages/diako_core/` e o teste pertinente em `server/`; confirmar as falhas esperadas antes da implementação.
4. Centralizar a elegibilidade para **divulgação** em `aniversariantesDaSemana`: `m.ativo && m.consentimentoEm != null && m.consentimentoRevogado == null`. Validar que a data de consentimento foi interpretada pelo modelo (e não é apenas texto arbitrário). O recado automático, mural e resumo usam essa função; não filtrar só uma tela.
5. Atualizar a orientação de uso: regularizar autorização para o nome entrar no recado e no resumo; a ausência de autorização oculta apenas a divulgação, não a ficha interna.
6. Executar `dart analyze --fatal-infos` e `dart test` em `packages/diako_core/` e `server/`; executar `flutter test` na raiz para detectar impacto no tablet.

**Aceite:** cadastros legados sem autorização, autorização revogada e pessoas inativas nunca aparecem no recado automático, no mural ou no resumo semanal; uma pessoa elegível continua aparecendo na semana correta. Publicação manual de nome/aniversário via recado livre não é tecnicamente bloqueada por esta regra e requer orientação operacional separada.

## 3. Garantir consistência do Store após falhas de escrita

**Arquivos:** `server/lib/store.dart`, novo `server/test/store_test.dart`; rever `server/lib/app.dart` para o tratamento HTTP de falhas de I/O e `server/lib/backup.dart` para a leitura de arquivos durante gravações.

1. Criar `server/test/store_test.dart` com cenários de inclusão, alteração, exclusão, lote e substituição; verificar dados em memória e em nova instância após reinício, versões e eventos de `mudancas`.
2. Simular falha determinística de persistência por uma função de escrita injetável em `Store` (ou mecanismo de falha isolado no teste), sem depender de permissões do Windows/Linux. Testar: operação falha sem mudar a coleção visível, sem incrementar versão e sem notificar; depois de remover a falha, outra operação grava normalmente. Adicionar teste de duas gravações concorrentes na mesma coleção, preservando a ordem.
3. Executar `dart test test/store_test.dart` em `server/` e confirmar as falhas dos novos cenários.
4. Serializar a operação **inteira** pela fila: construir uma cópia da coleção a partir do último estado confirmado, escrever snapshot em arquivo temporário e renomear, e só então publicar coleção/versão/evento. Não deixar uma `Future` rejeitada contaminar a fila de operações seguintes; propagar o erro somente ao chamador daquela operação. Revisar o comportamento de leitura durante a gravação e documentá-lo.
5. Cobrir a rota HTTP que usa `store.salvar`: em erro de disco, não responder `201` nem `200`. Usar resposta controlada `503`/`500` sem expor caminhos internos; registrar detalhes no log do servidor. Garantir que a ausência de catch em `_tratarErros` não derrube a aplicação.
6. Conferir o backup com gravações em andamento: idealmente criar um snapshot consistente por coleção após aguardar a fila; não alegar transação entre coleções sem implementá-la. Rodar `dart analyze --fatal-infos` e `dart test` em `server/`.

**Aceite:** ao falhar a escrita, API não confirma o salvamento, `listar` e `buscar` não exibem a alteração, `versoes` e WebSocket não anunciam mudança; a operação seguinte funciona após a causa ser removida. Após reinício, o conteúdo coincide com o último estado confirmado.

## Ordem e validação final

1. Executar 1 e 2 como correções independentes; executar 3 depois, por afetar todas as rotas de dados.
2. Rodar `dart analyze --fatal-infos && dart test` em `packages/diako_core/` e `server/`; rodar `flutter analyze` e `flutter test` na raiz. Corrigir regressões antes de integrar.
3. Fazer revisão manual em ambiente de teste: login de Recepção, visita anterior, aniversário autorizado/não autorizado/revogado, mural, resumo e falha simulada de disco. Não usar dados pessoais de produção nesse teste.
4. Integrar em três mudanças revisáveis, uma por correção, com teste junto da implementação; planejar implantação com backup e verificação pós-deploy.

**Dependências/riscos:** `dart` e `flutter` não estavam no `PATH` durante a elaboração do plano; a execução depende do SDK. Ocultar aniversariantes sem autorização altera o conteúdo visível imediatamente após a publicação, exigindo aviso à secretaria. A correção do `Store` não torna o cadastro familiar transacional entre coleções: isso deve ter tarefa própria posteriormente.
