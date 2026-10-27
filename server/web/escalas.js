// Aba Escalas do painel: cultos do mês com a escala pastoral e a do louvor.
// Carregado depois do painel.js (usa api, el, botao, mensagem, abrirDialogo, pode e o mapa carregar).

const escala = {
  mes: null, // 'aaaa-mm'
  tipo: 'louvor', // 'pastoral' | 'louvor'
  dados: null, // resposta de GET /api/escalas
};

const NOMES_ESCALA = { pastoral: 'Pastoral', louvor: 'Louvor' };

const mesIso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
const comMaiuscula = (s) => s.charAt(0).toUpperCase() + s.slice(1);
const nomeMes = (mes) => new Date(mes + '-15T12:00:00').toLocaleDateString('pt-BR', { month: 'long' });

function mudarMes(delta) {
  const [a, m] = escala.mes.split('-').map(Number);
  escala.mes = mesIso(new Date(a, m - 1 + delta, 1));
  carregarEscalas();
}

$('escala-anterior').addEventListener('click', () => mudarMes(-1));
$('escala-proximo').addEventListener('click', () => mudarMes(1));
document.querySelectorAll('[data-escala]').forEach((b) => b.addEventListener('click', () => {
  escala.tipo = b.dataset.escala;
  desenharEscala();
}));

async function carregarEscalas() {
  if (!escala.mes) {
    escala.mes = mesIso(new Date());
    // Quem só monta o louvor (ou só a pastoral) já abre na sua escala.
    escala.tipo = pode('escalaLouvor') && !pode('escalaPastoral') ? 'louvor' : pode('escalaPastoral') ? 'pastoral' : 'louvor';
  }
  try {
    escala.dados = await api('GET', '/api/escalas?mes=' + escala.mes);
    desenharEscala();
  } catch (err) {
    mensagem($('resultado-escala'), err.message, false);
  }
}
carregar.escalas = carregarEscalas;

/** Funções que viram colunas no mês: a Santa Ceia só se algum culto for de ceia. */
function colunasDoMes(d, tipo) {
  const todas = new Set(d.cultos.flatMap((c) => c.funcoes[tipo]));
  const ordem = tipo === 'pastoral' ? ['Direção', 'Pregação', 'Oração e ofertas', 'Santa Ceia'] : ['Ministro', 'Vocal', 'Teclado', 'Violão', 'Baixo', 'Bateria'];
  return ordem.filter((f) => todas.has(f));
}

