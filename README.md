# Diako News

Sistema da Igreja Diakonia Tulipas para projetar recados e motivos de oração no Holyrics.

```
 Celular (membro) ──QR──▶ /oracao ─┐
 Navegador (secretaria) ─▶ /painel ├─▶  Servidor Diako News (PC do Holyrics) ──▶ Holyrics
 TV da recepção ─────────▶ /mural  │      dados, cartazes, histórico, backup
 Tablet do pastor (este app) ──────┘
```
No painel também ficam o **resumo da semana para o WhatsApp** e o **histórico** do que foi projetado.

| Pasta | O que é |
|---|---|
| `server/` | Servidor que roda no PC do Holyrics: guarda os dados, tem o site de pedidos de oração e o painel, e comanda o Holyrics. Instalação em [`server/LEIA-ME.md`](server/LEIA-ME.md). |
| `lib/` | App Android (Flutter) do tablet do pastor. |
| `packages/diako_core/` | Modelos e regras usados pelo app e pelo servidor (recados, motivos, slides, aniversariantes). |

## Funções do app
- **Recados** com categorias (Aviso, Evento, Aniversário), fixos no topo, validade (expirados vão para uma aba própria) e ordenação arrastando. O recado **Aniversariantes da semana** é gerado sozinho pelo servidor.
- **Projetar** um recado com um toque, ou a **Sequência** dos selecionados passando sozinha.
- **Cartazes:** escolha uma imagem já enviada ou **envie uma foto do tablet**. Ela vai direto para o Holyrics.
- **Motivos de oração:** pedidos enviados pelo site chegam em **Aguardando**, com um aviso na hora. O pastor aprova ou recusa. Pedidos particulares (cadeado) nunca vão para o telão. **Projetar motivos** mostra vários por slide, e há um botão para **projetar o QR** do formulário de pedidos.
- **Orações respondidas:** atendidos mostram a data e o testemunho (editável). Um botão projeta as respondidas dos últimos 30 dias.
- **Barra de controle:** anterior, parar, próximo, tela vazia (F9) e tela preta (F10). Mostra o que está no ar.
- Contagem regressiva no telão e no palco, além de mensagem no painel de comunicação.
- **Sincronização ao vivo** com o servidor. Sem conexão, o app mostra a última cópia salva e bloqueia a edição.

## 1. Instalar o servidor no PC do Holyrics
Siga o [`server/LEIA-ME.md`](server/LEIA-ME.md). No fim, ele mostra o **endereço** (ex: `http://192.168.0.10:8080`) e você define a **senha**.

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
