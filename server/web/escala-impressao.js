'use strict';

/** Só cultos com ao menos uma pessoa escalada na aba impressa. */
function cultosParaImpressao(cultos, tipo) {
  return cultos.filter((culto) => (culto.funcoes?.[tipo] || []).some((funcao) => (culto[tipo]?.[funcao] || []).length > 0));
}

/** Monta os dois formatos com elementos DOM (sem interpretar texto cadastrado como HTML). */
function montarEscalaImpressao(cultos, tipo, formato, colunas, mes, el) {
  if (!['paisagem', 'retrato'].includes(formato)) throw new Error('Formato de impressão inválido.');
  const titulo = tipo === 'pastoral' ? 'Escala pastoral' : 'Escala do louvor';
  const pessoas = (c, funcao) => (c[tipo][funcao] || []).map((p) => p.nome).join(', ') || '—';
  const musicas = (c) => (c.musicas || []).map((m) => m.tom ? `${m.titulo} (${m.tom})` : m.titulo);
  const cabecalho = el('header', { class: 'escala-cabecalho' },
    el('img', { src: '/logo.png', alt: 'Igreja Diakonia Tulipas' }),
    el('div', {}, el('p', { class: 'escala-igreja' }, 'Igreja Diakonia Tulipas'),
      el('h1', {}, titulo), el('p', { class: 'escala-mes-impresso' }, mes)));

  let conteudo;
  if (formato === 'paisagem') {
    const cabecalhos = [el('th', { scope: 'col' }, 'Culto'),
      ...colunas.map((f) => el('th', { scope: 'col' }, f))];
    if (tipo === 'louvor') cabecalhos.push(el('th', { scope: 'col' }, 'Músicas'));
    const linhas = cultos.map((c) => {
      const celulas = [el('td', { class: 'escala-data' }, el('strong', {}, `${c.rotulo} · ${c.horaTexto}`),
        el('span', {}, c.nome + (c.ceia ? ' · Santa Ceia' : ''))),
        ...colunas.map((f) => el('td', {}, c.funcoes[tipo].includes(f) ? pessoas(c, f) : '—'))];
      if (tipo === 'louvor') celulas.push(el('td', {}, musicas(c).length
        ? el('ol', { class: 'escala-musicas' }, ...musicas(c).map((m) => el('li', {}, m))) : '—'));
      return el('tr', {}, ...celulas);
    });
    conteudo = el('table', { class: 'escala-tabela' },
      el('thead', {}, el('tr', {}, ...cabecalhos)), el('tbody', {}, ...linhas));
  } else {
    const cartoes = cultos.map((c) => {
      const partes = [el('header', {}, el('h2', {}, `${c.rotulo} · ${c.horaTexto}`),
        el('p', {}, c.nome + (c.ceia ? ' · Santa Ceia' : ''))),
        el('dl', { class: 'escala-funcoes' }, ...c.funcoes[tipo].flatMap((f) => [
          el('dt', {}, f), el('dd', {}, pessoas(c, f)),
        ]))];
      if (tipo === 'louvor' && musicas(c).length) {
        partes.push(el('div', { class: 'escala-repertorio' }, el('h3', {}, 'Músicas'),
          el('ol', { class: 'escala-musicas' }, ...musicas(c).map((m) => el('li', {}, m)))));
      }
      return el('article', { class: 'escala-cartao' }, ...partes);
    });
    conteudo = el('div', { class: 'escala-cartoes' }, ...cartoes);
  }

  return el('div', { class: `impressao-escala ${formato}` }, cabecalho, conteudo,
    el('p', { class: 'escala-rodape' }, `${titulo} · ${mes} · ${cultos.length} ${cultos.length === 1 ? 'culto' : 'cultos'} com pessoas escaladas`));
}

if (typeof module !== 'undefined' && module.exports) module.exports = { cultosParaImpressao, montarEscalaImpressao };
