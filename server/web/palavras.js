'use strict';
// Página Palavras: o pregador prepara o sermão; no culto, o tablet passa o texto trecho por
// trecho na TV do palco e projeta os versículos. Usa api, el, botao e $ de comum.js.

/** Palavra em edição (o documento completo do servidor; sem id quando é nova). */
let palavraAtual = null;
/** Decisões sobre os versículos achados: texto original -> {status, ajuste}. */
let decisoesPalavra = {};
/** Última análise do texto (trechos com as referências). */
let trechosPalavra = [];
let palavraAlterada = false;
let analiseAgendada = null;

const SITUACOES_PALAVRA = { rascunho: 'Rascunho', pronta: 'Pronta para o culto', pregada: 'Pregada' };

/** "2026-11-02" -> "dom., 02/11/2026" */
function dataDaPalavra(iso) {
  const [a, m, d] = iso.split('-').map(Number);
  return new Date(a, m - 1, d).toLocaleDateString('pt-BR', { weekday: 'short', day: '2-digit', month: '2-digit', year: 'numeric' });
}

async function carregarPalavras() {
  $('palavras-lista-tela').hidden = false;
  $('palavra-editor').hidden = true;
  try {
    desenharListaPalavras(await api('GET', '/api/palavras'));
  } catch (err) {
    mensagem($('palavras-resultado'), err.message, false);
  }
}
carregar.palavras = carregarPalavras;

function desenharListaPalavras(lista) {
  $('palavras-lista').replaceChildren(...(lista.length ? lista.map((p) =>
    el('div', { class: 'cartao palavra-item' },
      el('div', { class: 'palavra-item-texto' },
        el('strong', {}, p.titulo || '(sem título)'),
        el('div', { class: 'dica' }, [
          p.data ? dataDaPalavra(p.data) : 'sem data',
          p.serie,
          pode('palavrasTodas') ? p.autorNome : null,
          `${p.trechos} trecho(s)`,
          `${p.versiculos} versículo(s)`,
        ].filter(Boolean).join(' · '))),
      el('span', { class: 'palavra-situacao ' + p.situacao }, SITUACOES_PALAVRA[p.situacao]),
      botao('Abrir', () => abrirPalavra(p.id))))
    : [el('p', { class: 'dica' }, 'Nenhuma Palavra ainda. Toque em "+ Nova Palavra" para começar.')]));
}

async function abrirPalavra(id) {
  $('palavra-erro').hidden = true;
  try {
    palavraAtual = id ? await api('GET', '/api/palavras/' + id)
      : { titulo: '', data: '', serie: '', minutos: 40, texto: '', decisoes: {}, versoes: [], trechos: [], pronta: false };
  } catch (err) {
    mensagem($('palavras-resultado'), err.message, false);
    return;
  }
  decisoesPalavra = { ...palavraAtual.decisoes };
  $('palavra-campo-titulo').value = palavraAtual.titulo;
  $('palavra-campo-data').value = palavraAtual.data;
  $('palavra-campo-serie').value = palavraAtual.serie;
  $('palavra-campo-minutos').value = palavraAtual.minutos;
  $('palavra-texto').value = palavraAtual.texto;
  $('palavra-titulo-tela').textContent = id ? palavraAtual.titulo || 'Palavra' : 'Nova Palavra';
  $('palavra-excluir').hidden = !id;
  marcarPalavraAlterada(false);
  desenharAnalisePalavra(palavraAtual.trechos);
  desenharVersoesPalavra();
  $('palavras-lista-tela').hidden = true;
  $('palavra-editor').hidden = false;
  $('palavra-campo-titulo').focus();
}

function marcarPalavraAlterada(alterada = true) {
  palavraAlterada = alterada;
  const situacao = palavraAtual && palavraAtual.id ? SITUACOES_PALAVRA[palavraAtual.situacao] : 'Nova';
  $('palavra-salvo').textContent = alterada ? 'Alterações não salvas' : situacao;
  $('palavra-pronta').textContent = palavraAtual && palavraAtual.pronta ? 'Voltar para rascunho' : 'Marcar como pronta';
}

/** Pede ao servidor os trechos e versículos do texto atual (o mesmo cálculo que o tablet usa). */
function agendarAnalisePalavra(espera = 600) {
  clearTimeout(analiseAgendada);
  analiseAgendada = setTimeout(async () => {
    try {
      const r = await api('POST', '/api/palavras/analisar', { texto: $('palavra-texto').value, decisoes: decisoesPalavra });
      desenharAnalisePalavra(r.trechos);
    } catch (err) {
      mensagem($('palavra-contagem'), err.message, false);
    }
  }, espera);
}

const ROTULO_STATUS = { pendente: 'Conferir', confirmada: 'Confirmado', ignorada: 'Ignorado', incompleta: 'Incompleto' };

