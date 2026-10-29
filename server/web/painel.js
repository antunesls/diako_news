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
  fecharMenu();
  $('app').hidden = true;
  $('login').hidden = false;
  ($('usuario').value ? $('senha') : $('usuario')).focus();
}

// ---------- Quem está logado e o que pode (perfis) ----------

/** Resposta de /api/eu: nome, perfil e permissões. */
let eu = null;
const pode = (permissao) => !!eu && eu.permissoes.includes(permissao);

/** Esconde botões e cartões marcados com data-permissao que o perfil não tem. */
function aplicarPermissoes() {
  document.querySelectorAll('[data-permissao]').forEach((e) => e.classList.toggle('sem-permissao', !pode(e.dataset.permissao)));
  montarMenuLateral($('menu-lateral'), eu.permissoes);
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

// ---------- Menu lateral ----------

let abaAtual = 'inicio';
$('menu-lateral').addEventListener('click', (e) => {
  const item = e.target.closest('button[data-aba]');
  if (item) mostrarAba(item.dataset.aba);
});

function fecharMenu(restaurarFoco = false) {
  const aberto = $('menu-lateral').classList.contains('aberto');
  $('menu-lateral').classList.remove('aberto');
  $('abrir-menu').setAttribute('aria-expanded', 'false');
  $('fundo-menu').hidden = true;
  $('menu-lateral').inert = window.matchMedia('(max-width: 800px)').matches;
  if (aberto && restaurarFoco) $('abrir-menu').focus();
}

$('abrir-menu').addEventListener('click', () => {
  $('menu-lateral').inert = false;
  $('menu-lateral').classList.add('aberto');
  $('abrir-menu').setAttribute('aria-expanded', 'true');
  $('fundo-menu').hidden = false;
  $('fechar-menu').focus();
});
$('fechar-menu').addEventListener('click', () => fecharMenu(true));
$('fundo-menu').addEventListener('click', () => fecharMenu(true));
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && $('menu-lateral').classList.contains('aberto')) fecharMenu(true);
});
window.matchMedia('(max-width: 800px)').addEventListener('change', () => fecharMenu());
fecharMenu();

function mostrarAba(nome) {
  const botaoAba = [...$('menu-lateral').querySelectorAll('button[data-aba]')].find((b) => b.dataset.aba === nome);
  if (!botaoAba) nome = 'inicio';
  abaAtual = nome;
  $('menu-lateral').querySelectorAll('button[data-aba]').forEach((b) => {
    if (b.dataset.aba === nome) b.setAttribute('aria-current', 'page');
    else b.removeAttribute('aria-current');
  });
  fecharMenu();
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

  if (pode('visitantes')) carregarVisitantesInicio().catch(() => {});
}

/** Cartão "Visitantes de hoje": quem chegou, quem pode ser citado e o botão do telão. */
async function carregarVisitantesInicio() {
  const doDia = (await api('GET', '/api/visitas?desde=' + diaIso(new Date()))).filter((v) => v.data === diaIso(new Date()));
  const pendentes = doDia.filter((v) => v.mencionar && !v.mencionadaEm);
  $('ck-visitantes').replaceChildren(...(doDia.length ? [
    ...doDia.slice().reverse().map((v) => el('div', { class: 'par' },
      el('span', {}, v.nome, ' ', el('span', { class: 'dica' }, v.primeiraVez ? '· 1ª visita' : '· voltou')),
      !v.mencionar ? el('span', { class: 'dica' }, 'não citar')
        : v.mencionadaEm ? el('span', { class: 'dica' }, 'citado ✓')
          : el('strong', { style: 'color:var(--primaria)' }, 'citar'))),
    pode('projetar') && pendentes.length
      ? el('p', { style: 'margin:10px 0 0' }, botao(`Projetar boas-vindas (${pendentes.length})`, async (e) => {
        e.target.disabled = true;
        try {
          const r = await api('POST', '/api/projetar/boas-vindas');
          if (r.status && r.status !== 'ok') throw new Error(r.error || 'O Holyrics não aceitou.');
          await carregarVisitantesInicio();
        } catch (err) {
          e.target.disabled = false;
          $('ck-visitantes').append(el('p', { class: 'erro' }, err.message));
        }
      }, 'pequeno'))
      : null,
  ].filter(Boolean) : [vazioCk('Nenhum visitante cadastrado hoje.')]));
}
$('ck-acompanhamento').addEventListener('click', async () => {
  await carregarMembros();
  abrirAcompanhamento();
});

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
      el('strong', {}, ultima ? dataCurta(ultima.quando) : 'nenhuma')),
    ...(est.alertasBackup || []).map((a) => el('p', { class: 'erro', role: 'alert' }, a))].filter(Boolean));
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
      m.observacao ? el('div', { class: 'sub', style: 'white-space:pre-wrap' }, 'Observação interna: ' + m.observacao) : null,
      el('div', { class: 'sub' }, m.nome ? 'Nome: ' + m.nome : 'Anônima', m.contato ? ' · Contato: ' + m.contato : ''),
      el('div', { class: 'sub' }, 'Aviso por e-mail: ' + (m.avisoEmail === 'enviado' ? 'enviado' : m.avisoEmail === 'falhou' ? 'falhou' : 'pendente / SMTP não configurado'))),
    el('div', { class: 'acoes' },
      m.status !== 'nova' ? botao('Nova', () => mudarMensagem(m, 'nova'), 'pequeno') : null,
      m.status !== 'emAnalise' ? botao('Em análise', () => mudarMensagem(m, 'emAnalise'), 'pequeno') : null,
      m.status !== 'resolvida' ? botao('Resolvida', () => mudarMensagem(m, 'resolvida'), 'pequeno') : null,
      botao('Observação', () => editarObservacaoMensagem(m), 'pequeno'),
      m.avisoEmail !== 'enviado' ? botao('Tentar e-mail', async () => {
        try { await api('POST', '/api/mensagens/' + m.id + '/avisar'); await carregarMensagens(); }
        catch (e) { mensagem($('resultado-mensagens'), e.message, false); }
      }, 'pequeno') : null)));
  $('lista-mensagens').replaceChildren(...(cartoes.length ? cartoes : [el('p', { class: 'vazio' }, 'Nenhuma mensagem neste filtro.')]));
}
function editarObservacaoMensagem(m) {
  $('observacao-mensagem').value = m.observacao || '';
  abrirDialogo($('dlg-observacao-mensagem'), $('erro-observacao-mensagem'), async () => {
    await api('PUT', '/api/mensagens/' + m.id, { observacao: $('observacao-mensagem').value.trim() });
    await carregarMensagens();
  });
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
      m.observacao ? el('div', { class: 'sub', style: 'white-space:pre-wrap' }, 'Observação interna: ' + m.observacao) : null,
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
  $('m-observacao').value = m ? m.observacao || '' : '';
  $('campo-testemunho').hidden = !(m && m.status === 'atendido');
  abrirDialogo($('dlg-motivo'), $('erro-motivo'), async () => {
    const dados = { para: $('m-para').value.trim(), motivo: $('m-motivo').value.trim(), tipo: $('m-tipo').value, publico: $('m-publico').checked,
      observacao: $('m-observacao').value.trim() };
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
              (h.usuario ? ' · ' + h.usuario : '') + (h.via ? ' · ' + h.via : '')))))
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
let soNovas = false; // filtro "novas em 90 dias", ligado pelo atalho da barra de composição

const STATUS_MEMBRO = {
  visitante: ['Visitante', 'Visitante'],
  congregado: ['Congregado', 'Congregada'],
  membro: ['Membro', 'Membro'],
  inativo: ['Inativo', 'Inativa'],
  transferido: ['Transferido', 'Transferida'],
};
const NOVENTA_DIAS = 90 * 86400000;

const statusValido = (s) => (STATUS_MEMBRO[s] ? s : 'membro');
/** Nome do status concordando com o sexo da pessoa ("Congregada"). */
const rotuloStatus = (s, sexo) => STATUS_MEMBRO[statusValido(s)][sexo === 'F' ? 1 : 0];
const pilulaStatus = (m) => el('span', { class: 'pilula st-' + statusValido(m.status) }, rotuloStatus(m.status, m.sexo));

