'use strict';
// /admin › Telão › QR codes: a imagem que vai ao telão com cada QR (pedidos de oração, mensagens, PIX).
// Automático: este editor desenha a arte (fundo, logo, título, chamada) num canvas 1920x1080 e envia
// o PNG sem o QR. Arte própria: a imagem pronta é enviada como está. Nos dois, o servidor encaixa o
// QR num cartão branco (server/lib/qr_oracao.dart › comporQr).

const LARGURA_ARTE = 1920, ALTURA_ARTE = 1080;
const MARGEM_CARTAO = 96;
const LADO_CARTAO = { P: 0.44, M: 0.56, G: 0.70 };

/** Mesmo cálculo de retanguloCartaoQr (qr_oracao.dart): onde fica o cartão branco do QR. */
function retanguloCartaoQr(posicao, tamanho, modulos = 29) {
  const alvo = Math.round(ALTURA_ARTE * (LADO_CARTAO[tamanho] || LADO_CARTAO.M));
  const escala = Math.max(1, Math.floor(alvo / (modulos + 8)));
  const lado = escala * (modulos + 8);
  const [h, v] = posicao.split('-');
  const x = h === 'esquerda' ? MARGEM_CARTAO : h === 'direita' ? LARGURA_ARTE - MARGEM_CARTAO - lado : Math.floor((LARGURA_ARTE - lado) / 2);
  const y = v === 'baixo' ? ALTURA_ARTE - MARGEM_CARTAO - lado : Math.floor((ALTURA_ARTE - lado) / 2);
  return { x, y, lado };
}

/** Área livre para logo e textos, do lado oposto ao QR (com o QR no centro, a faixa de cima). */
function areaDoTexto(posicao, tamanho) {
  const r = retanguloCartaoQr(posicao, tamanho);
  const [h] = posicao.split('-');
  if (h === 'direita') return { x0: 120, x1: r.x - 100, y0: 90, y1: ALTURA_ARTE - 90, alinhar: 'left' };
  if (h === 'esquerda') return { x0: r.x + r.lado + 100, x1: LARGURA_ARTE - 120, y0: 90, y1: ALTURA_ARTE - 90, alinhar: 'left' };
  return { x0: 160, x1: LARGURA_ARTE - 160, y0: 60, y1: r.y - 40, alinhar: 'center' };
}

/** Quebra [texto] em linhas de até [largura] px, medindo com [medir] (ctx.measureText). */
function quebrarLinhas(texto, largura, medir) {
  const linhas = [];
  for (const paragrafo of String(texto || '').split('\n')) {
    let linha = '';
    for (const palavra of paragrafo.split(/\s+/).filter(Boolean)) {
      const tentativa = linha ? linha + ' ' + palavra : palavra;
      if (linha && medir(tentativa) > largura) {
        linhas.push(linha);
        linha = palavra;
      } else {
        linha = tentativa;
      }
    }
    if (linha) linhas.push(linha);
  }
  return linhas;
}

/**
 * Tamanhos e linhas do bloco de texto (título, chamada, endereço) que cabem em [area]: começa no
 * tamanho cheio e diminui até caber na altura e nenhuma palavra estourar a largura.
 * [medir](texto, peso, px) devolve a largura em px.
 */
function ajustarTexto(layout, area, medir, alturaLogo = 0) {
  const largura = area.x1 - area.x0;
  const altura = area.y1 - area.y0 - alturaLogo;
  for (let escala = 1; escala >= 0.3; escala -= 0.05) {
    const t = Math.round(120 * escala), c = Math.round(56 * escala), e = Math.round(40 * escala);
    const blocos = [
      { tipo: 'titulo', px: t, peso: 800, entre: 1.08, linhas: quebrarLinhas(layout.titulo, largura, (s) => medir(s, 800, t)) },
      { tipo: 'chamada', px: c, peso: 500, entre: 1.3, linhas: quebrarLinhas(layout.chamada, largura, (s) => medir(s, 500, c)) },
      { tipo: 'endereco', px: e, peso: 600, entre: 1.2, linhas: layout.enderecoTexto ? [layout.enderecoTexto] : [] },
    ].filter((b) => b.linhas.length);
    const palavraLarga = blocos.some((b) => b.linhas.some((l) => medir(l, b.peso, b.px) > largura));
    const respiro = Math.round(48 * escala);
    const total = blocos.reduce((s, b) => s + b.linhas.length * b.px * b.entre, 0) + respiro * Math.max(0, blocos.length - 1);
    if (!palavraLarga && total <= altura) return { escala, blocos, total, respiro };
  }
  return null; // não cabe nem pequeno: a prévia avisa
}

