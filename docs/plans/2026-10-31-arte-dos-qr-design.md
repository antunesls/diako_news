# Arte dos QR codes projetados

**Objetivo:** os QR codes que vão ao telão (pedidos de oração, caixa de mensagens e PIX das ofertas)
deixam de ser só o código preto em fundo branco. Cada um pode ganhar uma imagem trabalhada: montada
pelo próprio DiakoHub (título, chamada, fundo, logo) ou feita fora (Canva) e enviada pronta.

## Decisões

- **Cada QR é independente** (`oracao`, `mensagens`, `pix`), com três modos:
  - `padrao`: o PNG branco de hoje. É o modo inicial; nada muda até alguém configurar.
  - `automatico`: o `/admin` desenha a arte num `<canvas>` (fonte real, com acentos) e envia o PNG
    **sem o QR**.
  - `arte`: a pessoa envia a imagem pronta.
- **No servidor os dois modos são um só:** arte de fundo + QR encaixado. O servidor nunca desenha
  texto, então a tipografia fica com o navegador.
- **Posições prontas** para o QR: `esquerda | centro | direita` × `meio | baixo`, tamanhos `P | M | G`.
- O QR vai num **cartão branco arredondado** com zona silenciosa e sombra leve: contraste garantido
  sobre qualquer arte. Correção de erro `Q`.
- Limites: o lado do QR nunca fica abaixo de ~30% da altura; margem mínima de 60 px da borda.

## Servidor

- **Configurações:** `arteQr<Qr>Modo`, `arteQr<Qr>Fundo` (nome do arquivo), `arteQr<Qr>Posicao`,
  `arteQr<Qr>Tamanho`, `arteQr<Qr>Layout` (JSON com os parâmetros do automático, só para reabrir no
  editor). O nome do arquivo só muda pelo envio.
- **`artes_qr.dart`:** arquivos em `data/artes-qr/<qr>-<hex>.png`, normalizados para 1920×1080 (corta
  para preencher), sem EXIF; nome aleatório a cada envio.
- **`qr_oracao.dart`:** `comporQr(arte, conteudo, posicao, tamanho)`. `gravarQr`, `gravarQrMensagens`
  e `gravarQrPix` usam a arte quando o modo não é `padrao`. Arte ausente ou ilegível: QR padrão e um
  registro no log.
- **Rotas (admin):**
  - `POST /api/admin/arte-qr?qr=…&modo=automatico|arte`: imagem; troca e apaga a anterior.
  - `DELETE /api/admin/arte-qr?qr=…`: volta para `padrao`.
  - `GET /api/admin/arte-qr/previa?qr=…`: PNG final com o QR de verdade.
  - Salvar posição, tamanho e layout passa pelo `PUT` de configurações que já existe e recompõe o QR.
- O arquivo projetado continua `Diako/qr-*.png`: o agente baixa a versão nova sozinho; Holyrics e
  Modo Culto não mudam.
- **Backup:** pasta `artes-qr/` no zip e na restauração.

## `/admin` › Telão › QR codes

Um cartão por QR com prévia e a escolha **Padrão · Automático · Arte própria**.

- **Automático:** título e chamada (sugeridos por QR; no PIX a chamada é a chave), fundo cor ou foto
  com "escurecer", cor do texto automática pelo fundo, logo liga/desliga, endereço curto embaixo
  liga/desliga, posição e tamanho do QR. Prévia em canvas 1920×1080 com QR de exemplo. Fonte
  Montserrat (OFL) servida em `web/fontes/`, carregada antes de desenhar.
- **Arte própria:** enviar imagem + posição e tamanho; a prévia marca com tracejado a área que o QR
  cobre.
- **Ver como fica no telão** (PNG final do servidor) e **Voltar ao padrão**.
- PIX sem chave: cartão desabilitado com aviso.

## Tablet

No Modo Culto, "NO TELÃO" e "A SEGUIR" dos passos de QR mostram a imagem real
(`/qr-oracao.png`, `/qr-mensagens.png`, `/pix.png`); sem carregar, o ícone de hoje.

## Testes

- Servidor: `comporQr` em todas as posições e tamanhos, decodificando o QR do PNG final; rotas de
  envio, troca e remoção; arte ausente cai no padrão; backup inclui a pasta.
- App: prévia do passo de QR com imagem e com falha.
- Validação real pelo agente no Holyrics, decodificando o QR do print do telão.

## Fora do escopo

QR de visitante e de "minha escala", arrastar o QR, edição no tablet, modelos prontos de arte.