function desenharEscala() {
  const d = escala.dados;
  if (!d) return;
  const tipo = escala.tipo;
  const podeTipo = d.pode[tipo];
  const algum = d.pode.pastoral || d.pode.louvor;
  document.querySelectorAll('[data-escala]').forEach((b) => b.setAttribute('aria-selected', String(b.dataset.escala === tipo)));
  $('escala-titulo').textContent = comMaiuscula(d.titulo);
  $('resultado-escala').textContent = '';

  const [a, m] = escala.mes.split('-').map(Number);
  const anterior = mesIso(new Date(a, m - 2, 1));
  $('escala-repetir').textContent = 'Repetir ' + nomeMes(anterior);
  $('escala-repetir').hidden = !podeTipo || d.cultos.length === 0;
  $('escala-extra').hidden = !d.pode.pastoral;
  $('escala-link').hidden = !algum;
  $('escala-indisponivel').hidden = !algum;
  $('escala-imprimir').hidden = d.cultos.length === 0;

  const vazio = d.cultos.length === 0;
  $('escala-vazia').hidden = !vazio;
  $('escala-conteudo').hidden = vazio;
  $('escala-vazia-mes').textContent = d.titulo;
  $('escala-gerar').hidden = !d.pode.pastoral || !d.horariosConfigurados;
  $('escala-sem-horarios').hidden = d.horariosConfigurados;
  if (vazio) return;

  const colunas = colunasDoMes(d, tipo);
  let preenchidas = 0, total = 0;
  for (const c of d.cultos) {
    for (const f of c.funcoes[tipo]) {
      total++;
      if ((c[tipo][f] || []).length) preenchidas++;
    }
  }
  const avisos = d.avisos[tipo];
  $('escala-resumo').replaceChildren(
    el('span', {}, el('strong', {}, String(d.cultos.length)), d.cultos.length === 1 ? ' culto no mês' : ' cultos no mês'),
    el('span', {}, el('strong', {}, String(preenchidas)), ` de ${total} funções preenchidas`),
    avisos.length ? el('span', { class: 'alerta' }, `${avisos.length} ${avisos.length === 1 ? 'aviso' : 'avisos'}`) : null);

  const cabecalho = el('tr', {}, el('th', { scope: 'col' }, 'Culto'),
    ...colunas.map((f) => el('th', { scope: 'col' }, f)),
    tipo === 'louvor' ? el('th', { scope: 'col' }, 'Músicas') : null);
  const linhas = d.cultos.map((c) => el('tr', {},
    el('td', { class: 'culto' },
      el('div', { style: 'font-weight:600' }, `${c.rotulo} · ${c.horaTexto}`),
      el('div', { class: 'sub' }, c.nome + (c.tema && tipo === 'pastoral' ? ' · ' + c.tema : '')),
      c.ceia ? el('span', { class: 'ceia' }, 'Santa Ceia') : null,
      d.pode.pastoral ? el('div', {}, el('button', { type: 'button', class: 'link', style: 'font-size:13px', onclick: () => abrirCulto(c) }, 'Editar culto')) : null),
    ...colunas.map((f) => el('td', {}, celulaEscala(c, tipo, f, podeTipo))),
    tipo === 'louvor' ? el('td', {}, celulaMusicas(c, d.pode.louvor)) : null));
  $('escala-grade').replaceChildren(el('thead', {}, cabecalho), el('tbody', {}, ...linhas));

  $('escala-avisos').replaceChildren(...(avisos.length
    ? avisos.map((av) => el('div', { class: 'escala-aviso ' + av.tipo },
      el('span', { class: 'marca', 'aria-hidden': 'true' }, '!'),
      el('div', {}, el('div', { style: 'font-weight:600' }, av.titulo), el('div', { class: 'texto' }, av.texto))))
    : [el('p', { class: 'dica', style: 'margin:0' }, 'Nenhum aviso: escala completa e sem conflitos.')]));

  $('escala-indisponiveis').replaceChildren(...(d.indisponibilidades.length ? [
    el('h3', { style: 'font-size:15px;margin:18px 0 8px' }, 'Indisponíveis no mês'),
    ...d.indisponibilidades.map((i) => el('div', { class: 'par', style: 'display:flex;align-items:center;gap:8px;margin-bottom:6px' },
      el('span', { style: 'flex:1' }, `${i.nome}: ${periodo(i.de, i.ate)}${i.motivo ? ' · ' + i.motivo : ''}`),
      algum ? botao('Remover', async () => {
        if (!confirm(`Remover a indisponibilidade de ${i.nome}?`)) return;
        await api('DELETE', '/api/escalas/indisponibilidades/' + i.id).catch((err) => mensagem($('resultado-escala'), err.message, false));
        carregarEscalas();
      }) : null)),
  ] : []));

  $('escala-whatsapp').value = d.whatsapp[tipo];
  $('escala-abrir-whatsapp').href = 'https://wa.me/?text=' + encodeURIComponent(d.whatsapp[tipo]);
}

function periodo(de, ate) {
  const f = (iso) => iso.slice(8, 10) + '/' + iso.slice(5, 7);
  return de === ate ? f(de) : `${f(de)} a ${f(ate)}`;
}