function luminancia(hex) {
  const n = parseInt(String(hex).slice(1), 16);
  const canal = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
  return 0.2126 * canal((n >> 16) & 255) + 0.7152 * canal((n >> 8) & 255) + 0.0722 * canal(n & 255);
}

/** Texto escuro só sobre fundo claro sem foto (a foto sempre leva véu escuro). */
function textoEscuro(layout, temFoto) {
  return !temFoto && (luminancia(layout.cor) + luminancia(layout.cor2)) / 2 > 0.35;
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { retanguloCartaoQr, areaDoTexto, quebrarLinhas, ajustarTexto, textoEscuro, LADO_CARTAO };
}

// ---------- Editor (só no navegador) ----------

const QRS_ARTE = [
  { id: 'oracao', nome: 'Pedidos de oração', titulo: 'Pedidos de oração',
    chamada: 'Aponte a câmera do celular e envie seu pedido', caminho: '/oracao' },
  { id: 'mensagens', nome: 'Caixa de mensagens', titulo: 'Caixa de mensagens',
    chamada: 'Dúvidas, sugestões e críticas', caminho: '/mensagens' },
  { id: 'pix', nome: 'PIX das ofertas', titulo: 'Dízimos e ofertas', chamada: '', caminho: null },
];

const POSICOES_QR = [
  ['esquerda-meio', 'Esquerda'], ['centro-meio', 'Centro'], ['direita-meio', 'Direita'],
  ['esquerda-baixo', 'Esquerda, embaixo'], ['centro-baixo', 'Centro, embaixo'], ['direita-baixo', 'Direita, embaixo'],
];

const editoresQr = {};
const imagensQr = { logoClaro: null, logoEscuro: null };

function chaveQr(id, campo) { return 'arteQr' + id[0].toUpperCase() + id.slice(1) + campo; }

function carregarImagem(src) {
  return new Promise((ok, falha) => {
    const i = new Image();
    i.onload = () => ok(i);
    i.onerror = falha;
    i.src = src;
  });
}

/** Imagem protegida por login (foto, arte, prévia) como <img> local. */
async function imagemComLogin(caminho) {
  const r = await fetch(caminho, { headers: { Authorization: 'Bearer ' + token } });
  if (!r.ok) return null;
  return carregarImagem(URL.createObjectURL(await r.blob()));
}

