'use strict';

// Utilitários (api, el, $, botao, mensagem, abrirDialogo...) ficam em comum.js.

const CATEGORIAS = { aviso: ['Aviso', '#42A5F5'], evento: ['Evento', '#66BB6A'], aniversario: ['Aniversário', '#FFA726'] };
const TIPOS = { saude: 'Saúde', familia: 'Família', trabalho: 'Trabalho', gratidao: 'Gratidão', outro: 'Outro' };
const ORIGENS = { site: 'pelo site', app: 'pelo tablet', painel: 'pelo painel' };

// ---------- Login ----------

function sair() {
  if (token) fetch('/api/logout', { method: 'POST', headers: { Authorization: 'Bearer ' + token } }).catch(() => {});
  token = null;
  eu = null;
  localStorage.removeItem('diako_token');
  $('app').hidden = true;
  $('login').hidden = false;
  ($('usuario').value ? $('senha') : $('usuario')).focus();
}

// ---------- Quem está logado e o que pode (perfis) ----------

/** Resposta de /api/eu: nome, perfil e permissões. */
let eu = null;
const pode = (permissao) => !!eu && eu.permissoes.includes(permissao);

/** Esconde abas, botões e cartões marcados com data-permissao que o perfil não tem. */
function aplicarPermissoes() {
  document.querySelectorAll('[data-permissao]').forEach((e) => e.classList.toggle('sem-permissao', !pode(e.dataset.permissao)));
  $('quem').textContent = eu.nome + ' · ' + eu.perfilNome;
}

$('minha-senha').addEventListener('click', () => {
  for (const id of ['senha-atual', 'senha-nova', 'senha-confirma']) $(id).value = '';
  abrirDialogo($('dlg-senha'), $('erro-senha'), async () => {
    if ($('senha-nova').value !== $('senha-confirma').value) throw new Error('As duas senhas novas não são iguais.');
    const r = await api('POST', '/api/eu/senha', { atual: $('senha-atual').value, nova: $('senha-nova').value });
    $('conexao').textContent = r.sessoesEncerradas ? 'Senha trocada. Outros aparelhos saíram.' : 'Senha trocada.';
  });
});

