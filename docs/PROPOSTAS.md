# Propostas de melhorias e novas funcionalidades

Levantamento de 27/10/2026, depois das correções de prioridade alta (visitas da Recepção, aniversariantes com autorização da LGPD e gravação segura do Store). Cada item escolhido vira um plano próprio em `docs/plans/AAAA-MM-DD-<nome>.md`, com testes primeiro, e ganha página `/ajuda/<recurso>` quando precisar de configuração fora do sistema.

**Esforço:** P = até 1 dia · M = 2 a 4 dias · G = uma semana ou mais.

## Resumo

| # | Proposta | Tipo | Esforço | Prioridade |
|---|---|---|---|---|
| M1 | Registro de alterações nas fichas (auditoria) | Melhoria | M | Alta |
| M2 | Gravação conjunta do cadastro familiar | Melhoria | M | Alta |
| M3 | Backup fora do servidor e aviso de falha | Melhoria | P | Alta |
| M4 | Período de visitas do perfil Telão | Melhoria | P | Média |
| M5 | Aviso de recado manual com nome de quem não autorizou | Melhoria | P | Média |
| F1 | Roteiro do culto | Funcionalidade | M | Alta |
| F2 | Escalas dos ministérios | Funcionalidade | M | Alta |
| F3 | Painel de indicadores | Funcionalidade | M | Média |
| F4 | Presença nos cultos | Funcionalidade | P | Média |
| F5 | Resumo semanal por e-mail para a equipe | Funcionalidade | P | Média |
| F6 | Acompanhamento do pedido de oração por quem pediu | Funcionalidade | M | Média |
| F7 | Check-in do ministério infantil | Funcionalidade | G | Avaliar |
| F8 | Células (pequenos grupos) | Funcionalidade | G | Avaliar |
| F9 | Dízimos e ofertas | Funcionalidade | G | Avaliar |
| F10 | Repertório de músicas | Funcionalidade | M | Avaliar |
| F11 | Aviso no tablet com o app fechado | Funcionalidade | M | Avaliar |

**Ordem sugerida:** M3 → F1 → M1 → F2 → M2 → F3/F4 → o resto conforme a necessidade da igreja.

---

## Melhorias no que já existe

### M1. Registro de alterações nas fichas (auditoria)
- **Problema:** o histórico (`server/lib/historico.dart`) guarda só o que foi projetado. Não há registro de quem criou, alterou, exportou ou excluiu a ficha de uma pessoa. Para a LGPD, a igreja deve conseguir responder "quem mexeu nos meus dados e quando".
- **Proposta:** arquivo `data/auditoria.jsonl` (mesmo formato do `historico.jsonl`) com data, usuário, ação (criar, alterar, excluir, exportar CSV, ver CPF/RG, enviar link LGPD) e **só os nomes dos campos** alterados, nunca os valores. Na ficha, uma seção "Alterações" visível para Administrador e Pastor. Entra no backup.
- **Reaproveita:** `Historico`, `Auth.contaDa(req)`, as rotas de `/api/membros` em `server/lib/app.dart`.
- **Cuidados:** não gravar dados pessoais no log; definir quanto tempo guardar (ex.: 2 anos).

### M2. Gravação conjunta do cadastro familiar
- **Problema:** o cadastro de visitantes cria membros, vínculos (cônjuge, pais), visitas e pedido de oração em coleções diferentes. Se uma gravação falhar no meio, ficam registros pela metade. O Store novo garante cada coleção, mas não o conjunto.
- **Proposta:** `Store.salvarJuntos({colecao: docs})` que grava todos os arquivos temporários e só faz os renames e a publicação depois que todos foram escritos. Se algo falhar, nada é publicado. Usar no `_registrarVisita` e na restauração de backup.
- **Reaproveita:** a fila e `Store.gravarArquivo` em `server/lib/store.dart`.
- **Cuidados:** rename de vários arquivos não é atômico no sistema de arquivos. Documentar que uma queda de energia entre dois renames ainda pode deixar um arquivo novo e outro antigo. Avaliar um diário (journal) simples se isso importar.

