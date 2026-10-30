const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const menu = require('../web/menu-lateral.js');

test('organiza as catorze páginas nos grupos aprovados, com Agenda em Comunicação', () => {
  const grupos = menu.gruposPermitidos(['painel', 'motivosVer', 'mensagens', 'membros', 'escalasVer',
    'agendaVer', 'recados', 'cartazes', 'galeria', 'resumo', 'admin']);
  assert.deepEqual(grupos.map((g) => g.nome), ['Início', 'Acompanhamento', 'Cultos', 'Comunicação', 'Operação']);
  assert.deepEqual(grupos.find((g) => g.nome === 'Cultos').itens.map((i) => i.id), ['escalas', 'repertorio', 'roteiros']);
  assert.deepEqual(grupos.find((g) => g.nome === 'Comunicação').itens.map((i) => i.id),
    ['agenda', 'recados', 'cartazes', 'galeria', 'resumo']);
  assert.equal(grupos.flatMap((g) => g.itens).filter((i) => i.id !== 'admin').length, 14);
});

test('perfil Louvor só vê suas páginas e grupos sem permissão desaparecem', () => {
  const grupos = menu.gruposPermitidos(['painel', 'agendaVer', 'escalasVer', 'escalaLouvor']);
  assert.deepEqual(grupos.map((g) => g.nome), ['Início', 'Cultos', 'Comunicação', 'Operação']);
  assert.deepEqual(grupos.flatMap((g) => g.itens.map((i) => i.id)),
    ['inicio', 'escalas', 'repertorio', 'roteiros', 'agenda', 'historico', 'status']);
});

test('menu mantém os avisos nas páginas e respeita autorização para Administração', () => {
  const semAdmin = menu.gruposPermitidos(['painel', 'motivosVer', 'mensagens']);
  const itens = semAdmin.flatMap((g) => g.itens);
  assert.equal(itens.find((i) => i.id === 'motivos').badge, 'badge');
  assert.equal(itens.find((i) => i.id === 'mensagens').badge, 'badge-mensagens');
  assert.ok(!itens.some((i) => i.id === 'admin'));
  assert.ok(menu.gruposPermitidos(['painel', 'admin']).flatMap((g) => g.itens).some((i) => i.id === 'admin'));
  assert.ok(menu.gruposPermitidos(['painel', 'acessosEscala']).flatMap((g) => g.itens).some((i) => i.id === 'acessos'));
});

test('painel oferece menu lateral, botão móvel e preserva as páginas existentes', () => {
  const html = fs.readFileSync(path.join(__dirname, '../web/painel.html'), 'utf8');
  assert.match(html, /id="menu-lateral"/);
  assert.match(html, /id="abrir-menu"/);
  assert.match(html, /id="fechar-menu"/);
  assert.doesNotMatch(html, /<nav class="abas"/);
  for (const id of ['inicio', 'motivos', 'mensagens', 'membros', 'escalas', 'repertorio', 'agenda',
    'recados', 'cartazes', 'galeria', 'resumo', 'historico', 'status', 'acessos']) {
    assert.ok(html.includes(`data-painel="${id}"`), `página ${id} desapareceu`);
  }
});

test('Palavras fica em Cultos e aparece só para quem prepara Palavras', () => {
  const pregador = menu.gruposPermitidos(['painel', 'escalasVer', 'palavras', 'minhaEscala']);
  assert.deepEqual(pregador.find((g) => g.nome === 'Cultos').itens.map((i) => i.id), ['escalas', 'repertorio', 'roteiros', 'palavras']);
  assert.ok(!menu.gruposPermitidos(['painel', 'escalasVer']).flatMap((g) => g.itens).some((i) => i.id === 'palavras'));
});

test('painel carrega o script das Palavras e o menu na versão nova', () => {
  const html = fs.readFileSync(path.join(__dirname, '../web/painel.html'), 'utf8');
  assert.match(html, /data-painel="palavras"/);
  assert.match(html, /<script src="\/palavras-pdf\.js\?v=1"><\/script>\s*<script src="\/palavras\.js\?v=3"><\/script>/);
  assert.match(html, /<script src="\/menu-lateral\.js\?v=3"><\/script>/);
});
