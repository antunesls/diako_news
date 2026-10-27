# Servidor DiakoNews

Programa que roda **no PC do Holyrics** e centraliza recados, motivos de oração, cartazes e aniversariantes.
O tablet, o painel da secretaria e o formulário de pedidos de oração conversam com ele, e ele comanda o Holyrics.

| Endereço | Para quem | Precisa de senha? |
|---|---|---|
| `http://IP:8080/oracao` | Membros (pelo QR code) enviam pedidos de oração | Não |
| `http://IP:8080/mensagens` | Membros (por outro QR) enviam dúvidas, sugestões e críticas | Não |
| `http://IP:8080/visitante` | Visitantes (pelo QR da recepção) se cadastram e autorizam o uso dos dados (LGPD) | Não |
| `http://IP:8080/autorizar` | A pessoa abre o link que a secretaria enviou e autoriza o uso dos dados (LGPD) | Não (link individual) |
| `http://IP:8080/recepcao` | Obreiro da recepção (perfil *Recepção*) cadastra visitantes pelo celular | Sim (usuário próprio) |
| `http://IP:8080/painel` | Secretaria/pastor: recados, aprovar pedidos, cartazes, membros, resumo da semana, histórico | Sim |
| `http://IP:8080/admin` | Administração: nome e textos, mural, Holyrics, projeção, backup/restauração, senha | Sim |
| `http://IP:8080/mural` | TV de informações: avisos passando sozinhos | Não |
| `http://IP:8080/mural?tela=boas-vindas` | TV de boas-vindas: nomes dos visitantes de hoje (ou o QR do cadastro) | Não |
| `http://IP:8080` | Endereço que vai nas configurações do app do tablet | Sim |

Instalado assim, funciona para quem está no **Wi-Fi da igreja**. Para acessar de qualquer lugar, hospede o servidor na internet (LXC/VPS) e instale só o agente no PC da igreja: veja [`docs/HOSPEDAGEM.md`](../docs/HOSPEDAGEM.md).

### Monitor do agente (instalação `-Modo agente`)

O monitor é uma página **apenas neste PC**: `http://127.0.0.1:8096`. Não abra uma porta no firewall nem coloque um proxy público na frente dele. O instalador pede uma **senha própria do monitor**, independente da senha do painel; somente seu hash e sal são guardados em `agente.json`. Para mudar a senha, abra um terminal no PC da igreja e rode `C:\DiakoNews\diako_agente.exe --definir-senha C:\DiakoNews\agente.json`, depois reinicie a tarefa **DiakoNews Agente**. A porta pode ser alterada em `monitor.porta` (reinicie após a alteração). Se não houver senha configurada ou a porta estiver ocupada, o agente continua conectando ao backend, mas o monitor fica desligado.

- **Geral:** conexão WebSocket com o backend (o painel não abre uma segunda conexão), última mensagem, reconexões, configuração local do Holyrics sem mostrar token, última sincronização e quantidade de cartazes. O estado do Holyrics é conferido na aba Diagnósticos.
- **Diagnósticos:** testes individuais de leitura da conexão com backend, `GetCPInfo`, apresentação atual, `GetThemes` e pasta de cartazes. Uma pasta existente não prova que a escrita está autorizada; verifique `agente.log` se a sincronização falhar.
- **Temas:** nomes e miniaturas consultados via `GetThemes` + `GetThumbnail`. As miniaturas não são garantia de como o texto será projetado. Em `/admin` › *Projeção padrão*, use **Buscar temas e miniaturas**, escolha o tema e clique **Salvar**. O tablet também mostra miniaturas em *Configurações › Buscar temas*. Se o Holyrics ficar offline, a última lista em memória do backend é marcada como desatualizada; após reiniciar, só estará disponível depois da próxima consulta.
- **Ensaio:** opção separada que exige `SIM` em cada etapa. Só inicia com o telão livre; para avançar/voltar, verifica o ID da apresentação de teste. Não fecha o que estiver no ar. **Não rode durante um culto.**
- **Logs:** até 200 eventos operacionais recentes em memória, com filtro e botões de copiar/baixar relatório sem credenciais. O histórico é reiniciado junto com o agente; o log de inicialização `C:\DiakoNews\agente.log` é separado e não é exposto pelo monitor.

