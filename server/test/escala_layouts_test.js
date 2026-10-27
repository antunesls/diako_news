const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { cultosParaImpressao, montarEscalaImpressao } = require('../web/escala-impressao.js');

const el = (tag, props, ...children) => ({ tag, props, children: children.flat().filter((v) => v != null) });
const texto = (node) => typeof node === 'string' ? node : node.children.map(texto).join(' ');
const todos = (node) => typeof node === 'string' ? [] : [node, ...node.children.flatMap(todos)];

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

test('quadro mensal em paisagem traz logo, título grande, funções e músicas só dos cultos escalados', () => {
  const usados = cultosParaImpressao(cultos, 'louvor');
  const doc = montarEscalaImpressao(usados, 'louvor', 'paisagem', ['Vocal', 'Violão'], 'outubro de 2026', el);
  assert.equal(doc.props.class, 'impressao-escala paisagem');
  assert.ok(todos(doc).some((n) => n.tag === 'img' && n.props.src === '/logo.png'));
  assert.ok(todos(doc).some((n) => n.tag === 'table'));
  assert.match(texto(doc), /Escala do louvor/);
  assert.match(texto(doc), /Ana/);
  assert.match(texto(doc), /Canção A \(G\)/);
  assert.doesNotMatch(texto(doc), /Só música|Dom 11\/10/);
});

test('cartões em retrato preservam dados da pastoral sem músicas; no louvor incluem repertório', () => {
  const pastor = montarEscalaImpressao(cultosParaImpressao(cultos, 'pastoral'), 'pastoral', 'retrato', ['Direção'], 'outubro de 2026', el);
  assert.equal(pastor.props.class, 'impressao-escala retrato');
  assert.ok(todos(pastor).some((n) => n.tag === 'article'));
  assert.match(texto(pastor), /Pastor João/);
  assert.doesNotMatch(texto(pastor), /Canção A/);
  const louvor = montarEscalaImpressao(cultosParaImpressao(cultos, 'louvor'), 'louvor', 'retrato', ['Vocal', 'Violão'], 'outubro de 2026', el);
  assert.match(texto(louvor), /Canção B/);
  assert.doesNotMatch(texto(louvor), /Dom 11\/10/);
});

test('botão Imprimir permite escolher os dois modelos e CSS de impressão não altera os demais documentos', () => {
  const html = fs.readFileSync(path.join(__dirname, '../web/painel.html'), 'utf8');
  const js = fs.readFileSync(path.join(__dirname, '../web/escalas.js'), 'utf8');
  assert.ok(html.includes('id="dlg-formato-escala"'));
  assert.ok(html.includes('id="escala-formato-paisagem"'));
  assert.ok(html.includes('id="escala-formato-retrato"'));
  assert.match(html, /@page escala-paisagem\s*\{/);
  assert.match(html, /@page escala-retrato\s*\{/);
  assert.match(html, /@page escala-paisagem\s*\{\s*size:\s*A4 landscape/);
  assert.match(html, /@page escala-retrato\s*\{\s*size:\s*A4 portrait/);
  assert.match(html, /#impressao-membros\.impressao-escala/);
  assert.match(js, /montarEscalaImpressao\(/);
  assert.match(js, /escala-formato-paisagem'\)\.addEventListener\('click'/);
  assert.match(js, /escala-formato-retrato'\)\.addEventListener\('click'/);
  assert.match(js, /afterprint/);
});

test('a escolha abre o formato pedido; após imprimir limpa o formato e sem escalados não imprime', () => {
  const js = fs.readFileSync(path.join(__dirname, '../web/escalas.js'), 'utf8');
  const trecho = js.slice(js.indexOf("$('escala-imprimir').addEventListener"));
  const elementos = Object.fromEntries(['escala-imprimir', 'escala-formato-paisagem', 'escala-formato-retrato',
    'escala-formato-fechar', 'dlg-formato-escala', 'impressao-membros', 'resultado-escala']
    .map((id) => [id, { className: '', addEventListener(tipo, fn) { this[tipo] = fn; },
      showModal() { this.aberto = true; }, close() { this.aberto = false; },
      replaceChildren(...v) { this.children = v; } }]));
  const janela = { impressoes: 0, addEventListener(tipo, fn) { this[tipo] = fn; }, print() { this.impressoes++; } };
  const escala = { tipo: 'louvor', dados: { cultos, titulo: 'outubro de 2026' } };
  const ctx = { $, escala, window: janela, cultosParaImpressao, colunasDoMes: () => ['Vocal'],
    montarEscalaImpressao: (lista, tipo, formato) => ({ formato, lista, tipo }), el: () => null,
    mensagem: (alvo, texto) => { alvo.texto = texto; } };
  function $(id) { return elementos[id]; }
  vm.runInNewContext(trecho, ctx);
  elementos['escala-imprimir'].click();
  assert.equal(elementos['dlg-formato-escala'].aberto, true);
  elementos['escala-formato-paisagem'].click();
  assert.equal(elementos['impressao-membros'].children[0].formato, 'paisagem');
  assert.equal(elementos['impressao-membros'].children[0].lista.length, 1);
  assert.equal(janela.impressoes, 1);
  janela.afterprint();
  assert.equal(elementos['impressao-membros'].className, '');
  elementos['escala-imprimir'].click();
  elementos['escala-formato-retrato'].click();
  assert.equal(elementos['impressao-membros'].children[0].formato, 'retrato');
  assert.equal(janela.impressoes, 2);
  escala.dados.cultos = [cultos[1]];
  elementos['escala-imprimir'].click();
  assert.equal(janela.impressoes, 2);
  assert.match(elementos['resultado-escala'].texto, /Nenhuma pessoa escalada/);
});
