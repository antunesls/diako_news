// Catálogo local do louvor: importação inicial de CSV e manutenção no painel.
let repertorioMusicas = [];
const tomPadraoRepertorio = (texto) => ((texto || '').split(/\r?\n/)[0]
  .match(/(?:^|[^A-Za-z])([A-G](?:#|b)?m?)(?=$|[^A-Za-z#])/i) || [])[1] || '';
const opcoesTomRepertorio = (select, incluirTodos) => select.replaceChildren(
  ...(incluirTodos ? [new Option('Todos os tons', '')] : []),
  ...TONS_REPERTORIO.map(([valor, descricao]) => new Option(descricao, incluirTodos && !valor ? '_sem_tom' : valor)));
opcoesTomRepertorio($('repertorio-filtro-tom'), true);
opcoesTomRepertorio($('rep-tomSelecionado'), false);

async function carregarRepertorio() {
  try {
    repertorioMusicas = await api('GET', '/api/repertorio');
    desenharRepertorio();
  } catch (err) {
    mensagem($('repertorio-resultado'), err.message, false);
  }
}
carregar.repertorio = carregarRepertorio;

function desenharRepertorio() {
  const filtroTom = $('repertorio-filtro-tom').value;
  const musicas = buscarRepertorio(repertorioMusicas, {
    busca: $('repertorio-busca').value,
    status: $('repertorio-filtro-status').value,
    tom: filtroTom === '_sem_tom' ? '' : filtroTom,
  }).filter((m) => filtroTom !== '_sem_tom' || !tomDaMusica(m));
  $('repertorio-contagem').textContent = `${musicas.length} ${musicas.length === 1 ? 'música encontrada' : 'músicas encontradas'} de ${repertorioMusicas.length}.`;
  $('repertorio-lista').replaceChildren(...(musicas.length ? musicas.map((m) =>
    el('div', { class: 'cartao', style: 'margin-bottom:10px;display:flex;align-items:center;gap:16px' },
      el('div', { style: 'flex:1' }, el('strong', {}, m.titulo),
        el('div', { class: 'dica' }, `${m.cantor} · ${statusParaFiltro(m)}${tomDaMusica(m) ? ' · Tom Diakonia: ' + tomDaMusica(m) : ''}`)),
      pode('escalaLouvor') ? botao('Editar', () => abrirRepertorio(m)) : null))
    : [el('p', { class: 'dica' }, 'Nenhuma música encontrada.')]));
}
$('repertorio-busca').addEventListener('input', desenharRepertorio);
$('repertorio-filtro-status').addEventListener('change', desenharRepertorio);
$('repertorio-filtro-tom').addEventListener('change', desenharRepertorio);
$('repertorio-limpar').addEventListener('click', () => {
  $('repertorio-busca').value = '';
  $('repertorio-filtro-status').value = '';
  $('repertorio-filtro-tom').value = '';
  desenharRepertorio();
  $('repertorio-busca').focus();
});

const camposRepertorio = ['titulo', 'cantor', 'compositor', 'ano', 'bpm', 'tomOriginal', 'tomDiakonia',
  'referencia', 'solicitadoPor', 'observacoes', 'biografiaCantor', 'biografiaCompositor'];

function abrirRepertorio(m = null) {
  $('repertorio-dialogo-titulo').textContent = m ? 'Editar música' : 'Nova música';
  for (const campo of camposRepertorio) $('rep-' + campo).value = m?.[campo] || '';
  $('rep-tomSelecionado').value = m ? tomDaMusica(m) : '';
  $('rep-status').value = m ? statusParaFiltro(m) : 'OK';
  abrirDialogo($('dlg-repertorio'), $('rep-erro'), async () => {
    const j = Object.fromEntries(camposRepertorio.map((campo) => [campo, $('rep-' + campo).value.trim()]));
    j.tomSelecionado = $('rep-tomSelecionado').value;
    j.status = $('rep-status').value;
    if (!j.titulo || !j.cantor) throw new Error('Informe o título e o cantor.');
    await api(m ? 'PUT' : 'POST', m ? '/api/repertorio/' + m.id : '/api/repertorio', j);
    await carregarRepertorio();
  });
}
$('repertorio-novo').addEventListener('click', () => abrirRepertorio());

let csvRepertorio = '';
$('repertorio-importar').addEventListener('click', () => {
  csvRepertorio = '';
  $('repertorio-arquivo').value = '';
  $('repertorio-previa').textContent = 'Selecione um CSV exportado da planilha.';
  $('repertorio-preview-lista').replaceChildren();
  $('repertorio-confirmar').disabled = true;
  $('repertorio-erro').hidden = true;
  $('dlg-importar-repertorio').showModal();
});
$('repertorio-arquivo').addEventListener('change', async (e) => {
  const arquivo = e.target.files[0];
  csvRepertorio = '';
  $('repertorio-confirmar').disabled = true;
  if (!arquivo) return;
  try {
    if (arquivo.size > 2 * 1024 * 1024) throw new Error('CSV grande demais (limite de 2 MB).');
    csvRepertorio = await lerArquivoCsv(arquivo);
    const previa = await api('POST', '/api/repertorio/importar/previa', { csv: csvRepertorio });
    $('repertorio-previa').textContent = `${previa.novas} novas · ${previa.repetidas} já cadastradas (não serão alteradas).`;
    $('repertorio-preview-lista').replaceChildren(...previa.musicas.map((m) =>
      el('p', {}, `${m.titulo} — ${m.cantor} · ${m.ativo ? 'Ativa' : 'Inativa'}`)));
    $('repertorio-confirmar').disabled = !previa.novas;
    $('repertorio-erro').hidden = true;
  } catch (err) {
    mensagem($('repertorio-erro'), err.message, false);
    $('repertorio-erro').hidden = false;
  }
});
$('dlg-importar-repertorio').querySelector('form').addEventListener('submit', async (e) => {
  if (e.submitter?.value === 'cancelar') return;
  e.preventDefault();
  $('repertorio-confirmar').disabled = true;
  try {
    const r = await api('POST', '/api/repertorio/importar', { csv: csvRepertorio });
    $('dlg-importar-repertorio').close();
    await carregarRepertorio();
    mensagem($('repertorio-resultado'), `${r.importadas} músicas importadas; ${r.repetidas} já cadastradas.`);
  } catch (err) {
    mensagem($('repertorio-erro'), err.message, false);
    $('repertorio-erro').hidden = false;
    $('repertorio-confirmar').disabled = false;
  }
});
