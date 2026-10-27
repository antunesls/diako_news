# Backup fora do servidor e aviso de falha (M3) — plano de implementação

**Objetivo:** que um problema no disco ou no container do servidor não leve os backups junto, e que uma falha no backup diário não passe despercebida. Proposta M3 de `docs/PROPOSTAS.md`.

**Situação atual:** `Backup` (`server/lib/backup.dart`) grava o `.zip` diário em `pastaBackup` ou `data/backups`. No LXC, isso fica no mesmo disco dos dados. Se `executar` falhar, o timer só escreve no `stderr` e tenta de novo **a cada minuto** até o fim do dia. O painel mostra só a data do último backup.

**Arquitetura:** reaproveitar o agente que já roda no PC da igreja e já baixa os cartazes por HTTP com a chave dele. O agente passa a baixar também os backups para uma pasta do PC (que pode ser uma pasta do Google Drive) e avisa o servidor pelo WebSocket. O estado do backup (último sucesso, última falha, última cópia no PC) fica em `data/backup.json`. Uma função pura calcula os alertas mostrados no painel e no `/admin`. A falha do backup automático manda um e-mail (no máximo um por dia), se o SMTP estiver configurado.

## Decisões
- **Cópia no PC ligada por padrão** no modo agente, na pasta `backups-servidor` ao lado do `agente.json`, mantendo os 7 mais novos. `agente.json` › `"backup": {"pasta": "...", "manter": 7}`; `"manter": 0` desliga. O PC da igreja já guarda dados da igreja; a chave do agente passa a dar acesso também aos backups (documentar).
- No modo local (servidor no PC do Holyrics), o caminho continua sendo apontar `pastaBackup` para o Google Drive; o aviso de falha vale igual.
- **Nova tentativa depois de falha:** no máximo a cada 60 minutos (hoje é a cada minuto).
- **E-mail de falha:** só diz que falhou, quando, e o link do `/admin`; sem caminho nem mensagem de erro. No máximo um por dia.
- **Alertas** (lista de textos, vazia quando está tudo bem):
  - a última tentativa falhou depois do último sucesso;
  - o último backup tem mais de 2 dias;
  - modo agente: não há cópia no PC e o último backup tem mais de 1 dia, ou a última cópia tem mais de 3 dias.
- Sem página `/ajuda` nova: a configuração é opcional e cabe no LEIA-ME e no `HOSPEDAGEM.md`.

## 1. Estado e alertas do backup (`server/lib/backup.dart`)
1. `backup.json` passa a ter `{ultimo, falha?: {em}, copiaPc?: {em, nome}}`; as gravações mesclam com o que já existe. Novos: `estado()`, `registrarCopiaPc(nome)`.
2. Extrair o passo do timer para `Future<void> verificar()` (testável com o relógio): grava, ou registra a falha, chama `aoFalhar` (uma vez por dia) e só tenta de novo depois de 60 min.
3. `aoGravar` (callback após um backup gravado) para pedir a cópia ao agente.
4. Função pura `alertasBackup({ultimo, falha, copiaPc, modoAgente, agora})`.
5. Testes novos em `server/test/backup_test.dart`: alertas em cada caso; `verificar` com destino impossível (registra falha, chama `aoFalhar` uma vez, não tenta de novo antes de 60 min, depois volta a funcionar e o alerta some).

## 2. Rotas e WebSocket do agente (`server/lib/app.dart`, `server/lib/agente_hub.dart`)
1. `GET /agente/backups` (nome e tamanho, mais novos primeiro) e `GET /agente/backups/<nome>` (arquivo), com a mesma checagem de chave de `/agente/cartazes`.
2. Hub: mensagem servidor → agente `{"tipo":"backup"}` (`pedirCopiaBackup`) e agente → servidor `{"tipo":"backup-copiado","nome"}` (`aoCopiarBackup`).
3. No `Servidor`, em modo agente: `backup.aoGravar` pede a cópia; `aoCopiarBackup` chama `backup.registrarCopiaPc`.
4. `/api/estado` e `/api/backups` devolvem `alertasBackup` e `copiaBackupPc`.
5. `bin/diako_server.dart`: `aoFalhar` envia o e-mail (`enviarEmailFalhaBackup` em `server/lib/email_mensagens.dart`).

## 3. Agente (`server/lib/agente/agente.dart`, `monitor.dart`)
1. `AgenteConfig`: `pastaBackup` e `backupsManter` (bloco `"backup"` do `agente.json`).
2. `copiarBackups()`: lista, baixa os mais novos que faltam (temporário + rename, confere que é um zip), apaga os locais além do limite (só arquivos com nome de backup), envia `backup-copiado` com o mais novo. Roda ao conectar, ao receber `backup` e a cada 6 horas.
3. Estado e monitor mostram pasta, última cópia e erro.
4. Teste em `server/test/agente_test.dart`: backup gravado no servidor chega à pasta do PC, o servidor registra a cópia e o alerta não aparece; sem chave, `/agente/backups` responde 401.

## 4. Telas e documentação
- Painel (início e Status) e `/admin` › Backup: mostram os alertas em vermelho e a linha "Cópia no PC da igreja" no modo agente.
- `server/agente.example.json`, `server/LEIA-ME.md` (Backup), `docs/HOSPEDAGEM.md` (agente).

## 5. Segurança (revisão depois da primeira versão)
A primeira versão gravava o zip aberto no PC e dava à chave do agente (texto puro no `agente.json`, enviada na URL) acesso a todos os dados pela internet. Corrigido antes de publicar:
1. **Cópia cifrada** (`server/lib/backup_cifrado.dart`): ChaCha20-Poly1305 (RFC 8439) com chave de PBKDF2-HMAC-SHA256 (600 mil iterações) da *senha do backup*, definida em `/admin`. O servidor guarda só sal e chave derivada (`data/backup-senha.json`, fora dos backups). O cabeçalho do arquivo é autenticado. Restaurar um `.cifrado` em `/admin` pede a senha (cabeçalho `X-Senha-Backup`). A cifra roda em outro isolate. Não usar o atalho `process()` da pointycastle 4.0.0: devolve zeros e não confere a tag (os testes incluem o vetor da RFC 8439 e um do PBKDF2). AES-GCM da pointycastle foi descartado por ser lento demais (cerca de 1 MB/s).
2. **Chave no cabeçalho** `X-Chave-Agente`. As rotas de backup só aceitam o cabeçalho; as antigas ainda aceitam `?chave=` para agentes anteriores. Atualizar o servidor antes do agente.
3. **Desligada por padrão:** sem senha definida, `/agente/backups` responde 409 e o painel mostra como ligar.
4. **Permissões:** `instalar.ps1` restringe `C:\DiakoNews` (SYSTEM, Administradores e o usuário que instalou, que é o da tarefa).

Limites: quem usa o próprio usuário que instalou (ou é administrador do PC) continua lendo o `agente.json` e pode usar a chave para controlar o Holyrics e baixar cópias, mas só cifradas. A senha do backup esquecida torna as cópias do PC inúteis (os backups do servidor continuam valendo).

## Verificação
- `dart analyze --fatal-infos` e `dart test` em `server/` e `packages/diako_core/`.
- Rodar servidor e agente localmente (`tool/rodar_local.ps1` ou os dois `bin/`), gravar backup no `/admin` e conferir a pasta do agente e os alertas.
- Depois do deploy no LXC: gravar backup no `/admin` e conferir a pasta `C:\DiakoNews\backups-servidor` no PC da igreja.
