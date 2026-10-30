# Modo Culto no tablet (entrega 1)

Data: 2026-10-29

Proposta com as telas: [`docs/modo-culto.html`](../modo-culto.html).

## Objetivo

Uma segunda interface do app do tablet, só para o horário do culto. O app monta o roteiro do culto com os dados que já tem e o pastor acompanha o momento atual tocando **Avançar**. A tela de organizar (trilho e palco fixo) continua sendo a principal.

Esta entrega mexe só no app e no `diako_core`. O servidor não muda.

## Decisões

- **Roteiro padrão**, nesta ordem; momentos sem conteúdo somem:

| Momento | Passos (cada toque em Avançar executa um) | Fonte |
|---|---|---|
| Antes do culto | Contagem no telão até a hora do culto ("O culto começa em") | hora da escala |
| Boas-vindas | "Sejam bem-vindos!" pelo servidor, com os visitantes de hoje que autorizaram | visitas de hoje |
| Louvor | Tela vazia (a letra é do operador do Holyrics); a tela mostra músicas, tons e escalados | escala do louvor |
| Recados | Um recado por passo (texto ou imagem) | recados selecionados; sem seleção, os que não expiraram |
| Dízimos e ofertas | Slide de ofertas com Malaquias 3.10 | fixo |
| Santa Ceia | Slide da Ceia e tela vazia; só quando a escala marca Ceia | escala |
| Motivos de oração | Slides dos motivos aprovados e das orações respondidas | motivos |
| Palavra | Tela preta; a tela mostra pregador, tema e o cronômetro | escala |
| Oração final e bênção | Tela vazia | fixo |
| Encerramento | QR dos pedidos de oração, QR da caixa de mensagens e o próximo evento | servidor e agenda |

- **Recados um por vez** (decidido com o pastor). A Sequência automática continua na tela de organizar.
- **Boas-vindas** projeta pelo servidor (`/api/projetar/boas-vindas`) com os ids de todos os visitantes de hoje que autorizaram, e não só os pendentes. Assim o momento não some do roteiro depois que o servidor dá baixa.
- **Posição guardada por tipo de momento**, não por índice. O roteiro é remontado quando os dados mudam (pedido aprovado, visitante novo) sem perder o lugar.
- **Contagem:** ao chegar a hora do culto, o tablet destaca o Avançar ("Hora do culto") em vez de projetar o próximo momento sozinho. Isso evita uma troca no telão sem ninguém tocar.
- **Progresso salvo no tablet** (SharedPreferences): culto, momento, passo e a hora de início de cada momento. Se o app fechar, volta no mesmo ponto. Vale só para o mesmo dia.
- **Quem usa:** quem tem a permissão `projetar`.
- **Entrar:** botão **Modo Culto** no trilho, e um aviso na tela principal quando falta até 1 h para o culto de hoje (e até 3 h depois do início).
- **Sair:** segurar **Sair**; com PIN configurado, ele é pedido. Um toque simples só explica que é preciso segurar.
- **Tempo previsto da pregação:** 40 min por padrão, ajustável na própria tela da Palavra (de 5 em 5 min), guardado no tablet.

## Fora desta entrega

- QR do PIX no slide de ofertas (o servidor já tem chave, nome e cidade; falta pôr o QR na pasta do Holyrics). Fica para a entrega 2.
- Página **Palavras** no painel, texto do sermão na TV do palco e versículos no telão (entrega 2, depende do teste da API do Holyrics).
- Modelos de roteiro editáveis no painel.

## Tarefas

1. **`diako_core`: `roteiro.dart`**
   - `TipoMomento` (título, ícone por nome, minutos previstos).
   - `Passo` (ação, rótulo, texto/arquivo/ids) e `Momento` (tipo, detalhe, linhas informativas, passos).
   - `montarRoteiro(...)` com as regras da tabela.
   - `PosicaoRoteiro` com `proxima`, `anterior` e `localizar` (acha a posição pelo tipo depois de remontar).
   - `textoSemMarcacao(slide)` para mostrar a prévia sem as tags do Holyrics.
   - Testes em `test/roteiro_test.dart`.
   - Verificação: `dart test` em `packages/diako_core`.
2. **App: dados**
   - `CultoDoDia` ganha `id` e `hora` (hh:mm), que o servidor já envia.
   - `AppSettings` ganha `modoCulto` (estado salvo) e `minutosPregacao`.
3. **App: `ModoCultoController`** (`lib/data/modo_culto.dart`)
   - Escolhe o culto de hoje, remonta o roteiro, guarda a posição, executa os passos no Holyrics, salva e restaura.
4. **App: `ModoCultoPage`** (`lib/ui/modo_culto_page.dart`)
   - Tela "Antes do culto": conferência e os botões Iniciar contagem e Começar o culto agora.
   - Tela "Durante": roteiro à esquerda, momento atual no meio (prévias e passos; Louvor e Palavra com conteúdo próprio), comando à direita (Avançar, Voltar, Vazia, Preta, Parar e "Chegou agora").
5. **App: entrada**
   - Botão no trilho e aviso de culto próximo na `HomePage`.
6. **Testes de widget** (`test/modo_culto_test.dart`): a prévia de cada tipo de passo cabe em tamanho pequeno e grande, e o estado salvo só vale no mesmo dia. O aviso de culto próximo (`cultoProximo`) é testado no `diako_core`.
7. **README**: descrever o Modo Culto.

## Verificação

- `dart test` em `packages/diako_core`: roda nesta máquina.
- `flutter analyze` e `flutter test`: precisam do Flutter (não instalado nesta máquina). Rodar no PC com Flutter ou pelo CI.
- No tablet, num horário sem culto: entrar no modo, iniciar a contagem, avançar por todos os momentos, fechar o app no meio e conferir que volta no mesmo ponto, e sair segurando o botão.