function enderecoCurto(q) {
  const base = (cfg.urlPublica || cfg.urlDetectada || '').replace(/^https?:\/\//, '');
  return q.caminho ? base + q.caminho : '';
}

function chamadaPadrao(q) {
  return q.id === 'pix' ? (cfg.sitePixChave ? 'Chave PIX: ' + cfg.sitePixChave : '') : q.chamada;
}

function layoutDe(q) {
  let salvo = {};
  try { salvo = JSON.parse(cfg[chaveQr(q.id, 'Layout')] || '{}'); } catch (_) { /* layout ilegível: começa do padrão */ }
  return {
    titulo: q.titulo, chamada: chamadaPadrao(q), cor: '#14215c', cor2: '#3949ab', escurecer: 55,
    logo: true, endereco: q.id !== 'pix', ...salvo,
  };
}

/** Desenha a arte (sem o QR de verdade). [exemploQr] desenha um QR de mentira para a prévia. */
function desenharArte(ctx, e, { exemploQr }) {
  const L = e.layout;
  const foto = e.foto;
  ctx.clearRect(0, 0, LARGURA_ARTE, ALTURA_ARTE);
  if (e.modo === 'arte') {
    if (e.arte) ctx.drawImage(e.arte, 0, 0, LARGURA_ARTE, ALTURA_ARTE);
    else { ctx.fillStyle = '#e8e8ee'; ctx.fillRect(0, 0, LARGURA_ARTE, ALTURA_ARTE); }
  } else {
    const g = ctx.createLinearGradient(0, 0, LARGURA_ARTE, ALTURA_ARTE);
    g.addColorStop(0, L.cor);
    g.addColorStop(1, L.cor2);
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, LARGURA_ARTE, ALTURA_ARTE);
    if (foto) {
      ctx.drawImage(foto, 0, 0, LARGURA_ARTE, ALTURA_ARTE);
      ctx.fillStyle = `rgba(0,0,0,${L.escurecer / 100})`;
      ctx.fillRect(0, 0, LARGURA_ARTE, ALTURA_ARTE);
    }
    desenharTextos(ctx, e);
  }
  const r = retanguloCartaoQr(e.posicao, e.tamanho);
  if (exemploQr) desenharQrDeExemplo(ctx, r);
  if (e.modo === 'arte') {
    // Arte própria: mostra a área que o QR vai cobrir, para ajustar a arte no Canva.
    ctx.save();
    ctx.setLineDash([28, 18]);
    ctx.lineWidth = 8;
    ctx.strokeStyle = '#ff3d71';
    ctx.strokeRect(r.x, r.y, r.lado, r.lado);
    ctx.restore();
  }
}

function desenharTextos(ctx, e) {
  const L = e.layout;
  const escuro = textoEscuro(L, !!e.foto);
  const cor = escuro ? '#15171c' : '#ffffff';
  const area = areaDoTexto(e.posicao, e.tamanho);
  const logo = L.logo ? (escuro ? imagensQr.logoEscuro : imagensQr.logoClaro) : null;
  const alturaLogo = logo ? 150 : 0;
  const medir = (s, peso, px) => { ctx.font = `${peso} ${px}px Montserrat`; return ctx.measureText(s).width; };
  const texto = { ...L, enderecoTexto: L.endereco ? enderecoCurto(e.q) : '' };
  const ajuste = ajustarTexto(texto, area, medir, alturaLogo);
  e.cabe = !!ajuste;
  ctx.fillStyle = cor;
  ctx.textBaseline = 'top';
  ctx.textAlign = area.alinhar;
  const xTexto = area.alinhar === 'center' ? (area.x0 + area.x1) / 2 : area.x0;
  if (logo) {
    const h = 110, w = logo.width * h / logo.height;
    const xl = area.alinhar === 'center' ? 96 : area.x0;
    ctx.drawImage(logo, xl, area.alinhar === 'center' ? 60 : area.y0, w, h);
  }
  if (!ajuste) return;
  const y0 = area.alinhar === 'center' ? area.y0 + (area.y1 - area.y0 - ajuste.total) / 2
    : area.y0 + alturaLogo + (area.y1 - area.y0 - alturaLogo - ajuste.total) / 2;
  let y = y0;
  for (const [i, b] of ajuste.blocos.entries()) {
    ctx.font = `${b.peso} ${b.px}px Montserrat`;
    ctx.globalAlpha = b.tipo === 'endereco' ? 0.85 : 1;
    for (const linha of b.linhas) {
      ctx.fillText(linha, xTexto, y);
      y += b.px * b.entre;
    }
    ctx.globalAlpha = 1;
    if (b.tipo === 'titulo') {
      // Traço de destaque entre o título e a chamada.
      const w = 140 * ajuste.escala, h = Math.max(4, 10 * ajuste.escala);
      const xb = area.alinhar === 'center' ? xTexto - w / 2 : xTexto;
      ctx.globalAlpha = 0.6;
      ctx.fillRect(xb, y + ajuste.respiro * 0.25, w, h);
      ctx.globalAlpha = 1;
    }
    if (i < ajuste.blocos.length - 1) y += ajuste.respiro;
  }
}