function celulaEscala(c, tipo, funcao, podeEditar) {
  if (!c.funcoes[tipo].includes(funcao)) return null; // Santa Ceia fora do culto de ceia
  const pessoas = c[tipo][funcao] || [];
  const filhos = pessoas.map((p) => el('span', { class: 'pessoa' + (p.aviso ? (p.aviso === 'Indisponível' ? ' indisponivel' : ' conflito') : '') },
    p.nome, p.aviso ? el('small', {}, p.aviso) : null));
  if (!podeEditar) return el('div', { class: 'escala-celula' }, ...(filhos.length ? filhos : [el('span', { class: 'dica' }, '—')]));
  if (!filhos.length) filhos.push(el('span', { class: 'vaga' }, '+ Escalar'));
  return el('button', {
    type: 'button',
    class: 'escala-celula',
    'aria-label': `${funcao} em ${c.rotulo}: ${pessoas.map((p) => p.nome).join(', ') || 'vaga'}. Alterar`,
    onclick: () => abrirEscalar(c, tipo, funcao),
  }, ...filhos);
}

function celulaMusicas(c, podeEditar) {
  const n = (c.musicas || []).length;
  const texto = n ? `${n} ${n === 1 ? 'música' : 'músicas'}` : null;
  if (!podeEditar) return texto ? el('button', { type: 'button', class: 'escala-celula', onclick: () => abrirMusicas(c, false) }, el('span', { class: 'musicas' }, texto)) : el('span', { class: 'dica' }, '—');
  return el('button', { type: 'button', class: 'escala-celula', onclick: () => abrirMusicas(c, true) },
    texto ? el('span', { class: 'musicas' }, texto) : el('span', { class: 'vaga' }, '+ Músicas'));
}

// ---------- Escolher quem serve ----------

let escalarAtual = null;

/** Situação da pessoa para este culto: indisponível, já em outra função ou quantas vezes serve no mês. */
function situacaoPessoa(p, c, tipo, funcao) {
  const ind = escala.dados.indisponibilidades.find((i) => i.membroId === p.id && i.de <= c.data && i.ate >= c.data);
  if (ind) return { classe: 'indisponivel', texto: `Indisponível ${periodo(ind.de, ind.ate)}${ind.motivo ? ' · ' + ind.motivo : ''}` };
  for (const t of ['pastoral', 'louvor']) {
    for (const f of c.funcoes[t]) {
      if ((t !== tipo || f !== funcao) && (c[t][f] || []).some((x) => x.id === p.id)) {
        return { classe: 'conflito', texto: `Já está em ${f.toLowerCase()} neste culto` };
      }
    }
  }
  const vezes = escala.dados.cultos.filter((x) => x.funcoes[tipo].some((f) => (x[tipo][f] || []).some((y) => y.id === p.id))).length;
  return { classe: '', texto: `Disponível · ${vezes === 0 ? 'nenhum culto' : vezes === 1 ? '1 culto' : vezes + ' cultos'} no mês` };
}

const iniciais = (nome) => nome.split(/\s+/).filter((x) => !/^(pr|pra|pb|dc|ev|miss)\.?$/i.test(x)).slice(0, 2).map((x) => x[0]).join('').toUpperCase();

function desenharEscalar() {
  const { c, tipo, funcao, marcados } = escalarAtual;
  const busca = $('escalar-busca').value.trim().toLowerCase();
  const todos = $('escalar-todos').checked;
  const lista = escala.dados.pessoas.filter((p) => (todos || p[tipo] || marcados.has(p.id)) && (!busca || p.nome.toLowerCase().includes(busca)));
  $('escalar-lista').replaceChildren(...(lista.length ? lista.map((p) => {
    const s = situacaoPessoa(p, c, tipo, funcao);
    const caixa = el('input', { type: 'checkbox', value: p.id });
    caixa.checked = marcados.has(p.id);
    caixa.addEventListener('change', () => (caixa.checked ? marcados.add(p.id) : marcados.delete(p.id)));
    return el('label', { class: s.classe === 'indisponivel' ? 'indisponivel' : '' },
      caixa,
      el('span', { class: 'iniciais', 'aria-hidden': 'true' }, iniciais(p.nome)),
      el('span', { style: 'flex:1' }, el('span', { class: 'nome' }, p.nome), el('span', { class: 'situacao ' + s.classe }, s.texto)));
  }) : [el('p', { class: 'dica', style: 'margin:0' }, todos ? 'Ninguém encontrado.' : `Ninguém com o ministério ${tipo === 'louvor' ? 'Louvor' : 'Pastoral'} na ficha. Marque "Mostrar todos" ou ajuste as fichas em Membros.`)]));
}

