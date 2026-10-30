'use strict';
// Ensaio da Palavra no painel: percorre os trechos em tela cheia, sem projetar nada, e mede o tempo
// de cada tópico. Usa as contas de palavras-ensaio.js e o estado do editor de palavras.js.

const ensaio = { indice: -1, marcas: [], fim: 0, relogio: null };

function abrirEnsaio() {
  if (!trechosPalavra.length) {
    $('palavra-importar-erro').textContent = 'Escreva o texto antes de ensaiar.';
    $('palavra-importar-erro').hidden = false;
    return;
  }
  ensaio.indice = -1;
  ensaio.marcas = [];
  ensaio.fim = 0;
  $('ensaio-titulo').textContent = $('palavra-campo-titulo').value.trim() || 'Palavra';
  $('ensaio-resumo').hidden = true;
  $('ensaio-corpo').hidden = false;
  $('ensaio-acoes').hidden = false;
  $('ensaio-topico').textContent = `${trechosPalavra.length} trechos · nada é projetado no ensaio`;
  $('ensaio-num').textContent = '';
  $('ensaio-texto').textContent = 'Toque em Começar quando for pregar o primeiro trecho. O tempo de cada tópico é medido.';
  $('ensaio-extras').replaceChildren();
  $('ensaio-proximo').textContent = 'Começar';
  $('ensaio-anterior').disabled = true;
  $('ensaio-total').textContent = '0:00';
  $('ensaio-no-topico').textContent = '0:00';
  $('dlg-ensaio').showModal();
  $('ensaio-proximo').focus();
}

/** Desde quando o pastor está no tópico atual (a última sequência de trechos do mesmo tópico). */
function inicioDoTopicoAtual() {
  const topico = trechosPalavra[ensaio.indice].topico;
  let i = ensaio.marcas.length - 1;
  while (i > 0 && trechosPalavra[ensaio.marcas[i - 1].trecho].topico === topico) i--;
  return ensaio.marcas[i].em;
}

function atualizarRelogiosEnsaio() {
  if (ensaio.indice < 0) return;
  const agora = Date.now();
  $('ensaio-total').textContent = duracaoLegivel((agora - ensaio.marcas[0].em) / 1000);
  $('ensaio-no-topico').textContent = duracaoLegivel((agora - inicioDoTopicoAtual()) / 1000);
}

function irParaTrechoEnsaio(indice) {
  ensaio.indice = indice;
  ensaio.marcas.push({ trecho: indice, em: Date.now() });
  const t = trechosPalavra[indice];
  const topicos = [...new Set(trechosPalavra.map((x) => x.topico).filter(Boolean))];
  const previsto = minutosTopicosPalavra[t.topico];
  $('ensaio-topico').textContent = t.topico
    ? `Tópico ${topicos.indexOf(t.topico) + 1} de ${topicos.length} · ${t.topico}${previsto ? ` · previsto ${previsto} min` : ''}`
    : 'Antes do primeiro tópico';
  $('ensaio-num').textContent = `Trecho ${indice + 1} de ${trechosPalavra.length}`;
  $('ensaio-texto').textContent = t.texto;
  $('ensaio-extras').replaceChildren(
    ...t.referencias.filter((r) => r.ref && r.status !== 'ignorada').map((r) => el('span', { class: 'ensaio-ref' }, r.nome)),
    ...(t.destaques || []).map((d) => el('span', { class: 'ensaio-frase' }, '“' + d + '”')));
  $('ensaio-anterior').disabled = indice === 0;
  $('ensaio-proximo').textContent = indice + 1 < trechosPalavra.length ? 'Próximo trecho →' : 'Concluir ensaio';
  if (!ensaio.relogio) ensaio.relogio = setInterval(atualizarRelogiosEnsaio, 500);
  atualizarRelogiosEnsaio();
}

