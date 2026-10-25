# Gera dist\DiakoServer-<versão>.zip pronto para levar ao PC da igreja.
# Uso (com o Dart instalado): powershell -ExecutionPolicy Bypass -File .\empacotar.ps1 [-Versao 1.2.0]
# O GitHub Actions usa este mesmo script para publicar as releases.
param(
    [string]$Versao = 'dev'
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

dart test
if ($LASTEXITCODE -ne 0) { throw 'Testes falharam; pacote não gerado.' }

$saida = Join-Path $PSScriptRoot 'dist\DiakoServer'
Remove-Item (Join-Path $PSScriptRoot 'dist') -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $saida | Out-Null

dart compile exe "-DVERSAO=$Versao" bin\diako_server.dart -o (Join-Path $saida 'diako_server.exe')
if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar.' }

Copy-Item web $saida -Recurse
Copy-Item config.example.json, instalar.ps1, LEIA-ME.md $saida
$zip = Join-Path $PSScriptRoot "dist\DiakoServer-$Versao.zip"
Compress-Archive -Path $saida -DestinationPath $zip -Force
Write-Host "Pacote gerado: $zip" -ForegroundColor Green