Libere **GetThemes** e **GetThumbnail** no token do Holyrics para as miniaturas. Em versões anteriores a 2.27, `GetThemes` pode não estar disponível. A página responde apenas a `127.0.0.1`, exige senha, expira sessões após 30 minutos e não mostra chaves, tokens ou payloads pessoais.

### Tablet na rede da igreja (instalação `-Modo agente`)

O agente também escuta na porta `8097` da rede da igreja para os **tablets pareados**: com o tablet no mesmo Wi-Fi, os comandos do Holyrics vão direto ao PC, sem passar pela internet (e funcionam se ela cair). O instalador libera essa porta só em redes **Privadas** e mostra o IP do PC no final. No tablet: Configurações › PC da igreja › digite o IP › **Parear** (precisa de internet uma vez). A lista de tablets fica em `C:\DiakoNews\tablets.json` (só hashes) e as projeções feitas offline em `historico-pendente.json`, até o servidor confirmar. Para mudar a porta ou desligar: `"apiLocal": {"porta": 0}` no `agente.json`. Passo a passo e problemas comuns: `/ajuda/rede-local` no site.

## Instalar no PC da igreja
1. Leve o arquivo `DiakoServer.zip` (gerado pelo `empacotar.ps1`) e descompacte.
2. No Holyrics: **Arquivo > Configurações > API Server**. Ative, crie um token e libere estas ações:
   `GetCPInfo`, `GetCurrentPresentation`, `ShowQuickPresentation`, `ShowImage`, `ActionNext`, `ActionPrevious`,
   `ActionNextQuickPresentation`, `ActionPreviousQuickPresentation`, `CloseCurrentPresentation`, `SetF9`, `SetF10`,
   `SetTextCP`, `StartCountdownCP`, `StopCountdownCP`, `ShowCountdown`, `GetThemes`, `GetThumbnail`.
   Anote o token e a porta.
