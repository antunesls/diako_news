# Hospedar o DiakoNews na internet (LXC / VPS)

Com o servidor na internet, o painel, o formulário de pedidos de oração, o mural e o tablet funcionam de qualquer lugar. O Holyrics continua no PC da igreja. Lá roda um pequeno **agente**, que se conecta ao servidor **para fora** (não é preciso abrir portas no roteador da igreja).

```
Tablet / painel / celulares ──HTTPS──▶ Caddy ──▶ diako_server      (LXC na internet)
                                                      ▲
                                                      │ conexão segura iniciada pelo PC da igreja
PC da igreja: diako_agente.exe ───────────────────────┘
   ├─▶ Holyrics (API Server local)
   └─▶ pasta de imagens do Holyrics\Diako  (cartazes e QR sincronizados)
```

## O que você precisa
- Um **LXC ou VPS** com **Debian 12** ou **Ubuntu 22.04+** (x86_64). 1 vCPU, 512 MB de RAM e 2 GB de disco são suficientes.
- Um **domínio ou subdomínio** (ex: `diako.minhaigreja.com.br`) com registro **A/AAAA** apontando para o IP público do servidor.
- As portas **80 e 443** liberadas até o LXC (no Proxmox/roteador/firewall do provedor), para o HTTPS automático.

No **Proxmox**, um container *unprivileged* com Debian 12 serve. Com a opção *nesting* ligada (padrão nas versões recentes), o serviço roda com isolamento extra do systemd. Sem ela, o instalador detecta e segue sem o isolamento.