$('form-login').addEventListener('submit', async (e) => {
  e.preventDefault();
  const erro = $('erro-login');
  erro.hidden = true;
  const r = await fetch('/api/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ usuario: $('usuario').value.trim(), senha: $('senha').value }),
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

let abaAtual = 'inicio';
document.querySelectorAll('nav.abas button').forEach((b) =>
  b.addEventListener('click', () => mostrarAba(b.dataset.aba)));

function mostrarAba(nome) {
  const botaoAba = document.querySelector(`nav.abas button[data-aba="${nome}"]`);
  if (!botaoAba || botaoAba.classList.contains('sem-permissao')) nome = 'inicio';
  abaAtual = nome;
  document.querySelectorAll('nav.abas button').forEach((b) => b.setAttribute('aria-selected', String(b.dataset.aba === nome)));
  document.querySelectorAll('[data-painel]').forEach((s) => (s.hidden = s.dataset.painel !== nome));
  carregar[nome]();
}

const carregar = {
  inicio: carregarInicio,
  motivos: carregarMotivos,
  mensagens: carregarMensagens,
  recados: carregarRecados,
  agenda: carregarAgenda,
  cartazes: carregarCartazes,
  galeria: carregarGaleria,
  membros: carregarMembros,
  resumo: carregarResumo,
  historico: carregarHistorico,
  status: carregarStatus,
};

// ---------- Início (resumo de tudo) ----------

document.querySelectorAll('[data-ir]').forEach((b) => b.addEventListener('click', () => mostrarAba(b.dataset.ir)));

/** Dia local no formato AAAA-MM-DD. */
const diaIso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const ddmm = (d) => d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });

function indicador(id, valor, detalhe, alerta = false) {
  const b = $(id);
  b.querySelector('strong').textContent = valor;
  b.querySelector('small').textContent = detalhe;
  b.classList.toggle('alerta', alerta);
}

const vazioCk = (texto) => el('p', { class: 'vazio-ck' }, texto);

async function carregarInicio() {
  const agora = new Date();
  const hora = agora.getHours();
  $('saudacao').textContent = hora < 12 ? 'Bom dia!' : hora < 18 ? 'Boa tarde!' : 'Boa noite!';
  $('hoje').textContent = agora.toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' });
  carregarSistemaInicio();

  // Só busca o que o perfil pode ver (os cartões sem permissão já estão escondidos).
  const se = (permissao, caminho, vazio) => (pode(permissao) ? api('GET', caminho) : Promise.resolve(vazio));
  const [listaMotivos, listaMensagens, listaRecados, agenda, membros] = await Promise.all([
    se('motivosVer', '/api/motivos', []), se('mensagens', '/api/mensagens', []), se('recados', '/api/recados', []),
    se('agendaVer', '/api/agenda?dias=7', { configurada: false, eventos: [] }), se('membros', '/api/membros', [])]);
  motivos = listaMotivos;
  mensagensRecebidas = listaMensagens;
  atualizarBadge();
  atualizarBadgeMensagens();

  const hoje = diaIso(agora);
  const daquiUmaSemana = diaIso(new Date(agora.getFullYear(), agora.getMonth(), agora.getDate() + 7));

  // Pedidos
  const aguardando = motivos.filter((m) => m.status === 'aguardando').sort((a, b) => b.criadoEm.localeCompare(a.criadoEm));
  const naLista = motivos.filter((m) => m.status === 'pendente').length;
  indicador('ind-pedidos', aguardando.length, naLista + ' na lista de oração', aguardando.length > 0);
  $('ck-pedidos').replaceChildren(...(aguardando.length
    ? aguardando.slice(0, 3).map((m) => el('div', { class: 'linha-ck' },
        el('div', { class: 'conteudo' },
          el('strong', { class: 'texto' }, m.para || m.motivo),
          el('span', { class: 'sub' }, [TIPOS[m.tipo], dataCurta(m.criadoEm), m.publico ? null : 'particular'].filter(Boolean).join(' · '))),
        pode('motivosEditar') ? botao('Aprovar', () => api('POST', `/api/motivos/${m.id}/aprovar`).then(carregarInicio), 'pequeno') : null))
    : [vazioCk('Nenhum pedido aguardando aprovação.')]));

  // Mensagens
  const novas = mensagensRecebidas.filter((m) => m.status === 'nova').sort((a, b) => b.criadoEm.localeCompare(a.criadoEm));
  const emAnalise = mensagensRecebidas.filter((m) => m.status === 'emAnalise').length;
  indicador('ind-mensagens', novas.length, emAnalise + ' em análise', novas.length > 0);
  $('ck-mensagens').replaceChildren(...(novas.length
    ? novas.slice(0, 3).map((m) => el('div', { class: 'linha-ck' },
        el('div', { class: 'conteudo' },
          el('span', { class: 'rotulo' }, (nomesMensagem[m.tipo] || m.tipo) + ' · ' + dataCurta(m.criadoEm)),
          el('span', { class: 'texto' }, m.texto))))
    : [vazioCk('Nenhuma mensagem nova.')]));

  // Recados
  const ativos = listaRecados
    .filter((r) => !r.validoAte || r.validoAte.slice(0, 10) >= hoje)
    .sort((a, b) => (b.fixo - a.fixo) || (a.ordem - b.ordem));
  const vencendo = ativos.filter((r) => r.validoAte && r.validoAte.slice(0, 10) <= daquiUmaSemana).length;
  indicador('ind-recados', ativos.length,
    vencendo === 0 ? 'nenhum vence esta semana' : vencendo === 1 ? '1 vence esta semana' : vencendo + ' vencem esta semana');
  $('ck-recados').replaceChildren(...(ativos.length
    ? [...ativos.slice(0, 4).map((r) => {
        const vence = r.validoAte && r.validoAte.slice(0, 10) <= daquiUmaSemana;
        return el('div', { class: 'linha-ck' },
          el('div', { class: 'conteudo' },
            el('span', { class: 'texto' }, r.titulo,
              r.fixo ? el('span', { class: 'etiqueta' }, 'Fixo') : null,
              vence ? el('span', { class: 'etiqueta', style: 'color:var(--perigo)' }, 'vence ' + ddmm(new Date(r.validoAte))) : null)));
      }),
      ativos.length > 4 ? el('span', { class: 'dica' }, '+ ' + (ativos.length - 4) + ' recados') : null].filter(Boolean)
    : [vazioCk('Nenhum recado no tablet.')]));

  // Agenda
  $('ck-novo-evento').hidden = !agenda.editavel;
  if (!agenda.configurada) {
    indicador('ind-eventos', '–', 'agenda não configurada');
    $('ck-eventos').replaceChildren(el('p', { class: 'vazio-ck' }, 'Agenda do Google não configurada.',
      pode('admin') ? [' ', el('a', { href: '/admin#agenda' }, 'Configurar em Administração'), '.'] : null));
  } else {
    const eventos = agenda.eventos;
    indicador('ind-eventos', eventos.length, eventos.length ? 'próximo: ' + eventos[0].dia.split(',')[0].toLowerCase() + ', ' + eventos[0].horario : 'nada marcado');
    $('ck-eventos').replaceChildren(...(eventos.length
      ? eventos.slice(0, 4).map((e) => {
          const inicio = new Date(e.inicio);
          return el('div', { class: 'linha-ck' },
            el('span', { class: 'data-ck' + (diaIso(inicio) === hoje ? ' hoje' : '') },
              inicio.toLocaleDateString('pt-BR', { weekday: 'short' }).replace('.', ''),
              el('strong', {}, String(inicio.getDate()))),
            el('div', { class: 'conteudo' },
              el('strong', { class: 'texto' }, e.titulo),
              el('span', { class: 'sub' }, [e.horario, e.local].filter(Boolean).join(' · '))));
        })
      : [vazioCk('Nenhum evento nos próximos 7 dias.')]));
  }

  // Aniversariantes (hoje e nos próximos 6 dias)
  const inicioHoje = new Date(agora.getFullYear(), agora.getMonth(), agora.getDate());
  const aniversarios = membros.filter((m) => m.ativo).map((m) => {
    let data = new Date(agora.getFullYear(), m.mes - 1, m.dia);
    if (data < inicioHoje) data = new Date(agora.getFullYear() + 1, m.mes - 1, m.dia);
    return { nome: m.nome, data, dias: Math.round((data - inicioHoje) / 86400000) };
  }).filter((a) => a.dias < 7).sort((a, b) => a.dias - b.dias);
  $('ck-aniversarios').replaceChildren(...(aniversarios.length
    ? aniversarios.map((a) => el('div', { class: 'par' },
        el('span', {}, a.nome),
        a.dias === 0 ? el('strong', { style: 'color:var(--primaria)' }, 'hoje') : el('span', { class: 'dica' }, ddmm(a.data))))
    : [vazioCk('Nenhum aniversariante nos próximos 7 dias.')]));
}

/** O estado consulta o Holyrics e pode demorar; carrega à parte para não segurar o resto. */
async function carregarSistemaInicio() {
  const [est, historico] = await Promise.all([api('GET', '/api/estado'), api('GET', '/api/historico?limite=1')]);
  estado = est;
  const situacao = (ok, texto) => el('strong', { style: 'color:' + (ok ? 'var(--ok)' : 'var(--perigo)') },
    el('span', { class: 'ponto', style: 'background:currentColor' }), texto);
  const ultima = historico[0];
  $('ck-sistema').replaceChildren(...[
    est.modo === 'agente'
      ? el('div', { class: 'par' }, el('span', {}, 'PC da igreja (agente)'), situacao(est.agenteConectado, est.agenteConectado ? 'Conectado' : 'Desconectado'))
      : null,
    el('div', { class: 'par' }, el('span', {}, 'Holyrics'), situacao(est.holyricsConectado, est.holyricsConectado ? 'Conectado' : 'Sem conexão')),
    el('div', { class: 'par' }, el('span', {}, 'Último backup'),
      est.backupConfigurado ? el('strong', {}, est.ultimoBackup ? dataCurta(est.ultimoBackup) : 'ainda não feito') : situacao(false, 'Desativado')),
    el('div', { class: 'par' }, el('span', {}, 'Última projeção'),
      el('strong', {}, ultima ? dataCurta(ultima.quando) : 'nenhuma'))].filter(Boolean));
}

// ---------- Caixa de mensagens (privada) ----------

let mensagensRecebidas = [];
const nomesMensagem = { duvida: 'Dúvida', sugestao: 'Sugestão', critica: 'Crítica' };
async function carregarMensagens() {
  mensagensRecebidas = await api('GET', '/api/mensagens');
  atualizarBadgeMensagens();
  const filtro = $('filtro-mensagens').value;
  const lista = filtro === 'todas' ? mensagensRecebidas : mensagensRecebidas.filter(m => m.status === filtro);
  const cartoes = lista.map(m => el('article', { class: 'item' },
    el('div', { class: 'conteudo' },
      el('div', { class: 'titulo' }, nomesMensagem[m.tipo] || m.tipo, ' · ', dataCurta(m.criadoEm)),
      el('div', { style: 'white-space:pre-wrap;overflow-wrap:anywhere' }, m.texto),
      el('div', { class: 'sub' }, m.nome ? 'Nome: ' + m.nome : 'Anônima', m.contato ? ' · Contato: ' + m.contato : ''),
      el('div', { class: 'sub' }, 'Aviso por e-mail: ' + (m.avisoEmail === 'enviado' ? 'enviado' : m.avisoEmail === 'falhou' ? 'falhou' : 'pendente / SMTP não configurado'))),
    el('div', { class: 'acoes' },
      m.status !== 'nova' ? botao('Nova', () => mudarMensagem(m, 'nova'), 'pequeno') : null,
      m.status !== 'emAnalise' ? botao('Em análise', () => mudarMensagem(m, 'emAnalise'), 'pequeno') : null,
      m.status !== 'resolvida' ? botao('Resolvida', () => mudarMensagem(m, 'resolvida'), 'pequeno') : null,
      m.avisoEmail !== 'enviado' ? botao('Tentar e-mail', async () => {
        try { await api('POST', '/api/mensagens/' + m.id + '/avisar'); await carregarMensagens(); }
        catch (e) { mensagem($('resultado-mensagens'), e.message, false); }
      }, 'pequeno') : null)));
  $('lista-mensagens').replaceChildren(...(cartoes.length ? cartoes : [el('p', { class: 'vazio' }, 'Nenhuma mensagem neste filtro.')]));
}
function atualizarBadgeMensagens() {
  const novas = mensagensRecebidas.filter(m => m.status === 'nova').length;
  $('badge-mensagens').textContent = novas;
  $('badge-mensagens').hidden = !novas;
}
async function mudarMensagem(m, status) {
  try { await api('PUT', '/api/mensagens/' + m.id, { status }); await carregarMensagens(); }
  catch (e) { mensagem($('resultado-mensagens'), e.message, false); }
}
$('filtro-mensagens').addEventListener('change', carregarMensagens);

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
  if (!pode('motivosEditar')) {
    // Só leitura (Mídia, Telão): sem botões.
  } else if (m.status === 'aguardando') {
    acoes.push(botao('Aprovar', () => api('POST', `/api/motivos/${m.id}/aprovar`).then(carregarMotivos), 'pequeno'));
    acoes.push(botao('Recusar', () => confirm('Recusar e apagar este pedido?') && api('DELETE', '/api/motivos/' + m.id).then(carregarMotivos), 'perigo pequeno'));
  } else if (m.status === 'pendente') {
    acoes.push(botao('Atendido', () => api('PUT', '/api/motivos/' + m.id, { status: 'atendido' }).then(carregarMotivos)));
  } else {
    acoes.push(botao('Voltar para a lista', () => api('PUT', '/api/motivos/' + m.id, { status: 'pendente' }).then(carregarMotivos)));
  }
  if (pode('motivosEditar')) acoes.push(botao('Editar', () => editarMotivo(m)));
  if (pode('motivosEditar') && m.status !== 'aguardando') {
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
            el('div', { class: 'sub' }, new Date(h.quando).toLocaleString('pt-BR', { weekday: 'short', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }) +
              (h.usuario ? ' · ' + h.usuario : '')))))
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
    ? [el('span', { class: 'dica' }, 'Automático — edite na aba Membros')]
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
        r.urgente ? el('span', { class: 'etiqueta', style: 'background:#fbefe2;color:#6b3d00' }, 'Urgente no site')
          : r.site ? el('span', { class: 'etiqueta' }, 'No site') : null,
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

