# DiakoHub

Plataforma da Igreja Diakonia Tulipas. Junta num só lugar o **site da igreja**, o **painel da equipe**, o **telão** (Holyrics), o **tablet do pastor**, as **TVs** da recepção, o cadastro de **membros e visitantes**, as **escalas e o repertório do louvor** e a preparação da **Palavra**.

```
 Celular (membro/visitante) ─▶ /  /oracao  /mensagens  /visitante  /minha-escala ─┐
 Navegador (equipe) ────────▶ /painel  /admin  /recepcao ─────────────────────────┤
 TVs da igreja ─────────────▶ /mural  (mural de informações e TV de boas-vindas) ─┤
 Tablet do pastor (app) ───────────────────────────────────────────────────────────┤
                                                                                   ▼
                                     Servidor DiakoHub: dados, cartazes, histórico, backup
                                     (no PC do Holyrics, ou na internet + agente no PC)
                                                                                   │
                                                                                   ▼
                                                                    Holyrics (telão e palco)
```

## O que a plataforma faz

### Site público
- **Página inicial (`/`):** avisos da semana e aviso urgente, próximos eventos do Google Agenda, horários dos cultos, endereço com "Como chegar", PIX com QR, redes sociais e carrossel de fotos. Tudo se configura em `/admin`, e o que não tem conteúdo não aparece.
- **Pedidos de oração (`/oracao`):** quem pede escolhe se o pedido pode ir para o telão. Pedidos particulares nunca são projetados nem aparecem no mural.
- **Caixa de mensagens (`/mensagens`):** dúvidas, sugestões e críticas, anônimas ou com contato. A equipe recebe aviso por e-mail (sem o conteúdo).
- **Cadastro de visitante (`/visitante`):** o visitante se cadastra pelo QR da recepção e já autoriza o uso dos dados (LGPD).
- **Minha escala (`/minha-escala`):** cada integrante entra com usuário e senha e vê só os próprios cultos, com as músicas, o tom e o link do YouTube; também avisa indisponibilidades.

### Painel da equipe (`/painel`)
Menu organizado por área; cada pessoa vê só o que o seu perfil permite.

| Área | Páginas |
|---|---|
| Início | Visão geral |
| Acompanhamento | Motivos de oração (aprovação, testemunhos), Mensagens (*Nova*, *Em análise*, *Resolvida*), Membros (cadastro completo, família, visitantes, acompanhamento, LGPD) |
| Cultos | Escalas pastoral e do louvor, Repertório, Roteiros do Modo Culto, Palavras (sermões) |
| Comunicação | Agenda (Google), Recados, Cartazes, Galeria do site, Resumo da semana para o WhatsApp |
| Operação | Histórico do que foi projetado, Status (Holyrics, agente, QR codes), Acessos às escalas, Administração |

