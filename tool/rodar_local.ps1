# Sobe o DiakoHub neste PC para testes. Os dados de teste ficam em server\dev\ (ignorada pelo git).
#
# Holyrics simulado + servidor (padrão):
#   powershell -ExecutionPolicy Bypass -File .\tool\rodar_local.ps1
#
# Holyrics de verdade, pelo agente, como na igreja (servidor "na internet" + agente no PC do Holyrics):
#   $env:HOLYRICS_TOKEN = 'token da API Server do Holyrics'
#   powershell -ExecutionPolicy Bypass -File .\tool\rodar_local.ps1 -Agente
# O agente copia cartazes e QRs para a pasta de imagens do Holyrics (-PastaHolyrics) e atende os
# tablets pareados na porta 8097. Esse modo usa a porta 8098 e dados próprios (server\dev\modo-agente),
# então pode rodar ao lado do simulado. Abre uma janela por programa (feche-as para parar).
param(
    [int]$Porta = 0,
    [string]$Senha = '',
    [switch]$Agente,
    [string]$TokenHolyrics = $env:HOLYRICS_TOKEN,
    [string]$PastaHolyrics = 'C:\Holyrics\Holyrics\files\media\image'
)

function Em-Uso([int]$p) { [bool](Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue) }
if (-not $Porta) { $Porta = if ($Agente) { 8098 } else { 8095 } }
if (Em-Uso $Porta) {
    throw "A porta $Porta já está em uso por outro programa. Rode de novo com outra porta, ex: -Porta 8099"
}
$ErrorActionPreference = 'Stop'
$raiz = Split-Path $PSScriptRoot -Parent
$servidor = Join-Path $raiz 'server'
$dev = Join-Path $servidor 'dev'
if ($Agente) { $dev = Join-Path $dev 'modo-agente' }

if (-not (Get-Command dart -ErrorAction SilentlyContinue)) {
    throw 'Dart não encontrado. Instale com: winget install Google.DartSDK (e abra um novo PowerShell).'
}

# No modo agente o servidor se comporta como na internet: a senha precisa de 10 caracteres.
if (-not $Senha) { $Senha = if ($Agente) { 'teste12345' } else { 'teste123' } }

function Salvar-Json($objeto, [string]$arquivo) {
    $objeto | ConvertTo-Json -Depth 5 | ForEach-Object { [IO.File]::WriteAllText($arquivo, $_) }  # UTF-8 sem BOM
}

New-Item -ItemType Directory -Force (Join-Path $dev 'holyrics-imagens'), (Join-Path $dev 'backup') | Out-Null
$config = Join-Path $dev 'config.json'

if ($Agente) {
    if (-not $TokenHolyrics) {
        throw 'Informe o token da API Server do Holyrics: $env:HOLYRICS_TOKEN = ''...'' (ou -TokenHolyrics).'
    }
    if (-not (Test-Path $PastaHolyrics)) {
        throw "Pasta de imagens do Holyrics não encontrada: $PastaHolyrics. Informe com -PastaHolyrics."
    }
    if (-not (Em-Uso 8091)) { throw 'O Holyrics não está respondendo na porta 8091: abra-o e ative a API Server.' }
    foreach ($p in 8096, 8097) { if (Em-Uso $p) { throw "A porta $p (agente) já está em uso: feche o agente que está aberto." } }

    # Chave nova a cada execução, a mesma no servidor e no agente.
    $chave = -join ((1..32) | ForEach-Object { '{0:x2}' -f (Get-Random -Maximum 256) })
    Salvar-Json @{
        porta       = $Porta
        senhaAdmin  = $Senha
        holyrics    = @{ modo = 'agente' }
        chaveAgente = $chave
        pastaBackup = (Join-Path $dev 'backup')
        horaBackup  = '03:00'
        urlPublica  = ''
    } $config

    $pastaAgente = Join-Path $dev 'agente'
    New-Item -ItemType Directory -Force $pastaAgente, (Join-Path $pastaAgente 'backup') | Out-Null
    $configAgente = Join-Path $pastaAgente 'agente.json'
    Salvar-Json @{
        servidor             = "http://127.0.0.1:$Porta"
        chaveAgente          = $chave
        holyrics             = @{ host = '127.0.0.1'; porta = 8091; token = $TokenHolyrics }
        pastaImagensHolyrics = $PastaHolyrics
        monitor              = @{ porta = 8096; hash = ''; sal = '' }
        apiLocal             = @{ porta = 8097 }
        backup               = @{ pasta = (Join-Path $pastaAgente 'backup'); manter = 3 }
    } $configAgente
} else {
    Salvar-Json @{
        porta                = $Porta
        senhaAdmin           = $Senha
        holyrics             = @{ host = '127.0.0.1'; porta = 8091; token = 'teste' }
        pastaImagensHolyrics = (Join-Path $dev 'holyrics-imagens')
        pastaBackup          = (Join-Path $dev 'backup')
        horaBackup           = '03:00'
        urlPublica           = ''
    } $config
}

