'use strict';

// ---------- Utilitários ----------

let token = localStorage.getItem('diako_token');

async function api(metodo, caminho, corpo, { bruto = false, tipo } = {}) {
  const headers = { Authorization: 'Bearer ' + token };
  let body;
  if (bruto) {
    body = corpo;
    if (tipo) headers['Content-Type'] = tipo;
  } else if (corpo !== undefined) {
    body = typeof corpo === 'string' ? corpo : JSON.stringify(corpo);
    headers['Content-Type'] = typeof corpo === 'string' ? 'text/plain; charset=utf-8' : 'application/json';
  }
  const r = await fetch(caminho, { method: metodo, headers, body });
  if (r.status === 401) {
    sair();
    throw new Error('Sessão expirada. Entre novamente.');
  }
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j.erro || 'Erro ' + r.status);
  return j;
}

/** Cria elementos sem innerHTML (o conteúdo vem de usuários). */
function el(tag, props = {}, ...filhos) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (v === undefined || v === null || v === false) continue;
    if (k === 'class') e.className = v;
    else if (k === 'style') e.style.cssText = v;
    else if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
    else e.setAttribute(k, v === true ? '' : v);
  }
  for (const f of filhos.flat()) if (f !== null && f !== undefined && f !== false) e.append(f);
  return e;
}

const $ = (id) => document.getElementById(id);
const botao = (texto, onclick, classe = 'secundario pequeno') => el('button', { class: 'botao ' + classe, type: 'button', onclick }, texto);

function mensagem(alvo, texto, ok = true) {
  alvo.textContent = texto;
  alvo.className = ok ? 'sucesso' : 'erro';
}

function dataCurta(iso) {
  const d = new Date(iso);
  return d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' }) + ' ' +
    d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
}

const CATEGORIAS = { aviso: ['Aviso', '#42A5F5'], evento: ['Evento', '#66BB6A'], aniversario: ['Aniversário', '#FFA726'] };
const TIPOS = { saude: 'Saúde', familia: 'Família', trabalho: 'Trabalho', gratidao: 'Gratidão', outro: 'Outro' };
const ORIGENS = { site: 'pelo site', app: 'pelo tablet', painel: 'pelo painel' };

/** Abre um <dialog>; [salvar] devolve uma mensagem de erro ou nada. */
function abrirDialogo(dialogo, erroEl, salvar) {
  erroEl.hidden = true;
  const form = dialogo.querySelector('form');
  form.onsubmit = async (e) => {
    if (e.submitter && e.submitter.value === 'cancelar') return;
    e.preventDefault();
    try {
      await salvar();
      dialogo.close();
    } catch (err) {
      erroEl.textContent = err.message;
      erroEl.hidden = false;
    }
  };
  dialogo.showModal();
}

// ---------- Login ----------

function sair() {
  if (token) fetch('/api/logout', { method: 'POST', headers: { Authorization: 'Bearer ' + token } }).catch(() => {});
  token = null;
  localStorage.removeItem('diako_token');
  $('app').hidden = true;
  $('login').hidden = false;
  $('senha').focus();
}

$('form-login').addEventListener('submit', async (e) => {
  e.preventDefault();
  const erro = $('erro-login');
  erro.hidden = true;
  const r = await fetch('/api/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ senha: $('senha').value }),
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) {
    erro.textContent = j.erro || 'Não foi possível entrar.';
    erro.hidden = false;
    return;
  }
  token = j.token;
  localStorage.setItem('diako_token', token);
  $('senha').value = '';
  iniciar();
});

$('sair').addEventListener('click', sair);

// ---------- Abas ----------

let abaAtual = 'motivos';
document.querySelectorAll('nav.abas button').forEach((b) =>
  b.addEventListener('click', () => mostrarAba(b.dataset.aba)));

function mostrarAba(nome) {
  abaAtual = nome;
  document.querySelectorAll('nav.abas button').forEach((b) => b.setAttribute('aria-selected', String(b.dataset.aba === nome)));
  document.querySelectorAll('[data-painel]').forEach((s) => (s.hidden = s.dataset.painel !== nome));
  carregar[nome]();
}

const carregar = {
  motivos: carregarMotivos,
  recados: carregarRecados,
  cartazes: carregarCartazes,
  membros: carregarMembros,
  resumo: carregarResumo,
  historico: carregarHistorico,
  status: carregarStatus,
};

// ---------- Motivos ----------

let motivos = [];