function concluirEnsaio() {
  ensaio.fim = Date.now();
  clearInterval(ensaio.relogio);
  ensaio.relogio = null;
  const r = resumoDoEnsaio(trechosPalavra, ensaio.marcas, ensaio.fim, minutosTopicosPalavra);
  ensaio.resumo = r;
  const previstoTotal = Number($('palavra-campo-minutos').value) || 40;
  const diferenca = (seg) => (seg === null ? '–' : (seg > 0 ? '+' : '') + duracaoLegivel(seg));
  $('ensaio-tabela').replaceChildren(
    el('thead', {}, el('tr', {}, el('th', {}, 'Tópico'), el('th', {}, 'Previsto'), el('th', {}, 'Ensaio'), el('th', {}, 'Diferença'))),
    el('tbody', {}, r.linhas.map((l) => el('tr', { class: l.diferenca > 60 ? 'passou' : '' },
      el('td', {}, l.topico),
      el('td', {}, l.previsto ? `${l.previsto} min` : '–'),
      el('td', {}, duracaoLegivel(l.segundos)),
      el('td', {}, diferenca(l.diferenca))))),
    el('tfoot', {}, el('tr', {},
      el('th', {}, 'Total'),
      el('th', {}, `${previstoTotal} min`),
      el('th', {}, duracaoLegivel(r.totalSegundos)),
      el('th', {}, diferenca(r.totalSegundos - previstoTotal * 60)))));
  $('ensaio-guardado').textContent = palavraAtual && palavraAtual.id ? '' : 'Salve a Palavra para guardar o tempo do ensaio.';
  $('ensaio-guardar').disabled = !(palavraAtual && palavraAtual.id);
  $('ensaio-corpo').hidden = true;
  $('ensaio-acoes').hidden = true;
  $('ensaio-resumo').hidden = false;
  $('ensaio-topico').textContent = 'Ensaio concluído';
  $('ensaio-guardar').focus();
}

function proximoNoEnsaio() {
  if (!$('ensaio-resumo').hidden) return;
  if (ensaio.indice + 1 < trechosPalavra.length) irParaTrechoEnsaio(ensaio.indice + 1);
  else concluirEnsaio();
}

function anteriorNoEnsaio() {
  if ($('ensaio-resumo').hidden && ensaio.indice > 0) irParaTrechoEnsaio(ensaio.indice - 1);
}

/** Texto curto do último ensaio guardado, para o editor e a lista. */
function textoUltimoEnsaio(ultimo) {
  if (!ultimo) return '';
  return `Último ensaio: ${duracaoLegivel(ultimo.totalSegundos)} (${new Date(ultimo.em).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })})`;
}

$('palavra-ensaiar').addEventListener('click', abrirEnsaio);
$('ensaio-proximo').addEventListener('click', proximoNoEnsaio);
$('ensaio-anterior').addEventListener('click', anteriorNoEnsaio);
$('ensaio-fechar').addEventListener('click', () => $('dlg-ensaio').close());
$('ensaio-de-novo').addEventListener('click', abrirEnsaio);
$('dlg-ensaio').addEventListener('close', () => {
  clearInterval(ensaio.relogio);
  ensaio.relogio = null;
});
$('dlg-ensaio').addEventListener('keydown', (e) => {
  if (e.target.closest && e.target.closest('button') && (e.key === ' ' || e.key === 'Enter')) return;
  if (['ArrowRight', 'PageDown', ' '].includes(e.key)) {
    e.preventDefault();
    proximoNoEnsaio();
  } else if (['ArrowLeft', 'PageUp'].includes(e.key)) {
    e.preventDefault();
    anteriorNoEnsaio();
  }
});
$('ensaio-guardar').addEventListener('click', async () => {
  if (!palavraAtual || !palavraAtual.id || !ensaio.resumo) return;
  const ultimoEnsaio = {
    em: new Date(ensaio.fim).toISOString(),
    totalSegundos: ensaio.resumo.totalSegundos,
    topicos: Object.fromEntries(ensaio.resumo.linhas.map((l) => [l.topico, l.segundos])),
  };
  try {
    const salvo = await api('PUT', '/api/palavras/' + palavraAtual.id, { ultimoEnsaio });
    palavraAtual.ultimoEnsaio = salvo.ultimoEnsaio;
    palavraAtual.versoes = salvo.versoes;
    $('palavra-ensaio-info').textContent = textoUltimoEnsaio(salvo.ultimoEnsaio);
    mensagem($('ensaio-guardado'), 'Tempo do ensaio guardado na Palavra.');
  } catch (err) {
    mensagem($('ensaio-guardado'), err.message, false);
  }
});