const semAcento = (s) => (s || '').normalize('NFD').replace(/[̀-ͯ]/g, '');
const normalizado = (s) => semAcento(s).toLowerCase().replace(/\s+/g, ' ').trim();
const soDigitos = (s) => (s || '').replace(/\D/g, '');
const inicialMembro = (m) => m.nome.trim().split(/\s+/).slice(0, 2).map((p) => p[0]).join('').toUpperCase();
const doisDigitos = (n) => String(n).padStart(2, '0');
const aniversarioDe = (m) => doisDigitos(m.dia) + '/' + doisDigitos(m.mes) + (m.ano ? '/' + m.ano : '');
const dataBr = (iso) => (iso ? new Date(iso + 'T00:00:00').toLocaleDateString('pt-BR') : null);
const hojeIso = () => new Date().toLocaleDateString('sv-SE'); // aaaa-mm-dd no fuso local
const ehNova = (m) => m.criadoEm && Date.parse(m.criadoEm) >= Date.now() - NOVENTA_DIAS;

function idadeDe(m) {
  if (!m.ano) return null;
  const hoje = new Date();
  let i = hoje.getFullYear() - m.ano;
  if (hoje.getMonth() + 1 < m.mes || (hoje.getMonth() + 1 === m.mes && hoje.getDate() < m.dia)) i--;
  return i;
}

// ----- Máscaras e validações do formulário -----

function mascaraCpf(v) {
  const d = soDigitos(v).slice(0, 11);
  return d.replace(/^(\d{3})(\d)/, '$1.$2').replace(/^(\d{3})\.(\d{3})(\d)/, '$1.$2.$3').replace(/\.(\d{3})(\d)/, '.$1-$2');
}
function mascaraCep(v) {
  const d = soDigitos(v).slice(0, 8);
  return d.length > 5 ? d.slice(0, 5) + '-' + d.slice(5) : d;
}
function mascaraTelefone(v) {
  const d = soDigitos(v).slice(0, 11);
  if (d.length <= 2) return d.length ? '(' + d : '';
  const meio = d.length === 11 ? 7 : 6;
  return '(' + d.slice(0, 2) + ') ' + d.slice(2, meio) + (d.length > meio ? '-' + d.slice(meio) : '');
}
function mascaraData(v) {
  const d = soDigitos(v).slice(0, 8);
  return [d.slice(0, 2), d.slice(2, 4), d.slice(4)].filter(Boolean).join('/');
}

/** Mesmo cálculo do servidor (Membro.cpfValido): formato e os dois dígitos verificadores. */
function cpfValido(cpf) {
  const d = soDigitos(cpf);
  if (d.length !== 11 || /^(\d)\1{10}$/.test(d)) return false;
  const digito = (n) => {
    let soma = 0;
    for (let i = 0; i < n; i++) soma += Number(d[i]) * (n + 1 - i);
    const r = (soma * 10) % 11;
    return r === 10 ? 0 : r;
  };
  return digito(9) === Number(d[9]) && digito(10) === Number(d[10]);
}

/** "05/03" ou "05/03/1990" → {dia, mes, ano}; null quando a data não existe. */
function lerAniversario(texto) {
  const r = /^(\d{1,2})\/(\d{1,2})(?:\/(\d{4}))?$/.exec((texto || '').trim());
  if (!r) return null;
  const dia = Number(r[1]), mes = Number(r[2]), ano = r[3] ? Number(r[3]) : null;
  const maximo = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (mes < 1 || mes > 12 || dia < 1 || dia > maximo[mes - 1]) return null;
  if (ano != null) {
    if (ano < 1900 || ano > new Date().getFullYear()) return null;
    if (new Date(ano, mes - 1, dia).getDate() !== dia) return null; // 29/02 fora de ano bissexto
  }
  return { dia, mes, ano };
}

/** Telefone em links de contato: "tel:" e WhatsApp (wa.me). Só números brasileiros com DDD. */
function linksTelefone(numero, { ligar = true, whatsapp = false } = {}) {
  let d = soDigitos(numero);
  if (d.length === 13 && d.startsWith('55')) d = d.slice(2);
  if (d.length < 10 || d.length > 11) return [];
  return [
    ligar ? el('a', { href: 'tel:+55' + d }, 'Ligar') : null,
    whatsapp ? el('a', { href: 'https://wa.me/55' + d, target: '_blank', rel: 'noopener' }, 'WhatsApp') : null,
  ].filter(Boolean);
}

for (const [id, mascara] of [['b-cpf', mascaraCpf], ['b-cep', mascaraCep], ['b-telefone', mascaraTelefone],
  ['b-whatsapp', mascaraTelefone], ['b-emerg-telefone', mascaraTelefone], ['b-aniversario', mascaraData]]) {
  $(id).addEventListener('input', (e) => {
    const campo = e.target;
    // Só reformata digitando no fim (não atrapalha quem corrige no meio).
    if (campo.selectionStart === campo.value.length) campo.value = mascara(campo.value);
    campo.setCustomValidity('');
  });
}

for (const id of ['b-aniversario']) {
  $(id).addEventListener('blur', (e) => {
    const campo = e.target;
    if (campo.value && !lerAniversario(campo.value)) {
      campo.setCustomValidity('Data que não existe: confira o dia, o mês e o ano.');
      campo.reportValidity();
    }
  });
}

$('b-cpf').addEventListener('blur', () => {
  const campo = $('b-cpf');
  if (soDigitos(campo.value) && !cpfValido(campo.value)) {
    campo.setCustomValidity('CPF inválido: confira os números.');
    campo.reportValidity();
  }
});

// ----- CEP: preenche o endereço pela ViaCEP -----

let consultaCep = null;
async function buscarCep() {
  const cep = soDigitos($('b-cep').value);
  const aviso = $('b-cep-aviso');
  if (cep.length !== 8) {
    mensagem(aviso, 'Digite os 8 números do CEP.', false);
    return;
  }
  if (consultaCep) consultaCep.abort();
  const controle = (consultaCep = new AbortController());
  const tempo = setTimeout(() => controle.abort(), 8000);
  aviso.className = 'aviso-campo dica';
  aviso.textContent = 'Buscando o endereço…';
  try {
    const r = await fetch('https://viacep.com.br/ws/' + cep + '/json/', { signal: controle.signal });
    const j = await r.json();
    if (!r.ok || j.erro) {
      mensagem(aviso, 'CEP não encontrado. Confira o número ou preencha o endereço à mão.', false);
      return;
    }
    if (j.logradouro) $('b-rua').value = j.logradouro;
    if (j.bairro) $('b-bairro').value = j.bairro;
    if (j.localidade) $('b-cidade').value = j.localidade;
    if (j.uf) garantirOpcao($('b-uf'), j.uf);
    // O "complemento" da ViaCEP é a faixa de números da rua ("de 612 a 1510"), não o da pessoa: fica de fora.
    mensagem(aviso, 'Endereço preenchido pelo CEP. Falta o número.');
    $('b-numero').focus();
  } catch (e) {
    if (controle !== consultaCep) return; // outra consulta tomou o lugar
    mensagem(aviso, 'Não foi possível consultar o CEP agora. Preencha o endereço à mão.', false);
  } finally {
    clearTimeout(tempo);
    if (controle === consultaCep) consultaCep = null;
  }
}
$('b-buscar-cep').addEventListener('click', buscarCep);
$('b-cep').addEventListener('input', () => {
  if (soDigitos($('b-cep').value).length === 8) buscarCep();
  else $('b-cep-aviso').textContent = '';
});
$('b-cep').addEventListener('keydown', (e) => {
  if (e.key === 'Enter') {
    e.preventDefault();
    buscarCep();
  }
});

// ----- Lista -----

async function carregarMembros() {
  [membros] = await Promise.all([api('GET', '/api/membros'), carregarVisitas()]);
  montarFiltroMinisterios();
  renderMembros();
}

function montarFiltroMinisterios() {
  const atual = $('filtro-ministerio-membro').value;
  const todos = [...new Set(membros.flatMap((m) => m.ministerios || []))]
    .sort((a, b) => a.localeCompare(b, 'pt-BR'));
  $('filtro-ministerio-membro').replaceChildren(
    el('option', { value: '' }, 'Todos'),
    ...todos.map((x) => el('option', { value: x }, x)));
  $('filtro-ministerio-membro').value = todos.includes(atual) ? atual : '';
  $('dl-ministerios').replaceChildren(...todos.map((x) => el('option', { value: x })));
}

/** Os filtros da tela, no formato da exportação (o CSV sai com as mesmas pessoas). */
function filtrosMembros() {
  return {
    busca: $('busca-membro').value.trim(),
    status: $('filtro-status-membro').value,
    ministerio: $('filtro-ministerio-membro').value,
    aniversariantes: $('filtro-aniversariantes').checked,
    semConsentimento: $('filtro-sem-consentimento').checked,
    novas: soNovas,
  };
}