## 1. Instalar o servidor no LXC
Pegue o link do `DiakoServer-linux-x64-X.Y.Z.tar.gz` na [página de releases](../../releases) e, como root no LXC:
```bash
cd /tmp
curl -LO https://github.com/antunesls/diako_news/releases/download/vX.Y.Z/DiakoServer-linux-x64-X.Y.Z.tar.gz
tar xzf DiakoServer-linux-x64-X.Y.Z.tar.gz
cd DiakoServer-linux-x64-X.Y.Z
bash deploy/instalar-lxc.sh --dominio diako.minhaigreja.com.br
```
O instalador:
- cria o usuário `diako` e instala em `/opt/diako-news`;
- gera o `config.json` com uma **senha** aleatória, a **chave do agente** e a **chave do mural**;
- cria o serviço `diako-news` (systemd), que inicia com o sistema;
- instala o **Caddy**, que cuida do HTTPS (Let's Encrypt) e repassa para o servidor.

No fim ele mostra a **senha do painel/tablet**, a **chave do agente** e o **link do mural**. Guarde-os: eles também ficam em `/opt/diako-news/config.json`, que só o root lê.

Já tem um proxy reverso (Nginx Proxy Manager, Traefik...)? Use `--sem-caddy` e aponte o proxy para `http://IP-do-LXC:8080`. Nesse caso, troque `"endereco": "127.0.0.1"` por `"0.0.0.0"` no `config.json`.

Teste abrindo `https://diako.minhaigreja.com.br/painel`.

## 2. Instalar o agente no PC da igreja
1. No Holyrics: **Arquivo > Configurações > API Server**. Ative, crie um token e libere as ações listadas no [LEIA-ME do servidor](../server/LEIA-ME.md).
2. Descubra a **pasta de imagens do Holyrics** (na aba Imagens, use a opção de abrir a pasta).
3. Baixe o `DiakoServer-X.Y.Z.zip` (Windows) da mesma release, descompacte e, no PowerShell **como administrador**:
   ```
   powershell -ExecutionPolicy Bypass -File .\instalar.ps1 -Modo agente
   ```
4. No `agente.json` que abre, preencha e salve. O instalador também pede uma senha própria do monitor; depois abra `http://127.0.0.1:8096` **neste PC** para acompanhar backend, Holyrics, diagnósticos, logs recentes e ensaio guiado (não exposto à rede):
   ```json
   {
     "servidor": "https://diako.minhaigreja.com.br",
     "chaveAgente": "a chave mostrada no passo 1",
     "holyrics": { "host": "127.0.0.1", "porta": 8091, "token": "TOKEN DO HOLYRICS" },
     "pastaImagensHolyrics": "C:\\caminho\\da\\pasta\\de\\imagens\\do\\Holyrics"
   }
   ```
5. O agente inicia junto com o Windows (tarefa "DiakoNews Agente"). No painel, a aba **Status** deve mostrar **PC da igreja (agente): Conectado**.

Os cartazes enviados pelo painel ou pelo tablet, e o QR dos pedidos de oração, aparecem sozinhos em `pasta de imagens\Diako`.

## 3. Tablet, mural e pedidos
- **App do tablet:** em Configurações, digite `diako.minhaigreja.com.br` e a senha, e toque em **Entrar**. O app usa HTTPS automaticamente para domínios.
- **Mural da TV:** use o link com a chave, mostrado na instalação e na aba Status do painel (`https://…/mural?chave=…`). Sem a chave, o mural não abre.
- **Pedidos de oração:** `https://…/oracao`. O QR aponta para esse endereço e funciona de qualquer lugar.

## Atualizar
- **Servidor:** baixe o `.tar.gz` novo e rode o `instalar-lxc.sh` de novo, com o mesmo `--dominio`. O `config.json` e os dados são mantidos.
- **Agente:** rode `instalar.ps1 -Modo agente` da versão nova. O `agente.json` é mantido.

## Administração
Em `https://…/admin` (mesma senha do painel) você:
- **troca a senha** gerada na instalação (recomendado no primeiro acesso);
- configura o nome da igreja, os textos do formulário de pedidos, o endereço público, a chave do mural e os padrões de projeção;
- vê e copia a **chave do agente**, ou gera uma nova (o agente é desconectado até você atualizar o `agente.json`);
- liga a **Agenda do Google** colando o "Endereço secreto no formato iCal" (veja o [LEIA-ME do servidor](../server/LEIA-ME.md#agenda-do-google));
- liga a **edição da agenda** (criar, editar e excluir eventos pelo painel e pelo tablet) enviando a chave de uma conta de serviço do Google. O passo a passo fica em `https://…/ajuda/agenda-google`;
- desconecta todos os aparelhos, se um tablet for perdido.

## Backup e restauração
O servidor grava um `.zip` por dia em `/opt/diako-news/data/backup`. O horário e quantos manter se ajustam em `/admin`. Lá também dá para **baixar um backup na hora** e **restaurar** um da lista ou um `.zip` enviado. Isso serve também para **migrar** de um servidor no PC da igreja para o LXC: baixe o backup no antigo e restaure no novo. Antes de restaurar, o servidor grava um backup de segurança do estado atual.

Para guardar uma cópia fora do servidor, por exemplo no Google Drive, use o [rclone](https://rclone.org/drive/):
```bash
apt install rclone
rclone config            # crie um "remote" chamado gdrive (tipo Google Drive)
echo '30 3 * * * root rclone copy /opt/diako-news/data/backup gdrive:Backup-Diako-News' > /etc/cron.d/diako-backup
```

## Problemas comuns
| Sintoma | O que verificar |
|---|---|
| O site não abre / erro de certificado | O DNS do domínio aponta para o IP certo? As portas 80 e 443 chegam até o LXC? Veja `journalctl -u caddy -n 50`. |
| "PC da igreja (agente): Desconectado" | O PC está ligado e com internet? Veja `C:\DiakoNews\agente.log`. Confira `servidor` e `chaveAgente` no `agente.json`. |
| Agente conectado, mas "Holyrics: Sem conexão" | O Holyrics está aberto, com a API Server ativa? O token e a porta no `agente.json` conferem? |
| Cartaz não aparece no Holyrics | `pastaImagensHolyrics` no `agente.json` aponta para a pasta certa? Talvez seja preciso atualizar a lista de imagens no Holyrics. |
| Serviço não sobe | `systemctl status diako-news` e `journalctl -u diako-news -n 50`. |
