const { test } = require('node:test');
const assert = require('node:assert/strict');

const { textoDasPaginasPdf } = require('../web/palavras-pdf.js');

/** Itens como a pdf.js entrega: cada linha em um ou mais pedaços, a última com hasEOL. */
const linha = (texto, y, pedacos = 1) => {
  const tamanho = Math.ceil(texto.length / pedacos);
  const partes = [];
  for (let i = 0; i < texto.length; i += tamanho) partes.push(texto.slice(i, i + tamanho));
  return partes.map((str, i) => ({ str, transform: [12, 0, 0, 12, 72, y], hasEOL: i === partes.length - 1 }));
};

test('linhas próximas formam um parágrafo; espaço maior separa parágrafos', () => {
  const pagina = [
    ...linha('Jesus não improvisou aquela', 700, 2),
    ...linha('noite. Ele mandou preparar o lugar.', 686),
    ...linha('O texto diz que Ele desejou', 660),
    ...linha('muito aquele momento: Lc 22.15.', 646),
  ];
  assert.equal(textoDasPaginasPdf([pagina]),
    'Jesus não improvisou aquela noite. Ele mandou preparar o lugar.\n\nO texto diz que Ele desejou muito aquele momento: Lc 22.15.');
});

test('palavra com hífen no fim da linha é juntada; número de página some; páginas separam', () => {
  const p1 = [...linha('A graça che-', 700), ...linha('gou primeiro.', 686), ...linha('1', 40)];
  const p2 = [...linha('Venha à mesa.', 700), ...linha('2', 40)];
  assert.equal(textoDasPaginasPdf([p1, p2]), 'A graça chegou primeiro.\n\nVenha à mesa.');
});

test('linha vazia também separa parágrafos', () => {
  const pagina = [...linha('Primeiro.', 700), { str: '', transform: [12, 0, 0, 12, 72, 686], hasEOL: true }, ...linha('Segundo.', 672)];
  assert.equal(textoDasPaginasPdf([pagina]), 'Primeiro.\n\nSegundo.');
});