function membrosFiltrados() {
  const f = filtrosMembros();
  const busca = normalizado(f.busca);
  const mes = new Date().getMonth() + 1;
  return membros
    .filter((m) => {
      if (f.status === 'ativos' ? !m.ativo : f.status && m.status !== f.status) return false;
      if (f.ministerio && !(m.ministerios || []).includes(f.ministerio)) return false;
      if (f.aniversariantes && (!m.ativo || m.mes !== mes)) return false;
      if (f.semConsentimento && m.consentimentoEm) return false;
      if (f.novas && !ehNova(m)) return false;
      if (busca) {
        const alvo = normalizado([m.nome, m.telefone, m.whatsapp, m.email, m.cidade, m.bairro, m.funcao].filter(Boolean).join(' '));
        if (!alvo.includes(busca)) return false;
      }
      return true;
    })
    .sort((a, b) => a.nome.localeCompare(b.nome, 'pt-BR'));
}

function renderComposicao() {
  const agora = new Date();
  const mes = agora.getMonth() + 1;
  const total = membros.length;
  const atual = $('filtro-status-membro').value;
  const contagem = Object.keys(STATUS_MEMBRO).map((s) => [s, membros.filter((m) => statusValido(m.status) === s).length]);
  const aniversariantes = membros.filter((m) => m.ativo && m.mes === mes).length;
  const novas = membros.filter(ehNova).length;
  const alternarStatus = (s) => {
    $('filtro-status-membro').value = atual === s ? '' : s;
    renderMembros();
  };
  const plural = (n, um, varios) => n + ' ' + (n === 1 ? um : varios);
  if (!total) {
    $('composicao-membros').replaceChildren(
      el('div', { class: 'composicao-topo' }, el('strong', {}, 'Nenhuma pessoa cadastrada'),
        el('span', { class: 'dica' }, 'Use "Nova pessoa" ou "Importar" para começar.')));
    return;
  }
  $('composicao-membros').replaceChildren(
    el('div', { class: 'composicao-topo' },
      el('strong', {}, plural(total, 'pessoa', 'pessoas')),
      el('div', { class: 'atalhos' },
        el('button', { class: 'link', type: 'button', 'aria-pressed': String($('filtro-aniversariantes').checked),
          onclick: () => { $('filtro-aniversariantes').checked = !$('filtro-aniversariantes').checked; renderMembros(); } },
        plural(aniversariantes, 'aniversariante', 'aniversariantes') + ' em ' + agora.toLocaleDateString('pt-BR', { month: 'long' })),
        el('button', { class: 'link', type: 'button', 'aria-pressed': String(soNovas),
          onclick: () => { soNovas = !soNovas; renderMembros(); } },
        plural(novas, 'nova', 'novas') + ' em 90 dias'),
        aContatar().length ? el('button', { class: 'link', type: 'button', onclick: abrirAcompanhamento },
          plural(aContatar().length, 'visitante a contatar', 'visitantes a contatar')) : null)),
    el('div', { class: 'barra-status', role: 'group', 'aria-label': 'Pessoas por status (clique para filtrar)' },
      ...contagem.filter(([, n]) => n).map(([s, n]) => el('button', {
        type: 'button', class: 'st-' + s, style: 'flex-grow:' + n, title: STATUS_MEMBRO[s][0] + ': ' + n,
        'aria-label': STATUS_MEMBRO[s][0] + ': ' + n, 'aria-pressed': String(atual === s), onclick: () => alternarStatus(s),
      }))),
    el('div', { class: 'legenda-status' },
      ...contagem.filter(([, n]) => n).map(([s, n]) => el('button', {
        type: 'button', class: 'st-' + s, 'aria-pressed': String(atual === s), onclick: () => alternarStatus(s),
      }, STATUS_MEMBRO[s][0] + (n === 1 ? '' : 's') + ' ' + n))));
}

function renderMembros() {
  renderComposicao();
  const lista = membrosFiltrados();
  const avisos = [];
  if (soNovas) avisos.push('cadastradas nos últimos 90 dias');
  $('resultado-membros').className = 'dica';
  $('resultado-membros').replaceChildren(...(avisos.length
    ? ['Mostrando só pessoas ' + avisos.join(', ') + '. ', el('button', { class: 'link', type: 'button', onclick: () => { soNovas = false; renderMembros(); } }, 'Mostrar todas')]
    : []));
  $('lista-membros').replaceChildren(
    ...(lista.length ? lista.map(cardMembro) : [el('p', { class: 'vazio' }, membros.length ? 'Ninguém neste filtro.' : '')]));
  hidratarFotos($('lista-membros'));
}

/** Coloca a miniatura (atrás de login) nos <img data-foto-id>; sem foto, ficam as iniciais. */
function hidratarFotos(container, { grande = false } = {}) {
  for (const img of container.querySelectorAll('img[data-foto-id]')) {
    const m = membros.find((x) => x.id === img.dataset.fotoId);
    if (!m || !m.foto) continue;
    urlAutenticada(`/api/membros/${m.id}/${grande ? 'foto' : 'foto-miniatura'}?v=${encodeURIComponent(m.atualizadoEm || m.foto)}`)
      .then((url) => {
        if (!url || !img.isConnected) return;
        img.src = url;
        img.hidden = false;
        if (img.previousElementSibling) img.previousElementSibling.hidden = true;
      })
      .catch(() => {});
  }
}

function contatoRapido(m) {
  const whatsapp = m.whatsapp || (soDigitos(m.telefone).length === 11 ? m.telefone : null);
  const links = [
    ...(m.telefone ? linksTelefone(m.telefone) : []),
    ...(whatsapp ? linksTelefone(whatsapp, { ligar: !m.telefone, whatsapp: true }) : []),
    m.email ? el('a', { href: 'mailto:' + m.email }, 'E-mail') : null,
  ].filter(Boolean);
  return links.length ? el('div', { class: 'contato-rapido' }, ...links) : null;
}

function cardMembro(m) {
  const abrir = () => abrirFicha(m.id);
  const mins = m.ministerios || [];
  const idade = idadeDe(m);
  return el('article', {
    class: 'membro-card' + (m.ativo ? '' : ' inativo'),
    onclick: (e) => { if (!e.target.closest('a, button')) abrir(); },
  },
  el('div', { class: 'foto', 'aria-hidden': 'true' },
    el('span', {}, inicialMembro(m)),
    el('img', { 'data-foto-id': m.id, alt: '', hidden: true, loading: 'lazy' })),
  el('div', { class: 'conteudo' },
    el('div', { class: 'linha-nome' },
      el('button', { class: 'titulo', type: 'button', onclick: abrir, 'aria-label': 'Abrir a ficha de ' + m.nome }, m.nome),
      pilulaStatus(m)),
    el('span', { class: 'sub' }, [aniversarioDe(m), idade != null ? idade + ' anos' : null].filter(Boolean).join(' · ')),
    mins.length ? el('span', { class: 'sub' }, mins.slice(0, 3).join(', ') + (mins.length > 3 ? ` +${mins.length - 3}` : '')) : null,
    contatoRapido(m)));
}

// ----- Ficha (todos os dados + família com links) -----

let fichaAberta = null;

