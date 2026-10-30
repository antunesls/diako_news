'use strict';
// Página Roteiros: modelos de roteiro do Modo Culto (ordem dos momentos, tempos e momentos livres).
// O tablet recebe o modelo de cada culto junto com a escala do dia. Usa api, el, botao e $ de comum.js.

/** Momentos do sistema (os mesmos do diako_core): nome do tipo -> [título, minutos sugeridos]. */
const TIPOS_MOMENTO = {
  contagem: ['Antes do culto (contagem)', 0],
  boasVindas: ['Boas-vindas', 5],
  louvor: ['Louvor', 30],
  recados: ['Recados', 10],
  ofertas: ['Dízimos e ofertas', 5],
  ceia: ['Santa Ceia (só quando a escala marca)', 15],
  motivos: ['Motivos de oração', 10],
  palavra: ['Palavra', 40],
  oracaoFinal: ['Oração final e bênção', 5],
  encerramento: ['Encerramento', 5],
};

let modeloAtual = null;
let itensModelo = [];

async function carregarRoteiros() {
  $('roteiros-lista-tela').hidden = false;
  $('roteiro-editor').hidden = true;
  $('roteiro-novo').hidden = !pode('escalaPastoral');
  try {
    desenharListaRoteiros(await api('GET', '/api/roteiros'));
  } catch (err) {
    mensagem($('roteiros-resultado'), err.message, false);
  }
}
carregar.roteiros = carregarRoteiros;

function desenharListaRoteiros(lista) {
  $('roteiros-lista').replaceChildren(...(lista.length ? lista.map((m) =>
    el('div', { class: 'cartao palavra-item' },
      el('div', { class: 'palavra-item-texto' },
        el('strong', {}, m.nome),
        el('div', { class: 'dica' }, [
          m.cultos.length ? 'Vale para: ' + m.cultos.join(', ') : null,
          `${m.itens.length} momento(s)`,
        ].filter(Boolean).join(' · '))),
      m.padrao ? el('span', { class: 'palavra-situacao pronta' }, 'Padrão') : null,
      botao(pode('escalaPastoral') ? 'Editar' : 'Ver', () => abrirRoteiro(m))))
    : [el('p', { class: 'dica' }, 'Nenhum modelo ainda: o tablet usa o roteiro do sistema (contagem, boas-vindas, louvor, recados, ofertas, Santa Ceia, motivos, Palavra, oração final e encerramento).')]));
}

function abrirRoteiro(modelo) {
  modeloAtual = modelo;
  itensModelo = modelo ? modelo.itens.map((i) => ({ ...i }))
    : Object.keys(TIPOS_MOMENTO).map((tipo) => ({ chave: tipo, tipo }));
  $('roteiro-nome').value = modelo ? modelo.nome : '';
  $('roteiro-cultos').value = modelo ? modelo.cultos.join(', ') : '';
  $('roteiro-padrao').checked = modelo ? modelo.padrao : false;
  $('roteiro-titulo-tela').textContent = modelo ? modelo.nome : 'Novo modelo';
  $('roteiro-erro').hidden = true;
  const editavel = pode('escalaPastoral');
  for (const id of ['roteiro-nome', 'roteiro-cultos', 'roteiro-padrao']) $(id).disabled = !editavel;
  $('roteiro-acoes').hidden = !editavel;
  $('roteiro-adicionar-linha').hidden = !editavel;
  $('roteiro-excluir').hidden = !modelo;
  desenharItensRoteiro();
  $('roteiros-lista-tela').hidden = true;
  $('roteiro-editor').hidden = false;
}

function mover(i, delta) {
  const j = i + delta;
  if (j < 0 || j >= itensModelo.length) return;
  [itensModelo[i], itensModelo[j]] = [itensModelo[j], itensModelo[i]];
  desenharItensRoteiro();
}