# O servidor procura a pasta web\ ao lado do config.json: usa a do projeto.
$web = Join-Path $dev 'web'
if (Test-Path $web) { Remove-Item $web -Recurse -Force }
New-Item -ItemType Junction -Path $web -Target (Join-Path $servidor 'web') | Out-Null

Push-Location $servidor
dart pub get | Out-Null
Pop-Location

if (-not $Agente) {
    if (Em-Uso 8091) {
        Write-Host 'Porta 8091 já em uso: usando o Holyrics que já está aberto.' -ForegroundColor Yellow
        Write-Host '  Se for o Holyrics de verdade, use -Agente: o token "teste" e a pasta de imagens daqui são do simulado.' -ForegroundColor Yellow
    } else {
        Start-Process powershell -WorkingDirectory $servidor -ArgumentList '-NoExit', '-Command',
            "`$host.UI.RawUI.WindowTitle = 'Holyrics simulado'; dart run tool/fake_holyrics.dart 8091 teste"
    }
}
Start-Process powershell -WorkingDirectory $servidor -ArgumentList '-NoExit', '-Command',
    "`$host.UI.RawUI.WindowTitle = 'Servidor DiakoHub'; dart run bin/diako_server.dart '$config'"
if ($Agente) {
    # Espera o servidor subir para o agente não começar reclamando de conexão.
    for ($i = 0; $i -lt 60 -and -not (Em-Uso $Porta); $i++) { Start-Sleep -Seconds 1 }
    Start-Process powershell -WorkingDirectory $servidor -ArgumentList '-NoExit', '-Command',
        "`$host.UI.RawUI.WindowTitle = 'Agente DiakoHub'; dart run bin/diako_agente.dart '$configAgente'"
}

$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -match '^(192\.168|10\.|172\.(1[6-9]|2\d|3[01]))' } | Select-Object -First 1).IPAddress
Write-Host ''
Write-Host 'Subindo (leva alguns segundos na primeira vez)...' -ForegroundColor Green
Write-Host "  Painel:            http://localhost:$Porta/painel   (senha: $Senha)"
Write-Host "  Pedidos de oração: http://localhost:$Porta/oracao"
Write-Host "  Mural (TV):        http://localhost:$Porta/mural"
Write-Host "  No celular/tablet: http://${ip}:$Porta  (mesmo Wi-Fi; permita o Dart no firewall se o Windows perguntar)"
if ($Agente) {
    Write-Host "  Agente:            Holyrics 127.0.0.1:8091, imagens em $PastaHolyrics\Diako"
    Write-Host "  PC da igreja:      no tablet, Configurações › PC da igreja › $ip › Parear"
} else {
    Write-Host ''
    Write-Host 'A janela "Holyrics simulado" mostra cada comando de projeção que chegaria ao Holyrics.'
}
Write-Host ''
