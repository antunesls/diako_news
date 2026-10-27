$script = Join-Path (Split-Path $PSScriptRoot -Parent) 'diagnosticar_holyrics.ps1'

Describe 'Diagnostico local do Holyrics' {
    It 'existe e tem sintaxe PowerShell valida' {
        (Test-Path $script) | Should Be $true
        $erros = $null
        [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$null, [ref]$erros) | Out-Null
        $erros.Count | Should Be 0
    }

    It 'rejeita porta invalida antes de pedir token' {
        $saida = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script -Porta 0 -SemToken 2>&1
        $LASTEXITCODE | Should Be 2
        ($saida -join ' ') | Should Match 'porta'
    }

    It 'nao inclui acoes de alteracao do Holyrics' {
        $conteudo = [IO.File]::ReadAllText($script)
        $conteudo | Should Match "Consultar-Api 'GetCPInfo'"
        $conteudo | Should Match "Consultar-Api 'GetCurrentPresentation'"
        $conteudo | Should Not Match "Consultar-Api '(Set|Action|Close)"
    }

    It 'nao permite projetar sem autenticar' {
        $saida = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script -SemToken -ProjetarTexto 2>&1
        $LASTEXITCODE | Should Be 2
        ($saida -join ' ') | Should Match 'token'
    }

    It 'exige telão livre e confirmacao antes de enviar a projecao' {
        $conteudo = [IO.File]::ReadAllText($script)
        $conteudo | Should Match "Consultar-Api 'ShowQuickPresentation'"
        $conteudo | Should Match 'Dados -ne \$null'
        $conteudo | Should Match 'Read-Host.*SIM'
        $conteudo | Should Not Match "Consultar-Api 'CloseCurrentPresentation'"
    }
}
