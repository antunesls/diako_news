#!/usr/bin/env bash
# Gera a pasta android/ que falta (o repositório guarda só o AndroidManifest.xml).
# O `flutter create` não sobrescreve arquivos existentes.
set -euo pipefail

flutter create --org br.diako --project-name diako_news --platforms android .

# O flutter create adiciona um teste de exemplo que não faz parte do projeto.
if ! git ls-files --error-unmatch test/widget_test.dart >/dev/null 2>&1; then
  rm -f test/widget_test.dart
fi