/** [r] com id edita; sem id (modelo, ex: vindo da agenda) ou null cria um novo. */
function editarRecado(r) {
  const novo = !r || !r.id;
  $('titulo-recado').textContent = novo ? 'Novo recado' : 'Editar recado';
  $('r-titulo').value = r ? r.titulo : '';
  $('r-texto').value = r ? r.texto : '';
  $('r-categoria').value = r ? r.categoria : 'aviso';
  $('r-validade').value = r && r.validoAte ? r.validoAte.slice(0, 10) : '';
  $('r-fixo').checked = r ? r.fixo : false;
  $('r-site').checked = r ? !!(r.site || r.urgente) : false;
  $('r-urgente').checked = r ? !!r.urgente : false;
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
      site: $('r-site').checked || $('r-urgente').checked,
      urgente: $('r-urgente').checked,
    };
    if (novo) await api('POST', '/api/recados', dados);
    else await api('PUT', '/api/recados/' + r.id, dados);
    await carregarRecados();
  });
}

// Urgente sempre aparece no site.
$('r-urgente').addEventListener('change', () => {
  if ($('r-urgente').checked) $('r-site').checked = true;
});
$('r-site').addEventListener('change', () => {
  if (!$('r-site').checked) $('r-urgente').checked = false;
});

$('novo-recado').addEventListener('click', async () => {
  cartazes = await api('GET', '/api/cartazes');
  editarRecado(null);
});

// ---------- Agenda (Google, só leitura) ----------

async function carregarAgenda() {
  const r = await api('GET', '/api/agenda?dias=30');
  const estado = $('estado-agenda-painel');
  $('novo-evento').hidden = !r.editavel;
  if (!r.configurada) {
    estado.replaceChildren('Agenda do Google não configurada.',
      ...(pode('admin') ? [' ', el('a', { href: '/admin#agenda' }, 'Configurar em Administração'), '.'] : []));
    $('lista-agenda').replaceChildren();
    return;
  }
  const atualizada = r.atualizado ? ' · atualizada ' + dataCurta(r.atualizado) : '';
  if (r.erro) {
    estado.textContent = 'Problema ao atualizar a agenda: ' + r.erro + ' (mostrando a última cópia).';
  } else if (r.editavel) {
    estado.textContent = 'Eventos do Google Agenda nos próximos 30 dias' + atualizada + '. Crie, edite e exclua por aqui.';
  } else {
    estado.replaceChildren('Eventos do Google Agenda nos próximos 30 dias' + atualizada + '. Para criar ou mudar eventos por aqui, ',
      el('a', { href: '/ajuda/agenda-google', target: '_blank' }, 'ligue a conta de serviço'), '.');
  }
  const itens = [];
  let diaAtual = '';
  for (const e of r.eventos) {
    if (e.dia !== diaAtual) {
      diaAtual = e.dia;
      itens.push(el('h3', { style: 'font-size:15px;margin:16px 0 4px;color:var(--suave)' }, e.dia));
    }
    itens.push(el('div', { class: 'item' },
      el('div', { class: 'faixa', style: 'background:var(--primaria)' }),
      el('div', { class: 'conteudo' },
        el('div', { class: 'titulo' }, e.titulo, el('span', { class: 'etiqueta' }, e.horario)),
        e.local ? el('div', { class: 'sub' }, e.local) : null,
        e.descricao ? el('div', { class: 'sub' }, e.descricao) : null),
      el('div', { class: 'acoes' },
        botao('Criar recado', () => criarRecadoDoEvento(e)),
        e.editavel && pode('agendaEditar') ? botao('Editar', () => editarEvento(e)) : null,
        e.editavel && pode('agendaEditar') ? botao('Excluir', () => excluirEvento(e), 'perigo pequeno') : null,
        r.editavel && !e.editavel ? el('span', { class: 'dica' }, 'Repete: altere no Google Agenda') : null)));
  }
  $('lista-agenda').replaceChildren(...(itens.length ? itens : [el('p', { class: 'vazio' }, 'Nenhum evento nos próximos 30 dias.')]));
}

