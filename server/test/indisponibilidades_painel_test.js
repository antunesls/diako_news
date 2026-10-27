const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

test('Escalas oferece lista completa de indisponibilidades, autor, data e cancelamento', () => {
  const html = fs.readFileSync(path.join(__dirname, '../web/painel.html'), 'utf8');
  const js = fs.readFileSync(path.join(__dirname, '../web/escalas.js'), 'utf8');
  assert.ok(html.includes('id="escala-ver-indisponibilidades"'));
  assert.ok(html.includes('id="dlg-lista-indisponibilidades"'));
  assert.ok(html.includes('id="lista-indisponibilidades"'));
  assert.ok(html.includes('/escalas.js?v=8'));
  assert.match(js, /api\('GET', '\/api\/escalas\/indisponibilidades'\)/);
  assert.match(js, /api\('DELETE', '\/api\/escalas\/indisponibilidades\/'/);
  assert.match(js, /enviadoEm/);
  assert.match(js, /enviadoPor/);
  assert.match(js, /periodoCompleto\(i\.de, i\.ate\)/);
  assert.match(js, /confirm\(/);
});

test('lista apresenta avisos antigos e novos, e cancelar atualiza a tela', async () => {
  const script = fs.readFileSync(path.join(__dirname, '../web/escalas.js'), 'utf8');
  const trecho = script.slice(script.indexOf('function periodoCompleto('), script.indexOf("$('escala-ver-indisponibilidades').addEventListener"));
  const tela = {
    'resultado-lista-indisponibilidades': { textContent: '' },
    'lista-indisponibilidades': { children: [], replaceChildren(...itens) { this.children = itens; } },
  };
  let avisos = [
    { id: 'novo', nome: 'Ana', de: '2027-01-05', ate: '2027-01-07', enviadoPor: 'Ana', enviadoEm: '2026-10-27T10:00:00Z' },
    { id: 'antigo', nome: 'Bruno', de: '2025-01-01', ate: '2025-01-01' },
  ];
  const cancelados = [];
  let atualizacoes = 0;
  const ctx = {
    $: (id) => tela[id],
    api: async (metodo, url) => {
      if (metodo === 'GET') return avisos;
      const id = url.split('/').at(-1);
      cancelados.push(id);
      avisos = avisos.filter((aviso) => aviso.id !== id);
    },
    botao: (texto, onclick) => ({ texto, onclick, disabled: false }),
    el: (tag, props, ...children) => ({ tag, props, children: children.filter((c) => c != null) }),
    confirm: () => true,
    carregarEscalas: async () => { atualizacoes++; },
    mensagem: () => { throw Error('erro inesperado'); },
  };
  vm.createContext(ctx);
  vm.runInContext(trecho, ctx);
  await ctx.carregarTodasIndisponibilidades();
  assert.equal(tela['lista-indisponibilidades'].children.length, 2);
  const textos = JSON.stringify(tela['lista-indisponibilidades'].children);
  assert.match(textos, /05\/01\/2027 a 07\/01\/2027/);
  assert.match(textos, /não registrado/);
  await tela['lista-indisponibilidades'].children[0].children.at(-1).onclick();
  assert.deepEqual(cancelados, ['novo']);
  assert.equal(atualizacoes, 1);
  assert.equal(tela['lista-indisponibilidades'].children.length, 1);
});