3. Descubra a **pasta de imagens do Holyrics**: no Holyrics, abra a aba de Imagens e use a opção de abrir a pasta. Copie o caminho.
4. Abra o PowerShell **como administrador** na pasta descompactada e rode:
   ```
   powershell -ExecutionPolicy Bypass -File .\instalar.ps1
   ```
   O Bloco de Notas abre o `config.json`. Preencha e salve:
   ```json
   {
     "porta": 8080,
     "senhaAdmin": "uma senha forte para o painel e o tablet",
     "holyrics": { "host": "127.0.0.1", "porta": 8091, "token": "TOKEN DO HOLYRICS" },
     "pastaImagensHolyrics": "C:\\caminho\\da\\pasta\\de\\imagens\\do\\Holyrics",
     "pastaBackup": "G:\\Meu Drive\\Igreja\\Backup DiakoNews",
     "horaBackup": "03:00",
     "urlPublica": ""
   }
   ```
   Em JSON, cada `\` do caminho vira `\\`.
5. O instalador libera a porta no firewall (só redes privadas), cria a tarefa **"DiakoNews"** que inicia com o Windows e mostra os endereços.
6. **Reserve o IP do PC no roteador** para o endereço do tablet e do QR code não mudar.

Os arquivos ficam em `C:\DiakoNews`: `config.json`, `data\` (os dados), `servidor.log` (o registro).
Para atualizar, rode o `instalar.ps1` da versão nova. Ele não mexe em `config.json` nem em `data\`.

## Uso
- **Pedidos de oração:** quem envia escolhe se o pedido pode ir para o telão. Tudo chega como *Aguardando aprovação* no tablet e no painel. Só o que for aprovado **e** marcado como público entra na projeção.
- **QR code:** o servidor gera `Diako/qr-oracao.png` na pasta de imagens do Holyrics. Use **Projetar QR no telão** no painel (aba Status) ou no tablet.
- **Caixa de mensagens:** o servidor gera `Diako/qr-mensagens.png`. Na aba *Status* do painel, baixe o QR para imprimir ou projete no Holyrics. O mural também mostra esse QR. Mensagens recebidas aparecem somente no painel e no tablet, com estados *Nova*, *Em análise* e *Resolvida*. Nome e contato são opcionais e a resposta é feita manualmente pela equipe.
- **Avisos por e-mail:** em `/admin` › *Avisos por e-mail*, informe host SMTP, porta, SSL direto (porta 465) ou STARTTLS (porta 587), usuário, senha de aplicativo se exigida, remetente e destinatário. Salve e use *Enviar e-mail de teste*. O e-mail avisa apenas o tipo da mensagem e o link do painel; não inclui texto nem contato. Uma falha de SMTP não perde a mensagem: consulte o estado na caixa de entrada e use *Tentar e-mail* após corrigir a configuração. A senha SMTP não é mostrada no painel nem incluída em backups.
- **Cartazes:** envie pelo painel (aba Cartazes) ou pelo tablet. Eles vão para a subpasta `Diako` das imagens do Holyrics e podem ser ligados a um recado.
- **Membros:** aba *Membros* do painel com o cadastro completo, em abas (*Pessoal*, *Contato*, *Igreja*, *Família*): dados pessoais (com ano de nascimento e foto), contato, endereço (digite o **CEP** e rua, bairro, cidade e UF são preenchidos pela ViaCEP; sem internet, preencha à mão), documentos, vida na igreja (status de *Visitante* a *Transferido*, batismo, membresia, ministérios, função, como conheceu), família (cônjuge e pais também cadastrados, com links entre as fichas) e contato de emergência. **Novo visitante** é o cadastro rápido da porta da igreja (nome, aniversário, telefone e como conheceu). O campo *Autorizou o uso dos dados em* registra a autorização da LGPD, e o filtro *Sem autorização* mostra quem falta. Cada cartão tem *Ligar* e *WhatsApp*; a barra do topo mostra quantas pessoas há em cada status (clique para filtrar). Tem busca, filtros (status, ministério, aniversariantes do mês), **Importar** (arquivo `.csv` ou linhas coladas da planilha com cabeçalho `Nome;Aniversário;Telefone;…`; *Baixar modelo* traz todas as colunas; o formato antigo `Nome;dd/mm` continua valendo), **Exportar CSV** (as mesmas pessoas da tela) e **Imprimir** (listagem filtrada; use *Salvar como PDF*). O recado *Aniversariantes da semana* (domingo a sábado) aparece sozinho, fixo no topo, só com quem está ativo **e autorizou o uso dos dados** (LGPD); o mesmo vale para o mural e o resumo da semana. Quem não autorizou continua na ficha: use o filtro *Sem autorização* para regularizar. Fotos e dados completos ficam atrás de login (Administrador, Pastor e Secretaria); CPF e RG aparecem ocultos na ficha (botão *Mostrar*) e não saem na impressão.
- **Administração (`/admin`):** troque o nome da igreja, os textos do formulário de pedidos, o endereço público (o QR é refeito na hora), a chave do mural, os dados do Holyrics, os padrões de projeção, a agenda de backup e a senha. Também dá para desconectar todos os aparelhos.
- **Visitantes:** três formas de cadastrar, com a pergunta "o pastor pode citar a visita no culto?": o próprio visitante pelo **QR da recepção** (`/visitante`), o **obreiro** pelo celular em `/recepcao` (usuário com o perfil *Recepção*, que só cadastra visitantes e vê os do dia) e a secretaria pelo painel. Dá para incluir quem veio junto (cônjuge, filhos), marcar interesses (visita, oração, batismo, grupo) e um pedido de oração, que vai para a aprovação. Quem volta é reconhecido pelo nome e telefone (ou aniversário). O pastor vê as pendências na seção **Visitantes** do tablet e projeta "Sejam bem-vindos!" no telão; a **TV de boas-vindas** (`/mural?tela=boas-vindas`) mostra os nomes na hora. O **Acompanhamento** (aba Membros) lista quem falta contatar, com mensagem pronta de WhatsApp. Guia completo em `/ajuda/visitantes`.
- **Autorização de dados (LGPD):** na ficha de cada pessoa há três formas de registrar a autorização, cada uma com a sua prova: **Enviar link** (link individual, válido por 7 dias e uma vez, para mandar pelo WhatsApp; a pessoa vê quais dados a igreja guarda, lê o termo e confirma, e ficam data, hora, versão do termo e IP), **Imprimir termo** + **Anexar termo assinado** (foto ou PDF do papel assinado, guardado atrás de login e no backup) e o **QR code da recepção** (aba Status; o visitante se cadastra pelo celular e já autoriza). Para menores de 18 anos é pedido o nome do responsável. *Registrar revogação* desfaz a autorização (o termo anexado é apagado). O texto do termo fica em `/admin` › LGPD: o inicial é um modelo para a igreja revisar, e cada mudança cria uma versão nova. Lá também se desliga o cadastro pelo QR.
- **Backup:** todo dia no horário configurado (padrão 03:00), um `.zip` com dados (inclusive mensagens privadas), histórico, cartazes, fotos da galeria e do cadastro de membros, termos da LGPD assinados e configurações (sem senhas, tokens nem chaves) vai para a `pastaBackup` (ou `data\backups` se ela estiver vazia). Guarde esses arquivos com cuidado. A quantidade guardada é configurável. Em `/admin` dá para baixar um backup na hora, ver a lista, baixar ou excluir qualquer um.
- **Restauração:** em `/admin`, restaure um backup da lista ou envie um `.zip` (até de outro servidor). Antes de restaurar, o servidor grava um backup de segurança do estado atual. Arquivos inválidos são recusados sem mudar nada. As configurações só são restauradas se você marcar a opção.
- **Senha:** a do `config.json` vale até ser trocada em `/admin`. Depois disso, a nova fica guardada só como hash em `data\configuracoes.json`.
- **Orações respondidas (testemunhos):** ao marcar um motivo como *atendido*, o servidor guarda a data. Edite o motivo para escrever o testemunho. Em *Atendidos* (painel ou tablet), **Projetar orações respondidas** mostra as públicas dos últimos 30 dias.
- **Mural da recepção:** abra `http://IP:8080/mural` no navegador da TV e toque na tela para ficar em tela cheia. Ele passa pelos recados válidos, cartazes, aniversariantes, motivos de oração públicos, orações respondidas e o QR de pedidos, e se atualiza sozinho a cada minuto. Para mudar o tempo de cada tela, use `?segundos=15`. Pedidos particulares e o nome de quem enviou nunca aparecem.
- **Resumo da semana:** a aba *Resumo da semana* do painel monta o texto para o grupo do WhatsApp. Revise, depois use **Copiar** ou **Abrir no WhatsApp**. O envio é feito por você: o sistema não manda mensagens sozinho.
- **Histórico:** a aba *Histórico* mostra o que foi projetado (texto, imagem, contagem, mensagem para o palco) e quando.

