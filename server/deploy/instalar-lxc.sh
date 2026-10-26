#!/usr/bin/env bash
# Instala ou atualiza o servidor Diako News num LXC/VPS Debian 12 ou Ubuntu 22.04+ (x86_64).
#
# Uso (como root, de dentro da pasta descompactada DiakoServer-linux-x64-X.Y.Z):
#   bash deploy/instalar-lxc.sh --dominio diako.minhaigreja.com.br
#   bash deploy/instalar-lxc.sh --dominio ... --sem-caddy      # já tem proxy reverso (Nginx, Traefik...)
#
# Rodar de novo com uma versão nova só atualiza o programa: config.json e data/ são mantidos.
set -euo pipefail

DESTINO=/opt/diako-news
PORTA=8080
DOMINIO=""
COM_CADDY=1

while [ $# -gt 0 ]; do
  case "$1" in
    --dominio) DOMINIO="${2:-}"; shift 2 ;;
    --porta) PORTA="${2:-}"; shift 2 ;;
    --sem-caddy) COM_CADDY=0; shift ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "Opção desconhecida: $1" >&2; exit 1 ;;
  esac
done

[ "$(id -u)" -eq 0 ] || { echo "Rode como root (ou com sudo)." >&2; exit 1; }
[ -n "$DOMINIO" ] || { echo "Informe o domínio: --dominio diako.minhaigreja.com.br" >&2; exit 1; }
[ "$(uname -m)" = "x86_64" ] || { echo "Este pacote é para x86_64." >&2; exit 1; }
command -v apt-get >/dev/null || { echo "Este instalador é para Debian/Ubuntu (apt)." >&2; exit 1; }

ORIGEM="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$ORIGEM/diako_server" ] || { echo "diako_server não encontrado em $ORIGEM." >&2; exit 1; }

aleatorio() { tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$1" || true; }

echo "==> Usuário e pastas"
id diako >/dev/null 2>&1 || useradd --system --home-dir "$DESTINO" --shell /usr/sbin/nologin diako
install -d -o diako -g diako -m 750 "$DESTINO" "$DESTINO/data" "$DESTINO/data/backup"

echo "==> Programa"
systemctl stop diako-news 2>/dev/null || true
install -o root -g root -m 755 "$ORIGEM/diako_server" "$DESTINO/diako_server"
rm -rf "$DESTINO/web"
cp -r "$ORIGEM/web" "$DESTINO/web"
chown -R root:root "$DESTINO/web"
chmod -R a+rX "$DESTINO/web"
install -m 644 "$ORIGEM/config.example.json" "$DESTINO/config.example.json"

NOVO_CONFIG=0
SENHA=""
if [ ! -f "$DESTINO/config.json" ]; then
  NOVO_CONFIG=1
  SENHA="$(aleatorio 16)"
  CHAVE_AGENTE="$(aleatorio 40)"
  CHAVE_MURAL="$(aleatorio 20)"
  cat > "$DESTINO/config.json" <<EOF
{
  "porta": $PORTA,
  "endereco": "127.0.0.1",
  "confiarProxy": true,
  "senhaAdmin": "$SENHA",
  "holyrics": { "modo": "agente" },
  "chaveAgente": "$CHAVE_AGENTE",
  "chaveMural": "$CHAVE_MURAL",
  "pastaBackup": "$DESTINO/data/backup",
  "horaBackup": "03:00",
  "urlPublica": "https://$DOMINIO"
}
EOF
fi
chown diako:diako "$DESTINO/config.json"
chmod 600 "$DESTINO/config.json"

echo "==> Serviço systemd"
install -m 644 "$ORIGEM/deploy/diako-news.service" /etc/systemd/system/diako-news.service
install -d /etc/systemd/system/diako-news.service.d
install -m 644 "$ORIGEM/deploy/protecao.conf" /etc/systemd/system/diako-news.service.d/protecao.conf
systemctl daemon-reload
systemctl enable diako-news >/dev/null
systemctl restart diako-news
sleep 3
if ! systemctl is-active --quiet diako-news; then
  # LXC sem "nesting": o isolamento extra do systemd falha (status 226/NAMESPACE).
  echo "   Isolamento extra não suportado neste container; seguindo sem ele."
  rm -f /etc/systemd/system/diako-news.service.d/protecao.conf
  systemctl daemon-reload
  systemctl restart diako-news
  sleep 3
fi
systemctl is-active --quiet diako-news || { journalctl -u diako-news -n 30 --no-pager; echo "O serviço não subiu." >&2; exit 1; }

if [ "$COM_CADDY" -eq 1 ]; then
  echo "==> Caddy (HTTPS automático)"
  if ! command -v caddy >/dev/null; then
    apt-get update -qq
    apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https curl gnupg >/dev/null
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
    apt-get update -qq
    apt-get install -y -qq caddy >/dev/null
  fi
  if [ -f /etc/caddy/Caddyfile ] && ! grep -q "Diako News" /etc/caddy/Caddyfile; then
    cp /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.antes-diako.$(date +%Y%m%d%H%M%S)"
  fi
  cat > /etc/caddy/Caddyfile <<EOF
# Diako News — gerado por instalar-lxc.sh
$DOMINIO {
	encode gzip
	reverse_proxy 127.0.0.1:$PORTA
}
EOF
  systemctl enable caddy >/dev/null
  systemctl reload caddy 2>/dev/null || systemctl restart caddy
fi

echo
echo "Pronto! Diako News rodando."
echo "  Painel:   https://$DOMINIO/painel"
echo "  Admin:    https://$DOMINIO/admin   (troque a senha, backup e restauração)"
echo "  Tablet:   https://$DOMINIO"
if [ "$NOVO_CONFIG" -eq 1 ]; then
  echo
  echo "  Senha do painel/tablet: $SENHA"
  echo "  Chave do agente (vai no agente.json do PC da igreja): $CHAVE_AGENTE"
  echo "  Mural da TV: https://$DOMINIO/mural?chave=$CHAVE_MURAL"
  echo
  echo "  Guarde a senha e a chave do agente. Elas ficam em $DESTINO/config.json (só root/diako leem)."
else
  echo "  Configuração existente mantida ($DESTINO/config.json)."
fi
echo
echo "  Logs: journalctl -u diako-news -f"
[ "$COM_CADDY" -eq 1 ] && echo "  O HTTPS é emitido na primeira visita: o DNS de $DOMINIO precisa apontar para este servidor e as portas 80/443 precisam estar abertas."
exit 0