function abrirFicha(id) {
  const m = membros.find((x) => x.id === id);
  if (!m) return;
  fichaAberta = m;
  const linkMembro = (o) => o ? el('button', { class: 'link', type: 'button', onclick: () => abrirFicha(o.id) }, o.nome) : null;
  const par = (rotulo, ...valores) => {
    const v = valores.flat().filter((x) => x != null && x !== '');
    return v.length ? el('div', { class: 'ficha-par' }, el('span', { class: 'rotulo' }, rotulo), el('span', { class: 'valor' }, ...v)) : null;
  };
  const juntar = (itens) => itens.flatMap((l, i) => (i ? [', ', l] : [l]));
  /** Documento oculto por padrão: só os dígitos do meio, com botão "Mostrar". */
  const oculto = (valor, mascarar) => {
    if (!valor) return null;
    const texto = el('span', {}, mascarar(valor));
    const b = el('button', { class: 'link', type: 'button', style: 'margin-left:10px' }, 'Mostrar');
    b.addEventListener('click', () => {
      const mostrando = b.textContent === 'Ocultar';
      texto.textContent = mostrando ? mascarar(valor) : (valor.length === 11 && /^\d+$/.test(valor) ? mascaraCpf(valor) : valor);
      b.textContent = mostrando ? 'Mostrar' : 'Ocultar';
    });
    return [texto, b];
  };
  const conjuge = m.conjugeId ? membros.find((x) => x.id === m.conjugeId) : null;
  const pais = (m.paisIds || []).map((pid) => membros.find((x) => x.id === pid)).filter(Boolean);
  const filhos = membros.filter((x) => (x.paisIds || []).includes(m.id));
  const idade = idadeDe(m);
  const endereco = [
    m.rua ? [m.rua, m.numero].filter(Boolean).join(', ') : null,
    m.complemento, [m.bairro, m.cidade, m.estado].filter(Boolean).join(' — '),
    m.cep ? 'CEP ' + mascaraCep(m.cep) : null,
  ].filter(Boolean);
  const historico = m.historicoStatus || [];
  const linhaTempo = historico.length
    ? el('span', { class: 'linha-tempo' }, ...historico.flatMap((h, i) => [
      i ? el('span', { class: 'seta', 'aria-hidden': 'true' }, '→') : null,
      el('span', {}, pilulaStatus({ status: h.status, sexo: m.sexo }),
        el('small', {}, new Date(h.em).toLocaleDateString('pt-BR', { month: '2-digit', year: 'numeric' }))),
    ]))
    : null;

  // replaceChildren escreveria "null" para os campos vazios: só entram as linhas com valor.
  $('ficha-conteudo').replaceChildren(...[
    el('div', { class: 'ficha-topo' },
      el('div', { class: 'avatar' }, el('span', {}, inicialMembro(m)),
        el('img', { 'data-foto-id': m.id, alt: 'Foto de ' + m.nome, hidden: true })),
      el('div', {},
        el('h2', { style: 'font-size:24px;margin:0 0 4px' }, m.nome),
        pilulaStatus(m),
        idade != null ? el('span', { class: 'dica', style: 'margin-left:8px' }, idade + ' anos') : null)),
    par('Aniversário', aniversarioDe(m)),
    par('Sexo', m.sexo === 'M' ? 'Masculino' : m.sexo === 'F' ? 'Feminino' : null),
    par('Estado civil', m.estadoCivil),
    par('Telefone', m.telefone ? [mascaraTelefone(m.telefone) + '  ', ...linksTelefone(m.telefone, { ligar: true, whatsapp: !m.whatsapp })] : null),
    par('WhatsApp', m.whatsapp ? [mascaraTelefone(m.whatsapp) + '  ', ...linksTelefone(m.whatsapp, { ligar: false, whatsapp: true })] : null),
    par('E-mail', m.email ? el('a', { href: 'mailto:' + m.email }, m.email) : null),
    par('Endereço', endereco.length ? endereco.join('\n') : null),
    par('CPF', oculto(m.cpf, (v) => '***.' + v.slice(3, 6) + '.' + v.slice(6, 9) + '-**')),
    par('RG', oculto(m.rg, (v) => '*'.repeat(Math.max(0, v.length - 3)) + v.slice(-3))),
    par('Histórico', linhaTempo),
    par('Chegou em', dataBr(m.dataChegada)), par('Batismo', dataBr(m.dataBatismo)), par('Membresia', dataBr(m.dataMembresia)),
    par('Como conheceu', m.comoConheceu),
    par('Ministérios', (m.ministerios || []).join(', ') || null), par('Função', m.funcao),
    par('Cônjuge', linkMembro(conjuge)),
    pais.length ? par('Pais', juntar(pais.map(linkMembro))) : null,
    filhos.length ? par('Filhos', juntar(filhos.map(linkMembro))) : null,
    par('Emergência', [m.emergenciaNome, m.emergenciaVinculo, m.emergenciaTelefone].filter(Boolean).join(' · ')),
    par('Observações', m.observacoes),
    par('Visitas', blocoVisitas(m)),
    par('LGPD', blocoLgpd(m)),
  ].filter(Boolean));

  hidratarFotos($('ficha-conteudo'), { grande: true });
  if (!$('dlg-ficha').open) $('dlg-ficha').showModal();
  $('ficha-conteudo').scrollTop = 0;
}

// ----- LGPD: autorização pelo link, termo assinado ou recepção -----

const VIA_LGPD = {
  manual: 'registrada pela secretaria',
  link: 'pela própria pessoa, no link enviado',
  termo: 'termo impresso e assinado',
  recepcao: 'pela própria pessoa, no QR da recepção',
};
const dataHoraBr = (iso) => new Date(iso).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' });

let termoLgpd = null; // {versao, texto, igreja}, carregado na primeira vez que precisa
async function carregarTermoLgpd() {
  if (!termoLgpd) termoLgpd = await api('GET', '/api/membros/termo-lgpd');
  return termoLgpd;
}

/** Situação da autorização, a prova registrada e as ações (link, termo, revogação). */
function blocoLgpd(m) {
  const reg = m.consentimentoRegistro || {};
  const linhas = [];
  if (m.consentimentoEm) {
    linhas.push(el('div', {}, el('strong', {}, 'Autorizou em ' + dataBr(m.consentimentoEm)),
      ' — ' + (VIA_LGPD[m.consentimentoVia] || 'registro sem detalhes')));
    const prova = [
      reg.em ? 'registrado em ' + dataHoraBr(reg.em) : null,
      reg.versaoTermo ? 'termo versão ' + reg.versaoTermo : null,
      reg.por ? 'por ' + reg.por : null,
      reg.linkGeradoPor ? 'link enviado por ' + reg.linkGeradoPor : null,
      reg.ip ? 'IP ' + reg.ip : null,
    ].filter(Boolean);
    if (prova.length) linhas.push(el('div', { class: 'dica' }, prova.join(' · ')));
    if (reg.responsavel) linhas.push(el('div', { class: 'dica' }, 'Responsável que autorizou: ' + reg.responsavel));
  } else {
    linhas.push(el('div', { class: 'erro' }, 'Sem autorização registrada'));
  }
  if (m.consentimentoRevogado) {
    linhas.push(el('div', { class: 'dica' }, 'Revogada em ' + dataHoraBr(m.consentimentoRevogado.em)
      + (m.consentimentoRevogado.por ? ' por ' + m.consentimentoRevogado.por : '')));
  }
  if (m.linkLgpdValidoAte && !m.consentimentoEm) {
    linhas.push(el('div', { class: 'dica' }, 'Link enviado, aguardando a pessoa. Vale até ' + dataHoraBr(m.linkLgpdValidoAte) + '.'));
  }
  const acoes = el('div', { class: 'contato-rapido' },
    botao(m.linkLgpdValidoAte ? 'Gerar novo link' : 'Enviar link', () => enviarLinkLgpd(m)),
    botao('Imprimir termo', () => imprimirTermo(m)),
    botao(m.termoAssinado ? 'Trocar termo assinado' : 'Anexar termo assinado', () => anexarTermo(m)),
    m.termoAssinado ? botao('Ver termo assinado', () => verTermoAssinado(m)) : null,
    m.consentimentoEm ? botao('Registrar revogação', () => revogarLgpd(m), 'perigo pequeno') : null);
  return el('div', {}, ...linhas, acoes);
}

/** Recarrega a lista e mostra a ficha atualizada (depois de uma ação da LGPD). */
async function atualizarFicha(id) {
  await carregarMembros();
  if ($('dlg-ficha').open) abrirFicha(id);
}

let mensagemLinkLgpd = '';
async function enviarLinkLgpd(m) {
  try {
    const [r, termo] = await Promise.all([api('POST', `/api/membros/${m.id}/lgpd/link`), carregarTermoLgpd()]);
    const primeiroNome = m.nome.trim().split(/\s+/)[0];
    mensagemLinkLgpd = `Olá, ${primeiroNome}! A ${termo.igreja} pede a sua autorização para guardar os seus dados de cadastro `
      + `(Lei Geral de Proteção de Dados). Leia e confirme por este link, válido por 7 dias: ${r.url}`;
    $('link-lgpd-intro').textContent = `Envie para ${m.nome}. A pessoa lê o termo, vê quais dados a igreja guarda e confirma; `
      + 'a data, a hora e a versão do termo ficam registradas na ficha.';
    $('link-lgpd-url').value = r.url;
    $('link-lgpd-resultado').textContent = '';
    const whatsapp = soDigitos(m.whatsapp || m.telefone);
    const numero = whatsapp.length === 10 || whatsapp.length === 11 ? '55' + whatsapp : '';
    $('whatsapp-link-lgpd').href = `https://wa.me/${numero}?text=${encodeURIComponent(mensagemLinkLgpd)}`;
    $('whatsapp-link-lgpd').textContent = numero ? 'Enviar pelo WhatsApp' : 'Abrir no WhatsApp';
    $('dlg-link-lgpd').showModal();
    atualizarFicha(m.id);
  } catch (e) {
    mensagem($('resultado-membros'), e.message, false);
  }
}
$('fechar-link-lgpd').addEventListener('click', () => $('dlg-link-lgpd').close());
$('copiar-link-lgpd').addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText(mensagemLinkLgpd);
    mensagem($('link-lgpd-resultado'), 'Mensagem copiada. Cole no WhatsApp ou no e-mail.');
  } catch (e) {
    $('link-lgpd-url').select();
    mensagem($('link-lgpd-resultado'), 'Não deu para copiar sozinho: o link está selecionado, use Ctrl+C.', false);
  }
});

