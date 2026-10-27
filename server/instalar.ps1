# Instala o DiakoNews no PC do Holyrics. Execute como administrador, de dentro da pasta descompactada:
#   powershell -ExecutionPolicy Bypass -File .\instalar.ps1               # servidor completo neste PC
#   powershell -ExecutionPolicy Bypass -File .\instalar.ps1 -Modo agente  # servidor na internet: só o agente
param(
    [ValidateSet('servidor', 'agente')]
    [string]$Modo = 'servidor',
    [string]$Destino = 'C:\DiakoNews'
)
$ErrorActionPreference = 'Stop'
$origem = $PSScriptRoot

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Write-Host 'Abra o PowerShell como administrador e rode o instalador de novo.' -ForegroundColor Red
    exit 1
}

function Registrar-Tarefa([string]$Nome, [string]$Exe, [string]$Config, [string]$Log, [string]$Descricao) {
    $comando = "& '$Exe' '$Config' *>> '$Log'"
    $acao = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -Command `"$comando`"" -WorkingDirectory $Destino
    $gatilho = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $opcoes = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -RestartCount 10 -RestartInterval (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName $Nome -Action $acao -Trigger $gatilho -Settings $opcoes -Description $Descricao -Force | Out-Null
    Start-ScheduledTask -TaskName $Nome
}

# Para a tarefa (com o nome atual e o antigo, "Diako News", de instalações anteriores).
function Parar-Tarefa([string]$Nome) {
    foreach ($n in @($Nome, ($Nome -replace '^DiakoNews', 'Diako News'))) {
        Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue | Stop-ScheduledTask
    }
}

# Só o SYSTEM, os Administradores e quem instalou (a tarefa roda com esse usuário) acessam a pasta:
# ela guarda o config.json/agente.json (senha, chaves e token do Holyrics), os dados e as cópias do backup.
# Os arquivos de dentro herdam essas permissões.
function Proteger-Pasta([string]$Pasta) {
    $usuario = "$env:USERDOMAIN\$env:USERNAME"
    & icacls $Pasta /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' "${usuario}:(OI)(CI)F" /C /Q | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Aviso: não foi possível restringir as permissões de $Pasta (icacls)." -ForegroundColor Yellow
    } else {
        Write-Host "Pasta $Pasta acessível só para o SYSTEM, os Administradores e $usuario."
    }
}

# Remove a tarefa com o nome antigo, para não ficarem duas iniciando com o Windows.
function Remover-TarefaAntiga([string]$Nome) {
    $antigo = $Nome -replace '^DiakoNews', 'Diako News'
    Get-ScheduledTask -TaskName $antigo -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
}

if ($Modo -eq 'agente') {
    # O monitor do agente escuta somente em 127.0.0.1 (sem regra de firewall); a API local
    # dos tablets pareados escuta na rede da igreja (regra abaixo, só redes privadas).
    Parar-Tarefa 'DiakoNews Agente'
    Get-Process diako_agente -ErrorAction SilentlyContinue | Stop-Process -Force

    Write-Host "Copiando o agente para $Destino ..."
    New-Item -ItemType Directory -Force $Destino | Out-Null
    Proteger-Pasta $Destino
    Copy-Item (Join-Path $origem 'diako_agente.exe') $Destino -Force
    Copy-Item (Join-Path $origem 'agente.example.json') $Destino -Force

    $config = Join-Path $Destino 'agente.json'
    if (-not (Test-Path $config)) {
        Copy-Item (Join-Path $Destino 'agente.example.json') $config
        Write-Host ''
        Write-Host 'Preencha o agente.json que vai abrir agora: endereço do servidor, chave do agente,' -ForegroundColor Yellow
        Write-Host 'token do Holyrics e pasta de imagens do Holyrics. Salve e feche o Bloco de Notas.' -ForegroundColor Yellow
        Start-Process notepad.exe $config -Wait
    }
    $monitorConfig = (Get-Content $config -Raw -Encoding UTF8 | ConvertFrom-Json).monitor
    if (-not $monitorConfig -or -not $monitorConfig.hash) {
        Write-Host 'Defina uma senha exclusiva do monitor local (mínimo 12 caracteres).' -ForegroundColor Yellow
        & (Join-Path $Destino 'diako_agente.exe') --definir-senha $config
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao definir a senha do monitor.' }
    }

    $apiLocal = (Get-Content $config -Raw -Encoding UTF8 | ConvertFrom-Json).apiLocal
    $portaLocal = if ($apiLocal -and $null -ne $apiLocal.porta) { [int]$apiLocal.porta } else { 8097 }
    Get-NetFirewallRule -DisplayName 'DiakoNews Agente (tablets)' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    if ($portaLocal -gt 0) {
        Write-Host "Liberando a porta $portaLocal para os tablets da igreja (somente redes privadas) ..."
        New-NetFirewallRule -DisplayName 'DiakoNews Agente (tablets)' -Direction Inbound -Protocol TCP -LocalPort $portaLocal `
            -Profile Private -Action Allow | Out-Null
    }

    Write-Host 'Criando a tarefa que inicia o agente junto com o Windows ...'
    $log = Join-Path $Destino 'agente.log'
    Remover-TarefaAntiga 'DiakoNews Agente'
    Registrar-Tarefa 'DiakoNews Agente' (Join-Path $Destino 'diako_agente.exe') $config $log `
        'Agente do DiakoNews: liga o servidor na internet ao Holyrics deste PC'
    Start-Sleep -Seconds 4
    Write-Host ''
    Write-Host 'Pronto! Últimas linhas do log do agente:' -ForegroundColor Green
    if (Test-Path $log) { Get-Content $log -Tail 8 }
    Write-Host ''
    Write-Host "Confira no painel (aba Status) se aparece 'PC da igreja (agente): Conectado'. Log: $log"
    $portaMonitor = (Get-Content $config -Raw -Encoding UTF8 | ConvertFrom-Json).monitor.porta
    if (-not $portaMonitor) { $portaMonitor = 8096 }
    Write-Host "Monitor local deste PC: http://127.0.0.1:$portaMonitor (senha própria)."
    if ($portaLocal -gt 0) {
        $ipLocal = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -match '^(192\.168|10\.|172\.(1[6-9]|2\d|3[01]))' } | Select-Object -First 1).IPAddress
        Write-Host "Tablets na rede da igreja: em Configurações › PC da igreja, use o IP $ipLocal (porta $portaLocal)."
        Write-Host 'A rede Wi-Fi deste PC precisa estar como "Privada" no Windows.'
    }
    exit 0
}

