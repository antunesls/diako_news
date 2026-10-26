# Diagnostico seguro da API local do Holyrics. Nao projeta nem altera nada.
# Uso: powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\diagnosticar_holyrics.ps1
# Somente porta: acrescente -SemToken. Porta diferente: -Porta 8092.
param(
    [int]$Porta = 8091,
    [switch]$SemToken
)

$ErrorActionPreference = 'Stop'
if ($Porta -lt 1 -or $Porta -gt 65535) {
    Write-Host 'Porta invalida: informe um numero entre 1 e 65535.' -ForegroundColor Red
    exit 2
}

Write-Host "Diagnostico do Holyrics em 127.0.0.1:$Porta (somente leitura)"

function Testar-Porta([int]$Numero) {
    $cliente = New-Object System.Net.Sockets.TcpClient
    try {
        $pendente = $cliente.BeginConnect('127.0.0.1', $Numero, $null, $null)
        if (-not $pendente.AsyncWaitHandle.WaitOne(2500)) { return $false }
        $cliente.EndConnect($pendente)
        return $true
    } catch {
        return $false
    } finally {
        $cliente.Close()
    }
}

if (-not (Testar-Porta $Porta)) {
    Write-Host '[FALHA] Porta TCP indisponivel. Abra o Holyrics e confira Configuracoes > API Server > porta.' -ForegroundColor Red
    exit 1
}
Write-Host '[OK] A porta TCP responde.' -ForegroundColor Green

if ($SemToken) {
    Write-Host 'Autenticacao e API nao testadas (-SemToken). Porta aberta nao prova que o servico e o Holyrics.'
    exit 0
}

$seguro = Read-Host 'Digite o token NOVO do Holyrics (entrada oculta)' -AsSecureString
if ($seguro.Length -eq 0) {
    Write-Host '[FALHA] Token vazio. Gere um token no API Server do Holyrics.' -ForegroundColor Red
    exit 2
}

# A API do Holyrics exige token na query. Nunca imprima a URL, o token ou a excecao HTTP.
$ponteiro = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($seguro)
try {
    $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ponteiro)
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ponteiro)
    $seguro.Dispose()
}

function Consultar-Api([string]$Acao) {
    $uri = 'http://127.0.0.1:{0}/api/{1}?token={2}' -f $Porta, $Acao, [Uri]::EscapeDataString($token)
    try {
        $resposta = Invoke-WebRequest -UseBasicParsing -Method Post -Uri $uri -Body '{}' -ContentType 'application/json' -TimeoutSec 5
        $dados = $resposta.Content | ConvertFrom-Json
        if ($dados.status -eq 'ok') { return @{ Resultado = 'ok'; Dados = $dados.data } }
        if ($dados.error -eq 'invalid token') { return @{ Resultado = 'token' } }
        return @{ Resultado = 'api' }
    } catch [System.Net.WebException] {
        $codigo = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        if ($codigo -eq 401 -or $codigo -eq 403) { return @{ Resultado = 'token' } }
        return @{ Resultado = 'http'; Codigo = $codigo }
    } catch {
        return @{ Resultado = 'resposta' }
    }
}

try {
    $info = Consultar-Api 'GetCPInfo'
    switch ($info.Resultado) {
        'token' {
            Write-Host '[FALHA] A API recusou o token. Confira o token habilitado no Holyrics.' -ForegroundColor Red
            exit 3
        }
        'ok' { Write-Host '[OK] GetCPInfo autenticado.' -ForegroundColor Green }
        default {
            Write-Host '[FALHA] GetCPInfo nao respondeu com status ok. Confira API Server e permissoes de GetCPInfo.' -ForegroundColor Red
            exit 4
        }
    }

    $atual = Consultar-Api 'GetCurrentPresentation'
    if ($atual.Resultado -ne 'ok') {
        Write-Host '[FALHA] GetCurrentPresentation nao respondeu com status ok. Libere essa acao no token.' -ForegroundColor Red
        exit 4
    }
    Write-Host '[OK] GetCurrentPresentation autenticado (nenhuma projecao foi iniciada).' -ForegroundColor Green
    Write-Host 'API local funcionando. Se o DiakoNews ainda mostrar desconectado, confira host, porta e token na configuracao dele.'
    exit 0
} finally {
    $token = $null
}