// Eventos chegam como "relógio de parede" sem fuso (ex.: 2026-11-07T19:30:00.000).
const horaMinuto = (d) => String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
function somarDias(dia, n) {
  const d = new Date(dia + 'T00:00:00');
  d.setDate(d.getDate() + n);
  return diaIso(d);
}

function mostrarCamposEvento() {
  const diaInteiro = $('e-dia-inteiro').checked;
  document.querySelectorAll('#dlg-evento .so-horario').forEach((c) => (c.hidden = diaInteiro));
  document.querySelectorAll('#dlg-evento .so-dia-inteiro').forEach((c) => (c.hidden = !diaInteiro));
  $('rotulo-e-data').textContent = diaInteiro ? 'Primeiro dia' : 'Data';
}
$('e-dia-inteiro').addEventListener('change', mostrarCamposEvento);

function editarEvento(e) {
  const inicio = e ? new Date(e.inicio) : null;
  const fim = e ? new Date(e.fim) : null;
  $('titulo-evento').textContent = e ? 'Editar evento' : 'Novo evento';
  $('e-titulo').value = e ? e.titulo : '';
  $('e-dia-inteiro').checked = e ? e.diaInteiro : false;
  $('e-data').value = inicio ? diaIso(inicio) : diaIso(new Date());
  $('e-hora-inicio').value = inicio && !e.diaInteiro ? horaMinuto(inicio) : '19:00';
  $('e-hora-fim').value = fim && !e.diaInteiro ? horaMinuto(fim) : '21:00';
  $('e-data-fim').value = e && e.diaInteiro ? somarDias(diaIso(fim), -1) : '';
  $('e-local').value = e ? e.local : '';
  $('e-descricao').value = e ? e.descricao : '';
  mostrarCamposEvento();
  abrirDialogo($('dlg-evento'), $('erro-evento'), async () => {
    const dia = $('e-data').value;
    if (!dia) throw new Error('Informe a data.');
    const diaInteiro = $('e-dia-inteiro').checked;
    const dados = {
      titulo: $('e-titulo').value.trim(),
      diaInteiro,
      inicio: diaInteiro ? dia + 'T00:00:00' : `${dia}T${$('e-hora-inicio').value || '00:00'}:00`,
      fim: diaInteiro ? somarDias($('e-data-fim').value || dia, 1) + 'T00:00:00' : `${dia}T${$('e-hora-fim').value || '00:00'}:00`,
      local: $('e-local').value.trim(),
      descricao: $('e-descricao').value.trim(),
    };
    if (e) await api('PUT', '/api/agenda/eventos/' + encodeURIComponent(e.id), dados);
    else await api('POST', '/api/agenda/eventos', dados);
    await recarregarAgendaVisivel();
  });
}

async function excluirEvento(e) {
  if (!confirm(`Excluir "${e.titulo}" do Google Agenda?`)) return;
  try {
    await api('DELETE', '/api/agenda/eventos/' + encodeURIComponent(e.id));
    mensagem($('resultado-agenda'), `"${e.titulo}" foi excluído.`);
    await recarregarAgendaVisivel();
  } catch (err) {
    mensagem($('resultado-agenda'), '', false);
    $('resultado-agenda').replaceChildren(...textoDoErro(err).flat().filter(Boolean));
  }
}

function recarregarAgendaVisivel() {
  return abaAtual === 'inicio' ? carregarInicio() : carregarAgenda();
}

$('novo-evento').addEventListener('click', () => editarEvento(null));
$('ck-novo-evento').addEventListener('click', () => editarEvento(null));

async function criarRecadoDoEvento(e) {
  cartazes = await api('GET', '/api/cartazes');
  editarRecado({
    titulo: e.titulo,
    texto: e.textoRecado,
    categoria: 'evento',
    validoAte: e.inicio.slice(0, 10),
    fixo: false,
  });
}

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

// ---------- Galeria do site (carrossel da página inicial) ----------

let fotos = [];

async function carregarGaleria() {
  fotos = await api('GET', '/api/galeria');
  const site = (eu && eu.site) || {};
  const desligada = site.ativo === false || site.galeria === false;
  $('aviso-galeria').hidden = !desligada;
  $('aviso-galeria').replaceChildren(
    site.ativo === false ? 'A página inicial está desligada, então o carrossel não aparece. ' : 'O carrossel está desligado na página inicial. ',
    pode('admin') ? el('a', { href: '/admin#pagina-inicial' }, 'Ligar em Administração') : 'Peça ao administrador para ligar', '.');
  $('lista-galeria').replaceChildren(...(fotos.length
    ? fotos.map((f, i) => itemFoto(f, i))
    : [el('p', { class: 'vazio' }, 'Nenhuma foto ainda. Use "Enviar fotos".')]));
}

function itemFoto(f, i) {
  const resultado = $('resultado-galeria');
  // Legenda e link são salvos ao sair do campo (ou com Enter).
  const campo = (nome, rotulo, props) => {
    const input = el('input', { type: nome === 'link' ? 'url' : 'text', value: f[nome] || '', 'aria-label': rotulo + ' da foto ' + (i + 1), ...props });
    const salvar = async () => {
      const valor = input.value.trim();
      if (valor === (f[nome] || '')) return;
      try {
        await api('PUT', '/api/galeria/' + f.id, { [nome]: valor });
        f[nome] = valor;
        mensagem(resultado, rotulo + ' salvo.');
      } catch (err) {
        input.value = f[nome] || '';
        mensagem(resultado, err.message, false);
      }
    };
    input.addEventListener('change', salvar);
    input.addEventListener('keydown', (e) => e.key === 'Enter' && input.blur());
    return input;
  };
  const acoes = [
    botao('↑', () => moverFoto(i, -1), 'secundario pequeno'),
    botao('↓', () => moverFoto(i, 1), 'secundario pequeno'),
    botao(f.ativo === false ? 'Mostrar' : 'Ocultar', () =>
      api('PUT', '/api/galeria/' + f.id, { ativo: f.ativo === false }).then(carregarGaleria), 'secundario pequeno'),
    botao('Excluir', () => confirm('Excluir esta foto do site?') &&
      api('DELETE', '/api/galeria/' + f.id).then(carregarGaleria), 'perigo pequeno'),
  ];
  acoes[0].setAttribute('aria-label', 'Mover a foto ' + (i + 1) + ' para antes');
  acoes[1].setAttribute('aria-label', 'Mover a foto ' + (i + 1) + ' para depois');
  acoes[0].disabled = i === 0;
  acoes[1].disabled = i === fotos.length - 1;
  return el('article', { class: 'foto' + (f.ativo === false ? ' oculta' : '') },
    el('img', { src: f.urlMiniatura, alt: f.legenda || 'Foto ' + (i + 1), loading: 'lazy' }),
    el('div', { class: 'corpo' },
      el('div', { class: 'topo-foto' },
        i === 0 ? el('span', { class: 'etiqueta', style: 'margin:0' }, 'Capa') : null,
        f.ativo === false ? el('span', { class: 'etiqueta', style: 'margin:0' }, 'Oculta') : null,
        el('span', {}, f.largura + '×' + f.altura)),
      campo('legenda', 'Legenda', { maxlength: 140, placeholder: 'Legenda (opcional)' }),
      campo('link', 'Link', { maxlength: 300, placeholder: 'Link ao tocar (opcional, https://…)' }),
      el('div', { class: 'acoes' }, acoes)));
}

