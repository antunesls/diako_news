# Diagnóstico local da API do Holyrics

**Objetivo:** fornecer um script PowerShell reutilizável para distinguir falha de porta, falha de autenticação e falha de resposta da API local do Holyrics, sem projetar ou modificar o estado do programa.

**Decisões:** porta padrão 8091, host fixo `127.0.0.1`, HTTP POST com `{}` para `/api/GetCPInfo` e `/api/GetCurrentPresentation`, de acordo com `server/lib/holyrics.dart`. O token é lido interativamente com `Read-Host -AsSecureString`, nunca é passado como argumento nem gravado. Há opção `-SemToken` para diagnosticar somente a porta. O script nunca chama ações `Show*`, `Set*`, `Action*` ou `Close*`.

## Tarefas

1. Criar `tool/diagnosticar_holyrics.ps1` com parâmetros `-Porta` (1–65535, padrão 8091) e `-SemToken`. Validar o número da porta, testar TCP local com timeout curto e apresentar resultado sem lançar erro bruto contendo a URL/token.
2. Quando o teste TCP passar e `-SemToken` não estiver ativo, solicitar o token com entrada oculta. Chamar a API via POST e interpretar status HTTP, JSON `status: ok`, erro de token e resposta inesperada, apresentando instruções distintas por etapa.
3. Adicionar testes de parsing e um teste local de `-SemToken` (sem revelar credenciais). Documentar uso no `server/LEIA-ME.md` e avisar que `tool/rodar_local.ps1` usa token `teste` e não é apropriado para validar a instalação real sem ajustar sua configuração.
4. Executar as verificações locais: parsing PowerShell, `-SemToken -Porta 8091` e revisão de que o script não grava segredos nem chama ações de projeção. A autenticação real deve ser executada pelo usuário no próprio terminal após regenerar o token compartilhado anteriormente.

**Critério de aceite:** o diagnóstico sem token informa se a porta local responde; com token correto informa a resposta das duas ações de leitura; com token errado orienta a verificar a credencial sem exibi-la. Nenhum teste altera o telão.
