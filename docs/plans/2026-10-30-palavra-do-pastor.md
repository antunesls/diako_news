# A Palavra do pastor (entrega 2 do Modo Culto)

Data: 2026-10-30

Proposta com as telas: [`docs/modo-culto.html`](../modo-culto.html) (seção "A Palavra do pastor"). Depende da entrega 1 ([`2026-10-29-modo-culto.md`](2026-10-29-modo-culto.md)).

## Objetivo

O pastor (ou o pregador escalado) prepara o sermão no painel web. No culto, o tablet passa o texto **trecho por trecho na TV do palco** (painel de comunicação do Holyrics) e projeta **no telão** cada versículo citado, com um toque.

## Decisões

- **Formato do texto:** texto simples, editado num campo grande do painel.
  - Linha em branco separa os trechos (cada parágrafo é um trecho).
  - Linha que começa com `#` é um **tópico** (aparece como atalho no tablet; não vai à TV).
  - Parágrafo longo demais para a TV (mais de 500 caracteres) é dividido nas frases.
- **Versículos achados sozinhos** no `diako_core` (uma implementação, usada pelo painel via servidor e pelo tablet):
  - 66 livros por nome e abreviação, com ou sem acento ("Jo", "João", "1Co", "1 Coríntios", "I Coríntios").
  - Capítulo e versículo com ponto ou dois-pontos, intervalos e listas: "Jo 3.16", "Jo 3:16-18", "Rm 8.28,31".
  - Abreviações só valem com inicial maiúscula e com versículo ("Os 3 irmãos" não é Oseias). Nome completo sem versículo ("Salmo 23") vira referência **incompleta**, que o pastor ajusta.
  - O pastor confere cada uma no painel: **confirmar**, **ignorar** ou **ajustar** (digitar a referência certa). A decisão vale para o mesmo texto em qualquer trecho.
- **No Holyrics:** o versículo vai por `ShowVerse` com `ids` no formato `LLCCCVVV` (livro, capítulo, versículo), que não depende do idioma das abreviações; a versão é a padrão do Holyrics. É o único comando ainda não testado na igreja: fica isolado em `HolyricsClient.mostrarVersiculo`.
- **TV do palco:** `SetTextCP` com tema próprio para leitura (alinhado à esquerda, no alto). Sair do momento da Palavra limpa a TV do palco.
- **Permissões:**
  - `palavras`: preparar as próprias Palavras.
  - `palavrasTodas`: ver e revisar as de todos.
  - Administrador e Pastor ganham as duas. Perfil novo **Pregador**: `palavras` e a própria escala.
  - O tablet baixa a Palavra do dia com `projetar`.
- **Guardado no servidor:** coleção `palavras` (entra no backup). Cada salvamento guarda a versão anterior (até 20).
- **Status:** rascunho ou pronta. A Palavra **pronta** com a data de hoje desce para o tablet; com mais de uma, vale a ligada ao culto do dia.
- **Sem internet no culto:** o tablet guarda a cópia da Palavra do dia.

## Nesta execução

1. **`diako_core`: `palavra.dart`**
   - Tabela dos 66 livros, `acharReferencias`, `lerReferencia` (para o ajuste), `dividirEmTrechos`.
   - Modelo `Palavra` (com `decisoes` e `versoes`) e `TrechoPalavra`.
   - Testes.
2. **Servidor**
   - Permissões e perfil Pregador.
   - Coleção `palavras`.
   - Rotas:
     - `GET/POST /api/palavras`, `GET/PUT/DELETE /api/palavras/<id>`: cada um só as suas, sem `palavrasTodas`;
     - `POST /api/palavras/analisar`: trechos e versículos para a prévia;
     - `POST /api/palavras/importar`: Word `.docx` e `.txt`;
     - `GET /api/palavras/hoje`: para o tablet.
   - Testes.
3. **Painel:** página **Palavras** em "Cultos".
   - Lista (rascunho, pronta, pregada).
   - Editor com prévia dos trechos numerados.
   - Conferência dos versículos e versões anteriores.
   - Botões Colar e Importar Word/TXT.
   - Teste do menu atualizado.
4. **App**
   - `HolyricsClient.mostrarVersiculo` e `leituraPalco`.
   - `PalavraRepo` (com cache) no `AppScope`, sincronizado pelo tempo real.
   - Modo Culto, momento Palavra com texto:
     - trechos com os tópicos no alto;
     - versículos como botões;
     - prévias da TV do palco e do telão;
     - Próximo trecho e Trecho anterior;
     - Tirar versículo;
     - o trecho atual salvo com o resto do progresso.
5. **README** e conferência na tela inteira (teste com servidor falso).

## Depois (entrega 2b)

- **PDF:** extrair o texto de PDF com qualidade pede uma biblioteca no navegador (pdf.js). Até lá, o painel pede para copiar e colar o texto do PDF.
- **Google Docs:** importar pelo link, usando a conta de serviço do Google que já existe para a agenda (o documento precisa ser compartilhado com ela).
- **QR do PIX** no slide de ofertas: gravar o QR (o servidor já gera, para o site) na pasta do Holyrics, como o QR de mensagens.
- Ajustes depois do teste do `ShowVerse` na igreja.

## Verificação

- `dart test` em `packages/diako_core` e em `server`; `node --test server/test` (painel).
- `flutter analyze` e `flutter test` (com o Flutter em `C:\src\flutter`).
- Na igreja: rodar o roteiro de teste do Holyrics da página da proposta.

## Resultado (2026-10-30)

Itens 1 a 5 feitos. Verificado nesta máquina:

- `diako_core`: 93 testes (15 novos da Palavra: livros, intervalos, Jó × João, abreviação × palavra comum, trechos, decisões).
- Servidor: 195 testes (novos: importar Word/TXT, cada pregador só vê as suas, versões, "pronta" só sem pendências, rota do tablet); análise limpa.
- Painel: 26 testes de JS; página aberta no navegador com o servidor local: conferir e ajustar versículos, marcar como pronta, editar e voltar a rascunho com o motivo, versão anterior guardada.
- App: 52 testes, incluindo a leitura em tela inteira no tamanho do A9+ com a ordem exata dos comandos ao Holyrics (`SetTextCP` do trecho; `SetF10` desligado e `ShowVerse` com `ids` no versículo; TV do palco limpa ao sair da Palavra).

Falta conferir na igreja: o `ShowVerse` com `ids` e o tamanho do texto na TV do palco (roteiro de teste em `docs/modo-culto.html`).

## Entrega 2b (2026-10-30)

- **PDF:** lido no navegador com a pdf.js 4.10.38 (carregada do jsDelivr só quando se escolhe um PDF; precisa de internet no computador do pastor). A montagem dos parágrafos fica em `server/web/palavras-pdf.js`, testada no Node. Conferido no navegador com um PDF gerado pelo Chrome.
- **Google Docs:** `POST /api/palavras/google {link}` exporta o documento como texto pela API do Drive (`drive.readonly`), com a conta de serviço da agenda. O documento precisa estar compartilhado com o e-mail dela; os erros explicam isso e o caso da "Google Drive API" desativada. Testado com cliente HTTP falso; falta testar com a conta real da igreja.
- **QR do PIX:** o servidor grava `qr-pix.png` (com a chave escrita) na pasta que vai para o Holyrics, na inicialização, ao salvar a configuração e ao restaurar backup; sem chave, apaga. O estado informa `qrPixHolyrics` e o tablet acrescenta o passo "QR do PIX" ao momento das ofertas.