async function moverFoto(i, delta) {
  const ids = fotos.map((f) => f.id);
  const j = i + delta;
  if (j < 0 || j >= ids.length) return;
  [ids[i], ids[j]] = [ids[j], ids[i]];
  await api('PUT', '/api/galeria/ordem', ids);
  await carregarGaleria();
}

$('botao-fotos').addEventListener('click', () => $('arquivo-fotos').click());
$('arquivo-fotos').addEventListener('change', async (e) => {
  const arquivos = [...e.target.files];
  e.target.value = '';
  const resultado = $('resultado-galeria');
  for (let i = 0; i < arquivos.length; i++) {
    mensagem(resultado, arquivos.length > 1 ? `Enviando ${i + 1} de ${arquivos.length}…` : 'Enviando…');
    try {
      await api('POST', '/api/galeria', arquivos[i], { bruto: true, tipo: arquivos[i].type || 'application/octet-stream' });
    } catch (err) {
      mensagem(resultado, `${arquivos[i].name}: ${err.message}`, false);
      await carregarGaleria();
      return;
    }
  }
  mensagem(resultado, arquivos.length === 1 ? 'Foto enviada.' : `${arquivos.length} fotos enviadas.`);
  await carregarGaleria();
});

// ---------- Membros ----------

let membros = [];
let fotoPendente = null; // File escolhido no dialog (ainda não enviado)
let removerFoto = false; // apagar a foto atual ao salvar

const STATUS_MEMBRO = {
  visitante: ['Visitante', '#42A5F5'],
  congregado: ['Congregado', '#26A69A'],
  membro: ['Membro', '#66BB6A'],
  inativo: ['Inativo', '#8a8578'],
  transferido: ['Transferido', '#FFA726'],
};

const semAcento = (s) => (s || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '');
const inicialMembro = (m) => m.nome.trim().split(/\s+/).slice(0, 2).map((p) => p[0]).join('').toUpperCase();
const aniversarioDe = (m) =>
  String(m.dia).padStart(2, '0') + '/' + String(m.mes).padStart(2, '0') + (m.ano ? '/' + m.ano : '');
const dataBr = (iso) => (iso ? new Date(iso + 'T00:00:00').toLocaleDateString('pt-BR') : null);

function idadeDe(m) {
  if (!m.ano) return null;
  const hoje = new Date();
  let i = hoje.getFullYear() - m.ano;
  if (hoje.getMonth() + 1 < m.mes || (hoje.getMonth() + 1 === m.mes && hoje.getDate() < m.dia)) i--;
  return i;
}

async function carregarMembros() {
  membros = await api('GET', '/api/membros');
  montarFiltroMinisterios();
  renderMembros();
}

function montarFiltroMinisterios() {
  const atual = $('filtro-ministerio-membro').value;
  const todos = [...new Set(membros.flatMap((m) => m.ministerios || []))]
    .sort((a, b) => a.localeCompare(b, 'pt-BR'));
  $('filtro-ministerio-membro').replaceChildren(
    el('option', { value: '' }, 'Todos os ministérios'),
    ...todos.map((x) => el('option', { value: x }, x)));
  $('filtro-ministerio-membro').value = todos.includes(atual) ? atual : '';
  $('dl-ministerios').replaceChildren(...todos.map((x) => el('option', { value: x })));
}

function membrosFiltrados() {
  const busca = semAcento($('busca-membro').value.trim().toLowerCase());
  const status = $('filtro-status-membro').value;
  const ministerio = $('filtro-ministerio-membro').value;
  const aniversariantes = $('filtro-aniversariantes').checked;
  const mes = new Date().getMonth() + 1;
  return membros
    .filter((m) => {
      if (status === 'ativos' ? !m.ativo : status && m.status !== status) return false;
      if (ministerio && !(m.ministerios || []).includes(ministerio)) return false;
      if (aniversariantes && (!m.ativo || m.mes !== mes)) return false;
      if (busca) {
        const alvo = semAcento([m.nome, m.telefone, m.whatsapp, m.email, m.cidade, m.bairro, m.funcao]
          .filter(Boolean).join(' ').toLowerCase());
        if (!alvo.includes(busca)) return false;
      }
      return true;
    })
    .sort((a, b) => a.nome.localeCompare(b.nome, 'pt-BR'));
}

function renderMembros() {
  const lista = membrosFiltrados();
  const agora = new Date();
  const mes = agora.getMonth() + 1;
  const noventaDias = Date.now() - 90 * 86400000;
  const indicador = (rotulo, valor, detalhe) =>
    el('div', { class: 'cartao', style: 'padding:16px 20px;display:flex;flex-direction:column;gap:2px' },
      el('span', { class: 'dica' }, rotulo),
      el('strong', { style: 'font-family:var(--fonte-titulo);font-size:32px;font-weight:600' }, String(valor)),
      detalhe ? el('small', { class: 'dica' }, detalhe) : null);
  $('indicadores-membros').replaceChildren(...[
    indicador('Pessoas cadastradas', membros.length, membros.filter((m) => m.ativo).length + ' ativas'),
    indicador('Aniversariantes de ' + agora.toLocaleDateString('pt-BR', { month: 'long' }),
      membros.filter((m) => m.ativo && m.mes === mes).length),
    indicador('Novas pessoas em 90 dias', membros.filter((m) => m.criadoEm && Date.parse(m.criadoEm) >= noventaDias).length),
  ]);
  $('lista-membros').replaceChildren(
    ...(lista.length ? lista.map(cardMembro) : [el('p', { class: 'vazio' }, 'Ninguém neste filtro.')]));
  hidratarFotos($('lista-membros'));
}

/** Coloca a miniatura (atrás de login) nos <img data-foto-id>; sem foto, ficam as iniciais. */
function hidratarFotos(container) {
  for (const img of container.querySelectorAll('img[data-foto-id]')) {
    const m = membros.find((x) => x.id === img.dataset.fotoId);
    if (!m || !m.foto) continue;
    urlAutenticada(`/api/membros/${m.id}/foto-miniatura?v=${encodeURIComponent(m.atualizadoEm || m.foto)}`)
      .then((url) => {
        if (!url || !img.isConnected) return;
        img.src = url;
        img.hidden = false;
        const iniciais = img.parentElement && img.parentElement.querySelector('.iniciais, span:not([hidden])');
        if (iniciais) iniciais.hidden = true;
      })
      .catch(() => {});
  }
}