async function carregarMotivos() {
  motivos = await api('GET', '/api/motivos');
  atualizarBadge();
  const filtro = document.querySelector('input[name=filtro-motivo]:checked').value;
  $('projetar-respondidas').hidden = filtro !== 'atendido';
  const data = (m) => (filtro === 'atendido' && m.atendidoEm) || m.criadoEm;
  const lista = motivos.filter((m) => m.status === filtro).sort((a, b) => data(b).localeCompare(data(a)));
  const vazio = { aguardando: 'Nenhum pedido aguardando aprovação.', pendente: 'A lista de oração está vazia.', atendido: 'Nenhuma oração marcada como atendida.' };
  $('lista-motivos').replaceChildren(
    ...(lista.length ? lista.map(itemMotivo) : [el('p', { class: 'vazio' }, vazio[filtro])]));
}

function itemMotivo(m) {
  const detalhes = [TIPOS[m.tipo], ORIGENS[m.origem], dataCurta(m.criadoEm), m.enviadoPor && 'enviado por ' + m.enviadoPor,
    m.atendidoEm && 'atendido em ' + dataCurta(m.atendidoEm)]
    .filter(Boolean).join(' · ');
  const acoes = [];
  if (m.status === 'aguardando') {
    acoes.push(botao('Aprovar', () => api('POST', `/api/motivos/${m.id}/aprovar`).then(carregarMotivos), 'pequeno'));
    acoes.push(botao('Recusar', () => confirm('Recusar e apagar este pedido?') && api('DELETE', '/api/motivos/' + m.id).then(carregarMotivos), 'perigo pequeno'));
  } else if (m.status === 'pendente') {
    acoes.push(botao('Atendido', () => api('PUT', '/api/motivos/' + m.id, { status: 'atendido' }).then(carregarMotivos)));
  } else {
    acoes.push(botao('Voltar para a lista', () => api('PUT', '/api/motivos/' + m.id, { status: 'pendente' }).then(carregarMotivos)));
  }
  acoes.push(botao('Editar', () => editarMotivo(m)));
  if (m.status !== 'aguardando') {
    acoes.push(botao('Excluir', () => confirm('Excluir este motivo?') && api('DELETE', '/api/motivos/' + m.id).then(carregarMotivos), 'perigo pequeno'));
  }
  return el('div', { class: 'item' },
    el('div', { class: 'conteudo' },
      el('div', { class: 'titulo' }, m.para || m.motivo,
        m.publico ? null : el('span', { class: 'etiqueta', title: 'Não vai para o telão' }, 'Particular')),
      m.para ? el('div', { class: 'sub' }, m.motivo) : null,
      m.testemunho ? el('div', { class: 'sub', style: 'font-style:italic' }, '“' + m.testemunho + '”') : null,
      el('div', { class: 'sub' }, detalhes)),
    el('div', { class: 'acoes' }, acoes));
}

function editarMotivo(m) {
  $('titulo-motivo').textContent = m ? 'Editar motivo' : 'Novo motivo de oração';
  $('m-para').value = m ? m.para : '';
  $('m-motivo').value = m ? m.motivo : '';
  $('m-tipo').value = m ? m.tipo : 'outro';
  $('m-publico').checked = m ? m.publico : true;
  $('m-testemunho').value = m ? m.testemunho || '' : '';
  $('campo-testemunho').hidden = !(m && m.status === 'atendido');
  abrirDialogo($('dlg-motivo'), $('erro-motivo'), async () => {
    const dados = { para: $('m-para').value.trim(), motivo: $('m-motivo').value.trim(), tipo: $('m-tipo').value, publico: $('m-publico').checked };
    if (m && m.status === 'atendido') dados.testemunho = $('m-testemunho').value.trim();
    if (m) await api('PUT', '/api/motivos/' + m.id, dados);
    else await api('POST', '/api/motivos', { ...dados, origem: 'painel' });
    await carregarMotivos();
  });
}

$('novo-motivo').addEventListener('click', () => editarMotivo(null));

$('projetar-respondidas').addEventListener('click', async () => {
  const saida = $('resultado-motivos');
  try {
    const r = await api('POST', '/api/projetar/oracoes-respondidas', {});
    mensagem(saida, r.status === 'ok' ? 'Orações respondidas no telão.' : r.error, r.status === 'ok');
  } catch (err) {
    mensagem(saida, err.message, false);
  }
});

// ---------- Resumo da semana ----------

async function carregarResumo() {
  const r = await api('GET', '/api/resumo-semanal');
  $('texto-resumo').value = r.texto;
  atualizarPreviaResumo();
}

