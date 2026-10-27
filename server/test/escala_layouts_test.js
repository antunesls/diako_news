const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { cultosParaImpressao } = require('../web/escala-impressao.js');

const cultos = [
  { rotulo: 'Dom 04/10', horaTexto: '19h', nome: 'Culto da noite', ceia: true,
    funcoes: { pastoral: ['Direção'], louvor: ['Vocal', 'Violão'] },
    pastoral: { Direção: [{ nome: 'Pastor João' }] },
    louvor: { Vocal: [{ nome: 'Ana' }], Violão: [] },
    musicas: [{ titulo: 'Canção A', tom: 'G' }, { titulo: 'Canção B', tom: '' }] },
  { rotulo: 'Dom 11/10', horaTexto: '19h', nome: 'Culto', ceia: false,
    funcoes: { pastoral: ['Direção'], louvor: ['Vocal'] }, pastoral: { Direção: [] }, louvor: { Vocal: [] },
    musicas: [{ titulo: 'Só música', tom: 'D' }] },
];

test('painel oferece os dois PDFs e não abre mais a tela de impressão', () => {
  const html = fs.readFileSync(path.join(__dirname, '../web/painel.html'), 'utf8');
  const js = fs.readFileSync(path.join(__dirname, '../web/escalas.js'), 'utf8');
  const impressao = fs.readFileSync(path.join(__dirname, '../web/escala-impressao.js'), 'utf8');
  assert.ok(html.includes('id="dlg-formato-escala"'));
  assert.ok(html.includes('id="escala-formato-paisagem"'));
  assert.ok(html.includes('id="escala-formato-retrato"'));
  assert.match(html, /Baixar PDF/);
  assert.match(html, /Como deseja gerar o PDF da escala\?/);
  assert.ok(html.indexOf('/escala-impressao.js?v=3') !== -1);
  assert.ok(html.indexOf('/escala-impressao.js?v=3') < html.indexOf('/escalas.js?v=9'));
  assert.doesNotMatch(js, /window\.print/);
  assert.match(js, /baixarArquivo\(/);
  assert.match(js, /\/api\/escalas\/pdf\?mes=/);
  assert.doesNotMatch(impressao, /montarEscalaImpressao/);
});

test('baixar o PDF pede o formato certo e avisa quando não há escalados', () => {
  const js = fs.readFileSync(path.join(__dirname, '../web/escalas.js'), 'utf8');
  const trecho = js.slice(js.indexOf("$('escala-imprimir').addEventListener"));
  const ids = ['escala-imprimir', 'escala-formato-paisagem', 'escala-formato-retrato',
    'escala-formato-fechar', 'dlg-formato-escala', 'resultado-escala'];
  const elementos = Object.fromEntries(ids.map((id) => [id, {
    aberturas: 0,
    addEventListener(tipo, fn) { this['on' + tipo] = fn; },
    click() { this.onclick(); },
    showModal() { this.aberto = true; this.aberturas++; },
    close() { this.aberto = false; },
  }]));
  const baixados = [];
  const escala = { tipo: 'louvor', mes: '2026-11', dados: { cultos } };
  const ctx = {
    $: (id) => elementos[id],
    escala,
    cultosParaImpressao,
    baixarArquivo: async (caminho, nome) => { baixados.push([caminho, nome]); },
    mensagem: (alvo, texto) => { elementos['resultado-escala'].texto = texto; },
  };
  vm.createContext(ctx);
  vm.runInContext(trecho, ctx);

  elementos['escala-imprimir'].click();
  assert.equal(elementos['dlg-formato-escala'].aberto, true);
  elementos['escala-formato-paisagem'].click();
  assert.deepEqual(baixados, [['/api/escalas/pdf?mes=2026-11&tipo=louvor&formato=paisagem', 'escala-louvor-2026-11-paisagem.pdf']]);
  assert.equal(elementos['dlg-formato-escala'].aberto, false);

  elementos['escala-imprimir'].click();
  elementos['escala-formato-retrato'].click();
  assert.ok(baixados[1][0].endsWith('formato=retrato'));
  assert.equal(baixados[1][1], 'escala-louvor-2026-11-retrato.pdf');

  escala.dados.cultos = [cultos[1]]; // só música, ninguém escalado
  elementos['escala-imprimir'].click();
  assert.equal(elementos['dlg-formato-escala'].aberturas, 2, 'sem escalados o diálogo não abre');
  assert.match(elementos['resultado-escala'].texto, /Nenhuma pessoa escalada/);
  assert.equal(baixados.length, 2);
});
