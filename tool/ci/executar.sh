#!/usr/bin/env bash
# Executa um comando e, se ele falhar, publica as linhas finais da saída como anotação
# de erro do GitHub Actions (visível sem abrir o log completo).
# Uso: bash tool/ci/executar.sh "Título" comando arg1 arg2 ...
set -uo pipefail

titulo="$1"
shift
saida=$(mktemp)
"$@" 2>&1 | tee "$saida"
status=${PIPESTATUS[0]}

if [ "$status" -ne 0 ]; then
  # Prefere as linhas com erro; se não houver, usa o final da saída.
  trecho=$(grep -E -i "error|erro|failed|exception|what went wrong|•" "$saida" | grep -v -i "^\s*$" | tail -n 40)
  [ -z "$trecho" ] && trecho=$(tail -n 40 "$saida")
  # Quebras de linha precisam ser codificadas na anotação.
  trecho=${trecho//'%'/'%25'}
  trecho=${trecho//$'\r'/}
  trecho=${trecho//$'\n'/'%0A'}
  echo "::error title=${titulo}::${trecho}"
fi
exit "$status"
