# Instala o servidor Diako News no PC do Holyrics.
# Execute como administrador, de dentro da pasta descompactada:
#   powershell -ExecutionPolicy Bypass -File .\instalar.ps1
param(
    [string]$Destino = 'C:\DiakoNews'
)
$ErrorActionPreference = 'Stop'
$origem = $PSScriptRoot

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Write-Host 'Abra o PowerShell como administrador e rode o instalador de novo.' -ForegroundColor Red
    exit 1
}

# Para uma versão já em execução antes de copiar o .exe.
Get-ScheduledTask -TaskName 'Diako News' -ErrorAction SilentlyContinue | Stop-ScheduledTask
Get-Process diako_server -ErrorAction SilentlyContinue | Stop-Process -Force

Write-Host "Copiando arquivos para $Destino ..."
New-Item -ItemType Directory -Force $Destino | Out-Null
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
Get-NetFirewallRule -DisplayName 'Diako News' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -DisplayName 'Diako News' -Direction Inbound -Protocol TCP -LocalPort $porta -Profile Private -Action Allow | Out-Null

Write-Host 'Criando a tarefa que inicia o servidor junto com o Windows ...'
$exe = Join-Path $Destino 'diako_server.exe'
$log = Join-Path $Destino 'servidor.log'
$comando = "& '$exe' '$config' *>> '$log'"
$acao = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -Command `"$comando`"" -WorkingDirectory $Destino
$gatilho = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$opcoes = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 10 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName 'Diako News' -Action $acao -Trigger $gatilho -Settings $opcoes `
    -Description 'Servidor do Diako News (recados e motivos de oração para o Holyrics)' -Force | Out-Null
Start-ScheduledTask -TaskName 'Diako News'

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