function cardMembro(m) {
  const [rotuloStatus, cor] = STATUS_MEMBRO[m.status] || STATUS_MEMBRO.membro;
  const contatos = [m.telefone, m.whatsapp && m.whatsapp !== m.telefone ? m.whatsapp : null, m.email].filter(Boolean);
  const mins = m.ministerios || [];
  return el('article', { class: 'membro-card', style: m.ativo ? '' : 'opacity:.65' },
    el('button', { class: 'foto', type: 'button', 'aria-label': 'Abrir a ficha de ' + m.nome, onclick: () => abrirFicha(m.id) },
      el('span', { class: 'iniciais' }, inicialMembro(m)),
      el('img', { 'data-foto-id': m.id, alt: '', hidden: true, loading: 'lazy' })),
    el('div', { class: 'conteudo' },
      el('button', { class: 'titulo', type: 'button', onclick: () => abrirFicha(m.id) }, m.nome,
        el('span', { class: 'etiqueta', style: 'color:' + cor }, rotuloStatus)),
      el('span', { class: 'sub' },
        [aniversarioDe(m), idadeDe(m) != null ? idadeDe(m) + ' anos' : null].filter(Boolean).join(' · ')),
      contatos.length ? el('span', { class: 'sub' }, contatos.join(' · ')) : null,
      mins.length ? el('span', { class: 'sub' },
        mins.slice(0, 3).join(', ') + (mins.length > 3 ? ` +${mins.length - 3}` : '')) : null,
      el('div', { class: 'acoes' },
        botao('Ficha', () => abrirFicha(m.id)),
        botao('Editar', () => editarMembro(m)),
        botao('Excluir', () => excluirMembro(m), 'perigo pequeno'))));
}

// ----- Ficha (todos os dados + família com links) -----

let fichaAberta = null;

function abrirFicha(id) {
  const m = membros.find((x) => x.id === id);
  if (!m) return;
  fichaAberta = m;
  const [rotuloStatus, cor] = STATUS_MEMBRO[m.status] || STATUS_MEMBRO.membro;
  const linkMembro = (o) => o ? el('button', { class: 'link', type: 'button', onclick: () => abrirFicha(o.id) }, o.nome) : null;
  const par = (rotulo, ...valores) => {
    const tem = valores.some((v) => v != null && v !== '' && !(Array.isArray(v) && v.length === 0));
    return tem ? el('div', { class: 'ficha-par' },
      el('span', { class: 'rotulo' }, rotulo),
      el('span', { class: 'valor' }, ...valores.filter((v) => v != null && v !== ''))) : null;
  };
  const conjuge = m.conjugeId ? membros.find((x) => x.id === m.conjugeId) : null;
  const pais = (m.paisIds || []).map((pid) => membros.find((x) => x.id === pid)).filter(Boolean);
  const filhos = membros.filter((x) => (x.paisIds || []).includes(m.id));
  const idade = idadeDe(m);
  const endereco = [
    m.rua ? [m.rua, m.numero].filter(Boolean).join(', ') : null,
    m.complemento, [m.bairro, m.cidade, m.uf].filter(Boolean).join(' — '),
    m.cep ? 'CEP ' + m.cep : null,
  ].filter(Boolean);

  $('ficha-conteudo').replaceChildren(
    el('div', { class: 'ficha-topo' },
      el('div', { class: 'avatar' }, inicialMembro(m),
        el('img', { 'data-foto-id': m.id, alt: 'Foto de ' + m.nome, hidden: true })),
      el('div', {},
        el('h2', { style: 'font-size:24px;margin:0 0 4px' }, m.nome),
        el('span', { class: 'etiqueta', style: 'margin:0;color:' + cor }, rotuloStatus),
        idade != null ? el('span', { class: 'dica', style: 'margin-left:8px' }, idade + ' anos') : null)),
    par('Aniversário', aniversarioDe(m)), par('Sexo', m.sexo === 'M' ? 'Masculino' : m.sexo === 'F' ? 'Feminino' : null),
    par('Estado civil', m.estadoCivil),
    par('Telefone', m.telefone, m.whatsapp && m.whatsapp !== m.telefone ? ' · WhatsApp: ' + m.whatsapp : null),
    par('E-mail', m.email ? el('a', { href: 'mailto:' + m.email }, m.email) : null),
    par('Endereço', endereco.length ? endereco.join('\n') : null),
    par('CPF', m.cpf), par('RG', m.rg),
    par('Chegou em', dataBr(m.dataChegada)), par('Batismo', dataBr(m.dataBatismo)), par('Membresia', dataBr(m.dataMembresia)),
    par('Ministérios', (m.ministerios || []).join(', ') || null), par('Função', m.funcao),
    par('Cônjuge', linkMembro(conjuge)),
    pais.length ? par('Pais', ...pais.map(linkMembro).flatMap((l, i) => i ? [', ', l] : [l])) : null,
    filhos.length ? par('Filhos', ...filhos.map(linkMembro).flatMap((l, i) => i ? [', ', l] : [l])) : null,
    par('Emergência', [m.emergenciaNome, m.emergenciaVinculo, m.emergenciaTelefone].filter(Boolean).join(' · ')),
    par('Observações', m.observacoes));

  const ultima = (m.historicoStatus || []).slice(-1)[0];
  $('ficha-historico').textContent = ultima
    ? rotuloStatus + ' desde ' + new Date(ultima.em).toLocaleDateString('pt-BR') : '';

  hidratarFotos($('ficha-conteudo'));
  $('dlg-ficha').showModal();
}

$('fechar-ficha').addEventListener('click', () => $('dlg-ficha').close());
$('editar-da-ficha').addEventListener('click', () => {
  $('dlg-ficha').close();
  if (fichaAberta) editarMembro(fichaAberta);
});

// ----- Editar / criar -----

/** Garante que um valor salvo aparece no select, mesmo fora das opções padrão. */
function garantirOpcao(sel, valor) {
  if (valor && ![...sel.options].some((o) => o.value === valor)) sel.append(el('option', {}, valor));
  sel.value = valor || '';
}

function montarSelectsFamilia(m) {
  const outros = membros.filter((x) => !m || x.id !== m.id);
  const montar = (sel, selecionado) => {
    sel.replaceChildren(el('option', { value: '' }, '(nenhum)'),
      ...outros.map((x) => el('option', { value: x.id }, x.nome)));
    sel.value = selecionado || '';
  };
  montar($('b-conjuge'), m?.conjugeId);
  montar($('b-pai-1'), m?.paisIds?.[0]);
  montar($('b-pai-2'), m?.paisIds?.[1]);
}

