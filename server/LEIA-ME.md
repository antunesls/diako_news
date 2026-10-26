# Servidor DiakoNews

Programa que roda **no PC do Holyrics** e centraliza recados, motivos de oração, cartazes e aniversariantes.
O tablet, o painel da secretaria e o formulário de pedidos de oração conversam com ele, e ele comanda o Holyrics.

| Endereço | Para quem | Precisa de senha? |
|---|---|---|
| `http://IP:8080/oracao` | Membros (pelo QR code) enviam pedidos de oração | Não |
| `http://IP:8080/mensagens` | Membros (por outro QR) enviam dúvidas, sugestões e críticas | Não |
| `http://IP:8080/painel` | Secretaria/pastor: recados, aprovar pedidos, cartazes, aniversariantes, resumo da semana, histórico | Sim |
| `http://IP:8080/admin` | Administração: nome e textos, mural, Holyrics, projeção, backup/restauração, senha | Sim |
| `http://IP:8080/mural` | TV da recepção: avisos passando sozinhos | Não |
| `http://IP:8080` | Endereço que vai nas configurações do app do tablet | Sim |

Instalado assim, funciona para quem está no **Wi-Fi da igreja**. Para acessar de qualquer lugar, hospede o servidor na internet (LXC/VPS) e instale só o agente no PC da igreja: veja [`docs/HOSPEDAGEM.md`](../docs/HOSPEDAGEM.md).

## Instalar no PC da igreja
1. Leve o arquivo `DiakoServer.zip` (gerado pelo `empacotar.ps1`) e descompacte.
2. No Holyrics: **Arquivo > Configurações > API Server**. Ative, crie um token e libere estas ações:
   `GetCPInfo`, `GetCurrentPresentation`, `ShowQuickPresentation`, `ShowImage`, `ActionNext`, `ActionPrevious`,
   `ActionNextQuickPresentation`, `ActionPreviousQuickPresentation`, `CloseCurrentPresentation`, `SetF9`, `SetF10`,
   `SetTextCP`, `StartCountdownCP`, `StopCountdownCP`, `ShowCountdown`, `GetThemes`.
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
- **Aniversariantes:** cadastre os membros (ou cole a lista `Nome;dd/mm`). O recado *Aniversariantes da semana* (domingo a sábado) aparece sozinho, fixo no topo.
- **Administração (`/admin`):** troque o nome da igreja, os textos do formulário de pedidos, o endereço público (o QR é refeito na hora), a chave do mural, os dados do Holyrics, os padrões de projeção, a agenda de backup e a senha. Também dá para desconectar todos os aparelhos.
- **Backup:** todo dia no horário configurado (padrão 03:00), um `.zip` com dados (inclusive mensagens privadas), histórico, cartazes e configurações (sem senhas, tokens nem chaves) vai para a `pastaBackup` (ou `data\backups` se ela estiver vazia). Guarde esses arquivos com cuidado. A quantidade guardada é configurável. Em `/admin` dá para baixar um backup na hora, ver a lista, baixar ou excluir qualquer um.
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
