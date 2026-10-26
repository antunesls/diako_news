#!/usr/bin/env bash
# Gera dist/DiakoServer-linux-x64-<versão>.tar.gz para instalar num LXC/VPS (ver docs/HOSPEDAGEM.md).
# Uso (Linux x86_64 com Dart): bash empacotar-linux.sh [versão]
set -euo pipefail
cd "$(dirname "$0")"
VERSAO="${1:-dev}"
NOME="DiakoServer-linux-x64-$VERSAO"

dart pub get
dart test
rm -rf dist
mkdir -p "dist/$NOME"
dart compile exe "-DVERSAO=$VERSAO" bin/diako_server.dart -o "dist/$NOME/diako_server"
cp -r web deploy config.example.json LEIA-ME.md "dist/$NOME/"
chmod +x "dist/$NOME/diako_server" "dist/$NOME/deploy/instalar-lxc.sh"
tar -C dist -czf "dist/$NOME.tar.gz" "$NOME"
echo "Pacote gerado: dist/$NOME.tar.gz"