/** Mostra *negrito* e _itálico_ como no WhatsApp (só para visualizar). */
function atualizarPreviaResumo() {
  const texto = $('texto-resumo').value;
  const previa = $('previa-resumo');
  previa.replaceChildren();
  const partes = texto.split(/(\*[^*\n]+\*|_[^_\n]+_)/g);
  for (const p of partes) {
    if (/^\*[^*\n]+\*$/.test(p)) previa.append(el('strong', {}, p.slice(1, -1)));
    else if (/^_[^_\n]+_$/.test(p)) previa.append(el('em', {}, p.slice(1, -1)));
    else previa.append(p);
  }
  $('whatsapp-resumo').href = 'https://wa.me/?text=' + encodeURIComponent(texto);
}

$('texto-resumo').addEventListener('input', atualizarPreviaResumo);
$('atualizar-resumo').addEventListener('click', carregarResumo);
$('copiar-resumo').addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText($('texto-resumo').value);
    mensagem($('resultado-resumo'), 'Copiado! Cole no grupo do WhatsApp.');
  } catch {
    // Sem permissão de área de transferência (ex: http): seleciona para Ctrl+C.
    $('texto-resumo').select();
    mensagem($('resultado-resumo'), 'Texto selecionado: use Ctrl+C para copiar.');
  }
});

// ---------- Histórico ----------

const ACOES = {
  ShowQuickPresentation: 'Texto',
  ShowImage: 'Imagem',
  ShowCountdown: 'Contagem',
  StartCountdownCP: 'Palco',
  SetTextCP: 'Palco',
};

async function carregarHistorico() {
  const lista = await api('GET', '/api/historico?limite=300');
  $('lista-historico').replaceChildren(
    ...(lista.length
      ? lista.map((h) => el('div', { class: 'item' },
          el('div', { class: 'conteudo' },
            el('div', { class: 'titulo' }, h.descricao, el('span', { class: 'etiqueta' }, ACOES[h.acao] || h.acao)),
            el('div', { class: 'sub' }, new Date(h.quando).toLocaleString('pt-BR', { weekday: 'short', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })))))
      : [el('p', { class: 'vazio' }, 'Nada projetado ainda.')]));
}
document.querySelectorAll('input[name=filtro-motivo]').forEach((r) => r.addEventListener('change', carregarMotivos));

function atualizarBadge() {
  const n = motivos.filter((m) => m.status === 'aguardando').length;
  $('badge').textContent = n;
  $('badge').hidden = n === 0;
}

// ---------- Recados ----------

let recados = [];
let cartazes = [];

async function carregarRecados() {
  [recados, cartazes] = await Promise.all([api('GET', '/api/recados'), api('GET', '/api/cartazes')]);
  const hoje = new Date().toISOString().slice(0, 10);
  const ordenados = [...recados].sort((a, b) => (b.fixo - a.fixo) || (a.ordem - b.ordem));
  const editaveis = ordenados.filter((r) => !r.auto);
  $('lista-recados').replaceChildren(
    ...(ordenados.length ? ordenados.map((r) => itemRecado(r, editaveis, hoje)) : [el('p', { class: 'vazio' }, 'Nenhum recado ainda.')]));
}

function itemRecado(r, editaveis, hoje) {
  const [rotulo, cor] = CATEGORIAS[r.categoria] || CATEGORIAS.aviso;
  const expirado = r.validoAte && r.validoAte.slice(0, 10) < hoje;
  const sub = [r.imagemHolyrics ? 'Cartaz: ' + r.imagemHolyrics : r.texto, r.validoAte && 'até ' + new Date(r.validoAte).toLocaleDateString('pt-BR')]
    .filter(Boolean).join('\n');
  const i = editaveis.indexOf(r);
  const acoes = r.auto
    ? [el('span', { class: 'dica' }, 'Automático — edite na aba Aniversariantes')]
    : [
        botao('↑', () => mover(editaveis, i, -1), 'secundario pequeno'),
        botao('↓', () => mover(editaveis, i, 1), 'secundario pequeno'),
        botao('Editar', () => editarRecado(r)),
        botao('Excluir', () => confirm(`Excluir "${r.titulo}"?`) && api('DELETE', '/api/recados/' + r.id).then(carregarRecados), 'perigo pequeno'),
      ];
  if (!r.auto) {
    acoes[0].setAttribute('aria-label', 'Subir ' + r.titulo);
    acoes[1].setAttribute('aria-label', 'Descer ' + r.titulo);
    acoes[0].disabled = i === 0;
    acoes[1].disabled = i === editaveis.length - 1;
  }
  return el('div', { class: 'item', style: expirado ? 'opacity:.6' : '' },
    el('div', { class: 'faixa', style: 'background:' + cor }),
    el('div', { class: 'conteudo' },
      el('div', { class: 'titulo' }, r.titulo,
        el('span', { class: 'etiqueta' }, rotulo),
        r.fixo ? el('span', { class: 'etiqueta' }, 'Fixo') : null,
        expirado ? el('span', { class: 'etiqueta' }, 'Expirado') : null),
      sub ? el('div', { class: 'sub' }, sub) : null),
    el('div', { class: 'acoes' }, acoes));
}

