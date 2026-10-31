const { test } = require('node:test');
const assert = require('node:assert/strict');

const { retanguloCartaoQr, areaDoTexto, quebrarLinhas, ajustarTexto, textoEscuro } = require('../web/arte-qr.js');

// A mesma tabela está em test/artes_qr_test.dart: a prévia do /admin e o QR do telão no mesmo lugar.
const GEOMETRIA = [
  ['esquerda-meio', 'P', 96, 318, 444],
  ['esquerda-meio', 'G', 96, 170, 740],
  ['centro-baixo', 'P', 738, 540, 444],
  ['centro-baixo', 'G', 590, 244, 740],
  ['direita-meio', 'P', 1380, 318, 444],
  ['direita-meio', 'G', 1084, 170, 740],
];

test('cartão do QR no mesmo lugar que o servidor desenha', () => {
  for (const [posicao, tamanho, x, y, lado] of GEOMETRIA) {
    assert.deepEqual(retanguloCartaoQr(posicao, tamanho, 29), { x, y, lado }, `${posicao} ${tamanho}`);
  }
});

test('o texto fica do lado oposto ao QR, sem invadir o cartão', () => {
  for (const posicao of ['esquerda-meio', 'direita-baixo', 'centro-meio', 'centro-baixo']) {
    for (const tamanho of ['P', 'M', 'G']) {
      const r = retanguloCartaoQr(posicao, tamanho);
      const a = areaDoTexto(posicao, tamanho);
      const sobrepoe = a.x0 < r.x + r.lado && a.x1 > r.x && a.y0 < r.y + r.lado && a.y1 > r.y;
      assert.equal(sobrepoe, false, `${posicao} ${tamanho}`);
      assert.ok(a.x1 > a.x0 && a.y1 > a.y0);
    }
  }
});

// Medida falsa e previsível: cada caractere vale metade do tamanho da fonte.
const medir = (s, _peso, px) => s.length * px * 0.5;

test('quebra por palavras sem passar da largura', () => {
  const linhas = quebrarLinhas('Aponte a câmera do celular e envie seu pedido', 300, (s) => s.length * 20);
  assert.ok(linhas.length > 1);
  for (const l of linhas) assert.ok(l.length * 20 <= 300 || !l.includes(' '), l);
  assert.equal(linhas.join(' '), 'Aponte a câmera do celular e envie seu pedido');
  assert.deepEqual(quebrarLinhas('Linha 1\nLinha 2', 2000, (s) => s.length), ['Linha 1', 'Linha 2']);
});

test('texto curto fica no tamanho cheio; texto longo diminui até caber', () => {
  const area = areaDoTexto('direita-meio', 'M');
  const curto = ajustarTexto({ titulo: 'Oração', chamada: 'Envie seu pedido', enderecoTexto: 'igreja.com/oracao' }, area, medir);
  assert.equal(curto.escala, 1);
  const faixa = areaDoTexto('centro-meio', 'M'); // QR no centro: só a faixa de cima
  const longo = ajustarTexto({ titulo: 'Pedidos de oração', chamada: 'Aponte a câmera do celular e envie seu pedido', enderecoTexto: '' }, faixa, medir);
  assert.ok(longo.escala < 1);
  assert.ok(longo.total <= faixa.y1 - faixa.y0);
  assert.deepEqual(longo.blocos.map((b) => b.tipo), ['titulo', 'chamada'], 'sem endereço não há bloco vazio');
  assert.equal(ajustarTexto({ titulo: 'x'.repeat(400), chamada: '' }, areaDoTexto('centro-meio', 'G'), medir), null);
});

test('texto escuro só em fundo claro sem foto', () => {
  assert.equal(textoEscuro({ cor: '#ffffff', cor2: '#f0f0f0' }, false), true);
  assert.equal(textoEscuro({ cor: '#ffffff', cor2: '#f0f0f0' }, true), false);
  assert.equal(textoEscuro({ cor: '#14215c', cor2: '#3949ab' }, false), false);
});
