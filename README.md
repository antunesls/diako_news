# DiakoNews

Sistema da Igreja Diakonia Tulipas para projetar recados e motivos de oração no Holyrics.

```
 Celular (membro) ──QR──▶ /oracao ─┐
 Navegador (secretaria) ─▶ /painel ├─▶  Servidor DiakoNews (PC do Holyrics) ──▶ Holyrics
 TV da recepção ─────────▶ /mural  │      dados, cartazes, histórico, backup
 Tablet do pastor (este app) ──────┘
```
No painel também ficam o **resumo da semana para o WhatsApp**, o **histórico** do que foi projetado e o **cadastro de membros** (dados completos, foto, família e ministérios — veja o [`LEIA-ME do servidor`](server/LEIA-ME.md)).

| Pasta | O que é |
|---|---|
| `server/` | Servidor: guarda os dados, tem o site de pedidos de oração, o painel e o mural, e comanda o Holyrics. Roda no PC do Holyrics ([`server/LEIA-ME.md`](server/LEIA-ME.md)) ou na internet, num LXC/VPS, com um agente no PC da igreja ([`docs/HOSPEDAGEM.md`](docs/HOSPEDAGEM.md)). |
| `lib/` | App Android (Flutter) do tablet do pastor. |
| `packages/diako_core/` | Modelos e regras usados pelo app e pelo servidor (recados, motivos, slides, aniversariantes). |

## Funções do app
- **Recados** com categorias (Aviso, Evento, Aniversário), fixos no topo, validade (expirados vão para uma aba própria) e ordenação arrastando. O recado **Aniversariantes da semana** é gerado sozinho pelo servidor.
- **Projetar** um recado com um toque, ou a **Sequência** dos selecionados passando sozinha.
- **Cartazes:** escolha uma imagem já enviada ou **envie uma foto do tablet**. Ela vai direto para o Holyrics.
- **Motivos de oração:** pedidos enviados pelo site chegam em **Aguardando**, com um aviso na hora. O pastor aprova ou recusa. Pedidos particulares (cadeado) nunca vão para o telão. **Projetar motivos** mostra vários por slide, e há um botão para **projetar o QR** do formulário de pedidos.
- **Caixa de mensagens:** um QR separado leva a `/mensagens`, onde qualquer pessoa envia dúvida, sugestão ou crítica, anonimamente ou com contato opcional. Painel e tablet mostram as mensagens privadas como **Nova**, **Em análise** e **Resolvida**. Na administração, configure o SMTP para receber um aviso por e-mail (sem o conteúdo da mensagem). O QR também pode ser projetado e aparece no mural.
- **Orações respondidas:** atendidos mostram a data e o testemunho (editável). Um botão projeta as respondidas dos últimos 30 dias.
- **Agenda (Google Agenda):** aba com os próximos eventos por dia. O pastor projeta um evento no telão ou o transforma em recado. O próximo evento aparece também no topo da aba Recados. A TV mostra "Hoje" e os próximos eventos, e o resumo semanal inclui a agenda. A configuração fica em `/admin` (veja o [LEIA-ME do servidor](server/LEIA-ME.md#agenda-do-google)).
- **Barra de controle:** anterior, parar, próximo, tela vazia (F9) e tela preta (F10). Mostra o que está no ar.
- Contagem regressiva no telão e no palco, além de mensagem no painel de comunicação.
- **Sincronização ao vivo** com o servidor. Sem conexão, o app mostra a última cópia salva e bloqueia a edição.

## 1. Instalar o servidor
- **No PC do Holyrics** (só na rede da igreja): siga o [`server/LEIA-ME.md`](server/LEIA-ME.md). No fim, ele mostra o **endereço** (ex: `http://192.168.0.10:8080`) e você define a **senha**.
- **Na internet** (LXC/VPS + agente no PC da igreja, acesso de qualquer lugar): siga o [`docs/HOSPEDAGEM.md`](docs/HOSPEDAGEM.md). O endereço será o seu domínio (ex: `diako.minhaigreja.com.br`).

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

Para instalar sem cabo, envie o `app-release.apk` para o tablet (WhatsApp, Drive) e abra o arquivo.

## 4. Primeiro uso
Abra **Configurações** (engrenagem), digite o endereço do servidor e a senha e toque em **Entrar**.
Se aparecer `<b>` no telão em volta do título, desligue **Título em negrito**.

## Publicar uma versão (GitHub Releases)
O GitHub Actions faz tudo. A cada push roda o workflow **CI** (testes do servidor e do app, mais um APK de teste). Ao enviar uma tag, roda o workflow **Release**:
```
git tag v1.0.0
git push origin v1.0.0
```
Em alguns minutos aparece em **Releases** uma versão com:
- `DiakoServer-1.0.0.zip`: o servidor para o PC do Holyrics (instalar com `instalar.ps1`).
- `DiakoNews-1.0.0.apk`: o app para baixar e instalar no tablet.

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
  holyrics/holyrics_client.dart   comandos do Holyrics (passam pelo servidor)
  data/                           repositórios de recados e motivos, configurações
  ui/                             telas
```