/** Cartão branco com um QR de mentira (o de verdade vem do servidor em "Ver como fica no telão"). */
function desenharQrDeExemplo(ctx, r) {
  const modulos = 29, escala = r.lado / (modulos + 8);
  ctx.save();
  ctx.shadowColor = 'rgba(0,0,0,.35)';
  ctx.shadowBlur = 40;
  ctx.shadowOffsetY = 8;
  ctx.fillStyle = '#fff';
  ctx.beginPath();
  ctx.roundRect(r.x, r.y, r.lado, r.lado, escala * 2);
  ctx.fill();
  ctx.restore();
  ctx.fillStyle = '#000';
  const x0 = r.x + 4 * escala, y0 = r.y + 4 * escala;
  const olho = (c, l) => {
    ctx.fillRect(x0 + c * escala, y0 + l * escala, 7 * escala, 7 * escala);
    ctx.fillStyle = '#fff';
    ctx.fillRect(x0 + (c + 1) * escala, y0 + (l + 1) * escala, 5 * escala, 5 * escala);
    ctx.fillStyle = '#000';
    ctx.fillRect(x0 + (c + 2) * escala, y0 + (l + 2) * escala, 3 * escala, 3 * escala);
  };
  olho(0, 0); olho(modulos - 7, 0); olho(0, modulos - 7);
  for (let l = 0; l < modulos; l++) {
    for (let c = 0; c < modulos; c++) {
      const noOlho = (l < 8 && c < 8) || (l < 8 && c >= modulos - 8) || (l >= modulos - 8 && c < 8);
      if (!noOlho && ((l * 7 + c * 13 + l * c) % 5 < 2)) ctx.fillRect(x0 + c * escala, y0 + l * escala, escala, escala);
    }
  }
}

function desenharPrevia(e) {
  const ctx = e.canvas.getContext('2d');
  if (e.modo === 'padrao') {
    ctx.fillStyle = '#fff';
    ctx.fillRect(0, 0, LARGURA_ARTE, ALTURA_ARTE);
    if (e.previaServidor) ctx.drawImage(e.previaServidor, 0, 0, LARGURA_ARTE, ALTURA_ARTE);
    e.aviso.textContent = '';
    return;
  }
  desenharArte(ctx, e, { exemploQr: e.modo === 'automatico' });
  e.aviso.textContent = e.modo === 'automatico' && e.cabe === false
    ? 'O texto não cabe nesse espaço: encurte o título ou a chamada, ou use um QR menor.'
    : e.modo === 'arte' && !e.arte ? 'Envie a imagem da arte (o ideal é 1920×1080).'
      : e.modo === 'arte' ? 'O tracejado mostra onde o QR entra: deixe essa área livre na arte.' : '';
}

function mostrarCampos(e) {
  e.campos.automatico.hidden = e.modo !== 'automatico';
  e.campos.arte.hidden = e.modo !== 'arte';
  e.campos.posicao.hidden = e.modo === 'padrao';
  e.botoes.salvar.hidden = e.modo === 'padrao';
  desenharPrevia(e);
}

function campo(rotulo, controle, dica) {
  const id = controle.id;
  return el('div', { class: 'campo' }, el('label', { for: id }, rotulo, dica ? [' ', el('span', { class: 'dica' }, dica)] : null), controle);
}