function abrirEscalar(c, tipo, funcao) {
  escalarAtual = { c, tipo, funcao, marcados: new Set((c[tipo][funcao] || []).map((p) => p.id)) };
  $('escalar-funcao').textContent = `${NOMES_ESCALA[tipo]} · ${funcao}`;
  $('escalar-culto').textContent = `${c.rotulo} · ${c.horaTexto}`;
  $('escalar-nome-culto').textContent = c.nome + (c.ceia ? ' · Santa Ceia' : '');
  $('escalar-pergunta').textContent = `Quem fica com ${funcao.toLowerCase()} neste culto?`;
  $('escalar-busca').value = '';
  $('escalar-todos').checked = false;
  $('escalar-dica').textContent = tipo === 'louvor'
    ? 'A lista mostra quem tem o ministério Louvor (ou Música) na ficha. Pode marcar mais de uma pessoa.'
    : 'A lista mostra quem tem o ministério Pastoral ou Liderança, ou a função de pastor, presbítero, diácono ou evangelista na ficha.';
  desenharEscalar();
  abrirDialogo($('dlg-escalar'), $('erro-escalar'), async () => {
    await api('PUT', '/api/escalas/' + c.id, { tipo, funcao, membros: [...escalarAtual.marcados] });
    await carregarEscalas();
  });
}
$('escalar-busca').addEventListener('input', () => escalarAtual && desenharEscalar());
$('escalar-todos').addEventListener('change', () => escalarAtual && desenharEscalar());

// ---------- Músicas ----------

function linhaMusica(m = { titulo: '', tom: '' }, editavel = true) {
  const titulo = el('input', { type: 'text', maxlength: '120', placeholder: 'Nome da música', 'aria-label': 'Nome da música' });
  const tom = el('input', { type: 'text', maxlength: '12', placeholder: 'Tom', 'aria-label': 'Tom' });
  titulo.value = m.titulo || '';
  tom.value = m.tom || '';
  titulo.disabled = tom.disabled = !editavel;
  const linha = el('div', { class: 'musica' }, el('span', { class: 'ordem' }), titulo, tom,
    editavel ? el('button', { type: 'button', class: 'botao secundario pequeno', 'aria-label': 'Remover música', style: 'padding:0', onclick: () => { linha.remove(); numerarMusicas(); } }, '×') : el('span'));
  return linha;
}

function numerarMusicas() {
  $('musicas-lista').querySelectorAll('.ordem').forEach((o, i) => (o.textContent = String(i + 1)));
}

function abrirMusicas(c, editavel) {
  $('musicas-culto').textContent = `${c.rotulo} · ${c.horaTexto} · ${c.nome}. Na ordem do ministro.`;
  const musicas = c.musicas || [];
  $('musicas-lista').replaceChildren(...(musicas.length || !editavel ? musicas : [{}]).map((m) => linhaMusica(m, editavel)));
  numerarMusicas();
  $('musicas-adicionar').hidden = !editavel;
  $('musicas-salvar').hidden = !editavel;
  abrirDialogo($('dlg-musicas'), $('erro-musicas'), async () => {
    const lista = [...$('musicas-lista').querySelectorAll('.musica')]
      .map((l) => ({ titulo: l.querySelectorAll('input')[0].value.trim(), tom: l.querySelectorAll('input')[1].value.trim() }))
      .filter((m) => m.titulo);
    await api('PUT', '/api/escalas/' + c.id, { musicas: lista });
    await carregarEscalas();
  });
}
$('musicas-adicionar').addEventListener('click', () => {
  $('musicas-lista').append(linhaMusica());
  numerarMusicas();
});