# Para uma versão já em execução antes de copiar o .exe.
Parar-Tarefa 'DiakoNews'
Get-Process diako_server -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "Copiando arquivos para $Destino ..."
New-Item -ItemType Directory -Force $Destino | Out-Null
Proteger-Pasta $Destino
Copy-Item (Join-Path $origem 'diako_server.exe') $Destino -Force
Copy-Item (Join-Path $origem 'web') $Destino -Recurse -Force
Copy-Item (Join-Path $origem 'config.example.json') $Destino -Force
Copy-Item (Join-Path $origem 'LEIA-ME.md') $Destino -Force -ErrorAction SilentlyContinue

# config.json e data\ nunca são sobrescritos (guardam senhas e os dados da igreja).
$config = Join-Path $Destino 'config.json'
if (-not (Test-Path $config)) {
    Copy-Item (Join-Path $Destino 'config.example.json') $config
    Write-Host ''
    Write-Host 'Preencha o config.json que vai abrir agora (senha do painel, token do Holyrics, pastas).' -ForegroundColor Yellow
    Write-Host 'Salve, feche o Bloco de Notas e o instalador continua.' -ForegroundColor Yellow
    Start-Process notepad.exe $config -Wait
}
$porta = (Get-Content $config -Raw -Encoding UTF8 | ConvertFrom-Json).porta
if (-not $porta) { $porta = 8080 }

Write-Host "Liberando a porta $porta no firewall (somente redes privadas) ..."
foreach ($regra in 'DiakoNews', 'Diako News') {
    Get-NetFirewallRule -DisplayName $regra -ErrorAction SilentlyContinue | Remove-NetFirewallRule
}
New-NetFirewallRule -DisplayName 'DiakoNews' -Direction Inbound -Protocol TCP -LocalPort $porta -Profile Private -Action Allow | Out-Null

Write-Host 'Criando a tarefa que inicia o servidor junto com o Windows ...'
$log = Join-Path $Destino 'servidor.log'
Remover-TarefaAntiga 'DiakoNews'
Registrar-Tarefa 'DiakoNews' (Join-Path $Destino 'diako_server.exe') $config $log `
    'Servidor do DiakoNews (recados e motivos de oração para o Holyrics)'

Start-Sleep -Seconds 3
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -match '^(192\.168|10\.|172\.(1[6-9]|2\d|3[01]))' } | Select-Object -First 1).IPAddress
Write-Host ''
Write-Host 'Pronto!' -ForegroundColor Green
Write-Host "  Painel:            http://${ip}:$porta/painel"
Write-Host "  Pedidos de oração: http://${ip}:$porta/oracao"
Write-Host "  No tablet, use:    http://${ip}:$porta"
Write-Host "  Log do servidor:   $log"
Write-Host ''
Write-Host 'Dica: reserve esse IP no roteador para ele não mudar.'