function montarEditor(q) {
  const id = (s) => `arte-qr-${q.id}-${s}`;
  const e = { q, modo: 'padrao', posicao: 'direita-meio', tamanho: 'M', layout: layoutDe(q), foto: null, arte: null, arteNova: null };
  e.canvas = el('canvas', { width: LARGURA_ARTE, height: ALTURA_ARTE, class: 'previa-arte-qr', 'aria-label': 'Prévia: ' + q.nome });
  e.aviso = el('p', { class: 'dica', role: 'status' });
  e.saida = el('span', { role: 'status' });

  const modo = el('div', { class: 'modos-arte-qr', role: 'radiogroup', 'aria-label': 'Imagem do QR' },
    ...[['padrao', 'Padrão'], ['automatico', 'Automático'], ['arte', 'Arte própria']].map(([v, r]) =>
      el('label', { class: 'marcar' }, el('input', { type: 'radio', name: id('modo'), value: v, onchange: () => { e.modo = v; mostrarCampos(e); } }), r)));
  e.radios = modo.querySelectorAll('input');

  const entrada = (s, props) => el('input', { id: id(s), ...props });
  const titulo = entrada('titulo', { type: 'text', maxlength: 60 });
  const chamada = el('textarea', { id: id('chamada'), rows: 2, maxlength: 140 });
  const cor = entrada('cor', { type: 'color' });
  const cor2 = entrada('cor2', { type: 'color' });
  const escurecer = entrada('escurecer', { type: 'range', min: 0, max: 90, step: 5 });
  const logo = entrada('logo', { type: 'checkbox' });
  const endereco = entrada('endereco', { type: 'checkbox' });
  const foto = entrada('foto', { type: 'file', accept: 'image/jpeg,image/png', class: 'escondido' });
  const removerFoto = el('button', { type: 'button', class: 'botao secundario pequeno' }, 'Tirar a foto');
  e.entradas = { titulo, chamada, cor, cor2, escurecer, logo, endereco };
  const aoMudar = () => {
    Object.assign(e.layout, {
      titulo: titulo.value, chamada: chamada.value, cor: cor.value, cor2: cor2.value,
      escurecer: Number(escurecer.value), logo: logo.checked, endereco: endereco.checked,
    });
    desenharPrevia(e);
  };
  for (const c of [titulo, chamada, cor, cor2, escurecer, logo, endereco]) c.addEventListener('input', aoMudar);
  foto.addEventListener('change', async () => {
    const arquivo = foto.files[0];
    foto.value = '';
    if (!arquivo) return;
    mensagem(e.saida, 'Enviando a foto…');
    try {
      await api('POST', '/api/admin/arte-qr/foto?qr=' + q.id, arquivo, { bruto: true, tipo: arquivo.type });
      e.foto = await imagemComLogin('/api/admin/arte-qr/foto?qr=' + q.id);
      removerFoto.disabled = false;
      desenharPrevia(e);
      mensagem(e.saida, 'Foto pronta. Salve para mandar ao telão.');
    } catch (err) { mensagem(e.saida, err.message, false); }
  });
  removerFoto.addEventListener('click', async () => {
    try {
      await api('DELETE', '/api/admin/arte-qr/foto?qr=' + q.id);
      e.foto = null;
      removerFoto.disabled = true;
      desenharPrevia(e);
    } catch (err) { mensagem(e.saida, err.message, false); }
  });
  e.removerFoto = removerFoto;

  e.campos = {};
  e.campos.automatico = el('div', {},
    campo('Título', titulo),
    campo('Chamada', chamada, q.id === 'pix' ? '(a chave PIX ajuda quem não lê o QR)' : null),
    el('div', { class: 'grade2' }, campo('Cor do fundo', cor), campo('Segunda cor (degradê)', cor2)),
    el('div', { class: 'acoes' },
      el('label', { class: 'botao secundario pequeno' }, 'Foto de fundo', foto), removerFoto),
    campo('Escurecer a foto', escurecer),
    el('label', { class: 'marcar' }, logo, ' Logo da igreja'),
    q.caminho ? el('label', { class: 'marcar' }, endereco, ' Endereço curto embaixo (para quem não lê o QR)') : null);

  const arte = entrada('arte', { type: 'file', accept: 'image/jpeg,image/png', class: 'escondido' });
  arte.addEventListener('change', async () => {
    const arquivo = arte.files[0];
    arte.value = '';
    if (!arquivo) return;
    e.arteNova = arquivo;
    e.arte = await carregarImagem(URL.createObjectURL(arquivo));
    desenharPrevia(e);
    mensagem(e.saida, 'Arte carregada. Ajuste a posição e salve.');
  });
  e.campos.arte = el('div', {},
    el('p', { class: 'dica' }, 'Monte a arte no Canva em 1920×1080 com o título e as cores da igreja. Deixe livre a área tracejada: o QR entra ali, num cartão branco.'),
    el('label', { class: 'botao secundario' }, 'Escolher a imagem', arte));

  const posicao = el('select', { id: id('posicao') }, ...POSICOES_QR.map(([v, r]) => el('option', { value: v }, r)));
  const tamanho = el('select', { id: id('tamanho') }, el('option', { value: 'P' }, 'Pequeno'), el('option', { value: 'M' }, 'Médio'), el('option', { value: 'G' }, 'Grande'));
  posicao.addEventListener('change', () => { e.posicao = posicao.value; desenharPrevia(e); });
  tamanho.addEventListener('change', () => { e.tamanho = tamanho.value; desenharPrevia(e); });
  e.selects = { posicao, tamanho };
  e.campos.posicao = el('div', { class: 'grade2' }, campo('Posição do QR', posicao), campo('Tamanho do QR', tamanho));

  e.botoes = {
    salvar: el('button', { type: 'button', class: 'botao', onclick: () => salvarArteQr(e) }, 'Salvar e mandar ao telão'),
    ver: el('button', { type: 'button', class: 'botao secundario', onclick: () => verNoTelao(e) }, 'Ver como fica no telão'),
    padrao: el('button', { type: 'button', class: 'botao secundario', onclick: () => voltarAoPadrao(e) }, 'Voltar ao padrão'),
  };
  e.semPix = el('p', { class: 'dica erro', hidden: true }, 'Configure a chave PIX em Página inicial para usar este QR.');

  e.raiz = el('div', { class: 'fundo-tv arte-qr', id: 'arte-qr-' + q.id },
    el('h3', {}, q.nome),
    e.semPix,
    el('div', { class: 'fundo-tv-grade' },
      el('div', {}, e.canvas, e.aviso),
      el('div', {}, modo, e.campos.automatico, e.campos.arte, e.campos.posicao,
        el('div', { class: 'acoes' }, e.botoes.salvar, e.botoes.ver, e.botoes.padrao), e.saida)));
  return e;
}