### Tablet do pastor (app Android)
Opera o telão durante o culto: recados, cartazes, motivos de oração, boas-vindas aos visitantes, agenda, escala do dia, **Modo Culto** com o roteiro passo a passo e a leitura da **Palavra** com versículos e frases de destaque. Funciona com a última cópia salva se a internet cair. Detalhes em [Funções do app](#funções-do-app).

### TVs da igreja
- **Mural de informações (`/mural`):** passa recados, cartazes, aniversariantes, motivos públicos, orações respondidas, agenda e os QR codes. Atualiza sozinho.
- **TV de boas-vindas (`/mural?tela=boas-vindas`):** mostra o nome dos visitantes assim que são cadastrados.

### Pessoas e LGPD
- **Membros:** ficha em abas (*Pessoal*, *Contato*, *Igreja*, *Família*), foto, CEP com preenchimento automático, ministérios, importação e exportação em CSV e impressão.
- **Visitantes:** três formas de cadastrar (QR da recepção, obreiro pelo celular em `/recepcao`, secretaria pelo painel), quem veio junto, interesses e acompanhamento com mensagem pronta de WhatsApp.
- **LGPD:** autorização com prova (link individual, termo assinado anexado ou QR), revogação e termo versionado. Aniversariantes só aparecem para quem autorizou.

### Escalas, repertório e PDF
- **Escalas pastoral e do louvor:** cultos do mês gerados pelos horários cadastrados, sugestão de pessoas por ministério, avisos de conflito e de indisponibilidade, texto pronto para o WhatsApp.
- **Repertório pesquisável:** a busca procura título, cantor e compositor sem diferenciar acentos, aceita palavras fora de ordem e tolera pequenos erros; há filtros por status e tom. O tom usa 12 maiores, 12 menores e "Não definido". O status **OK** disponibiliza a música para novas escalas; **Em análise** e **Inativo** não.
- **Importação da planilha:** CSV exportado do Google Sheets. Músicas já cadastradas não são alteradas, exceto para ganhar o link do vídeo quando ainda não têm um.
- **Músicas da escala:** a escolha abre uma janela com busca, miniatura e link do YouTube, tom e BPM; a ordem e o tom de cada música são definidos na escala do culto.
- **Indisponibilidades:** quem administra escalas vê todos os avisos ativos, com integrante, conta que enviou, data, período e motivo, e pode cancelar.
- **PDF da escala:** baixado direto, como *quadro mensal* (A4 paisagem) ou *cartões por culto* (A4 retrato), com logo e cabeçalho da igreja.

### Administração, segurança e backup (`/admin`)
- **Usuários e perfis** com senha própria (guardada só como hash) e permissões por perfil.
- **Configurações:** nome da igreja, página inicial, Holyrics, padrões de projeção, chave do mural, agenda do Google, e-mail (SMTP) e termo da LGPD.
- **Backup diário** em `.zip` com dados, cartazes, fotos e termos (sem senhas nem chaves), restauração pelo `/admin` e, com o servidor na internet, cópia **cifrada** no PC da igreja. Falhas geram alerta no painel e por e-mail.

## Perfis de acesso

| Perfil | O que faz |
|---|---|
| Administrador | Tudo, inclusive configurações, backup e usuários. |
| Pastor | Todo o conteúdo, inclusive pedidos particulares. Sem configurações técnicas. |
| Secretaria | Recados, agenda, mensagens, membros, visitantes, aniversariantes e acessos às escalas. |
| Mídia | Cartazes, galeria do site, recados e projeção no telão. |
| Telão (tablet) | Operar o telão no culto: recados, pedidos públicos, boas-vindas e projeção. |
| Recepção | Cadastra visitantes pelo celular (`/recepcao`) e vê os do dia. |
| Comissão do Louvor | Monta a escala e as músicas do louvor; vê a escala pastoral e a agenda. |
| Ministro | Escolhe as músicas dos cultos em que ministra. |
| Pregador | Prepara as próprias Palavras no painel. |
| Louvor / Integrante | Consulta a própria escala e avisa indisponibilidades. |

A tabela completa fica em `/ajuda/usuarios`, no próprio site.

## Endereços

| Endereço | Para quem |
|---|---|
| `/` | Página inicial pública da igreja |
| `/oracao`, `/mensagens`, `/visitante` | Formulários públicos (também abertos pelos QR codes) |
| `/minha-escala` | Integrantes das escalas (com login) |
| `/painel` | Equipe (com login) |
| `/admin` | Administração (com login) |
| `/recepcao` | Obreiro da recepção (com login) |
| `/mural` | TVs da igreja (exige `?chave=`; TV de boas-vindas: `&tela=boas-vindas`) |
| `/ajuda/...` | Guias passo a passo: agenda, usuários, visitantes, tablet na rede local |

## Onde roda
- **No PC do Holyrics:** tudo num computador só, acessível na rede da igreja. Instalação em [`server/LEIA-ME.md`](server/LEIA-ME.md).
- **Na internet (LXC/VPS):** o servidor fica num domínio próprio e um **agente** no PC da igreja liga o servidor ao Holyrics. O tablet fala direto com o agente quando está no Wi-Fi da igreja e continua funcionando se a internet cair. Instalação em [`docs/HOSPEDAGEM.md`](docs/HOSPEDAGEM.md).

## Estrutura do repositório

| Pasta | O que é |
|---|---|
| `server/` | Servidor (Dart + shelf): API, site, painel, mural, PDF, backup e o agente do PC da igreja (`bin/diako_agente.dart`). |
| `server/web/` | Páginas do site e do painel (HTML, CSS e JavaScript, sem framework). |
| `lib/` | App Android (Flutter) do tablet do pastor. |
| `packages/diako_core/` | Modelos e regras usados pelo app e pelo servidor (recados, motivos, slides, aniversariantes, escalas, repertório, visitantes e roteiros). |
| `docs/` | Hospedagem, propostas e planos de funcionalidades. |
| `tool/` | Scripts: rodar localmente com Holyrics simulado, diagnóstico do Holyrics, chave de assinatura do APK. |

## Funções do app
- **Recados** com categorias (Aviso, Evento, Aniversário), fixos no topo, validade (expirados vão para uma aba própria) e ordenação arrastando. O recado **Aniversariantes da semana** é gerado sozinho pelo servidor, só com quem autorizou o uso dos dados (LGPD).
- **Projetar** um recado com um toque, ou a **Sequência** dos selecionados passando sozinha.
- **Cartazes:** escolha uma imagem já enviada ou **envie uma foto do tablet**. Ela vai direto para o Holyrics.
- **Motivos de oração:** pedidos enviados pelo site chegam em **Aguardando**, com um aviso na hora. O pastor aprova ou recusa. Pedidos particulares (cadeado) nunca vão para o telão. **Projetar motivos** mostra vários por slide, e há um botão para **projetar o QR** do formulário de pedidos.
- **Caixa de mensagens:** um QR separado leva a `/mensagens`, onde qualquer pessoa envia dúvida, sugestão ou crítica, anonimamente ou com contato opcional. Painel e tablet mostram as mensagens privadas como **Nova**, **Em análise** e **Resolvida**. Na administração, configure o SMTP para receber um aviso por e-mail (sem o conteúdo da mensagem). O QR também pode ser projetado e aparece no mural.
- **Orações respondidas:** atendidos mostram a data e o testemunho (editável). Um botão projeta as respondidas dos últimos 30 dias.
- **Visitantes:** pendências de boas-vindas com um toque para projetar "Sejam bem-vindos!" no telão.
- **Agenda (Google Agenda):** aba com os próximos eventos por dia. O pastor projeta um evento no telão ou o transforma em recado. O próximo evento aparece também no topo da aba Recados. A TV mostra "Hoje" e os próximos eventos, e o resumo semanal inclui a agenda. A configuração fica em `/admin` (veja o [LEIA-ME do servidor](server/LEIA-ME.md#agenda-do-google)).
- **Escala e repertório:** mostra quem serve no culto de hoje (pastoral e louvor) e as músicas escolhidas do repertório da igreja. Se não houver culto hoje, mostra o próximo em até 7 dias; mantém a última cópia para consulta sem conexão. O repertório e as escalas são mantidos no painel ([instruções](server/LEIA-ME.md#escalas-pastoral-e-do-louvor)).
- **Coluna do palco:** fica sempre à direita, em qualquer seção. Mostra a conexão com o Holyrics, o que está no ar, a prévia do recado tocado, anterior, parar e próximo em botões grandes, tela vazia (F9), tela preta (F10), a contagem e as frases prontas do palco. As seções ficam num trilho à esquerda, com o número de pendências em cada uma.
- **Modo Culto:** segunda tela, só para o horário do culto (botão no trilho, ou o aviso que aparece a partir de 1 h antes do culto da escala). O app monta o roteiro do dia: contagem até a hora do culto, boas-vindas aos visitantes, louvor (músicas, tons e escalados; tela vazia no telão), recados um por vez, dízimos e ofertas (com o QR do PIX quando a chave está configurada em Administração › Página inicial), Santa Ceia (quando a escala marca), motivos de oração, Palavra (tela preta, cronômetro da pregação e avisos ao palco), oração final e encerramento com os QR codes e o próximo evento. Um toque em **Avançar** projeta o próximo passo; pedidos e visitantes que chegam aparecem num canto. O ponto do roteiro fica salvo se o app fechar. Para sair, segure **Sair** (pede o PIN, se houver). A ordem dos momentos, os tempos e momentos livres (apresentação de crianças, batismo) são montados no painel, na página **Roteiros**: um modelo por tipo de culto, mais um padrão.
- **Palavra do pastor:** o sermão é preparado no painel (página **Palavras**): colar o texto ou importar Word, PDF, TXT ou um documento do Google Docs (compartilhado com a conta de serviço do Google da agenda), cada parágrafo vira um trecho e linhas com `#` viram tópicos. O painel acha os versículos citados ("Jo 3.16", "1 Coríntios 13:4-7") e o pastor confirma, ajusta ou ignora cada um; cada salvamento guarda a versão anterior. A Palavra **pronta** com a data do culto desce para o tablet (e fica salva nele para funcionar sem internet): no Modo Culto, **Próximo trecho** passa o texto para a TV do palco e um toque no versículo o projeta no telão. Perfil **Pregador**: cada pregador cuida só das próprias Palavras. O tempo de cada tópico vai no próprio tópico (`# A mesa preparada (10 min)`); durante a leitura, o tablet mostra o tempo no tópico e se a pregação está adiantada ou atrasada, só para o pastor. Frases marcadas com `**dois asteriscos**` (botão **Destacar frase**) viram botões no tablet: um toque projeta a frase no telão, entre aspas. O botão **Ensaiar** percorre a Palavra em tela cheia no painel, sem projetar nada, mede o tempo de cada tópico e mostra previsto × ensaio; o tempo do ensaio pode ser guardado na Palavra. A lista de Palavras tem busca (título, texto ou versículo citado, como "Jo 3") e filtro por série; o botão **Resumo para o WhatsApp** monta título, tópicos, versículos e frases para copiar.
- Contagem regressiva no telão e no palco, além de mensagem no painel de comunicação.
- **Sincronização ao vivo** com o servidor. Sem conexão, o app mostra a última cópia salva e bloqueia a edição.

## 1. Instalar o servidor
- **No PC do Holyrics** (só na rede da igreja): siga o [`server/LEIA-ME.md`](server/LEIA-ME.md). No fim, ele mostra o **endereço** (ex: `http://192.168.0.10:8080`) e você define a **senha**.
- **Na internet** (LXC/VPS + agente no PC da igreja, acesso de qualquer lugar): siga o [`docs/HOSPEDAGEM.md`](docs/HOSPEDAGEM.md). O endereço será o seu domínio (ex: `diako.minhaigreja.com.br`).

O jeito mais simples é baixar o pacote pronto em [Releases](https://github.com/antunesls/diakohub/releases) (veja [Publicar uma versão](#publicar-uma-versão-github-releases)).

## 2. Instalar as ferramentas (uma vez, no seu PC)
1. Instale o [Flutter](https://docs.flutter.dev/get-started/install/windows/mobile) e o Android Studio, depois rode `flutter doctor` até ficar tudo verde.
2. No tablet: ative as *Opções do desenvolvedor* e a *Depuração USB*.

## 3. Gerar e instalar o app
Na pasta do projeto:
```
flutter create --org br.diako --platforms android .
flutter pub get
dart run flutter_launcher_icons   # ícone do app a partir do logo
flutter test
flutter run            # com o tablet conectado por USB
flutter build apk      # gera build/app/outputs/flutter-apk/app-release.apk
```
O `flutter create .` cria só o que falta na pasta `android/` e mantém o `lib/` e o `AndroidManifest.xml` que já existem. Esse manifesto libera o acesso à rede local.

Para instalar sem cabo, envie o `app-release.apk` para o tablet (WhatsApp, Drive) e abra o arquivo, ou baixe o `DiakoHub-*.apk` da última release direto no tablet.

## 4. Primeiro uso
Abra **Configurações** (engrenagem), digite o endereço do servidor e a senha e toque em **Entrar**.
Se aparecer `<b>` no telão em volta do título, desligue **Título em negrito**.

Com o servidor na internet, o tablet pode ser **pareado** com o PC da igreja (Configurações › PC da igreja) para falar direto com o Holyrics pelo Wi-Fi. Passo a passo em `/ajuda/rede-local`.

## Desenvolvimento
Requisitos: Dart 3.5+ e Flutter (para o app).

```
cd packages/diako_core && dart test          # modelos e regras compartilhados
cd server && dart analyze && dart test       # servidor e agente
flutter analyze && flutter test              # app do tablet
```

Para rodar tudo no seu PC com um Holyrics simulado: `powershell -ExecutionPolicy Bypass -File .\tool\rodar_local.ps1`. Mais detalhes em [Para desenvolvedores](server/LEIA-ME.md#para-desenvolvedores).

## Publicar uma versão (GitHub Releases)
O GitHub Actions faz tudo. A cada push roda o workflow **CI** (testes do servidor, do pacote compartilhado e do app, mais um APK de teste). Ao enviar uma tag, roda o workflow **Release**:
```
git tag v1.0.0
git push origin v1.0.0
```
Em alguns minutos aparece em **Releases** uma versão com:
- `DiakoServer-1.0.0.zip`: o servidor para o PC do Holyrics (instalar com `instalar.ps1`).
- `DiakoServer-linux-x64-1.0.0.tar.gz`: o servidor para LXC/VPS (veja [`docs/HOSPEDAGEM.md`](docs/HOSPEDAGEM.md)).
- `DiakoHub-1.0.0.apk`: o app para baixar e instalar no tablet.

**Assinatura do APK (fazer uma vez):** para que cada versão nova instale por cima da anterior, o APK precisa ser assinado sempre com a mesma chave.
1. Rode `powershell -ExecutionPolicy Bypass -File .\tool\gerar_keystore.ps1` (precisa do Android Studio ou de um JDK).
2. Cadastre os 4 secrets que ele mostra em **Settings > Secrets and variables > Actions**.
3. Guarde o arquivo `.jks` e a senha em lugar seguro. Se perder, o app terá de ser desinstalado e instalado de novo.

Sem os secrets, a release sai assinada com uma chave temporária. Funciona, mas cada atualização exige desinstalar o app antes.

## Estrutura do app
```
lib/
  sync/server_api.dart            REST do servidor (login, recados, motivos, cartazes, Holyrics)
  sync/repo_sincronizado.dart     lista do servidor com cópia local para uso sem conexão
  sync/tempo_real.dart            WebSocket: recarrega quando algo muda no servidor
  holyrics/holyrics_client.dart   comandos do Holyrics (pelo agente na rede local ou pelo servidor)
  data/                           repositórios de recados e motivos, configurações
  ui/                             telas
```

## Nomes técnicos
O sistema se chamava **DiakoNews**. Alguns nomes internos continuam assim para não exigir reinstalação: o serviço `diako-news` e a pasta `/opt/diako-news` no servidor, a pasta `C:\DiakoNews` e as tarefas do Windows no PC da igreja, a pasta de mídia `DiakoNews/` no Holyrics e os pacotes `diako_core` e `diako_server`.