function desenharAnalisePalavra(trechos) {
  trechosPalavra = trechos;
  const refs = trechos.flatMap((t) => t.referencias);
  $('palavra-contagem').textContent = `${trechos.length} trecho(s) · ${refs.filter((r) => r.status !== 'ignorada' && r.ref).length} versículo(s)`;

  // Trechos numerados como vão para a TV do palco, com os versículos destacados.
  let topico = null;
  const blocos = [];
  for (const t of trechos) {
    if (t.topico && t.topico !== topico) blocos.push(el('h3', { class: 'palavra-topico' }, t.topico));
    topico = t.topico;
    const partes = [];
    let pos = 0;
    for (const r of t.referencias) {
      partes.push(t.texto.slice(pos, r.inicio));
      partes.push(el('mark', { class: 'palavra-ref ' + r.status, title: r.nome || 'Referência incompleta' }, t.texto.slice(r.inicio, r.fim)));
      pos = r.fim;
    }
    partes.push(t.texto.slice(pos));
    blocos.push(el('div', { class: 'palavra-trecho' }, el('span', { class: 'palavra-num' }, String(t.numero)), el('p', {}, partes)));
  }
  $('palavra-trechos').replaceChildren(...(blocos.length ? blocos
    : [el('p', { class: 'dica' }, 'Escreva ou cole o texto: cada parágrafo vira um trecho.')]));

  // Uma linha por referência (a mesma escrita em vários trechos aparece uma vez só).
  const vistas = new Map();
  for (const r of refs) if (!vistas.has(r.original)) vistas.set(r.original, r);
  $('palavra-versiculos').replaceChildren(...(vistas.size ? [...vistas.values()].map(linhaVersiculo)
    : [el('p', { class: 'dica' }, 'Nenhum versículo achado. Escreva as referências no texto, como "Jo 3.16" ou "1 Coríntios 13:4-7".')]));
}

function decidir(original, status, ajuste) {
  if (status) decisoesPalavra[original] = ajuste ? { status, ajuste } : { status };
  else delete decisoesPalavra[original];
  marcarPalavraAlterada();
  agendarAnalisePalavra(0);
}

function linhaVersiculo(r) {
  const acoes = [];
  if (r.status === 'pendente') {
    acoes.push(botao('Confirmar', () => decidir(r.original, 'confirmada'), 'pequeno'));
    acoes.push(botao('Ajustar', () => abrirAjuste(linha, r)));
    acoes.push(botao('Ignorar', () => decidir(r.original, 'ignorada')));
  } else if (r.status === 'incompleta') {
    acoes.push(botao('Ajustar', () => abrirAjuste(linha, r), 'pequeno'));
    acoes.push(botao('Ignorar', () => decidir(r.original, 'ignorada')));
  } else {
    acoes.push(botao('Desfazer', () => decidir(r.original, null)));
  }
  const linha = el('div', { class: 'palavra-versiculo ' + r.status },
    el('div', { class: 'palavra-versiculo-texto' },
      el('strong', {}, r.nome || r.original),
      el('div', { class: 'dica' }, [
        ROTULO_STATUS[r.status],
        r.nome && r.nome !== r.original ? `escrito "${r.original}"` : null,
        r.status === 'incompleta' ? 'falta o versículo' : null,
      ].filter(Boolean).join(' · '))),
    el('div', { class: 'palavra-versiculo-acoes' }, acoes));
  return linha;
}

/** Campo para digitar a referência certa no lugar da achada. */
function abrirAjuste(linha, r) {
  const campo = el('input', { type: 'text', value: r.ref || r.original, 'aria-label': 'Referência certa, ex.: Jo 3.16' });
  const erro = el('p', { class: 'erro', hidden: true });
  const confirmar = () => {
    if (!/\d+\s*[.:]\s*\d+/.test(campo.value)) {
      erro.textContent = 'Escreva livro, capítulo e versículo, como "Sl 23.1-6".';
      erro.hidden = false;
      return;
    }
    decidir(r.original, 'confirmada', campo.value.trim());
  };
  campo.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); confirmar(); } });
  linha.querySelector('.palavra-versiculo-acoes').replaceChildren(campo, botao('OK', confirmar, 'pequeno'), botao('Cancelar', () => desenharAnalisePalavra(trechosPalavra)));
  linha.append(erro);
  campo.focus();
  campo.select();
}

function desenharVersoesPalavra() {
  const versoes = palavraAtual.versoes || [];
  $('palavra-versoes').replaceChildren(...(versoes.length ? versoes.map((v) =>
    el('div', { class: 'palavra-versao' },
      el('span', {}, `${dataCurta(v.em)}${v.por ? ' · ' + v.por : ''}`),
      botao('Restaurar', () => {
        if (palavraAlterada && !confirm('Trocar o texto atual, que tem alterações não salvas, por esta versão?')) return;
        $('palavra-campo-titulo').value = v.titulo;
        $('palavra-texto').value = v.texto;
        marcarPalavraAlterada();
        agendarAnalisePalavra(0);
      })))
    : [el('p', { class: 'dica' }, 'Cada vez que você salva, o texto anterior fica guardado aqui.')]));
}