function editarMembro(m) {
  const novo = !m;
  $('titulo-membro').textContent = novo ? 'Novo membro' : 'Editar: ' + m.nome;
  $('b-ano').max = new Date().getFullYear();
  montarSelectsFamilia(m);
  $('b-nome').value = m ? m.nome : '';
  $('b-dia').value = m ? m.dia : '';
  $('b-mes').value = m ? m.mes : '';
  $('b-ano').value = m?.ano || '';
  $('b-sexo').value = m?.sexo || '';
  garantirOpcao($('b-estado-civil'), m?.estadoCivil);
  $('b-telefone').value = m?.telefone || '';
  $('b-whatsapp').value = m?.whatsapp || '';
  $('b-email').value = m?.email || '';
  $('b-cep').value = m?.cep || '';
  $('b-rua').value = m?.rua || '';
  $('b-numero').value = m?.numero || '';
  $('b-complemento').value = m?.complemento || '';
  $('b-bairro').value = m?.bairro || '';
  $('b-cidade').value = m?.cidade || '';
  garantirOpcao($('b-uf'), m?.estado);
  $('b-cpf').value = m?.cpf || '';
  $('b-rg').value = m?.rg || '';
  $('b-status').value = m ? m.status : 'membro';
  $('b-chegada').value = m?.dataChegada || '';
  $('b-batismo').value = m?.dataBatismo || '';
  $('b-membresia').value = m?.dataMembresia || '';
  $('b-ministerios').value = (m?.ministerios || []).join(', ');
  $('b-funcao').value = m?.funcao || '';
  $('b-emerg-nome').value = m?.emergenciaNome || '';
  $('b-emerg-telefone').value = m?.emergenciaTelefone || '';
  $('b-emerg-vinculo').value = m?.emergenciaVinculo || '';
  $('b-observacoes').value = m?.observacoes || '';

  // Foto: prévia da atual (se houver) ou iniciais; a escolha nova aparece na hora.
  fotoPendente = null;
  removerFoto = false;
  $('b-arquivo-foto').value = '';
  $('b-remover-foto').hidden = !(m && m.foto);
  const img = $('b-foto-atual');
  img.hidden = true;
  img.removeAttribute('src');
  $('b-foto-iniciais').textContent = m ? inicialMembro(m) : '?';
  $('b-foto-iniciais').hidden = false;
  if (m && m.foto) {
    urlAutenticada(`/api/membros/${m.id}/foto?v=${encodeURIComponent(m.atualizadoEm || m.foto)}`)
      .then((url) => {
        if (url && !fotoPendente && img.isConnected) {
          img.src = url;
          img.hidden = false;
          $('b-foto-iniciais').hidden = true;
        }
      }).catch(() => {});
  }

  abrirDialogo($('dlg-membro'), $('erro-membro'), async () => {
    const dados = {
      nome: $('b-nome').value.trim(),
      dia: Number($('b-dia').value),
      mes: Number($('b-mes').value),
      ano: $('b-ano').value ? Number($('b-ano').value) : null,
      sexo: $('b-sexo').value || null,
      estadoCivil: $('b-estado-civil').value || null,
      cpf: $('b-cpf').value.trim() || null,
      rg: $('b-rg').value.trim() || null,
      telefone: $('b-telefone').value.trim() || null,
      whatsapp: $('b-whatsapp').value.trim() || null,
      email: $('b-email').value.trim() || null,
      cep: $('b-cep').value.trim() || null,
      rua: $('b-rua').value.trim() || null,
      numero: $('b-numero').value.trim() || null,
      complemento: $('b-complemento').value.trim() || null,
      bairro: $('b-bairro').value.trim() || null,
      cidade: $('b-cidade').value.trim() || null,
      estado: $('b-uf').value || null,
      status: $('b-status').value,
      dataChegada: $('b-chegada').value || null,
      dataBatismo: $('b-batismo').value || null,
      dataMembresia: $('b-membresia').value || null,
      ministerios: $('b-ministerios').value.split(',').map((s) => s.trim()).filter(Boolean),
      funcao: $('b-funcao').value.trim() || null,
      conjugeId: $('b-conjuge').value || null,
      paisIds: [...new Set([$('b-pai-1').value, $('b-pai-2').value].filter(Boolean))],
      emergenciaNome: $('b-emerg-nome').value.trim() || null,
      emergenciaTelefone: $('b-emerg-telefone').value.trim() || null,
      emergenciaVinculo: $('b-emerg-vinculo').value.trim() || null,
      observacoes: $('b-observacoes').value.trim() || null,
    };
    const salvo = m ? await api('PUT', '/api/membros/' + m.id, dados) : await api('POST', '/api/membros', dados);
    if (fotoPendente) {
      await api('POST', '/api/membros/' + salvo.id + '/foto', fotoPendente,
        { bruto: true, tipo: fotoPendente.type || 'application/octet-stream' });
    } else if (removerFoto && m && m.foto) {
      await api('DELETE', '/api/membros/' + m.id + '/foto');
    }
    await carregarMembros();
  });
}

$('novo-membro').addEventListener('click', () => editarMembro(null));

$('b-arquivo-foto').addEventListener('change', (e) => {
  const f = e.target.files[0];
  if (!f) return;
  fotoPendente = f;
  removerFoto = false;
  $('b-foto-atual').src = URL.createObjectURL(f);
  $('b-foto-atual').hidden = false;
  $('b-foto-iniciais').hidden = true;
  $('b-remover-foto').hidden = false;
});

$('b-remover-foto').addEventListener('click', () => {
  fotoPendente = null;
  removerFoto = true;
  $('b-arquivo-foto').value = '';
  $('b-foto-atual').hidden = true;
  $('b-foto-atual').removeAttribute('src');
  $('b-foto-iniciais').hidden = false;
  $('b-remover-foto').hidden = true;
});

async function excluirMembro(m) {
  if (!confirm(`Excluir ${m.nome}? A foto e os vínculos de família também saem.`)) return;
  try {
    await api('DELETE', '/api/membros/' + m.id);
    await carregarMembros();
  } catch (e) {
    mensagem($('resultado-membros'), e.message, false);
  }
}

// Filtros (só re-renderiza, sem buscar de novo).
for (const id of ['busca-membro', 'filtro-status-membro', 'filtro-ministerio-membro', 'filtro-aniversariantes']) {
  $(id).addEventListener('input', renderMembros);
  $(id).addEventListener('change', renderMembros);
}

// ----- Importar -----

$('abrir-importar-membros').addEventListener('click', () => {
  mensagem($('resultado-importacao'), '');
  $('dlg-importar').showModal();
});

$('form-importar').addEventListener('submit', async (e) => {
  if (e.submitter && e.submitter.value === 'cancelar') return; // deixa o dialog fechar
  e.preventDefault();
  const saida = $('resultado-importacao');
  try {
    const r = await api('POST', '/api/membros/importar', $('csv-membros').value);
    const partes = [`${r.importados} membro(s) importado(s).`];
    if (r.linhasComErro && r.linhasComErro.length) partes.push(`Linhas com erro: ${r.linhasComErro.join(', ')}.`);
    for (const d of r.detalhes || []) partes.push(d);
    mensagem(saida, partes.join('\n'), !(r.linhasComErro || []).length);
    if (r.importados) {
      $('csv-membros').value = '';
      await carregarMembros();
      if (!(r.linhasComErro || []).length && !(r.detalhes || []).length) $('dlg-importar').close();
    }
  } catch (err) {
    mensagem(saida, err.message, false);
  }
});

