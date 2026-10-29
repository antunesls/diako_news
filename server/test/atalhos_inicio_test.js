const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

test('menu do site oferece acessos à Recepção e ao Louvor, sem substituir as seções públicas', () => {
  const html = fs.readFileSync(path.join(__dirname, '../web/inicio.html'), 'utf8');
  assert.match(html, /\['recepcao', 'Recepção', '\/recepcao'\]/);
  assert.match(html, /\['louvor', 'Louvor', 'https:\/\/diakoniatulipas\.com\.br\/minha-escala'\]/);
  assert.match(html, /menu\.map\(\(\[id, nome, destino\]\) => el\('a', \{ href: destino \|\| '#' \+ id \}, nome\)\)/);
  assert.match(html, /\.topo-site nav \{ order: 3; width: 100%; justify-content: center; \}/);
  assert.match(html, /secao\('agenda', 'Próximos eventos'/);
  assert.match(html, /id: 'cultos'/);
  assert.doesNotMatch(html, /menu\.push\(\['agenda', 'Agenda'\]\)/);
  assert.doesNotMatch(html, /menu\.push\(\['cultos', 'Cultos'\]\)/);
});