async function imprimirTermo(m) {
  let termo;
  try {
    termo = await carregarTermoLgpd();
  } catch (e) {
    mensagem($('resultado-membros'), e.message, false);
    return;
  }
  const idade = idadeDe(m);
  const dados = [
    'Nome: ' + m.nome,
    'Data de nascimento: ' + aniversarioDe(m),
    m.cpf ? 'CPF: ' + mascaraCpf(m.cpf) : null,
  ].filter(Boolean);
  $('impressao-membros').replaceChildren(
    el('h1', {}, 'Termo de autorização de uso de dados pessoais'),
    el('p', {}, termo.igreja + ' · versão ' + termo.versao + ' do termo'),
    ...dados.map((d) => el('p', { class: 'termo-dados' }, d)),
    el('div', { class: 'termo-texto' }, termo.texto),
    el('p', { class: 'termo-dados' }, 'Local e data: ______________________________, ____/____/________'),
    el('div', { class: 'assinatura' }, 'Assinatura de ' + m.nome),
    idade == null || idade < 18
      ? el('div', { class: 'assinatura' }, 'Nome e assinatura do pai, mãe ou responsável (se menor de 18 anos)')
      : null);
  window.print();
}

function anexarTermo(m) {
  $('termo-intro').textContent = `Foto ou PDF do termo de ${m.nome}, impresso pelo botão "Imprimir termo" e assinado. `
    + 'Substitui o termo anexado antes, se houver.';
  $('t-arquivo').value = '';
  $('t-data').value = hojeIso();
  $('t-data').max = hojeIso();
  $('t-responsavel').value = '';
  abrirDialogo($('dlg-termo'), $('erro-termo'), async () => {
    const arquivo = $('t-arquivo').files[0];
    if (!arquivo) throw new Error('Escolha a foto ou o PDF do termo assinado.');
    const termo = await carregarTermoLgpd();
    const qs = new URLSearchParams({ data: $('t-data').value, responsavel: $('t-responsavel').value.trim(), versao: termo.versao });
    await api('POST', `/api/membros/${m.id}/lgpd/termo?${qs}`, arquivo, { bruto: true, tipo: arquivo.type || 'application/octet-stream' });
    await atualizarFicha(m.id);
  });
}

async function verTermoAssinado(m) {
  // Abre a aba antes do fetch (senão o navegador bloqueia como pop-up) e depois aponta para o arquivo.
  const aba = window.open('', '_blank');
  try {
    const url = await urlAutenticada(`/api/membros/${m.id}/lgpd/termo?v=${encodeURIComponent(m.termoAssinado)}`);
    if (!url) throw new Error('Termo assinado não encontrado.');
    if (aba) aba.location = url;
    else window.location.assign(url);
  } catch (e) {
    if (aba) aba.close();
    mensagem($('resultado-membros'), e.message, false);
  }
}

async function revogarLgpd(m) {
  if (!confirm(`Registrar que ${m.nome} retirou a autorização de uso dos dados?\n\n`
    + 'O termo assinado anexado (se houver) será apagado. Os dados do cadastro continuam: '
    + 'se a pessoa pediu para apagá-los, exclua o cadastro depois.')) return;
  try {
    await api('POST', `/api/membros/${m.id}/lgpd/revogar`);
    await atualizarFicha(m.id);
  } catch (e) {
    mensagem($('resultado-membros'), e.message, false);
  }
}

$('fechar-ficha').addEventListener('click', () => $('dlg-ficha').close());
$('editar-da-ficha').addEventListener('click', () => {
  $('dlg-ficha').close();
  if (fichaAberta) editarMembro(fichaAberta);
});
$('excluir-da-ficha').addEventListener('click', async () => {
  if (!fichaAberta) return;
  if (await excluirMembro(fichaAberta)) $('dlg-ficha').close();
});

// ----- Editar / criar -----

/** Garante que um valor salvo aparece no select, mesmo fora das opções padrão. */
function garantirOpcao(sel, valor) {
  if (valor && ![...sel.options].some((o) => o.value === valor)) sel.append(el('option', {}, valor));
  sel.value = valor || '';
}

/** Rótulo único de cada pessoa nos campos de família ("Ana Souza (05/03)") → id. */
let pessoasPorRotulo = new Map();
const rotuloDe = (id) => [...pessoasPorRotulo].find(([, v]) => v === id)?.[0] || '';

function montarPessoas(m) {
  pessoasPorRotulo = new Map();
  const outros = membros.filter((x) => !m || x.id !== m.id).sort((a, b) => a.nome.localeCompare(b.nome, 'pt-BR'));
  const opcoes = [];
  for (const x of outros) {
    let rotulo = `${x.nome} (${doisDigitos(x.dia)}/${doisDigitos(x.mes)})`;
    for (let n = 2; pessoasPorRotulo.has(rotulo); n++) rotulo = `${x.nome} (${doisDigitos(x.dia)}/${doisDigitos(x.mes)}) ${n}`;
    pessoasPorRotulo.set(rotulo, x.id);
    const conj = x.conjugeId && x.conjugeId !== m?.id ? membros.find((y) => y.id === x.conjugeId) : null;
    opcoes.push(el('option', { value: rotulo, label: conj ? 'cônjuge de ' + conj.nome : rotuloStatus(x.status, x.sexo) }));
  }
  $('dl-pessoas').replaceChildren(...opcoes);
  $('b-conjuge').value = rotuloDe(m?.conjugeId);
  $('b-pai-1').value = rotuloDe(m?.paisIds?.[0]);
  $('b-pai-2').value = rotuloDe(m?.paisIds?.[1]);
}

/** Id da pessoa escolhida num campo de família; erro se o texto não for da lista. */
function pessoaDoCampo(id, nomeCampo) {
  const texto = $(id).value.trim();
  if (!texto) return null;
  const achado = pessoasPorRotulo.get(texto);
  if (!achado) {
    mostrarSecao('familia');
    $(id).focus();
    throw new Error(`${nomeCampo}: escolha um nome da lista (digite parte do nome e clique na pessoa).`);
  }
  return achado;
}

function avisoConjuge(m) {
  const aviso = $('b-conjuge-aviso');
  const id = pessoasPorRotulo.get($('b-conjuge').value.trim());
  const escolhido = id && membros.find((x) => x.id === id);
  const atualDele = escolhido && escolhido.conjugeId && escolhido.conjugeId !== m?.id
    ? membros.find((x) => x.id === escolhido.conjugeId) : null;
  aviso.hidden = !atualDele;
  aviso.textContent = atualDele
    ? `${escolhido.nome} está ligado(a) a ${atualDele.nome} como cônjuge. Ao salvar, esse vínculo será desfeito.` : '';
  return atualDele ? { escolhido, atualDele } : null;
}

/** Outra pessoa com o mesmo nome (sem acento/maiúsculas): aviso com link para a ficha. */
function avisoDuplicado(campoNome, avisoEl, idAtual, fechar) {
  const nome = normalizado(campoNome.value);
  const igual = nome.length >= 3 && membros.find((x) => x.id !== idAtual && normalizado(x.nome) === nome);
  avisoEl.hidden = !igual;
  avisoEl.replaceChildren(...(igual ? [
    `Já existe ${igual.nome} (${aniversarioDe(igual)}). `,
    el('button', { class: 'link', type: 'button', onclick: () => { if (fechar()) abrirFicha(igual.id); } }, 'Abrir a ficha'),
  ] : []));
}

// Abas do formulário: um campo inválido numa aba escondida leva até ela.
function mostrarSecao(nome) {
  for (const b of document.querySelectorAll('#form-membro .abas-form button')) b.setAttribute('aria-selected', String(b.dataset.secao === nome));
  for (const p of document.querySelectorAll('#form-membro [role=tabpanel]')) p.hidden = p.dataset.secao !== nome;
}
for (const b of document.querySelectorAll('#form-membro .abas-form button')) b.addEventListener('click', () => mostrarSecao(b.dataset.secao));
$('form-membro').addEventListener('invalid', (e) => {
  const painel = e.target.closest('[role=tabpanel]');
  if (!painel) return;
  $('aba-b-' + painel.dataset.secao).classList.add('com-erro');
  if (painel.hidden) {
    mostrarSecao(painel.dataset.secao);
    requestAnimationFrame(() => e.target.reportValidity());
  }
}, true);
$('form-membro').addEventListener('input', (e) => {
  const painel = e.target.closest('[role=tabpanel]');
  if (painel && !painel.querySelector(':invalid')) $('aba-b-' + painel.dataset.secao).classList.remove('com-erro');
});