### M3. Backup fora do servidor e aviso de falha
- **Problema:** no LXC, `pastaBackup` fica no mesmo disco do servidor. Se o disco ou o container se perder, os backups vão junto. Uma falha no backup diário também passa despercebida.
- **Proposta:** (a) enviar o `.zip` diário por e-mail para um endereço da igreja, se couber no limite do SMTP, ou copiar para um destino remoto configurável (pasta montada, rclone); (b) mostrar em `/admin` e no painel um alerta "último backup há X dias" e enviar e-mail quando o backup falhar.
- **Reaproveita:** `server/lib/backup.dart`, `server/lib/email_mensagens.dart`.
- **Cuidados:** o zip tem dados pessoais. Se for enviado por e-mail, avaliar proteger com senha.

### M4. Período de visitas do perfil Telão
- **Problema:** o plano de correções deixou em aberto o que o perfil Telão (tablet) pode consultar em `/api/visitas`. Hoje ele recebe o mesmo período padrão de 30 dias que a secretaria, sem os contatos.
- **Proposta:** confirmar com o pastor o que a seção Visitantes do tablet precisa (pendências de hoje) e limitar o Telão a hoje, como já é na Recepção.
- **Reaproveita:** a regra nova em `_listarVisitas`.

### M5. Aviso de recado manual com nome de quem não autorizou
- **Problema:** o filtro da LGPD vale para o recado automático, mas nada impede que alguém escreva um recado manual "Parabéns, Fulano!" para quem não autorizou a divulgação.
- **Proposta:** ao salvar um recado, conferir se o texto cita o nome completo de alguém ativo sem autorização e mostrar um aviso (sem bloquear): "Fulano ainda não autorizou a divulgação do nome".
- **Reaproveita:** `podeDivulgarAniversario` em `packages/diako_core/lib/src/aniversariantes.dart`.

---

## Novas funcionalidades

### F1. Roteiro do culto — prioridade alta
- **Para quê:** hoje o pastor ou a mídia monta o culto na hora, tocando em várias telas do tablet. O roteiro deixa a ordem pronta antes e, no domingo, é só tocar em "próximo".
- **Como funciona:** no painel, monta-se a ordem do culto com itens de tipos já existentes: texto rápido, recado, sequência de recados, cartaz, motivos de oração, QR de pedidos, boas-vindas aos visitantes, contagem regressiva, mensagem para o palco e tela preta/vazia. O tablet ganha a aba **Roteiro**: mostra o item atual e o próximo, com botões "projetar" e "próximo", e marca o que já foi. Roteiros podem ser copiados de um domingo para outro (modelo).
- **Reaproveita:** comandos do `server/lib/holyrics.dart`, a sequência de recados, `_projetarBoasVindas`, o histórico de projeções e a API local do agente (funciona com a internet fora).
- **Dados:** nova coleção `roteiros` no Store.
- **Esforço:** M.

### F2. Escalas dos ministérios — prioridade alta
- **Para quê:** organizar quem serve em cada culto (louvor, mídia, recepção, infantil, limpeza) sem depender de planilhas e mensagens soltas.
- **Como funciona:** no painel, escala por mês e por ministério, escolhendo pessoas que já têm aquele ministério na ficha. Mostra conflito (a mesma pessoa em dois ministérios no mesmo culto) e indisponibilidade informada. Gera o texto da escala para o grupo do WhatsApp (o envio continua sendo manual) e um link individual "minha escala", sem login, como o link da LGPD. O tablet e o mural da equipe mostram quem está escalado hoje. O perfil Recepção vê a escala da recepção.
- **Reaproveita:** `Membro.ministerios`, o padrão do resumo semanal (`packages/diako_core/lib/src/resumo.dart`), os links individuais da LGPD e `permissoes.dart`.
- **Cuidados:** o link individual mostra só nome e escala, nada da ficha.
- **Esforço:** M.

### F3. Painel de indicadores
- **Para quê:** dar ao pastor uma visão rápida da saúde da igreja.
- **Como funciona:** aba no painel com membros por status, novos visitantes no mês, quantos voltaram, quantos visitantes viraram congregados ou membros (pelo histórico de status), pedidos de oração recebidos e atendidos, mensagens pendentes, fichas sem autorização da LGPD e visitantes sem contato há mais de 7 dias. Cada número leva à lista filtrada.
- **Reaproveita:** `MudancaStatus`, coleções `visitas`, `motivos` e `mensagens`, e os filtros já existentes da aba Membros.
- **Esforço:** M (só leitura, sem dados novos).

### F4. Presença nos cultos
- **Para quê:** saber como a frequência evolui ao longo dos meses.
- **Como funciona:** o obreiro, em `/recepcao`, registra no fim do culto as contagens de adultos, crianças e visitantes. O painel mostra um gráfico semanal e mensal, junto com os visitantes cadastrados no dia.
- **Reaproveita:** perfil Recepção, página `/recepcao`, coleção `visitas`.
- **Dados:** nova coleção `presencas` (só números, sem nomes).
- **Esforço:** P.