async function salvarArteQr(e) {
  const q = e.q;
  try {
    if (e.modo === 'automatico' && e.cabe === false) throw new Error('O texto não cabe: encurte ou diminua o QR antes de salvar.');
    if (e.modo === 'arte' && !e.arteNova && !(e.modoSalvo === 'arte' && e.arte)) throw new Error('Escolha a imagem da arte.');
    mensagem(e.saida, 'Salvando…');
    cfg = await api('PUT', '/api/admin/configuracoes', {
      [chaveQr(q.id, 'Posicao')]: e.posicao,
      [chaveQr(q.id, 'Tamanho')]: e.tamanho,
      [chaveQr(q.id, 'Layout')]: JSON.stringify(e.layout),
    });
    if (e.modo === 'automatico') {
      await document.fonts.load('800 100px Montserrat');
      await document.fonts.load('500 100px Montserrat');
      const tela = document.createElement('canvas');
      tela.width = LARGURA_ARTE;
      tela.height = ALTURA_ARTE;
      desenharArte(tela.getContext('2d'), e, { exemploQr: false });
      const png = await new Promise((ok) => tela.toBlob(ok, 'image/png'));
      await api('POST', `/api/admin/arte-qr?qr=${q.id}&modo=automatico`, png, { bruto: true, tipo: 'image/png' });
    } else if (e.arteNova) {
      await api('POST', `/api/admin/arte-qr?qr=${q.id}&modo=arte`, e.arteNova, { bruto: true, tipo: e.arteNova.type });
      e.arteNova = null;
    }
    cfg = await api('GET', '/api/admin/configuracoes');
    e.modoSalvo = e.modo;
    mensagem(e.saida, 'Salvo. O telão usa a nova imagem no próximo QR projetado.');
  } catch (err) {
    mensagem(e.saida, err.message, false);
  }
}