async function mover(lista, i, delta) {
  const j = i + delta;
  if (j < 0 || j >= lista.length) return;
  const ids = lista.map((r) => r.id);
  [ids[i], ids[j]] = [ids[j], ids[i]];
  await api('PUT', '/api/recados/ordem', ids);
  await carregarRecados();
}

function editarRecado(r) {
  $('titulo-recado').textContent = r ? 'Editar recado' : 'Novo recado';
  $('r-titulo').value = r ? r.titulo : '';
  $('r-texto').value = r ? r.texto : '';
  $('r-categoria').value = r ? r.categoria : 'aviso';
  $('r-validade').value = r && r.validoAte ? r.validoAte.slice(0, 10) : '';
  $('r-fixo').checked = r ? r.fixo : false;
  $('r-imagem').replaceChildren(
    el('option', { value: '' }, '(nenhum — projetar o texto)'),
    ...cartazes.map((c) => el('option', { value: c.holyrics }, c.nome)));
  $('r-imagem').value = r && r.imagemHolyrics ? r.imagemHolyrics : '';
  abrirDialogo($('dlg-recado'), $('erro-recado'), async () => {
    const dados = {
      titulo: $('r-titulo').value.trim(),
      texto: $('r-texto').value.trim(),
      categoria: $('r-categoria').value,
      validoAte: $('r-validade').value ? $('r-validade').value + 'T00:00:00.000' : null,
      imagemHolyrics: $('r-imagem').value || null,
      fixo: $('r-fixo').checked,
    };
    if (r) await api('PUT', '/api/recados/' + r.id, dados);
    else await api('POST', '/api/recados', dados);
    await carregarRecados();
  });
}

$('novo-recado').addEventListener('click', async () => {
  cartazes = await api('GET', '/api/cartazes');
  editarRecado(null);
});

// ---------- Cartazes ----------

async function carregarCartazes() {
  const lista = await api('GET', '/api/cartazes');
  $('lista-cartazes').replaceChildren(
    ...(lista.length
      ? lista.map((c) => el('div', { class: 'cartaz' },
          el('img', { src: c.url, alt: c.nome, loading: 'lazy' }),
          el('div', {},
            el('code', {}, c.holyrics),
            botao('Excluir', () => confirm(`Excluir ${c.nome}?`) && api('DELETE', '/api/cartazes/' + encodeURIComponent(c.nome)).then(carregarCartazes), 'perigo pequeno'))))
      : [el('p', { class: 'vazio' }, 'Nenhum cartaz enviado.')]));
}

$('arquivo-cartaz').addEventListener('change', async (e) => {
  const aviso = $('aviso-cartazes');
  aviso.hidden = false;
  const arquivos = [...e.target.files];
  const erros = [];
  for (const [i, f] of arquivos.entries()) {
    aviso.textContent = `Enviando ${i + 1} de ${arquivos.length}…`;
    try {
      await api('POST', '/api/cartazes?nome=' + encodeURIComponent(f.name), f, { bruto: true, tipo: f.type || 'application/octet-stream' });
    } catch (err) {
      erros.push(`${f.name}: ${err.message}`);
    }
  }
  aviso.textContent = erros.length ? erros.join(' · ') : `${arquivos.length} imagem(ns) enviada(s).`;
  e.target.value = '';
  carregarCartazes();
});

// ---------- Membros ----------

async function carregarMembros() {
  const lista = (await api('GET', '/api/membros')).sort((a, b) => (a.mes - b.mes) || (a.dia - b.dia));
  $('lista-membros').replaceChildren(
    ...(lista.length
      ? lista.map((m) => el('div', { class: 'item', style: m.ativo ? '' : 'opacity:.6' },
          el('div', { class: 'conteudo' },
            el('div', { class: 'titulo' }, m.nome, m.ativo ? null : el('span', { class: 'etiqueta' }, 'Inativo')),
            el('div', { class: 'sub' }, String(m.dia).padStart(2, '0') + '/' + String(m.mes).padStart(2, '0'))),
          el('div', { class: 'acoes' },
            botao('Editar', () => editarMembro(m)),
            botao('Excluir', () => confirm(`Excluir ${m.nome}?`) && api('DELETE', '/api/membros/' + m.id).then(carregarMembros), 'perigo pequeno'))))
      : [el('p', { class: 'vazio' }, 'Nenhum membro cadastrado.')]));
}