function desenharItensRoteiro() {
  const editavel = pode('escalaPastoral');
  $('roteiro-itens').replaceChildren(...itensModelo.map((item, i) => {
    const livre = item.tipo === 'livre';
    const [titulo, minutosPadrao] = livre ? ['Momento livre', 5] : TIPOS_MOMENTO[item.tipo];
    const minutos = el('input', {
      type: 'number', min: '0', max: '180', step: '1', value: item.minutos ?? '', placeholder: String(minutosPadrao),
      'aria-label': 'Minutos de ' + (item.titulo || titulo), disabled: !editavel,
      oninput: (e) => { item.minutos = e.target.value === '' ? undefined : Number(e.target.value); },
    });
    const corpo = livre
      ? el('div', { class: 'roteiro-livre' },
        el('input', { type: 'text', maxlength: '60', value: item.titulo || '', placeholder: 'Título (ex.: Apresentação de crianças)',
          'aria-label': 'Título do momento livre', disabled: !editavel, oninput: (e) => { item.titulo = e.target.value; } }),
        el('textarea', { rows: '2', maxlength: '600', placeholder: 'Slide no telão (opcional; vazio = tela vazia). Primeira linha em negrito.',
          'aria-label': 'Slide do momento livre', disabled: !editavel, oninput: (e) => { item.texto = e.target.value; } }, item.texto || ''))
      : el('strong', {}, titulo);
    return el('li', { class: 'roteiro-item' + (livre ? ' livre' : '') },
      el('span', { class: 'roteiro-num' }, String(i + 1)),
      el('div', { class: 'roteiro-corpo' }, corpo),
      el('label', { class: 'roteiro-minutos' }, minutos, el('span', { class: 'dica' }, 'min')),
      editavel ? el('div', { class: 'roteiro-mover' },
        botao('↑', () => mover(i, -1)),
        botao('↓', () => mover(i, 1)),
        botao('Remover', () => { itensModelo.splice(i, 1); desenharItensRoteiro(); }, 'perigo pequeno')) : null);
  }));

  // O que ainda dá para adicionar: os momentos do sistema que saíram e quantos livres quiser.
  const presentes = new Set(itensModelo.map((i) => i.tipo));
  $('roteiro-adicionar').replaceChildren(
    ...Object.entries(TIPOS_MOMENTO).filter(([tipo]) => !presentes.has(tipo)).map(([tipo, [titulo]]) => el('option', { value: tipo }, titulo)),
    el('option', { value: 'livre' }, 'Momento livre (apresentação, batismo, testemunho…)'));
}

$('roteiro-adicionar-botao').addEventListener('click', () => {
  const tipo = $('roteiro-adicionar').value;
  itensModelo.push(tipo === 'livre' ? { chave: 'livre-' + Date.now().toString(36), tipo, titulo: '' } : { chave: tipo, tipo });
  desenharItensRoteiro();
});

$('roteiro-novo').addEventListener('click', () => abrirRoteiro(null));
$('roteiro-voltar').addEventListener('click', carregarRoteiros);

$('roteiro-salvar').addEventListener('click', async () => {
  const erro = $('roteiro-erro');
  erro.hidden = true;
  const corpo = {
    nome: $('roteiro-nome').value.trim(),
    cultos: $('roteiro-cultos').value.split(',').map((c) => c.trim()).filter(Boolean),
    padrao: $('roteiro-padrao').checked,
    itens: itensModelo.map((i) => ({
      chave: i.chave,
      tipo: i.tipo,
      ...(i.tipo === 'livre' ? { titulo: (i.titulo || '').trim(), texto: (i.texto || '').trim() } : {}),
      ...(Number.isFinite(i.minutos) ? { minutos: i.minutos } : {}),
    })),
  };
  try {
    const salvo = modeloAtual
      ? await api('PUT', '/api/roteiros/' + modeloAtual.id, corpo)
      : await api('POST', '/api/roteiros', corpo);
    modeloAtual = salvo;
    $('roteiro-titulo-tela').textContent = salvo.nome;
    $('roteiro-excluir').hidden = false;
    mensagem($('roteiro-salvo'), 'Salvo. O tablet recebe na próxima atualização da escala.');
  } catch (err) {
    erro.textContent = err.message;
    erro.hidden = false;
  }
});

$('roteiro-excluir').addEventListener('click', async () => {
  if (!modeloAtual || !confirm(`Excluir o modelo "${modeloAtual.nome}"? Os cultos dele voltam a usar o padrão.`)) return;
  try {
    await api('DELETE', '/api/roteiros/' + modeloAtual.id);
    carregarRoteiros();
  } catch (err) {
    $('roteiro-erro').textContent = err.message;
    $('roteiro-erro').hidden = false;
  }
});