$('modelo-csv').addEventListener('click', () => {
  $('csv-membros').value =
    'Nome;Aniversário;Sexo;Estado civil;CPF;Telefone;WhatsApp;E-mail;Status;Data de batismo;Ministérios;Função;Cidade;UF\n'
    + 'Ana Souza;05/03/1990;F;Casada;111.444.777-35;(11) 98888-7777;;ana@exemplo.com;Congregado;14/06/2015;Louvor|Infantil;Líder;São Paulo;SP\n'
    + 'Bruno Lima;05/11;;;;;;;;;;;;\n';
});

// ----- Exportar CSV / Imprimir -----

$('exportar-membros').addEventListener('click', () => {
  const qs = new URLSearchParams();
  const status = $('filtro-status-membro').value;
  if (status) qs.set('status', status);
  if ($('filtro-ministerio-membro').value) qs.set('ministerio', $('filtro-ministerio-membro').value);
  if ($('filtro-aniversariantes').checked) qs.set('aniversariantes', 'mes');
  baixarArquivo('/api/membros/exportar' + (qs.toString() ? '?' + qs.toString() : ''), 'membros.csv');
});

$('imprimir-membros').addEventListener('click', () => {
  const lista = membrosFiltrados();
  if (!lista.length) return;
  const filtros = [];
  const st = $('filtro-status-membro').value;
  if (st === 'ativos') filtros.push('ativos');
  else if (st) filtros.push(((STATUS_MEMBRO[st] || STATUS_MEMBRO.membro)[0]).toLowerCase() + 's');
  if ($('filtro-ministerio-membro').value) filtros.push($('filtro-ministerio-membro').value);
  if ($('filtro-aniversariantes').checked) filtros.push('aniversariantes do mês');
  const linha = (m) => el('tr', {},
    el('td', {}, m.nome),
    el('td', {}, aniversarioDe(m)),
    el('td', {}, idadeDe(m) != null ? String(idadeDe(m)) : ''),
    el('td', {}, (STATUS_MEMBRO[m.status] || STATUS_MEMBRO.membro)[0]),
    el('td', {}, [m.telefone, m.whatsapp].filter(Boolean).join(' / ')),
    el('td', {}, m.email || ''),
    el('td', {}, [...(m.ministerios || []), m.funcao].filter(Boolean).join(' · ')),
    el('td', {}, [m.cidade, m.uf].filter(Boolean).join('/')));
  $('impressao-membros').replaceChildren(
    el('h1', {}, 'Cadastro de membros' + (filtros.length ? ' — ' + filtros.join(', ') : '')),
    el('p', {}, new Date().toLocaleDateString('pt-BR') + ' · ' + lista.length + ' pessoa(s)'),
    el('table', {},
      el('thead', {}, el('tr', {},
        ...['Nome', 'Aniversário', 'Idade', 'Status', 'Telefone / WhatsApp', 'E-mail', 'Ministério / Função', 'Cidade']
          .map((h) => el('th', {}, h)))),
      el('tbody', {}, ...lista.map(linha))));
  window.print();
});

// ---------- Status ----------

let estado = {};

async function carregarStatus() {
  estado = await api('GET', '/api/estado');
  const linha = (rotulo, valor, ok) => el('div', { class: 'status-linha' },
    el('span', {}, rotulo),
    el('strong', {}, ok === undefined ? null : el('span', { class: 'ponto', style: 'background:' + (ok ? 'var(--ok)' : 'var(--perigo)') }), valor));
  $('status-linhas').replaceChildren(
    estado.modo === 'agente'
      ? linha('PC da igreja (agente)', estado.agenteConectado ? 'Conectado' + (estado.agenteVersao ? ' · ' + estado.agenteVersao : '') : 'Desconectado' + (estado.agenteVistoEm ? ' · visto ' + dataCurta(estado.agenteVistoEm) : ''), estado.agenteConectado)
      : null,
    linha('Holyrics', estado.holyricsConectado ? 'Conectado' : 'Sem conexão', estado.holyricsConectado),
    linha('Cartazes no Holyrics', estado.cartazesNoHolyrics ? 'Sim' : 'Não configurado', estado.cartazesNoHolyrics),
    linha('Backup', estado.backupConfigurado ? (estado.ultimoBackup ? 'Último: ' + dataCurta(estado.ultimoBackup) : 'Ainda não feito') : 'Desativado', estado.backupConfigurado),
    linha('Pedidos aguardando', String(estado.aguardandoAprovacao)),
    linha('Versão do servidor', estado.versao));
  $('link-oracao').textContent = estado.urlOracao;
  $('link-oracao').href = estado.urlOracao;
  $('link-mensagens').textContent = estado.urlMensagens;
  $('link-mensagens').href = estado.urlMensagens;
  const urlMural = estado.urlOracao.replace(/\/oracao$/, '/mural') +
    (estado.chaveMural ? '?chave=' + encodeURIComponent(estado.chaveMural) : '');
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
$('projetar-qr-mensagens').addEventListener('click', async () => {
  const r = await api('POST', '/api/holyrics/ShowImage', { file: estado.qrMensagensHolyrics });
  mensagem($('resultado-status'), r.status === 'ok' ? 'QR de mensagens no telão.' : r.error, r.status === 'ok');
});

// ---------- Tempo real ----------

let ws;
function conectarTempoReal() {
  if (!token) return;
  ws = new WebSocket(`${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/ws?token=${encodeURIComponent(token)}`);
  ws.onopen = () => ($('conexao').textContent = '● ao vivo');
  ws.onmessage = (e) => {
    const { tipo } = JSON.parse(e.data);
    if (tipo === 'motivos') { if (pode('motivosVer')) carregarMotivos(); }
    else if (tipo === 'mensagens') { if (pode('mensagens')) carregarMensagens(); }
    else if (tipo === abaAtual || (tipo === 'membros' && abaAtual === 'recados')) carregar[abaAtual]();
    if (abaAtual === 'inicio') carregarInicio();
  };
  ws.onclose = () => {
    $('conexao').textContent = 'reconectando…';
    if (token) setTimeout(conectarTempoReal, 3000);
  };
}

// ---------- Início ----------

async function iniciar() {
  try {
    eu = await api('GET', '/api/eu');
  } catch {
    return; // sessão expirada: api() já voltou para o login
  }
  aplicarPermissoes();
  $('login').hidden = true;
  $('app').hidden = false;
  mostrarAba(abaAtual);
  if (abaAtual !== 'motivos' && pode('motivosVer')) carregarMotivos();
  if (abaAtual !== 'mensagens' && pode('mensagens')) carregarMensagens();
  conectarTempoReal();
}

if (token) iniciar();
else sair();