function editarMembro(m) {
  $('titulo-membro').textContent = m ? 'Editar membro' : 'Novo membro';
  $('b-nome').value = m ? m.nome : '';
  $('b-dia').value = m ? m.dia : '';
  $('b-mes').value = m ? m.mes : '';
  $('b-ativo').checked = m ? m.ativo : true;
  abrirDialogo($('dlg-membro'), $('erro-membro'), async () => {
    const dados = { nome: $('b-nome').value.trim(), dia: Number($('b-dia').value), mes: Number($('b-mes').value), ativo: $('b-ativo').checked };
    if (m) await api('PUT', '/api/membros/' + m.id, dados);
    else await api('POST', '/api/membros', dados);
    await carregarMembros();
  });
}

$('novo-membro').addEventListener('click', () => editarMembro(null));

$('importar').addEventListener('click', async () => {
  const saida = $('resultado-importacao');
  try {
    const r = await api('POST', '/api/membros/importar', $('csv').value);
    let texto = `${r.importados} membro(s) importado(s).`;
    if (r.linhasComErro.length) texto += ` Linhas com erro: ${r.linhasComErro.join(', ')}.`;
    mensagem(saida, texto, r.linhasComErro.length === 0);
    if (r.importados) $('csv').value = '';
    carregarMembros();
  } catch (err) {
    mensagem(saida, err.message, false);
  }
});

// ---------- Status ----------

let estado = {};

async function carregarStatus() {
  estado = await api('GET', '/api/estado');
  const linha = (rotulo, valor, ok) => el('div', { class: 'status-linha' },
    el('span', {}, rotulo),
    el('strong', {}, ok === undefined ? null : el('span', { class: 'ponto', style: 'background:' + (ok ? '#1e7d3a' : '#b3261e') }), valor));
  $('status-linhas').replaceChildren(
    linha('Holyrics', estado.holyricsConectado ? 'Conectado' : 'Sem conexão', estado.holyricsConectado),
    linha('Cartazes no Holyrics', estado.cartazesNoHolyrics ? 'Sim' : 'Não configurado', estado.cartazesNoHolyrics),
    linha('Backup', estado.backupConfigurado ? (estado.ultimoBackup ? 'Último: ' + dataCurta(estado.ultimoBackup) : 'Ainda não feito') : 'Desativado', estado.backupConfigurado),
    linha('Pedidos aguardando', String(estado.aguardandoAprovacao)));
  $('link-oracao').textContent = estado.urlOracao;
  $('link-oracao').href = estado.urlOracao;
  const urlMural = estado.urlOracao.replace(/\/oracao$/, '/mural');
  $('link-mural').textContent = urlMural;
  $('link-mural').href = urlMural;
  $('backup-agora').disabled = !estado.backupConfigurado;
}

$('backup-agora').addEventListener('click', async () => {
  try {
    const r = await api('POST', '/api/backup');
    mensagem($('resultado-status'), 'Backup gravado em ' + r.arquivo);
    carregarStatus();
  } catch (err) {
    mensagem($('resultado-status'), err.message, false);
  }
});

$('projetar-qr').addEventListener('click', async () => {
  const r = await api('POST', '/api/holyrics/ShowImage', { file: estado.qrHolyrics });
  mensagem($('resultado-status'), r.status === 'ok' ? 'QR code no telão.' : r.error, r.status === 'ok');
});

// ---------- Tempo real ----------

let ws;
function conectarTempoReal() {
  if (!token) return;
  ws = new WebSocket(`${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/ws?token=${encodeURIComponent(token)}`);
  ws.onopen = () => ($('conexao').textContent = '● ao vivo');
  ws.onmessage = (e) => {
    const { tipo } = JSON.parse(e.data);
    if (tipo === 'motivos') carregarMotivos();
    else if (tipo === abaAtual || (tipo === 'membros' && abaAtual === 'recados')) carregar[abaAtual]();
  };
  ws.onclose = () => {
    $('conexao').textContent = 'reconectando…';
    if (token) setTimeout(conectarTempoReal, 3000);
  };
}

// ---------- Início ----------

function iniciar() {
  $('login').hidden = true;
  $('app').hidden = false;
  mostrarAba(abaAtual);
  if (abaAtual !== 'motivos') carregarMotivos();
  conectarTempoReal();
}

if (token) iniciar();
else sair();
