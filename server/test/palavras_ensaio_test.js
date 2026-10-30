const { test } = require('node:test');
const assert = require('node:assert/strict');

const { tempoPorTopico, resumoDoEnsaio, duracaoLegivel } = require('../web/palavras-ensaio.js');

const trechos = [
  { topico: '' },
  { topico: 'A mesa' },
  { topico: 'A mesa' },
  { topico: 'Apelo' },
];
const min = (m) => m * 60 * 1000;

test('soma o tempo de cada trecho no tópico dele, na ordem do texto', () => {
  const marcas = [{ trecho: 0, em: 0 }, { trecho: 1, em: min(1) }, { trecho: 2, em: min(4) }, { trecho: 3, em: min(9) }];
  assert.deepEqual(tempoPorTopico(trechos, marcas, min(11)), [
    { topico: 'Início', segundos: 60 },
    { topico: 'A mesa', segundos: 480 },
    { topico: 'Apelo', segundos: 120 },
  ]);
});

test('voltar a um trecho soma de novo no tópico dele', () => {
  const marcas = [{ trecho: 1, em: 0 }, { trecho: 3, em: min(2) }, { trecho: 2, em: min(3) }];
  assert.deepEqual(tempoPorTopico(trechos, marcas, min(5)), [
    { topico: 'A mesa', segundos: 240 },
    { topico: 'Apelo', segundos: 60 },
  ]);
});

test('resumo com previsto e diferença; tópico sem tempo fica sem diferença', () => {
  const marcas = [{ trecho: 1, em: 0 }, { trecho: 3, em: min(12) }];
  const r = resumoDoEnsaio(trechos, marcas, min(14), { 'A mesa': 10 });
  assert.deepEqual(r.linhas, [
    { topico: 'A mesa', previsto: 10, segundos: 720, diferenca: 120 },
    { topico: 'Apelo', previsto: null, segundos: 120, diferenca: null },
  ]);
  assert.equal(r.totalSegundos, 840);
});

test('duração legível', () => {
  assert.equal(duracaoLegivel(185), '3:05');
  assert.equal(duracaoLegivel(3750), '1:02:30');
  assert.equal(duracaoLegivel(-45), '-0:45');
});
