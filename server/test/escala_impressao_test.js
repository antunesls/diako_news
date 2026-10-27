const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { cultosParaImpressao } = require('../web/escala-impressao.js');

test('imprime somente cultos com pessoas na escala selecionada', () => {
  const cultos = [
    { id: 'vazio', funcoes: { pastoral: ['Direção'], louvor: ['Vocal'] }, pastoral: { Direção: [] }, louvor: { Vocal: [] }, musicas: [] },
    { id: 'so-musica', funcoes: { pastoral: [], louvor: [] }, pastoral: {}, louvor: {}, musicas: [{ titulo: 'Abertura' }] },
    { id: 'so-pastoral', funcoes: { pastoral: ['Pregação'], louvor: ['Vocal'] }, pastoral: { Pregação: [{ nome: 'Pastor' }] }, louvor: { Vocal: [] } },
    { id: 'so-louvor', funcoes: { pastoral: [], louvor: ['Técnico de som'] }, pastoral: {}, louvor: { 'Técnico de som': [{ nome: 'Ana' }] } },
    { id: 'ambos', funcoes: { pastoral: ['Direção'], louvor: ['Projeção'] }, pastoral: { Direção: [{ nome: 'Pastor' }] }, louvor: { Projeção: [{ nome: 'João' }] } },
    { id: 'função-inativa', funcoes: { pastoral: ['Direção'], louvor: [] }, pastoral: { 'Santa Ceia': [{ nome: 'Pastor' }] }, louvor: {} },
  ];
  assert.deepEqual(cultosParaImpressao(cultos, 'pastoral').map((c) => c.id), ['so-pastoral', 'ambos']);
  assert.deepEqual(cultosParaImpressao(cultos, 'louvor').map((c) => c.id), ['so-louvor', 'ambos']);
});

test('painel carrega o filtro antes do script que imprime', () => {
  const html = fs.readFileSync(path.join(__dirname, '../web/painel.html'), 'utf8');
  const script = fs.readFileSync(path.join(__dirname, '../web/escalas.js'), 'utf8');
  assert.ok(html.indexOf('/escala-impressao.js?v=1') !== -1);
  assert.ok(html.indexOf('/escala-impressao.js?v=1') < html.indexOf('/escalas.js?v=4'));
  assert.match(script, /const cultos = cultosParaImpressao\(d\.cultos, tipo\)/);
  assert.match(script, /\.\.\.cultos\.map\(\(c\) => el\('tr'/);
});
