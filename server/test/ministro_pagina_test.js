const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

test('Minha escala oferece editor de músicas só nos cultos autorizados', () => {
  const html = fs.readFileSync(path.join(__dirname, '../web/minha-escala.html'), 'utf8');
  assert.match(html, /if \(c\.podeEscolherMusicas\)/);
  assert.match(html, /dados\.repertorio/);
  assert.match(html, /\/api\/minha-escala\/cultos\/\$\{c\.id\}\/musicas/);
  assert.match(html, /'PUT'/);
});

test('painel encaminha ministros para Minha escala', () => {
  const js = fs.readFileSync(path.join(__dirname, '../web/painel.js'), 'utf8');
  assert.match(js, /eu\.perfil === 'integrante' \|\| eu\.perfil === 'ministro' \|\| eu\.perfil === 'louvor'/);
});

test('Louvor não vê formulário de indisponibilidade em Minha escala', () => {
  const html = fs.readFileSync(path.join(__dirname, '../web/minha-escala.html'), 'utf8');
  assert.match(html, /\$\('form'\)\.hidden = !dados\.podeAvisarIndisponibilidade/);
  assert.match(html, /\$\('agenda'\)\.hidden = n === 0 \|\| !dados\.podeAvisarIndisponibilidade/);
});

test('administração de acessos permite vincular uma conta Ministro ao membro', () => {
  const js = fs.readFileSync(path.join(__dirname, '../web/acessos-escala.js'), 'utf8');
  assert.match(js, /u\.perfil === 'pastor' \|\| u\.perfil === 'ministro'/);
  assert.match(js, /u\.perfil === 'louvor'/);
});
