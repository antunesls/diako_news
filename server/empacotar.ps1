# Gera dist\DiakoServer.zip pronto para levar ao PC da igreja.
# Uso (neste PC, com o Dart instalado): powershell -ExecutionPolicy Bypass -File .\empacotar.ps1
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

dart test
if ($LASTEXITCODE -ne 0) { throw 'Testes falharam; pacote não gerado.' }

$saida = Join-Path $PSScriptRoot 'dist\DiakoServer'
Remove-Item (Join-Path $PSScriptRoot 'dist') -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $saida | Out-Null

dart compile exe bin\diako_server.dart -o (Join-Path $saida 'diako_server.exe')
if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar.' }

Copy-Item web $saida -Recurse
Copy-Item config.example.json, instalar.ps1, LEIA-ME.md $saida
Compress-Archive -Path $saida -DestinationPath (Join-Path $PSScriptRoot 'dist\DiakoServer.zip') -Force
Write-Host "Pacote gerado: $(Join-Path $PSScriptRoot 'dist\DiakoServer.zip')" -ForegroundColor Green