// Alterações não salvas: Cancelar e Esc perguntam antes de descartar.
let estadoInicialForm = '';
const estadoForm = () => JSON.stringify([...$('form-membro').querySelectorAll('input:not([type=file]), select, textarea')]
  .map((c) => c.value)) + (fotoPendente ? '+foto' : '') + (removerFoto ? '-foto' : '');
function fecharFormulario() {
  if (estadoForm() !== estadoInicialForm && !confirm('Descartar as alterações feitas nesta ficha?')) return false;
  $('dlg-membro').close();
  return true;
}
$('cancelar-membro').addEventListener('click', fecharFormulario);
$('dlg-membro').addEventListener('cancel', (e) => {
  e.preventDefault();
  fecharFormulario();
});

let membroEmEdicao = null; // o registro que o formulário edita (vira o criado depois do primeiro salvar)
const DICA_CONSENTIMENTO = $('b-consentimento-dica').textContent.replace(/\s+/g, ' ').trim();
$('b-nome').addEventListener('input', () => avisoDuplicado($('b-nome'), $('b-nome-aviso'), membroEmEdicao?.id, fecharFormulario));
$('b-conjuge').addEventListener('input', () => avisoConjuge(membroEmEdicao));

function editarMembro(m) {
  membroEmEdicao = m;
  $('titulo-membro').textContent = m ? 'Editar: ' + m.nome : 'Nova pessoa';
  mostrarSecao('pessoal');
  for (const b of document.querySelectorAll('#form-membro .abas-form button')) b.classList.remove('com-erro');
  for (const c of $('form-membro').querySelectorAll('input, select, textarea')) c.setCustomValidity('');
  montarPessoas(m);
  $('b-nome').value = m ? m.nome : '';
  $('b-aniversario').value = m ? aniversarioDe(m) : '';
  $('b-sexo').value = m?.sexo || '';
  garantirOpcao($('b-estado-civil'), m?.estadoCivil);
  $('b-telefone').value = m?.telefone ? mascaraTelefone(m.telefone) : '';
  $('b-whatsapp').value = m?.whatsapp ? mascaraTelefone(m.whatsapp) : '';
  $('b-email').value = m?.email || '';
  $('b-cep').value = m?.cep ? mascaraCep(m.cep) : '';
  $('b-cep-aviso').textContent = '';
  $('b-rua').value = m?.rua || '';
  $('b-numero').value = m?.numero || '';
  $('b-complemento').value = m?.complemento || '';
  $('b-bairro').value = m?.bairro || '';
  $('b-cidade').value = m?.cidade || '';
  garantirOpcao($('b-uf'), m?.estado);
  $('b-cpf').value = m?.cpf ? mascaraCpf(m.cpf) : '';
  $('b-rg').value = m?.rg || '';
  $('b-consentimento').value = m?.consentimentoEm || '';
  $('b-consentimento').max = hojeIso();
  // Autorização dada pela própria pessoa (link, termo, recepção) é prova: não se edita à mão.
  const viaPropria = m?.consentimentoEm && m.consentimentoVia && m.consentimentoVia !== 'manual';
  $('b-consentimento').disabled = !!viaPropria;
  $('b-consentimento-dica').textContent = viaPropria
    ? `Autorizado ${VIA_LGPD[m.consentimentoVia]}. Não dá para mudar aqui; para desfazer, use "Registrar revogação" na ficha.`
    : DICA_CONSENTIMENTO;
  $('b-status').value = m ? statusValido(m.status) : 'membro';
  $('b-chegada').value = m?.dataChegada || '';
  $('b-batismo').value = m?.dataBatismo || '';
  $('b-membresia').value = m?.dataMembresia || '';
  $('b-ministerios').value = (m?.ministerios || []).join(', ');
  $('b-funcao').value = m?.funcao || '';
  $('b-como-conheceu').value = m?.comoConheceu || '';
  $('b-emerg-nome').value = m?.emergenciaNome || '';
  $('b-emerg-telefone').value = m?.emergenciaTelefone ? mascaraTelefone(m.emergenciaTelefone) : '';
  $('b-emerg-vinculo').value = m?.emergenciaVinculo || '';
  $('b-observacoes').value = m?.observacoes || '';
  $('b-nome-aviso').hidden = true;
  avisoConjuge(m);

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
  estadoInicialForm = estadoForm();

  abrirDialogo($('dlg-membro'), $('erro-membro'), async () => {
    const atual = membroEmEdicao;
    const aniversario = lerAniversario($('b-aniversario').value);
    if (!aniversario) {
      mostrarSecao('pessoal');
      throw new Error('Aniversário: use dd/mm ou dd/mm/aaaa com uma data que exista.');
    }
    if (soDigitos($('b-cpf').value) && !cpfValido($('b-cpf').value)) {
      mostrarSecao('pessoal');
      throw new Error('CPF inválido: confira os números.');
    }
    const conjugeId = pessoaDoCampo('b-conjuge', 'Cônjuge');
    const paisIds = [...new Set([pessoaDoCampo('b-pai-1', 'Pai/mãe'), pessoaDoCampo('b-pai-2', 'Pai/mãe')].filter(Boolean))];
    const troca = conjugeId !== (atual?.conjugeId || null) ? avisoConjuge(atual) : null;
    if (troca && !confirm(`${troca.escolhido.nome} hoje é cônjuge de ${troca.atualDele.nome}. Desfazer esse vínculo e ligar a esta pessoa?`)) {
      mostrarSecao('familia');
      throw new Error('Cônjuge não alterado. Escolha outra pessoa ou confirme a troca.');
    }
    const texto = (id) => $(id).value.trim() || null;
    const dados = {
      nome: $('b-nome').value.trim(),
      dia: aniversario.dia,
      mes: aniversario.mes,
      ano: aniversario.ano,
      sexo: $('b-sexo').value || null,
      estadoCivil: $('b-estado-civil').value || null,
      cpf: soDigitos($('b-cpf').value) || null,
      rg: texto('b-rg'),
      telefone: texto('b-telefone'),
      whatsapp: texto('b-whatsapp'),
      email: texto('b-email'),
      cep: soDigitos($('b-cep').value) || null,
      rua: texto('b-rua'),
      numero: texto('b-numero'),
      complemento: texto('b-complemento'),
      bairro: texto('b-bairro'),
      cidade: texto('b-cidade'),
      estado: $('b-uf').value || null,
      status: $('b-status').value,
      dataChegada: $('b-chegada').value || null,
      dataBatismo: $('b-batismo').value || null,
      dataMembresia: $('b-membresia').value || null,
      // Campo bloqueado (autorização da própria pessoa) não vai no corpo: o servidor mantém a prova.
      consentimentoEm: $('b-consentimento').disabled ? undefined : $('b-consentimento').value || null,
      ministerios: $('b-ministerios').value.split(',').map((s) => s.trim()).filter(Boolean),
      funcao: texto('b-funcao'),
      comoConheceu: texto('b-como-conheceu'),
      conjugeId,
      paisIds,
      emergenciaNome: texto('b-emerg-nome'),
      emergenciaTelefone: texto('b-emerg-telefone'),
      emergenciaVinculo: texto('b-emerg-vinculo'),
      observacoes: texto('b-observacoes'),
    };
    const salvo = atual ? await api('PUT', '/api/membros/' + atual.id, dados) : await api('POST', '/api/membros', dados);
    // Daqui em diante o formulário edita o registro salvo: se a foto falhar, salvar de novo não duplica a pessoa.
    membroEmEdicao = salvo;
    $('titulo-membro').textContent = 'Editar: ' + salvo.nome;
    if (fotoPendente) {
      await api('POST', '/api/membros/' + salvo.id + '/foto', fotoPendente,
        { bruto: true, tipo: fotoPendente.type || 'application/octet-stream' });
      fotoPendente = null;
    } else if (removerFoto && atual && atual.foto) {
      await api('DELETE', '/api/membros/' + atual.id + '/foto');
      removerFoto = false;
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
  if (!confirm(`Excluir ${m.nome}? A foto e os vínculos de família também saem.`)) return false;
  try {
    await api('DELETE', '/api/membros/' + m.id);
    await carregarMembros();
    return true;
  } catch (e) {
    mensagem($('resultado-membros'), e.message, false);
    return false;
  }
}

// ----- Visitantes: cadastro completo, visitas na ficha e acompanhamento pós-visita -----

let visitas = []; // todas as visitas (para a ficha e o acompanhamento), carregadas junto com os membros
const INTERESSE_ROTULO = { visitaPastoral: 'Quer visita', oracao: 'Quer oração', batismo: 'Batismo', celula: 'Grupo/célula' };
const ORIGEM_VISITA = { qr: 'pelo QR', recepcao: 'na recepção', painel: 'pelo painel' };
const CONTATO_ROTULO = { aContatar: 'A contatar', contatado: 'Contatado', semResposta: 'Sem resposta' };
const dataVisitaBr = (iso) => iso.split('-').reverse().join('/');

async function carregarVisitas() {
  visitas = pode('visitantes') ? await api('GET', '/api/visitas?desde=2000-01-01') : [];
}

/** Visitas dos últimos 30 dias ainda sem contato concluído. */
function aContatar() {
  const desde = diaIso(new Date(Date.now() - 30 * 86400000));
  return visitas.filter((v) => v.data >= desde && (v.contato || 'aContatar') !== 'contatado');
}

const pilulaInteresse = (i) => el('span', { class: 'pilula st-visitante', style: 'margin-right:4px' }, INTERESSE_ROTULO[i] || i);

/** Linhas da ficha: cada visita com a origem, se foi citada, interesses e o contato. */
function blocoVisitas(m) {
  const dela = visitas.filter((v) => v.membroId === m.id);
  if (!dela.length) return null;
  return el('div', {}, ...dela.map((v) => el('div', { style: 'margin-bottom:6px' },
    el('strong', {}, dataVisitaBr(v.data)), ' · ' + (v.primeiraVez ? '1ª visita' : 'voltou') + ' · ' + (ORIGEM_VISITA[v.origem] || '')
      + (v.registradoPor ? ' (' + v.registradoPor + ')' : '')
      + ' · ' + (!v.mencionar ? 'não quis ser citado' : v.mencionadaEm ? 'citado no culto' : 'pode ser citado'),
    (v.interesses || []).length ? el('div', {}, ...v.interesses.map(pilulaInteresse)) : null,
    v.contato && v.contato !== 'aContatar'
      ? el('div', { class: 'dica' }, CONTATO_ROTULO[v.contato] + (v.contatoPor ? ' por ' + v.contatoPor : '') + (v.contatoNota ? ': ' + v.contatoNota : ''))
      : null)));
}

let formVisitantePainel = null;
$('novo-visitante').addEventListener('click', async () => {
  const termo = await carregarTermoLgpd().catch(() => null);
  if (!formVisitantePainel) {
    formVisitantePainel = montarFormVisitante($('form-visitante-painel'), {
      termo,
      exigirAutorizacao: false,
      textoAutorizo: 'A pessoa leu (ou ouviu) o termo e autorizou o uso dos dados. Se não autorizou agora, deixe desmarcado e envie o link depois, pela ficha.',
      textoBotao: 'Cadastrar visitante',
      enviar: (corpo) => api('POST', '/api/visitas', corpo),
      async aoConcluir(r) {
        $('dlg-visitante').close();
        await carregarMembros();
        const pessoas = r.pessoas || [];
        mensagem($('resultado-membros'), (pessoas.length > 1 ? 'Cadastrados: ' : 'Cadastrado: ')
          + pessoas.map((p) => p.nome + (p.primeiraVez ? '' : ' (voltou)')).join(', ') + '.');
      },
    });
  } else {
    formVisitantePainel.limpar();
  }
  $('dlg-visitante').showModal();
});
$('fechar-visitante').addEventListener('click', () => $('dlg-visitante').close());

// Acompanhamento: quem visitou nos últimos 30 dias e ainda não recebeu contato.
async function abrirAcompanhamento() {
  await carregarTermoLgpd().catch(() => null);
  renderAcompanhamento();
  if (!$('dlg-acompanhamento').open) $('dlg-acompanhamento').showModal();
}
$('fechar-acompanhamento').addEventListener('click', () => $('dlg-acompanhamento').close());
for (const r of document.querySelectorAll('input[name=filtro-acomp]')) r.addEventListener('change', renderAcompanhamento);

function renderAcompanhamento() {
  const todos = document.querySelector('input[name=filtro-acomp]:checked').value === 'todos';
  const desde = diaIso(new Date(Date.now() - 30 * 86400000));
  const lista = todos ? visitas.filter((v) => v.data >= desde) : aContatar();
  $('lista-acompanhamento').replaceChildren(...(lista.length ? lista.map(itemAcompanhamento)
    : [el('p', { class: 'vazio' }, todos ? 'Nenhuma visita nos últimos 30 dias.' : 'Ninguém para contatar.')]));
}

function itemAcompanhamento(v) {
  const m = membros.find((x) => x.id === v.membroId);
  const primeiroNome = v.nome.trim().split(/\s+/)[0];
  const quando = v.data === diaIso(new Date()) ? 'hoje' : 'no dia ' + dataVisitaBr(v.data).slice(0, 5);
  const texto = `Olá, ${primeiroNome}! Aqui é da ${termoLgpd ? termoLgpd.igreja : 'igreja'}. Obrigado pela sua visita ${quando}! `
    + 'Foi uma alegria ter você com a gente. Se precisar de qualquer coisa, é só responder esta mensagem.';
  const fone = soDigitos(m && (m.whatsapp || m.telefone));
  const nota = el('input', { type: 'text', maxlength: '500', placeholder: 'Anotação (opcional)', value: v.contatoNota || '',
    'aria-label': 'Anotação sobre o contato com ' + v.nome, style: 'flex:1;min-width:160px;padding:8px 12px' });
  const salvar = (status) => async () => {
    try {
      await api('PUT', `/api/visitas/${v.id}/contato`, { status, nota: nota.value.trim() });
      await carregarVisitas();
      renderAcompanhamento();
      renderMembros();
    } catch (e) {
      mensagem($('resultado-membros'), e.message, false);
    }
  };
  return el('div', { class: 'cartao', style: 'padding:14px 16px;margin-bottom:10px' },
    el('div', { style: 'display:flex;flex-wrap:wrap;gap:6px 10px;align-items:center' },
      m ? el('button', { class: 'link', type: 'button', onclick: () => { $('dlg-acompanhamento').close(); abrirFicha(m.id); } }, v.nome)
        : el('strong', {}, v.nome),
      el('span', { class: 'dica' }, dataVisitaBr(v.data) + ' · ' + (v.primeiraVez ? '1ª visita' : 'voltou') + ' · ' + (ORIGEM_VISITA[v.origem] || '')),
      el('span', { class: 'pilula ' + (v.contato === 'contatado' ? 'st-membro' : v.contato === 'semResposta' ? 'st-transferido' : 'st-inativo') },
        CONTATO_ROTULO[v.contato || 'aContatar'])),
    (v.interesses || []).length ? el('div', { style: 'margin-top:6px' }, ...v.interesses.map(pilulaInteresse)) : null,
    el('div', { class: 'contato-rapido' },
      fone.length >= 10 ? el('a', { href: `https://wa.me/55${fone}?text=${encodeURIComponent(texto)}`, target: '_blank', rel: 'noopener' }, 'WhatsApp com mensagem') : null,
      fone.length >= 10 ? el('a', { href: 'tel:+55' + fone }, 'Ligar') : el('span', { class: 'dica' }, 'Sem telefone cadastrado')),
    el('div', { style: 'display:flex;flex-wrap:wrap;gap:8px;margin-top:10px;align-items:center' },
      nota, botao('Contatado', salvar('contatado'), 'pequeno'), botao('Sem resposta', salvar('semResposta'))));
}

// Filtros (só re-renderiza, sem buscar de novo).
for (const id of ['busca-membro', 'filtro-status-membro', 'filtro-ministerio-membro', 'filtro-aniversariantes', 'filtro-sem-consentimento']) {
  $(id).addEventListener('input', renderMembros);
  $(id).addEventListener('change', renderMembros);
}

// ----- Importar -----

const CABECALHO_MODELO = 'Nome;Aniversário;Sexo;Estado civil;CPF;RG;Telefone;WhatsApp;E-mail;CEP;Rua;Número;Complemento;Bairro;Cidade;UF;'
  + 'Status;Data de chegada;Data de batismo;Data de membresia;Ministérios;Função;Como conheceu;Consentimento;Observações';
const EXEMPLO_MODELO = 'Ana Souza;05/03/1990;F;Casada;111.444.777-35;;(11) 98888-7777;(11) 98888-7777;ana@exemplo.com;01310-100;'
  + 'Av. Paulista;1000;;Bela Vista;São Paulo;SP;Congregada;10/02/2024;14/06/2015;;Louvor|Infantil;Líder;Convite de amigo;10/02/2024;';

$('abrir-importar-membros').addEventListener('click', () => {
  mensagem($('resultado-importacao'), '');
  $('dlg-importar').showModal();
});

/** Lê o .csv em UTF-8; se vier do Excel em Windows-1252 (acentos quebrados), relê nessa codificação. */
async function lerArquivoCsv(arquivo) {
  const bytes = await arquivo.arrayBuffer();
  let texto = new TextDecoder('utf-8').decode(bytes);
  if (texto.includes('�')) texto = new TextDecoder('windows-1252').decode(bytes);
  return texto.replace(/^﻿/, '');
}
async function carregarArquivoCsv(arquivo) {
  if (!arquivo) return;
  if (arquivo.size > 2 * 1024 * 1024) {
    mensagem($('resultado-importacao'), 'Arquivo grande demais (máximo 2 MB).', false);
    return;
  }
  $('csv-membros').value = await lerArquivoCsv(arquivo);
  mensagem($('resultado-importacao'), `"${arquivo.name}" carregado. Confira as linhas e clique em Importar.`);
}
$('arquivo-csv').addEventListener('change', (e) => carregarArquivoCsv(e.target.files[0]));
$('dlg-importar').addEventListener('dragover', (e) => e.preventDefault());
$('dlg-importar').addEventListener('drop', (e) => {
  e.preventDefault();
  carregarArquivoCsv(e.dataTransfer.files[0]);
});

$('form-importar').addEventListener('submit', async (e) => {
  if (e.submitter && e.submitter.value === 'cancelar') return; // deixa o dialog fechar
  e.preventDefault();
  const saida = $('resultado-importacao');
  try {
    const r = await api('POST', '/api/membros/importar', $('csv-membros').value);
    const partes = [`${r.importados} pessoa(s) importada(s).`];
    if (r.linhasComErro && r.linhasComErro.length) partes.push(`Linhas com erro: ${r.linhasComErro.join(', ')}.`);
    for (const d of r.detalhes || []) partes.push(d);
    mensagem(saida, partes.join('\n'), !(r.linhasComErro || []).length && !(r.detalhes || []).length);
    if (r.importados) {
      $('csv-membros').value = '';
      $('arquivo-csv').value = '';
      await carregarMembros();
      if (!(r.linhasComErro || []).length && !(r.detalhes || []).length) $('dlg-importar').close();
    }
  } catch (err) {
    mensagem(saida, err.message, false);
  }
});

$('modelo-csv').addEventListener('click', () => {
  $('csv-membros').value = CABECALHO_MODELO + '\n' + EXEMPLO_MODELO + '\n';
});
$('baixar-modelo-csv').addEventListener('click', () => {
  const blob = new Blob(['﻿' + CABECALHO_MODELO + '\r\n' + EXEMPLO_MODELO + '\r\n'], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = el('a', { href: url, download: 'modelo-membros.csv' });
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10000);
});

// ----- Exportar CSV / Imprimir -----

$('exportar-membros').addEventListener('click', () => {
  const f = filtrosMembros();
  const qs = new URLSearchParams();
  if (f.busca) qs.set('busca', f.busca);
  if (f.status) qs.set('status', f.status);
  if (f.ministerio) qs.set('ministerio', f.ministerio);
  if (f.aniversariantes) qs.set('aniversariantes', 'mes');
  if (f.semConsentimento) qs.set('semConsentimento', '1');
  if (f.novas) qs.set('novasDias', '90');
  baixarArquivo('/api/membros/exportar' + (qs.toString() ? '?' + qs.toString() : ''), 'membros.csv')
    .catch((e) => mensagem($('resultado-membros'), e.message, false));
});

$('imprimir-membros').addEventListener('click', () => {
  const lista = membrosFiltrados();
  if (!lista.length) return;
  const f = filtrosMembros();
  const filtros = [];
  if (f.status === 'ativos') filtros.push('ativos');
  else if (f.status) filtros.push(STATUS_MEMBRO[f.status][0].toLowerCase() + 's');
  if (f.ministerio) filtros.push(f.ministerio);
  if (f.aniversariantes) filtros.push('aniversariantes do mês');
  if (f.semConsentimento) filtros.push('sem autorização LGPD');
  if (f.novas) filtros.push('novas em 90 dias');
  if (f.busca) filtros.push('"' + f.busca + '"');
  const linha = (m) => el('tr', {},
    el('td', {}, m.nome),
    el('td', {}, aniversarioDe(m)),
    el('td', {}, idadeDe(m) != null ? String(idadeDe(m)) : ''),
    el('td', {}, rotuloStatus(m.status, m.sexo)),
    el('td', {}, [m.telefone, m.whatsapp && m.whatsapp !== m.telefone ? m.whatsapp : null].filter(Boolean).join(' / ')),
    el('td', {}, m.email || ''),
    el('td', {}, [...(m.ministerios || []), m.funcao].filter(Boolean).join(' · ')),
    el('td', {}, [m.cidade, m.estado].filter(Boolean).join('/')));
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
  $('status-linhas').replaceChildren(...[
    estado.modo === 'agente'
      ? linha('PC da igreja (agente)', estado.agenteConectado ? 'Conectado' + (estado.agenteVersao ? ' · ' + estado.agenteVersao : '') : 'Desconectado' + (estado.agenteVistoEm ? ' · visto ' + dataCurta(estado.agenteVistoEm) : ''), estado.agenteConectado)
      : null,
    linha('Holyrics', estado.holyricsConectado ? 'Conectado' : 'Sem conexão', estado.holyricsConectado),
    linha('Cartazes no Holyrics', estado.cartazesNoHolyrics ? 'Sim' : 'Não configurado', estado.cartazesNoHolyrics),
    linha('Backup', estado.backupConfigurado ? (estado.ultimoBackup ? 'Último: ' + dataCurta(estado.ultimoBackup) : 'Ainda não feito') : 'Desativado',
      estado.backupConfigurado && !(estado.alertasBackup || []).length),
    estado.modo === 'agente'
      ? linha('Cópia do backup no PC da igreja', estado.copiaBackupPc ? dataCurta(estado.copiaBackupPc) : 'Ainda não feita', !!estado.copiaBackupPc)
      : null,
    linha('Pedidos aguardando', String(estado.aguardandoAprovacao)),
    linha('Versão do servidor', estado.versao),
    ...(estado.alertasBackup || []).map((a) => el('p', { class: 'erro', role: 'alert' }, a))].filter(Boolean));
  $('link-oracao').textContent = estado.urlOracao;
  $('link-oracao').href = estado.urlOracao;
  $('link-mensagens').textContent = estado.urlMensagens;
  $('link-mensagens').href = estado.urlMensagens;
  $('cartao-qr-visitante').hidden = estado.visitanteQrAtivo === false;
  if (estado.urlVisitante) {
    $('link-visitante').textContent = estado.urlVisitante;
    $('link-visitante').href = estado.urlVisitante;
  }
  const urlMural = estado.urlOracao.replace(/\/oracao$/, '/mural') +
    (estado.chaveMural ? '?chave=' + encodeURIComponent(estado.chaveMural) : '');
  $('link-mural').textContent = urlMural;
  $('link-mural').href = urlMural;
  const urlBoasVindas = urlMural + (urlMural.includes('?') ? '&' : '?') + 'tela=boas-vindas';
  $('link-mural-boas-vindas').textContent = urlBoasVindas;
  $('link-mural-boas-vindas').href = urlBoasVindas;
  const urlRecepcao = estado.urlOracao.replace(/\/oracao$/, '/recepcao');
  $('link-recepcao').textContent = urlRecepcao;
  $('link-recepcao').href = urlRecepcao;
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
    else if (tipo === abaAtual || (tipo === 'membros' && abaAtual === 'recados') || (tipo === 'visitas' && abaAtual === 'membros') ||
      (abaAtual === 'escalas' && (tipo === 'indisponibilidades' || tipo === 'membros'))) {
      carregar[abaAtual]();
    }
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
  if (eu.perfil === 'integrante' || eu.perfil === 'ministro' || eu.perfil === 'louvor') {
    location.replace('/minha-escala');
    return;
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
