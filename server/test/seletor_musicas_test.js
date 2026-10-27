const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { videoYoutube, miniaturaYoutube, linkYoutube } = require('../web/musica-youtube.js');

test('miniatura e link aceitam somente vídeos do YouTube', () => {
  assert.equal(videoYoutube('https://youtu.be/dQw4w9WgXcQ?t=20'), 'dQw4w9WgXcQ');
  assert.equal(videoYoutube('https://www.youtube.com/watch?v=dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
  assert.equal(miniaturaYoutube('https://youtu.be/dQw4w9WgXcQ'), 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg');
  assert.equal(linkYoutube('https://youtu.be/dQw4w9WgXcQ'), 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
  for (const url of ['javascript:alert(1)', 'https://youtube.com.evil.test/watch?v=dQw4w9WgXcQ', 'https://youtube.com/redirect?q=x']) {
    assert.equal(videoYoutube(url), null);
    assert.equal(linkYoutube(url), null);
  }
});

test('escala tem seletor independente com busca e Minha escala mostra link e tom', () => {
  const html = fs.readFileSync(path.join(__dirname, '../web/painel.html'), 'utf8');
  const script = fs.readFileSync(path.join(__dirname, '../web/escalas.js'), 'utf8');
  const minha = fs.readFileSync(path.join(__dirname, '../web/minha-escala.html'), 'utf8');
  assert.ok(html.includes('<dialog id="dlg-selecionar-musica"'));
  assert.match(html, /id="seletor-musica-busca"/);
  assert.match(html, /id="seletor-musica-lista"/);
  assert.match(script, /buscarRepertorio\(/);
  assert.match(script, /miniaturaYoutube\(/);
  assert.match(script, /linkYoutube\(/);
  assert.match(minha, /m\.youtube/);
  assert.match(minha, /m\.tom/);
  assert.ok(html.indexOf('/musica-youtube.js?v=1') < html.indexOf('/escalas.js?v=5'));
});
