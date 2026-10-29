$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot '..\normalizar-agente.ps1'
. $script

$pasta = Join-Path ([System.IO.Path]::GetTempPath()) ("diako-json-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $pasta | Out-Null
$arquivo = Join-Path $pasta 'agente.json'

function Verificar([bool]$condicao, [string]$mensagem) {
    if (-not $condicao) { throw $mensagem }
}

try {
    foreach ($caso in @(
        @{ Nome = 'simples'; Valor = 'C:\Holyrics\imagens'; Esperado = 'C:\Holyrics\imagens' },
        @{ Nome = 'escapado'; Valor = 'C:\\Holyrics\\imagens'; Esperado = 'C:\Holyrics\imagens' },
        @{ Nome = 'misto'; Valor = 'C:\\Holyrics\imagens'; Esperado = 'C:\Holyrics\imagens' },
        @{ Nome = 'escapes-validos-errados'; Valor = 'C:\temp\base'; Esperado = 'C:\temp\base' },
        @{ Nome = 'barras-normais'; Valor = 'C:/Holyrics/imagens'; Esperado = 'C:/Holyrics/imagens' }
    )) {
        $conteudo = '{"chaveAgente":"segredo", "holyrics":{"token":"token-privado"}, "pastaImagensHolyrics":"' + $caso.Valor + '"}'
        [System.IO.File]::WriteAllText($arquivo, $conteudo)
        $config = Ler-ConfigAgente $arquivo
        Verificar ($config.pastaImagensHolyrics -ceq $caso.Esperado) "Caminho incorreto: $($caso.Nome)"
        Verificar ($config.chaveAgente -ceq 'segredo' -and $config.holyrics.token -ceq 'token-privado') "Credenciais modificadas: $($caso.Nome)"
        Verificar (((Get-Content $arquivo -Raw -Encoding UTF8 | ConvertFrom-Json).pastaImagensHolyrics) -ceq $caso.Esperado) "Arquivo não foi corrigido: $($caso.Nome)"
    }

    # Objeto não fechado: inválido tanto no Windows PowerShell 5.1 quanto no PowerShell 7
    # (o 7 aceita "chave":, como nulo, então esse formato não serve de amostra inválida).
    $invalido = '{"chaveAgente":"segredo", "holyrics":{"token":"x"}, "pastaImagensHolyrics":"C:\Holyrics\imagens"'
    [System.IO.File]::WriteAllText($arquivo, $invalido)
    $falhou = $false
    try { Ler-ConfigAgente $arquivo | Out-Null } catch { $falhou = $true }
    Verificar $falhou 'JSON inválido deveria ser rejeitado'
    Verificar (([System.IO.File]::ReadAllText($arquivo)) -ceq $invalido) 'JSON inválido não deve ser sobrescrito'
    $modelo = Get-Content (Join-Path $PSScriptRoot '..\agente.example.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Verificar ($modelo.pastaImagensHolyrics -like 'C:/*') 'O exemplo distribuído deve ser JSON válido'
    Write-Host 'Teste do instalador: normalização do agente.json OK'
} finally {
    Remove-Item $pasta -Recurse -Force
}