// ---------- Cultos: gerar, repetir, extra, editar ----------

$('escala-gerar').addEventListener('click', async () => {
  try {
    const r = await api('POST', '/api/escalas/gerar', { mes: escala.mes });
    await carregarEscalas();
    mensagem($('resultado-escala'), r.criados ? `${r.criados} cultos criados.` : 'Os cultos do mês já existiam.');
  } catch (err) {
    mensagem($('resultado-escala'), err.message, false);
  }
});

$('escala-repetir').addEventListener('click', async () => {
  try {
    const r = await api('POST', '/api/escalas/repetir', { mes: escala.mes, tipo: escala.tipo });
    await carregarEscalas();
    mensagem($('resultado-escala'), r.preenchidas
      ? `${r.preenchidas} ${r.preenchidas === 1 ? 'função preenchida' : 'funções preenchidas'} com a escala do mês anterior. As que já tinham alguém não mudaram.`
      : 'Nada para repetir: o mês anterior não tem escala nessas funções vazias.');
  } catch (err) {
    mensagem($('resultado-escala'), err.message, false);
  }
});

function abrirCulto(c) {
  const novo = !c;
  $('culto-titulo').textContent = novo ? 'Culto extra' : `${c.rotulo} · ${c.horaTexto}`;
  $('culto-data').value = novo ? escala.mes + '-01' : c.data;
  $('culto-data').disabled = !novo;
  $('culto-hora').value = novo ? '19:00' : c.hora;
  $('culto-nome').value = novo ? '' : c.nome;
  $('culto-tema').value = novo ? '' : c.tema || '';
  $('culto-ceia').checked = !novo && !!c.ceia;
  $('culto-excluir').hidden = novo;
  $('culto-excluir').onclick = async () => {
    if (!confirm(`Excluir o culto de ${c.rotulo} e a escala dele?`)) return;
    try {
      await api('DELETE', '/api/escalas/' + c.id);
      $('dlg-culto').close();
      await carregarEscalas();
    } catch (err) {
      mensagem($('erro-culto'), err.message, false);
      $('erro-culto').hidden = false;
    }
  };
  abrirDialogo($('dlg-culto'), $('erro-culto'), async () => {
    const dados = { hora: $('culto-hora').value, nome: $('culto-nome').value.trim(), ceia: $('culto-ceia').checked, tema: $('culto-tema').value.trim() };
    if (novo) await api('POST', '/api/escalas', { ...dados, data: $('culto-data').value });
    else await api('PUT', '/api/escalas/' + c.id, dados);
    await carregarEscalas();
  });
}
$('escala-extra').addEventListener('click', () => abrirCulto(null));

// ---------- Indisponibilidade e link "Minha escala" ----------

function opcoesPessoas(select) {
  const pessoas = escala.dados.pessoas;
  // Quem tem o ministério desta escala primeiro.
  const daEscala = pessoas.filter((p) => p[escala.tipo]);
  const outros = pessoas.filter((p) => !p[escala.tipo]);
  select.replaceChildren(
    el('option', { value: '' }, 'Escolha…'),
    daEscala.length ? el('optgroup', { label: NOMES_ESCALA[escala.tipo] }, ...daEscala.map((p) => el('option', { value: p.id }, p.nome))) : null,
    outros.length ? el('optgroup', { label: 'Outros membros' }, ...outros.map((p) => el('option', { value: p.id }, p.nome))) : null);
}