### F5. Resumo semanal por e-mail para a equipe
- **Para quê:** lembrar a secretaria e o pastor do que precisa de atenção sem que precisem abrir o painel.
- **Como funciona:** toda segunda de manhã, um e-mail com a contagem de aniversariantes da semana, visitantes sem contato, autorizações faltando, mensagens novas e (com F2) a escala da semana. Configurável em `/admin` (dia, hora e destinatários). Por segurança, o e-mail leva números e links para o painel, não nomes ou contatos.
- **Reaproveita:** `server/lib/email_mensagens.dart` e o agendador do backup diário.
- **Esforço:** P.

### F6. Acompanhamento do pedido de oração por quem pediu
- **Para quê:** quem pede oração hoje não sabe o que aconteceu com o pedido.
- **Como funciona:** ao enviar o pedido, a pessoa recebe um link (guardado no navegador, ou enviado se ela informou um contato) para ver se foi aprovado e projetado. Ela pode marcar "foi respondida" e escrever o testemunho, que entra para aprovação antes de ir ao telão.
- **Reaproveita:** `/oracao`, modelo `Motivo` (já tem `atendidoEm` e `testemunho`), tokens de link individual (só o hash é guardado, como na LGPD).
- **Esforço:** M.

### F7. Check-in do ministério infantil — avaliar
- **Para quê:** segurança na entrega das crianças.
- **Como funciona:** check-in pelo responsável ou pelo obreiro gera um código curto (impresso ou mostrado no celular). Só quem apresenta o código retira a criança. Para chamar o responsável, o código aparece na mensagem para o palco ou no mural ("Responsável pelo código 123, favor ir à sala infantil").
- **Reaproveita:** famílias (`paisIds`) do cadastro de membros, `SetTextCP`, mural.
- **Cuidados:** dados de menores. Exige autorização do responsável e não deve mostrar o nome da criança em telas públicas.
- **Esforço:** G (inclui impressão de etiquetas).

### F8. Células (pequenos grupos) — avaliar
- **Para quê:** organizar e acompanhar os grupos que se reúnem durante a semana.
- **Como funciona:** cadastro de células (líder, dia, horário, bairro, participantes), relatório semanal da reunião feito pelo líder no celular (presentes, visitantes, pedidos) e bloco "Encontre uma célula" na página inicial, só com bairro e dia (sem endereço exato).
- **Reaproveita:** perfis de usuário (novo perfil Líder de célula), página inicial, cadastro de membros.
- **Esforço:** G.

### F9. Dízimos e ofertas — avaliar
- **Para quê:** registrar a arrecadação por culto e gerar o relatório mensal da tesouraria.
- **Como funciona:** lançamentos por culto (dinheiro, PIX, cartão), relatório mensal e exportação CSV. Lançamentos por pessoa só se a igreja quiser, e com autorização.
- **Cuidados:** dado muito sensível. Exige o novo perfil Tesouraria, auditoria (M1) e nenhuma exibição pública. Avaliar se uma ferramenta contábil já usada pela igreja não atende melhor.
- **Esforço:** G.

### F10. Repertório de músicas — avaliar
- **Para quê:** saber o que foi cantado em cada culto, evitar repetição e ter dados para o relatório de licenças (CCLI).
- **Como funciona:** o agente consulta o Holyrics durante o culto e registra as músicas apresentadas. O painel mostra por culto, as mais cantadas e as que não são cantadas há tempo.
- **Reaproveita:** agente local (`server/lib/agente/`), histórico.
- **Cuidados:** confirmar quais ações da API do Holyrics trazem o título da música (pode exigir liberar uma ação nova no token).
- **Esforço:** M.

### F11. Aviso no tablet com o app fechado — avaliar
- **Para quê:** hoje o tablet só avisa de pedido novo com o app aberto (WebSocket).
- **Como funciona:** notificação do Android para pedido de oração aguardando, mensagem nova e visitante que pediu visita pastoral.
- **Cuidados:** Firebase Cloud Messaging exige conta Google e configuração no app. Alternativa sem Firebase: serviço em segundo plano com consulta periódica (gasta mais bateria). A notificação não deve mostrar o conteúdo de pedidos particulares.
- **Esforço:** M.