## Usuários e perfis
Cada pessoa da equipe pode ter o próprio usuário e senha, com um perfil: **Administrador**, **Pastor**, **Secretaria**, **Mídia** ou **Telão (tablet)**. O perfil define o que ela vê e faz no painel e no tablet. Pedidos de oração particulares e o nome de quem pediu aparecem só para Pastor e Administrador.

Cadastre em `/admin` › *Usuários e perfis*: a senha temporária aparece uma vez, e a pessoa troca em **Minha senha**, no painel. A senha definida na instalação continua valendo como a conta **admin** (no login, usuário em branco ou `admin`). Os usuários ficam em `data/usuarios.json` (só com o hash das senhas) e não vão para o backup. Detalhes e a tabela do que cada perfil pode fazer: `/ajuda/usuarios`.

## Página inicial (site da igreja)
O endereço do site (`/`) abre uma página pública com:
- **Aviso urgente** em destaque no topo e **Avisos da semana**: são os recados marcados com **Urgente** ou **Mostrar no site** (no painel ou no tablet). A data "Mostrar até" tira o aviso do ar sozinha;
- botões de **Pedido de oração** e **Fale com a igreja**;
- **Próximos eventos** do Google Agenda, com "+ Agenda" para a pessoa salvar no celular. Fica desligado até você liberar em `/admin`, porque deixa a agenda visível para qualquer pessoa;
- **Horários dos cultos**, **endereço** com "Como chegar" (Google Maps), **PIX** com chave e QR code, e links do Instagram, YouTube e WhatsApp.

**Carrossel de fotos:** no painel, aba **Galeria do site**, envie fotos (JPG ou PNG até 15 MB, até 30 fotos). A primeira é a capa; use ↑/↓ para ordenar, coloque legenda e link se quiser, e **Ocultar** tira a foto do site sem apagar. O servidor reduz as fotos para no máximo 1920 px e remove os dados escondidos da câmera (como a localização GPS). As fotos entram no backup. Para tirar o carrossel da página, desmarque "Mostrar o carrossel de fotos" em `/admin`.

Tudo se configura em `/admin` › *Página inicial*. Bloco sem conteúdo não aparece. Pedidos de oração, mensagens, nomes e aniversariantes nunca vão para a página. Para voltar ao comportamento antigo (o endereço abre o painel), desligue a página inicial no `/admin`. O painel continua em `/painel` ("Área da equipe").