/** O que falta para ficar pronta (a mesma regra do servidor). */
function pendenciasPalavra() {
  const refs = trechosPalavra.flatMap((t) => t.referencias);
  return [
    $('palavra-campo-titulo').value.trim() ? null : 'Falta o título.',
    trechosPalavra.length ? null : 'O texto está vazio.',
    $('palavra-campo-data').value ? null : 'Falta a data do culto.',
    refs.some((r) => r.status === 'pendente') ? 'Há versículos para conferir.' : null,
    refs.some((r) => r.status === 'incompleta') ? 'Há referências incompletas para ajustar ou ignorar.' : null,
  ].filter(Boolean);
}

async function salvarPalavra(pronta) {
  const erro = $('palavra-erro');
  erro.hidden = true;
  clearTimeout(analiseAgendada);
  const corpo = {
    titulo: $('palavra-campo-titulo').value.trim(),
    data: $('palavra-campo-data').value,
    serie: $('palavra-campo-serie').value.trim(),
    minutos: Number($('palavra-campo-minutos').value) || 40,
    texto: $('palavra-texto').value,
    decisoes: decisoesPalavra,
    pronta,
  };
  try {
    palavraAtual = palavraAtual.id
      ? await api('PUT', '/api/palavras/' + palavraAtual.id, corpo)
      : await api('POST', '/api/palavras', corpo);
    decisoesPalavra = { ...palavraAtual.decisoes };
    $('palavra-titulo-tela').textContent = palavraAtual.titulo || 'Palavra';
    $('palavra-excluir').hidden = false;
    marcarPalavraAlterada(false);
    desenharAnalisePalavra(palavraAtual.trechos);
    desenharVersoesPalavra();
  } catch (err) {
    erro.textContent = err.message;
    erro.hidden = false;
  }
}

$('palavra-nova').addEventListener('click', () => abrirPalavra(null));
$('palavra-voltar').addEventListener('click', () => {
  if (palavraAlterada && !confirm('Sair sem salvar as alterações?')) return;
  carregarPalavras();
});
$('palavra-salvar').addEventListener('click', async () => {
  // Uma Palavra pronta que ganhou pendências volta para rascunho ao salvar (e o aviso diz por quê).
  const eraPronta = !!palavraAtual.pronta;
  const falta = pendenciasPalavra();
  await salvarPalavra(eraPronta && !falta.length);
  if (eraPronta && falta.length && $('palavra-erro').hidden) {
    mensagem($('palavra-salvo'), 'Salvo como rascunho: ' + falta.join(' '), false);
  }
});
$('palavra-pronta').addEventListener('click', () => {
  if (palavraAtual.pronta) return salvarPalavra(false);
  const falta = pendenciasPalavra();
  if (falta.length) {
    $('palavra-erro').textContent = 'Ainda não pode ficar pronta: ' + falta.join(' ');
    $('palavra-erro').hidden = false;
    return;
  }
  return salvarPalavra(true);
});
$('palavra-excluir').addEventListener('click', async () => {
  if (!palavraAtual.id || !confirm(`Excluir a Palavra "${palavraAtual.titulo}" e as versões guardadas?`)) return;
  try {
    await api('DELETE', '/api/palavras/' + palavraAtual.id);
    palavraAlterada = false;
    carregarPalavras();
  } catch (err) {
    $('palavra-erro').textContent = err.message;
    $('palavra-erro').hidden = false;
  }
});

for (const id of ['palavra-campo-titulo', 'palavra-campo-data', 'palavra-campo-serie', 'palavra-campo-minutos']) {
  $(id).addEventListener('input', () => marcarPalavraAlterada());
}
$('palavra-texto').addEventListener('input', () => {
  marcarPalavraAlterada();
  agendarAnalisePalavra();
});

$('palavra-topico').addEventListener('click', () => {
  const t = $('palavra-texto');
  const antes = t.value.slice(0, t.selectionStart).replace(/\s*$/, '');
  const depois = t.value.slice(t.selectionEnd).replace(/^\s*/, '');
  const marca = '# Novo tópico';
  t.value = (antes ? antes + '\n\n' : '') + marca + '\n' + depois;
  const inicio = (antes ? antes.length + 2 : 0) + 2;
  t.focus();
  t.setSelectionRange(inicio, inicio + marca.length - 2);
  marcarPalavraAlterada();
  agendarAnalisePalavra();
});

$('palavra-arquivo').addEventListener('change', async (e) => {
  const arquivo = e.target.files[0];
  e.target.value = '';
  if (!arquivo) return;
  const erro = $('palavra-erro');
  erro.hidden = true;
  if ($('palavra-texto').value.trim() && !confirm(`Trocar o texto atual pelo de "${arquivo.name}"?`)) return;
  try {
    const r = await api('POST', '/api/palavras/importar?nome=' + encodeURIComponent(arquivo.name),
      await arquivo.arrayBuffer(), { bruto: true, tipo: 'application/octet-stream' });
    $('palavra-texto').value = r.texto;
    if (!$('palavra-campo-titulo').value.trim()) $('palavra-campo-titulo').value = arquivo.name.replace(/\.[^.]+$/, '');
    marcarPalavraAlterada();
    agendarAnalisePalavra(0);
  } catch (err) {
    erro.textContent = err.message;
    erro.hidden = false;
  }
});