$('escala-indisponivel').addEventListener('click', () => {
  opcoesPessoas($('ind-pessoa'));
  $('ind-de').value = '';
  $('ind-ate').value = '';
  $('ind-motivo').value = '';
  abrirDialogo($('dlg-indisponivel'), $('erro-indisponivel'), async () => {
    if (!$('ind-pessoa').value || !$('ind-de').value) throw new Error('Escolha a pessoa e a data.');
    await api('POST', '/api/escalas/indisponibilidades', {
      membroId: $('ind-pessoa').value, de: $('ind-de').value, ate: $('ind-ate').value || $('ind-de').value, motivo: $('ind-motivo').value.trim(),
    });
    await carregarEscalas();
  });
});

$('escala-link').addEventListener('click', () => {
  opcoesPessoas($('link-escala-pessoa'));
  $('link-escala-resultado').hidden = true;
  $('erro-link-escala').hidden = true;
  $('link-escala-gerar').hidden = false;
  $('dlg-link-escala').querySelector('form').onsubmit = async (e) => {
    if (e.submitter && e.submitter.value === 'cancelar') return;
    e.preventDefault();
    $('erro-link-escala').hidden = true;
    if (!$('link-escala-pessoa').value) {
      mensagem($('erro-link-escala'), 'Escolha a pessoa.', false);
      $('erro-link-escala').hidden = false;
      return;
    }
    try {
      const r = await api('POST', '/api/escalas/link/' + encodeURIComponent($('link-escala-pessoa').value));
      $('link-escala-url').value = r.url;
      const texto = `Olá, ${r.nome.split(' ')[0]}! Este é o seu link da escala da igreja: ${r.url}`;
      $('link-escala-whatsapp').href = 'https://wa.me/?text=' + encodeURIComponent(texto);
      $('link-escala-resultado').hidden = false;
    } catch (err) {
      mensagem($('erro-link-escala'), err.message, false);
      $('erro-link-escala').hidden = false;
    }
  };
  $('dlg-link-escala').showModal();
});
$('link-escala-pessoa').addEventListener('change', () => ($('link-escala-resultado').hidden = true));
$('link-escala-copiar').addEventListener('click', () => navigator.clipboard.writeText($('link-escala-url').value));

// ---------- WhatsApp e impressão ----------

$('escala-whatsapp').addEventListener('input', () => {
  $('escala-abrir-whatsapp').href = 'https://wa.me/?text=' + encodeURIComponent($('escala-whatsapp').value);
});
$('escala-copiar').addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText($('escala-whatsapp').value);
    mensagem($('resultado-escala'), 'Texto copiado.');
  } catch {
    $('escala-whatsapp').select();
  }
});

$('escala-imprimir').addEventListener('click', () => {
  const d = escala.dados, tipo = escala.tipo;
  const colunas = colunasDoMes(d, tipo);
  $('impressao-membros').replaceChildren(
    el('h1', {}, `Escala ${tipo === 'pastoral' ? 'pastoral' : 'do louvor'} — ${d.titulo}`),
    el('p', {}, 'Igreja Diakonia Tulipas'),
    el('table', {},
      el('thead', {}, el('tr', {}, el('th', {}, 'Culto'), ...colunas.map((f) => el('th', {}, f)), tipo === 'louvor' ? el('th', {}, 'Músicas') : null)),
      el('tbody', {}, ...d.cultos.map((c) => el('tr', {},
        el('td', {}, `${c.rotulo} · ${c.horaTexto}${c.ceia ? ' · Santa Ceia' : ''}`),
        ...colunas.map((f) => el('td', {}, c.funcoes[tipo].includes(f) ? (c[tipo][f] || []).map((p) => p.nome).join(', ') : '')),
        tipo === 'louvor' ? el('td', {}, (c.musicas || []).map((m) => m.tom ? `${m.titulo} (${m.tom})` : m.titulo).join('; ')) : null)))));
  window.print();
});