## Agenda do Google
Os eventos continuam sendo criados no **Google Agenda**. O DiakoNews só lê e mostra:
- na **TV** (mural), com um slide **Hoje** e os **Próximos eventos** (7 dias por padrão, com descrição se quiser);
- no **tablet**, na aba **Agenda**, onde o pastor projeta um evento no telão ou o transforma em recado;
- no **painel**, na aba *Agenda*, com o botão **Criar recado**;
- no **resumo da semana** para o WhatsApp.

Para ligar:
1. No Google Agenda (no computador), abra **Configurações e compartilhamento** da agenda da igreja.
2. Em **Integrar agenda**, copie o **Endereço secreto no formato iCal**.
3. Em `/admin` › *Agenda (Google)*, cole o endereço, clique em **Testar** e depois em **Salvar**.

O servidor busca a agenda a cada 15 minutos (use **Atualizar agora** para não esperar). O próprio Google pode levar alguns minutos para publicar as mudanças. Sem internet, a última cópia continua aparecendo.

Trate o endereço secreto como uma senha: ele dá acesso a todos os eventos. Ele não aparece no painel nem vai para os backups. Se vazar, use **Redefinir** no Google e cole o novo endereço.

### Criar e editar eventos pelo DiakoNews
Com uma **conta de serviço** do Google (gratuita), o painel e o tablet também **criam, editam e excluem** eventos direto na agenda da igreja, e as mudanças aparecem na hora (o servidor passa a ler pela API do Google em vez do iCal). Resumo:
1. No Google Cloud, crie um projeto, ative a **Google Calendar API** e crie uma conta de serviço com uma chave **JSON**.
2. No Google Agenda, compartilhe a agenda da igreja com o e-mail da conta de serviço com a permissão **Fazer alterações e ver detalhes do evento**.
3. Em `/admin` › *Agenda (Google)* › *Criar e editar eventos pelo DiakoNews*, envie o arquivo JSON e clique em **Testar e ligar**.

O passo a passo completo, com os problemas comuns, fica no próprio servidor em **`/ajuda/agenda-google`**. A chave é guardada em `data/google-conta-servico.json`, não vai para os backups e nunca aparece no painel. Eventos que se repetem continuam sendo alterados no Google Agenda.

## Problemas comuns
Para testar o Holyrics **real** neste PC sem projetar nada, rode na raiz do projeto:
`powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\diagnosticar_holyrics.ps1`
O script testa a porta 8091, pede o token em entrada oculta e consulta apenas `GetCPInfo` e `GetCurrentPresentation`.
Use `-SemToken` para verificar só a porta; nesse caso não há confirmação da autenticação nem da API.
Para **projetar um texto de teste** (opcional), acrescente `-ProjetarTexto`. O script só envia
`ShowQuickPresentation` após confirmar que não há apresentação ativa e pedir que você digite `SIM`;
qualquer outra resposta cancela. Não rode durante um culto. O script não fecha a projeção de teste.
Se um token foi compartilhado fora do PC, revogue-o e crie outro antes de testar.
Não use `tool/rodar_local.ps1` para diagnosticar a instalação real sem revisar a configuração:
ele configura o token de desenvolvimento `teste` e pode iniciar um Holyrics simulado.

| Sintoma | O que verificar |
|---|---|
| Tablet ou celular não abre o endereço | Estão no mesmo Wi-Fi? A rede do Windows está como **Privada**? O IP mudou? |
| "Holyrics: Sem conexão" no painel | O Holyrics está aberto, a API Server está ativa e o token/porta conferem com o `config.json`? |
| Cartaz não aparece no Holyrics | `pastaImagensHolyrics` aponta para a pasta certa? Talvez seja preciso atualizar a lista de imagens no Holyrics. |
| Servidor não sobe | Veja `C:\DiakoNews\servidor.log`. Rodar `C:\DiakoNews\diako_server.exe` num PowerShell mostra o erro na tela. |

## Para desenvolvedores
```
dart pub get
dart test                                  # testes
dart run tool/fake_holyrics.dart 8091 teste  # Holyrics simulado
dart run bin/diako_server.dart config.json # servidor (config.json nesta pasta)
powershell -File empacotar.ps1             # gera dist\DiakoServer.zip
```
