# Fundo personalizado das TVs (mural e boas-vindas)

**Objetivo:** o administrador escolhe, no `/admin` › Mural, o fundo de cada TV: a de informações
(`/mural`) e a de boas-vindas (`/mural?tela=boas-vindas`). Hoje as duas usam o azul-marinho fixo
`#0b1026` do `mural.html`.

## Decisões

- **Cada TV tem o seu fundo**, com três ajustes:
  - **Cor** (`#rrggbb`), padrão `#0b1026` (o atual).
  - **Imagem** opcional (JPG/PNG), reduzida para 1920 px e regravada sem EXIF, como as fotos da galeria.
  - **Escurecer a imagem** (0 a 90 %, padrão 55 %): véu preto por cima da foto para o texto branco
    continuar legível.
- **Cor do texto automática:** sem imagem e com cor clara (luminância > 0,3), o texto fica escuro e o
  logo troca para a versão escura (`logo.png`). Com imagem, o véu garante texto branco.
- A faixa colorida de cada slide (categoria do recado, oração, agenda, boas-vindas) continua igual.
- Cartazes (recados com imagem) seguem por cima do fundo, sem mudança.

## Servidor

- `configuracoes.dart`: chaves `muralFundoCor`, `muralFundoImagem`, `muralFundoEscurecer` e as mesmas
  com `boasVindas…`. Cor e escurecer validados em `atualizar`; a imagem só muda pelo envio (não aceita
  nome vindo do painel). Entram em `restaurarPublicas`.
- `fundos_tv.dart` (novo): arquivos em `data/fundos-tv/<tela>-<hex>.jpg`; nome aleatório a cada envio
  (cache longo no navegador). Reaproveita `processarFoto` da galeria.
- Rotas:
  - `POST /api/admin/fundo-tv?tela=mural|boas-vindas`: bytes da imagem; troca e apaga a anterior.
  - `DELETE /api/admin/fundo-tv?tela=…`: volta para só a cor.
  - `GET /fundo-tv/<arquivo>`: imagem pública (o mural é aberto na TV sem login).
- `GET /api/public/mural` (as duas telas) ganha `fundo: {cor, imagem, escurecer}`; `imagem` só vem
  quando o arquivo existe.
- Backup: pasta `fundos-tv/` no zip e na restauração, como `galeria/`.
- Salvar no `/admin` já avisa `configuracoes`; o mural pega o fundo novo na próxima consulta
  (60 s no mural, 10 s nas boas-vindas).

## Telas

- `mural.html`: aplica cor, imagem e véu no `body`; tokens de texto e pontos passam a depender do tema
  claro/escuro calculado.
- `/admin` › Mural: um bloco por TV com seletor de cor, envio/remoção de imagem, controle de
  escurecer e uma prévia em 16:9. `admin.js?v=` sobe.

## Testes

- Validação das chaves novas (cor inválida, escurecer fora da faixa).
- Envio de imagem: aparece no `/api/public/mural` da tela certa, arquivo é servido, troca apaga o
  antigo, remover volta a `imagem: null`; tela inválida dá 400; sem login dá 401.
- Backup leva e restaura a pasta `fundos-tv/`.