async function verNoTelao(e) {
  const r = await fetch('/api/admin/arte-qr/previa?qr=' + e.q.id, { headers: { Authorization: 'Bearer ' + token } });
  if (!r.ok) { mensagem(e.saida, (await r.text()) || 'Prévia indisponível.', false); return; }
  if (e.modo !== e.modoSalvo) mensagem(e.saida, 'Mostrando o que está salvo: salve para ver as mudanças.');
  window.open(URL.createObjectURL(await r.blob()), '_blank', 'noopener');
}

async function voltarAoPadrao(e) {
  if (!await confirmar('Voltar ao QR padrão?', 'O telão volta a mostrar só o QR em fundo branco. A arte e a foto deste QR são apagadas.', 'Voltar ao padrão')) return;
  try {
    await api('DELETE', '/api/admin/arte-qr?qr=' + e.q.id);
    cfg = await api('GET', '/api/admin/configuracoes');
    await carregarEditor(e);
    mensagem(e.saida, 'Pronto: QR padrão.');
  } catch (err) {
    mensagem(e.saida, err.message, false);
  }
}

/** Lê do servidor o estado salvo de um QR e redesenha. */
async function carregarEditor(e) {
  const q = e.q;
  e.modo = e.modoSalvo = cfg[chaveQr(q.id, 'Modo')] || 'padrao';
  e.posicao = cfg[chaveQr(q.id, 'Posicao')] || 'direita-meio';
  e.tamanho = cfg[chaveQr(q.id, 'Tamanho')] || 'M';
  e.layout = layoutDe(q);
  const L = e.layout;
  Object.assign(e.entradas.titulo, { value: L.titulo });
  e.entradas.chamada.value = L.chamada;
  e.entradas.cor.value = L.cor;
  e.entradas.cor2.value = L.cor2;
  e.entradas.escurecer.value = L.escurecer;
  e.entradas.logo.checked = !!L.logo;
  e.entradas.endereco.checked = !!L.endereco;
  e.selects.posicao.value = e.posicao;
  e.selects.tamanho.value = e.tamanho;
  for (const r of e.radios) r.checked = r.value === e.modo;
  atualizarPix(e);
  const [foto, arte, previa] = await Promise.all([
    cfg[chaveQr(q.id, 'Foto')] ? imagemComLogin('/api/admin/arte-qr/foto?qr=' + q.id) : null,
    e.modo === 'arte' ? imagemComLogin('/api/admin/arte-qr/fundo?qr=' + q.id) : null,
    imagemComLogin('/api/admin/arte-qr/previa?qr=' + q.id),
  ]);
  e.foto = foto;
  e.arte = arte;
  e.arteNova = null;
  e.previaServidor = previa;
  e.removerFoto.disabled = !foto;
  mostrarCampos(e);
}

/** O QR do PIX só existe com chave, nome e cidade (Página inicial). */
function atualizarPix(e) {
  const semPix = e.q.id === 'pix' && !(cfg.sitePixChave && cfg.sitePixNome && cfg.sitePixCidade);
  e.semPix.hidden = !semPix;
  for (const b of [e.botoes.salvar, ...e.radios]) b.disabled = semPix;
}

/**
 * Chamado pelo admin.js a cada preencher(). Na primeira vez monta e carrega os editores; depois
 * só atualiza o aviso do PIX, para não desfazer uma edição em andamento.
 */
async function preencherArtesQr() {
  const lista = document.getElementById('lista-artes-qr');
  if (!lista) return;
  if (Object.keys(editoresQr).length) {
    for (const e of Object.values(editoresQr)) atualizarPix(e);
    return;
  }
  for (const q of QRS_ARTE) {
    editoresQr[q.id] = montarEditor(q);
    lista.append(editoresQr[q.id].raiz);
  }
  [imagensQr.logoClaro, imagensQr.logoEscuro] = await Promise.all([carregarImagem('/logo-claro.png'), carregarImagem('/logo.png')]);
  await Promise.all([document.fonts.load('800 100px Montserrat'), document.fonts.load('500 100px Montserrat')]);
  for (const e of Object.values(editoresQr)) await carregarEditor(e);
}
