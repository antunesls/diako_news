# Servidor Diako News

Programa que roda **no PC do Holyrics** e centraliza recados, motivos de oração, cartazes e aniversariantes.
O tablet, o painel da secretaria e o formulário de pedidos de oração conversam com ele, e ele comanda o Holyrics.

| Endereço | Para quem | Precisa de senha? |
|---|---|---|
| `http://IP:8080/oracao` | Membros (pelo QR code) enviam pedidos de oração | Não |
| `http://IP:8080/painel` | Secretaria/pastor: recados, aprovar pedidos, cartazes, aniversariantes, resumo da semana, histórico | Sim |
| `http://IP:8080/mural` | TV da recepção: avisos passando sozinhos | Não |
| `http://IP:8080` | Endereço que vai nas configurações do app do tablet | Sim |

Funciona só para quem está no **Wi-Fi da igreja**.

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
     "pastaBackup": "G:\\Meu Drive\\Igreja\\Backup Diako News",
     "horaBackup": "03:00",
     "urlPublica": ""
   }
   ```
   Em JSON, cada `\` do caminho vira `\\`.
5. O instalador libera a porta no firewall (só redes privadas), cria a tarefa **"Diako News"** que inicia com o Windows e mostra os endereços.
6. **Reserve o IP do PC no roteador** para o endereço do tablet e do QR code não mudar.

Os arquivos ficam em `C:\DiakoNews`: `config.json`, `data\` (os dados), `servidor.log` (o registro).
Para atualizar, rode o `instalar.ps1` da versão nova. Ele não mexe em `config.json` nem em `data\`.

## Uso
- **Pedidos de oração:** quem envia escolhe se o pedido pode ir para o telão. Tudo chega como *Aguardando aprovação* no tablet e no painel. Só o que for aprovado **e** marcado como público entra na projeção.
- **QR code:** o servidor gera `Diako/qr-oracao.png` na pasta de imagens do Holyrics. Use **Projetar QR no telão** no painel (aba Status) ou no tablet.
- **Cartazes:** envie pelo painel (aba Cartazes) ou pelo tablet. Eles vão para a subpasta `Diako` das imagens do Holyrics e podem ser ligados a um recado.
- **Aniversariantes:** cadastre os membros (ou cole a lista `Nome;dd/mm`). O recado *Aniversariantes da semana* (domingo a sábado) aparece sozinho, fixo no topo.
- **Backup:** todo dia no horário configurado, um `.zip` com os dados e o histórico vai para a `pastaBackup`. Ficam os 30 mais recentes. Também dá para fazer na hora pelo painel.
- **Orações respondidas (testemunhos):** ao marcar um motivo como *atendido*, o servidor guarda a data. Edite o motivo para escrever o testemunho. Em *Atendidos* (painel ou tablet), **Projetar orações respondidas** mostra as públicas dos últimos 30 dias.
- **Mural da recepção:** abra `http://IP:8080/mural` no navegador da TV e toque na tela para ficar em tela cheia. Ele passa pelos recados válidos, cartazes, aniversariantes, motivos de oração públicos, orações respondidas e o QR de pedidos, e se atualiza sozinho a cada minuto. Para mudar o tempo de cada tela, use `?segundos=15`. Pedidos particulares e o nome de quem enviou nunca aparecem.
- **Resumo da semana:** a aba *Resumo da semana* do painel monta o texto para o grupo do WhatsApp. Revise, depois use **Copiar** ou **Abrir no WhatsApp**. O envio é feito por você: o sistema não manda mensagens sozinho.
- **Histórico:** a aba *Histórico* mostra o que foi projetado (texto, imagem, contagem, mensagem para o palco) e quando.

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
