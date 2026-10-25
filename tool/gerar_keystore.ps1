# Cria a chave que assina o APK das releases (uma única vez) e mostra os secrets do GitHub.
# Uso: powershell -ExecutionPolicy Bypass -File .\tool\gerar_keystore.ps1
# Guarde o arquivo .jks e as senhas em lugar seguro (ex: gerenciador de senhas):
# sem eles, versões futuras do app não instalam por cima da atual.
param(
    [string]$Saida = (Join-Path $HOME 'diako-news-release.jks'),
    [string]$Alias = 'diako'
)
$ErrorActionPreference = 'Stop'

$keytool = Get-Command keytool -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if (-not $keytool) {
    $candidatos = @(
        "$env:ProgramFiles\Android\Android Studio\jbr\bin\keytool.exe",
        "$env:JAVA_HOME\bin\keytool.exe"
    ) + (Get-ChildItem "$env:ProgramFiles\Java\*\bin\keytool.exe", "$env:ProgramFiles\Eclipse Adoptium\*\bin\keytool.exe" -ErrorAction SilentlyContinue | ForEach-Object FullName)
    $keytool = $candidatos | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
if (-not $keytool) { throw 'keytool não encontrado. Instale o Android Studio ou um JDK (ex: winget install EclipseAdoptium.Temurin.17.JDK).' }
if (Test-Path $Saida) { throw "Já existe $Saida. Use a chave existente ou escolha outro -Saida." }

$senha = Read-Host 'Senha da keystore (mínimo 6 caracteres)' -AsSecureString
$texto = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($senha))
if ($texto.Length -lt 6) { throw 'Senha muito curta.' }

& $keytool -genkeypair -v -keystore $Saida -alias $Alias -keyalg RSA -keysize 2048 -validity 10000 `
    -storepass $texto -keypass $texto -dname 'CN=Igreja Diakonia Tulipas, O=Diako News, C=BR'
if ($LASTEXITCODE -ne 0) { throw 'Falha ao gerar a keystore.' }

$base64 = Join-Path (Split-Path $Saida) 'diako-news-release.jks.base64.txt'
[Convert]::ToBase64String([IO.File]::ReadAllBytes($Saida)) | Set-Content $base64 -Encoding ascii

Write-Host ''
Write-Host "Keystore criada: $Saida" -ForegroundColor Green
Write-Host 'No GitHub: Settings > Secrets and variables > Actions > New repository secret, crie:'
Write-Host "  ANDROID_KEYSTORE_BASE64   = conteúdo do arquivo $base64"
Write-Host '  ANDROID_KEYSTORE_PASSWORD = a senha que você digitou'
Write-Host "  ANDROID_KEY_ALIAS         = $Alias"
Write-Host '  ANDROID_KEY_PASSWORD      = a mesma senha'
Write-Host ''
Write-Host "Depois de cadastrar, apague $base64 e guarde o .jks e a senha em lugar seguro." -ForegroundColor Yellow
