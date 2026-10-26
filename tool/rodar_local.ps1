# Sobe o DiakoNews neste PC para testes: Holyrics simulado + servidor.
# Uso: powershell -ExecutionPolicy Bypass -File .\tool\rodar_local.ps1
# Abre duas janelas (feche-as para parar). Os dados de teste ficam em server\dev\.
param(
    [int]$Porta = 8095,
    [string]$Senha = 'teste123'
)

function Em-Uso([int]$p) { [bool](Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue) }
if (Em-Uso $Porta) {
    throw "A porta $Porta já está em uso por outro programa. Rode de novo com outra porta, ex: -Porta 8096"
}
$ErrorActionPreference = 'Stop'
$raiz = Split-Path $PSScriptRoot -Parent
$servidor = Join-Path $raiz 'server'
$dev = Join-Path $servidor 'dev'

if (-not (Get-Command dart -ErrorAction SilentlyContinue)) {
    throw 'Dart não encontrado. Instale com: winget install Google.DartSDK (e abra um novo PowerShell).'
}

# A pasta dev\ guarda config, dados, cartazes e backups de teste (ignorada pelo git).
New-Item -ItemType Directory -Force (Join-Path $dev 'holyrics-imagens'), (Join-Path $dev 'backup') | Out-Null
$config = Join-Path $dev 'config.json'
@{
    porta                = $Porta
    senhaAdmin           = $Senha
    holyrics             = @{ host = '127.0.0.1'; porta = 8091; token = 'teste' }
    pastaImagensHolyrics = (Join-Path $dev 'holyrics-imagens')
    pastaBackup          = (Join-Path $dev 'backup')
    horaBackup           = '03:00'
    urlPublica           = ''
} | ConvertTo-Json | ForEach-Object { [IO.File]::WriteAllText($config, $_) }  # UTF-8 sem BOM

# O servidor procura a pasta web\ ao lado do config.json: usa a do projeto.
$web = Join-Path $dev 'web'
if (Test-Path $web) { Remove-Item $web -Recurse -Force }
New-Item -ItemType Junction -Path $web -Target (Join-Path $servidor 'web') | Out-Null

Push-Location $servidor
dart pub get | Out-Null
Pop-Location

if (Em-Uso 8091) {
    Write-Host 'Porta 8091 já em uso: usando o Holyrics (simulado ou real) que já está aberto.' -ForegroundColor Yellow
} else {
    Start-Process powershell -WorkingDirectory $servidor -ArgumentList '-NoExit', '-Command',
        "`$host.UI.RawUI.WindowTitle = 'Holyrics simulado'; dart run tool/fake_holyrics.dart 8091 teste"
}
Start-Process powershell -WorkingDirectory $servidor -ArgumentList '-NoExit', '-Command',
    "`$host.UI.RawUI.WindowTitle = 'Servidor DiakoNews'; dart run bin/diako_server.dart '$config'"

$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -match '^(192\.168|10\.|172\.(1[6-9]|2\d|3[01]))' } | Select-Object -First 1).IPAddress
Write-Host ''
Write-Host 'Subindo (leva alguns segundos na primeira vez)...' -ForegroundColor Green
Write-Host "  Painel:            http://localhost:$Porta/painel   (senha: $Senha)"
Write-Host "  Pedidos de oração: http://localhost:$Porta/oracao"
Write-Host "  Mural (TV):        http://localhost:$Porta/mural"
Write-Host "  No celular/tablet: http://${ip}:$Porta  (mesmo Wi-Fi; permita o Dart no firewall se o Windows perguntar)"
Write-Host ''
Write-Host 'A janela "Holyrics simulado" mostra cada comando de projeção que chegaria ao Holyrics.'
