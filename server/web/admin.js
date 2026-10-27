'use strict';
// Página de administração. Utilitários (api, el, $, mensagem...) em comum.js.

let cfg = {};
let chaveAgenteVisivel = false;

// ---------- Login ----------

function sair() {
  if (token) fetch('/api/logout', { method: 'POST', headers: { Authorization: 'Bearer ' + token } }).catch(() => {});
  token = null;
  localStorage.removeItem('diako_token');
  $('app').hidden = true;
  $('login').hidden = false;
  $('senha-login').focus();
}

$('form-login').addEventListener('submit', async (e) => {
  e.preventDefault();
  const erro = $('erro-login');
  erro.hidden = true;
  const r = await fetch('/api/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ usuario: $('usuario-login').value.trim(), senha: $('senha-login').value }),
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) {
    erro.textContent = j.erro || 'Não foi possível entrar.';
    erro.hidden = false;
    return;
  }
  token = j.token;
  localStorage.setItem('diako_token', token);
  $('senha-login').value = '';
  iniciar();
});

$('sair').addEventListener('click', sair);

/** Pergunta antes de ações que não têm volta. */
function confirmar(titulo, texto, rotulo = 'Confirmar') {
  $('titulo-confirmar').textContent = titulo;
  $('texto-confirmar').textContent = texto;
  $('botao-confirmar').textContent = rotulo;
  const dlg = $('dlg-confirmar');
  return new Promise((ok) => {
    dlg.onclose = () => ok(dlg.returnValue === 'ok');
    dlg.showModal();
  });
}

/** Envia um formulário de configurações e mostra o resultado em [saida]. */
async function salvar(campos, saida) {
  try {
    cfg = await api('PUT', '/api/admin/configuracoes', campos);
    preencher();
    mensagem(saida, 'Salvo.');
  } catch (err) {
    mensagem(saida, err.message, false);
  }
}

const valor = (id) => $(id).value.trim();
const numero = (id) => Number($(id).value);

// ---------- Carregar ----------

async function carregar() {
  cfg = await api('GET', '/api/admin/configuracoes');
  preencher();
  await carregarBackups();
}

function preencher() {
  for (const id of ['nomeIgreja', 'urlPublica', 'pedidoTitulo', 'pedidoIntro', 'pedidoObrigado', 'holyricsHost',
    'holyricsPorta', 'motivosPorSlide', 'segundosPorSlide', 'diasRespondidas', 'temaPadrao', 'horaBackup', 'backupsManter',
    'siteCultos', 'siteEndereco', 'sitePixChave', 'sitePixNome', 'sitePixCidade', 'siteInstagram', 'siteYoutube', 'siteWhatsapp']) {
    if ($(id) && document.activeElement !== $(id)) $(id).value = cfg[id] ?? '';
  }
  $('siteAtivo').checked = cfg.siteAtivo !== false;
  $('siteAgenda').checked = cfg.siteAgenda === true;
  $('sitePix').checked = cfg.sitePix !== false;
  $('siteGaleria').checked = cfg.siteGaleria !== false;
  $('endereco-inicio').textContent = (cfg.urlPublica || cfg.urlDetectada || '') + '/';
  $('urlPublica').placeholder = cfg.urlDetectada || '';
  $('dica-url').textContent = cfg.urlPublica
    ? 'O QR code aponta para ' + cfg.urlPublica + '/oracao'
    : 'Vazio: usa o endereço da rede local (' + cfg.urlDetectada + '). Preencha se o site está na internet.';

  // Mural
  const base = cfg.urlPublica || cfg.urlDetectada;
  const link = base + '/mural' + (cfg.chaveMural ? '?chave=' + encodeURIComponent(cfg.chaveMural) : '');
  $('link-mural').textContent = link;
  $('estado-mural').textContent = cfg.chaveMural ? 'Protegido com chave.' : 'Aberto: qualquer pessoa com o endereço vê o mural.';
  $('desativar-chave-mural').disabled = !cfg.chaveMural;

  // LGPD
  if (document.activeElement !== $('termoLgpdTexto')) $('termoLgpdTexto').value = cfg.termoLgpdEmVigor || '';
  $('versao-termo').textContent = '(versão ' + (cfg.termoLgpdVersao || 1) + (cfg.termoLgpdTexto ? '' : ', texto modelo') + ')';
  $('visitanteQrAtivo').checked = cfg.visitanteQrAtivo !== false;
  $('muralBoasVindas').checked = cfg.muralBoasVindas === true;
  $('link-visitante-admin').textContent = base + '/visitante';

  // Holyrics
  const agente = cfg.modo === 'agente';
  $('holyrics-local').hidden = agente;
  $('holyrics-agente').hidden = !agente;
  $('holyricsToken').value = '';
  $('holyricsToken').placeholder = cfg.holyricsTokenDefinido ? '•••••••• (deixe em branco para manter)' : 'Cole o token do Holyrics';
  $('dica-token').textContent = cfg.holyricsTokenDefinido ? 'Token definido.' : 'Token ainda não definido: os comandos de projeção não vão funcionar.';
  $('chave-agente').textContent = chaveAgenteVisivel ? (cfg.chaveAgente || '') : '••••••••••••';
  $('mostrar-chave-agente').textContent = chaveAgenteVisivel ? 'Ocultar' : 'Mostrar';

  // Agenda
  const ag = cfg.agenda || {};
  $('agendaUrl').value = '';
  $('agendaUrl').placeholder = cfg.agendaConfigurada
    ? '•••••••• (definido — cole um novo endereço para trocar)'
    : 'https://calendar.google.com/calendar/ical/…/basic.ics';
  if (document.activeElement !== $('agendaDiasMural')) $('agendaDiasMural').value = cfg.agendaDiasMural ?? 7;
  $('agendaMostrarDescricao').checked = cfg.agendaMostrarDescricao !== false;
  for (const id of ['smtpHost', 'smtpPorta', 'smtpUsuario', 'smtpRemetente', 'smtpDestinatario']) {
    if (document.activeElement !== $(id)) $(id).value = cfg[id] ?? '';
  }
  $('smtpSsl').checked = cfg.smtpSsl === true;
  $('smtpSenha').value = '';
  $('smtpSenha').placeholder = cfg.smtpSenhaDefinida ? '•••••••• (deixe vazio para manter)' : 'Senha de aplicativo (se exigida)';
  $('atualizar-agenda').disabled = !ag.configurada;
  $('remover-agenda').disabled = !cfg.agendaConfigurada;
  preencherGoogle(cfg, ag);
  const estado = $('estado-agenda');
  if (!ag.configurada) {
    estado.textContent = 'Agenda desligada.';
    estado.className = 'dica';
  } else if (ag.erro) {
    mensagem(estado, 'Problema na última atualização: ' + ag.erro +
      (ag.atualizado ? ' (mostrando a cópia de ' + dataCurta(ag.atualizado) + ')' : ''), false);
  } else {
    mensagem(estado, 'Conectada. ' + (ag.proximos30dias ?? 0) + ' evento(s) nos próximos 30 dias' +
      (ag.atualizado ? ' · atualizada ' + dataCurta(ag.atualizado) : '') + '.');
  }

  // Backup e sessões
  $('pasta-backup').textContent = 'Pasta dos backups no servidor: ' + cfg.pastaBackup;
  $('qtd-sessoes').textContent = cfg.sessoes === 1 ? '1 aparelho conectado (este).' : cfg.sessoes + ' aparelhos conectados (incluindo este).';
  $('senhaNova').minLength = cfg.senhaMinima || 6;
  $('senhaNova').placeholder = 'Mínimo de ' + (cfg.senhaMinima || 6) + ' caracteres';
}

// ---------- Igreja, projeção, Holyrics ----------

$('form-inicio').addEventListener('submit', (e) => {
  e.preventDefault();
  const campos = { siteAtivo: $('siteAtivo').checked, siteAgenda: $('siteAgenda').checked, sitePix: $('sitePix').checked, siteGaleria: $('siteGaleria').checked };
  for (const id of ['siteCultos', 'siteEndereco', 'sitePixChave', 'sitePixNome', 'sitePixCidade', 'siteInstagram', 'siteYoutube', 'siteWhatsapp']) {
    campos[id] = $(id).value.trim();
  }
  salvar(campos, $('res-inicio'));
});

$('muralBoasVindas').addEventListener('change', () => salvar({ muralBoasVindas: $('muralBoasVindas').checked }, $('res-mural')));

$('form-lgpd').addEventListener('submit', (e) => {
  e.preventDefault();
  salvar({ termoLgpdTexto: $('termoLgpdTexto').value.trim(), visitanteQrAtivo: $('visitanteQrAtivo').checked }, $('res-lgpd'));
});
$('termo-padrao').addEventListener('click', () => {
  if (!confirm('Trocar o texto atual pelo modelo? Isso cria uma versão nova do termo.')) return;
  salvar({ termoLgpdTexto: '' }, $('res-lgpd'));
});

$('form-igreja').addEventListener('submit', (e) => {
  e.preventDefault();
  salvar({
    nomeIgreja: valor('nomeIgreja'),
    urlPublica: valor('urlPublica'),
    pedidoTitulo: valor('pedidoTitulo'),
    pedidoIntro: valor('pedidoIntro'),
    pedidoObrigado: valor('pedidoObrigado'),
  }, $('res-igreja'));
});

$('form-email').addEventListener('submit', (e) => {
  e.preventDefault();
  salvar({ smtpHost: valor('smtpHost'), smtpPorta: numero('smtpPorta'), smtpUsuario: valor('smtpUsuario'),
    smtpSenha: $('smtpSenha').value, smtpRemetente: valor('smtpRemetente'),
    smtpDestinatario: valor('smtpDestinatario'), smtpSsl: $('smtpSsl').checked }, $('res-email'));
});
$('testar-email').addEventListener('click', async () => {
  try { await api('POST', '/api/admin/testar-email'); mensagem($('res-email'), 'E-mail de teste enviado.'); }
  catch (e) { mensagem($('res-email'), e.message, false); }
});

$('form-projecao').addEventListener('submit', (e) => {
  e.preventDefault();
  salvar({
    motivosPorSlide: numero('motivosPorSlide'),
    segundosPorSlide: numero('segundosPorSlide'),
    diasRespondidas: numero('diasRespondidas'),
    temaPadrao: valor('temaPadrao'),
  }, $('res-projecao'));
});

$('buscar-temas-holyrics').addEventListener('click', async () => {
  const lista = $('lista-temas-holyrics');
  const estado = $('estado-temas');
  estado.textContent = 'Consultando Holyrics…';
  try {
    const dados = await api('GET', '/api/admin/temas?atualizar=1');
    lista.replaceChildren();
    for (const tema of dados.temas) {
      const botao = document.createElement('button');
      botao.type = 'button';
      botao.className = 'botao secundario';
      botao.style.cssText = 'display:grid;gap:6px;margin:6px;min-width:160px;max-width:200px;';
      if (tema.thumbnail) {
        const img = document.createElement('img');
        img.alt = 'Prévia do tema ' + tema.name;
        img.width = 160;
        const mime = tema.thumbnail.startsWith('/9j/') ? 'image/jpeg'
          : tema.thumbnail.startsWith('UklGR') ? 'image/webp' : 'image/png';
        img.src = 'data:' + mime + ';base64,' + tema.thumbnail;
        botao.append(img);
      }
      const nome = document.createElement('span');
      nome.textContent = tema.name;
      botao.append(nome);
      botao.addEventListener('click', () => {
        $('temaPadrao').value = tema.name;
        estado.textContent = 'Selecionado: ' + tema.name + '. Clique em Salvar para aplicar.';
      });
      lista.append(botao);
    }
    estado.textContent = dados.desatualizado ? 'Lista salva (Holyrics indisponível): confirme antes de projetar.'
      : !dados.miniaturasDisponiveis && dados.temas.length ? 'Temas carregados sem miniaturas: libere GetThumbnail no token do Holyrics.'
        : 'Atualizado em ' + dados.atualizadoEm + '. A miniatura é ilustrativa.';
  } catch (err) {
    estado.textContent = err.message + ' O tema digitado foi preservado.';
  }
});

$('form-holyrics').addEventListener('submit', (e) => {
  e.preventDefault();
  salvar({ holyricsHost: valor('holyricsHost'), holyricsPorta: numero('holyricsPorta'), holyricsToken: valor('holyricsToken') }, $('res-holyrics'));
});

async function testarHolyrics(saida) {
  mensagem(saida, 'Testando…');
  try {
    const r = await api('POST', '/api/admin/testar-holyrics');
    mensagem(saida, r.status === 'ok' ? 'Holyrics respondeu: conectado.' : (r.error || 'Sem resposta do Holyrics.'), r.status === 'ok');
  } catch (err) {
    mensagem(saida, err.message, false);
  }
}
$('testar-holyrics').addEventListener('click', () => testarHolyrics($('res-holyrics')));
$('testar-holyrics-agente').addEventListener('click', () => testarHolyrics($('res-agente')));

// ---------- Agenda ----------

$('form-agenda').addEventListener('submit', (e) => {
  e.preventDefault();
  const campos = { agendaDiasMural: numero('agendaDiasMural'), agendaMostrarDescricao: $('agendaMostrarDescricao').checked };
  if (valor('agendaUrl')) campos.agendaUrl = valor('agendaUrl');
  $('teste-agenda').replaceChildren();
  salvar(campos, $('res-agenda'));
});

$('testar-agenda').addEventListener('click', async () => {
  const saida = $('res-agenda');
  const url = valor('agendaUrl');
  if (!url) {
    mensagem(saida, 'Cole o endereço para testar.', false);
    return;
  }
  mensagem(saida, 'Testando…');
  try {
    const r = await api('POST', '/api/admin/agenda/testar', { url });
    mensagem(saida, `Funcionou: ${r.eventos} evento(s) nos próximos 60 dias. Clique em Salvar para usar.`);
    $('teste-agenda').replaceChildren(...r.proximos.map((t) => el('li', {}, t)));
  } catch (err) {
    mensagem(saida, err.message, false);
    $('teste-agenda').replaceChildren();
  }
});

$('atualizar-agenda').addEventListener('click', async () => {
  try {
    mensagem($('res-agenda'), 'Atualizando…');
    const r = await api('POST', '/api/admin/agenda/atualizar');
    await carregar();
    mensagem($('res-agenda'), r.erro ? r.erro : `Atualizada: ${r.eventos.length} evento(s) nos próximos 30 dias.`, !r.erro);
  } catch (err) {
    mensagem($('res-agenda'), err.message, false);
  }
});

// Conta de serviço: criar e editar eventos pelo painel e pelo tablet.
let trocandoChave = false;

function preencherGoogle(cfg, ag) {
  const ligada = ag.modo === 'google';
  $('google-ligada').hidden = !ligada;
  $('form-google').hidden = ligada && !trocandoChave;
  $('cancelar-troca').hidden = !(ligada && trocandoChave);
  $('email-conta').textContent = ag.contaServico || '';
  if (document.activeElement !== $('agendaCalendarioId')) $('agendaCalendarioId').value = cfg.agendaCalendarioId || ag.calendarioId || '';
  const estado = $('estado-google');
  if (!ligada) {
    estado.textContent = 'Desligada: a agenda é só para leitura.';
    estado.className = 'dica';
  } else if (ag.erro) {
    mensagem(estado, 'Ligada, mas a última atualização falhou: ' + ag.erro, false);
    estado.append(' ', el('a', { href: '/ajuda/agenda-google#problemas', target: '_blank', rel: 'noopener' }, 'Como resolver'));
  } else {
    mensagem(estado, 'Ligada: o painel e o tablet criam, editam e excluem eventos.');
  }
}

function erroComAjuda(saida, err) {
  saida.className = 'erro';
  saida.replaceChildren(...textoDoErro(err).flat().filter(Boolean));
}

$('form-google').addEventListener('submit', async (e) => {
  e.preventDefault();
  const saida = $('res-form-google');
  const arquivo = $('arquivo-chave').files[0];
  if (!arquivo) {
    mensagem(saida, 'Escolha o arquivo .json da chave.', false);
    return;
  }
  if (arquivo.size > 20000) {
    mensagem(saida, 'Esse arquivo é grande demais para ser a chave da conta de serviço.', false);
    return;
  }
  mensagem(saida, 'Testando com o Google…');
  try {
    const r = await api('POST', '/api/admin/agenda/conta-servico', { chave: await arquivo.text(), calendarioId: valor('agendaCalendarioId') });
    $('arquivo-chave').value = '';
    trocandoChave = false;
    saida.textContent = '';
    await carregar();
    mensagem($('res-google'), `Tudo certo: ligada à agenda "${r.agenda}".`);
  } catch (err) {
    erroComAjuda(saida, err);
  }
});

$('copiar-email-conta').addEventListener('click', () => copiar($('email-conta').textContent, $('res-google')));

$('testar-google').addEventListener('click', async () => {
  const saida = $('res-google');
  mensagem(saida, 'Testando…');
  try {
    const r = await api('POST', '/api/admin/agenda/conta-servico/testar');
    await carregar();
    mensagem(saida, `Funcionando: a conta pode alterar a agenda "${r.agenda}".`);
  } catch (err) {
    erroComAjuda(saida, err);
  }
});

$('trocar-google').addEventListener('click', () => {
  trocandoChave = true;
  carregar();
});
$('cancelar-troca').addEventListener('click', () => {
  trocandoChave = false;
  carregar();
});

$('desligar-google').addEventListener('click', async () => {
  if (!await confirmar('Desligar a edição da agenda?',
    'A chave é apagada do servidor e a agenda volta a ser só para leitura (pelo endereço iCal, se houver). Os eventos no Google não são alterados. Para cortar o acesso de vez, remova também o compartilhamento da agenda com a conta de serviço.',
    'Desligar')) return;
  try {
    await api('DELETE', '/api/admin/agenda/conta-servico');
    await carregar();
    mensagem($('estado-google'), 'Edição desligada.');
  } catch (err) {
    erroComAjuda($('res-google'), err);
  }
});

$('remover-agenda').addEventListener('click', async () => {
  if (!await confirmar('Desligar a agenda?', 'Os eventos deixam de aparecer na TV, no tablet e no resumo. A agenda no Google não é alterada.', 'Desligar')) return;
  await salvar({ agendaUrl: '' }, $('res-agenda'));
});

// ---------- Chaves ----------

async function copiar(texto, saida) {
  try {
    await navigator.clipboard.writeText(texto);
    mensagem(saida, 'Copiado.');
  } catch {
    mensagem(saida, 'Não foi possível copiar: selecione e copie manualmente.', false);
  }
}

$('copiar-mural').addEventListener('click', () => copiar($('link-mural').textContent, $('res-mural')));
$('nova-chave-mural').addEventListener('click', async () => {
  if (!await confirmar('Gerar nova chave do mural?', 'O link atual da TV deixa de funcionar. Depois, abra o novo link na TV.', 'Gerar nova')) return;
  await api('POST', '/api/admin/chave', { tipo: 'mural' });
  await carregar();
  mensagem($('res-mural'), 'Nova chave gerada. Atualize o link na TV.');
});
$('desativar-chave-mural').addEventListener('click', async () => {
  if (!await confirmar('Deixar o mural aberto?', 'Qualquer pessoa com o endereço verá os recados e os motivos de oração públicos.', 'Deixar aberto')) return;
  await api('POST', '/api/admin/chave', { tipo: 'mural-desativar' });
  await carregar();
  mensagem($('res-mural'), 'Mural aberto, sem chave.');
});

$('mostrar-chave-agente').addEventListener('click', () => {
  chaveAgenteVisivel = !chaveAgenteVisivel;
  preencher();
});
$('copiar-chave-agente').addEventListener('click', () => copiar(cfg.chaveAgente || '', $('res-agente')));
$('nova-chave-agente').addEventListener('click', async () => {
  if (!await confirmar('Gerar nova chave do agente?', 'O agente do PC da igreja é desconectado agora e só volta depois que a chave nova for colocada no agente.json.', 'Gerar nova')) return;
  await api('POST', '/api/admin/chave', { tipo: 'agente' });
  chaveAgenteVisivel = true;
  await carregar();
  mensagem($('res-agente'), 'Nova chave gerada. Copie e atualize o agente.json no PC da igreja.');
});

// ---------- Backup ----------

$('form-backup').addEventListener('submit', (e) => {
  e.preventDefault();
  salvar({ horaBackup: valor('horaBackup'), backupsManter: numero('backupsManter') }, $('res-backup'));
});

$('baixar-agora').addEventListener('click', async () => {
  try {
    mensagem($('res-backup'), 'Gerando…');
    await baixarArquivo('/api/backups/agora/download', 'diako-backup.zip');
    mensagem($('res-backup'), 'Backup baixado.');
  } catch (err) {
    mensagem($('res-backup'), err.message, false);
  }
});

$('gravar-agora').addEventListener('click', async () => {
  try {
    const r = await api('POST', '/api/backup');
    mensagem($('res-backup'), 'Gravado: ' + r.nome);
    await carregarBackups();
  } catch (err) {
    mensagem($('res-backup'), err.message, false);
  }
});

async function carregarBackups() {
  const r = await api('GET', '/api/backups');
  const linhas = r.backups.map((b) => el('tr', {},
    el('td', {}, el('div', { style: 'font-weight:500' }, b.nome), el('div', { class: 'dica' }, dataCurta(b.criado))),
    el('td', {}, tamanhoLegivel(b.tamanho)),
    el('td', { class: 'acoes-tabela' },
      botao('Baixar', () => baixarArquivo('/api/backups/' + encodeURIComponent(b.nome) + '/download', b.nome)
        .catch((err) => mensagem($('res-backup'), err.message, false))),
      botao('Restaurar', () => restaurarDaLista(b.nome)),
      botao('Excluir', async () => {
        if (!await confirmar('Excluir backup?', b.nome, 'Excluir')) return;
        await api('DELETE', '/api/backups/' + encodeURIComponent(b.nome));
        await carregarBackups();
      }, 'perigo pequeno'))));
  $('lista-backups').replaceChildren(...(linhas.length ? linhas : [el('tr', {}, el('td', { colspan: '3', class: 'dica' }, 'Nenhum backup ainda.'))]));
}

function descreverRestauracao(r) {
  const c = r.colecoes || {};
  return `Restaurado: ${c.recados ?? 0} recado(s), ${c.motivos ?? 0} motivo(s), ${c.membros ?? 0} membro(s), ` +
    `${r.cartazes} cartaz(es)${r.configuracoes ? ' e configurações' : ''}. Backup de segurança: ${r.backupSeguranca}.`;
}

const avisoRestaurar = 'Os recados, motivos de oração, aniversariantes, histórico e cartazes atuais serão substituídos pelos do backup. ' +
  'Antes, um backup de segurança do estado atual é gravado no servidor.';

async function restaurarDaLista(nome) {
  if (!await confirmar('Restaurar ' + nome + '?', avisoRestaurar, 'Restaurar')) return;
  const saida = $('res-restaurar');
  try {
    mensagem(saida, 'Restaurando…');
    const r = await api('POST', '/api/backups/' + encodeURIComponent(nome) + '/restaurar', { configuracoes: $('restaurar-config').checked });
    mensagem(saida, descreverRestauracao(r));
    await carregar();
  } catch (err) {
    mensagem(saida, err.message, false);
  }
  saida.scrollIntoView({ behavior: 'smooth', block: 'center' });
}

$('restaurar-arquivo').addEventListener('click', async () => {
  const saida = $('res-restaurar');
  const arquivo = $('arquivo-restaurar').files[0];
  if (!arquivo) {
    mensagem(saida, 'Escolha o arquivo .zip do backup.', false);
    return;
  }
  if (!await confirmar('Restaurar ' + arquivo.name + '?', avisoRestaurar, 'Restaurar')) return;
  try {
    mensagem(saida, 'Enviando e restaurando…');
    const q = $('restaurar-config').checked ? '?configuracoes=1' : '';
    const r = await api('POST', '/api/backups/restaurar' + q, arquivo, { bruto: true, tipo: 'application/zip' });
    mensagem(saida, descreverRestauracao(r));
    $('arquivo-restaurar').value = '';
    await carregar();
  } catch (err) {
    mensagem(saida, err.message, false);
  }
});

// ---------- Senha e sessões ----------

$('form-senha').addEventListener('submit', async (e) => {
  e.preventDefault();
  const saida = $('res-senha');
  if ($('senhaNova').value !== $('senhaConfirma').value) {
    mensagem(saida, 'A nova senha e a confirmação não são iguais.', false);
    return;
  }
  try {
    const r = await api('POST', '/api/admin/senha', {
      atual: $('senhaAtual').value,
      nova: $('senhaNova').value,
      encerrarSessoes: $('encerrarSessoes').checked,
    });
    e.target.reset();
    mensagem(saida, 'Senha trocada.' + (r.sessoesEncerradas ? ` ${r.sessoesEncerradas} aparelho(s) desconectado(s).` : ''));
    await carregar();
  } catch (err) {
    mensagem(saida, err.message, false);
  }
});

$('encerrar-sessoes').addEventListener('click', async () => {
  if (!await confirmar('Desconectar os outros aparelhos?', 'O tablet e outros navegadores precisarão entrar de novo com a senha.', 'Desconectar')) return;
  const r = await api('POST', '/api/admin/sessoes/encerrar');
  mensagem($('res-sessoes'), r.sessoesEncerradas + ' aparelho(s) desconectado(s).');
  await carregar();
});

// ---------- Início ----------

async function iniciar() {
  let eu;
  try {
    eu = await api('GET', '/api/eu');
  } catch {
    return; // sessão expirada: api() já voltou para o login
  }
  $('login').hidden = true;
  $('app').hidden = false;
  const admin = eu.permissoes.includes('admin');
  $('layout-admin').hidden = !admin;
  $('sem-acesso').hidden = admin;
  if (!admin) {
    $('texto-sem-acesso').textContent = `Você entrou como ${eu.nome} (${eu.perfilNome}). Só o perfil Administrador mexe nas configurações.`;
    return;
  }
  try {
    await carregar();
    await carregarUsuarios();
  } catch (err) {
    if (token) mensagem($('res-igreja'), 'Não foi possível carregar as configurações: ' + err.message, false);
  }
}

// ---------- Usuários e perfis ----------

let perfis = [];

async function carregarUsuarios() {
  const r = await api('GET', '/api/admin/usuarios');
  perfis = r.perfis;
  if (!$('u-perfil').options.length) {
    $('u-perfil').replaceChildren(...perfis.map((p) => el('option', { value: p.id }, p.nome)));
    $('u-perfil').value = 'secretaria';
  }
  mostrarDicaPerfil();
  $('tabela-usuarios').tBodies[0].replaceChildren(...(r.usuarios.length
    ? r.usuarios.map(linhaUsuario)
    : [el('tr', {}, el('td', { colspan: 5, class: 'dica' }, 'Ninguém cadastrado ainda. Hoje só a conta principal entra.'))]));
  montarMatriz(r.permissoes);
  await carregarTablets();
}

async function carregarTablets() {
  const r = await api('GET', '/api/admin/tablets-locais');
  $('bloco-tablets').hidden = !r.modoAgente;
  $('tabela-tablets').tBodies[0].replaceChildren(...(r.tablets.length
    ? r.tablets.map((t) => el('tr', { style: t.ativo ? '' : 'opacity:.55' },
      el('td', {}, t.aparelho),
      el('td', {}, t.conta, t.ativo ? null : el('span', { class: 'dica' }, ' (sem acesso: conta desativada ou sem "Projetar")')),
      el('td', { class: 'dica' }, dataCurta(t.criadoEm)),
      el('td', { class: 'acoes-tabela' }, botao('Remover', async () => {
        if (!await confirmar('Remover tablet?', `${t.aparelho} deixa de falar direto com o PC da igreja e passa a usar só a internet.`, 'Remover')) return;
        await api('DELETE', '/api/admin/tablets-locais/' + t.id);
        mensagem($('res-tablets'), 'Tablet removido.');
        await carregarTablets();
      }, 'perigo pequeno'))))
    : [el('tr', {}, el('td', { colspan: 4, class: 'dica' }, 'Nenhum tablet pareado.'))]));
}

function mostrarDicaPerfil() {
  const p = perfis.find((x) => x.id === $('u-perfil').value);
  $('u-perfil-dica').textContent = p ? p.descricao : '';
}
$('u-perfil').addEventListener('change', mostrarDicaPerfil);

function linhaUsuario(u) {
  const saida = $('res-usuario');
  const seletor = el('select', { 'aria-label': 'Perfil de ' + u.nome },
    perfis.map((p) => el('option', { value: p.id, selected: p.id === u.perfil }, p.nome)));
  seletor.addEventListener('change', async () => {
    try {
      await api('PUT', '/api/admin/usuarios/' + u.id, { perfil: seletor.value });
      mensagem(saida, `${u.nome} agora tem o perfil ${seletor.selectedOptions[0].textContent} e precisa entrar de novo.`);
      await carregarUsuarios();
    } catch (err) {
      mensagem(saida, err.message, false);
    }
  });
  const acoes = el('td', { class: 'acoes-tabela' },
    botao('Nova senha', async () => {
      if (!await confirmar('Gerar nova senha?', `${u.nome} sai de todos os aparelhos e precisa entrar com a senha nova.`, 'Gerar')) return;
      const r = await api('POST', `/api/admin/usuarios/${u.id}/senha`);
      mostrarSenhaGerada(u.nome, u.login, r.senhaTemporaria);
    }),
    botao(u.ativo ? 'Desativar' : 'Reativar', async () => {
      await api('PUT', '/api/admin/usuarios/' + u.id, { ativo: !u.ativo });
      await carregarUsuarios();
    }),
    botao('Excluir', async () => {
      if (!await confirmar('Excluir usuário?', `${u.nome} perde o acesso. O histórico do que foi feito com esse usuário continua registrado.`, 'Excluir')) return;
      await api('DELETE', '/api/admin/usuarios/' + u.id);
      await carregarUsuarios();
    }, 'perigo pequeno'));
  return el('tr', { style: u.ativo ? '' : 'opacity:.55' },
    el('td', {}, u.nome, u.ativo ? null : el('span', { class: 'dica' }, ' (desativado)')),
    el('td', {}, el('code', {}, u.login)),
    el('td', {}, seletor),
    el('td', { class: 'dica' }, u.ultimoAcesso ? dataCurta(u.ultimoAcesso) : 'nunca'),
    acoes);
}

function mostrarSenhaGerada(nome, login, senha) {
  const caixa = $('senha-gerada');
  caixa.replaceChildren(
    el('strong', {}, `Acesso de ${nome}: `), 'usuário ', el('code', {}, login), ' e senha ', el('code', {}, senha), '. ',
    'Anote e entregue à pessoa; ela não aparece de novo. A pessoa pode trocar em "Minha senha", no painel. ',
    botao('Copiar', () => copiar(`Usuário: ${login}\nSenha: ${senha}`, $('res-usuario'))));
  caixa.hidden = false;
}

function montarMatriz(permissoes) {
  $('matriz-perfis').replaceChildren(
    el('thead', {}, el('tr', {}, el('th', {}, 'Pode'), perfis.map((p) => el('th', { style: 'text-align:center' }, p.nome)))),
    el('tbody', {}, permissoes.map((perm) => el('tr', {},
      el('td', {}, perm.descricao),
      perfis.map((p) => el('td', { style: 'text-align:center' }, p.permissoes.includes(perm.id)
        ? el('span', { 'aria-label': 'sim' }, '✓') : el('span', { 'aria-label': 'não', class: 'dica' }, '—')))))));
}

$('form-usuario').addEventListener('submit', async (e) => {
  e.preventDefault();
  const saida = $('res-usuario');
  try {
    const r = await api('POST', '/api/admin/usuarios', { nome: valor('u-nome'), login: valor('u-login'), perfil: $('u-perfil').value });
    $('u-nome').value = '';
    $('u-login').value = '';
    mensagem(saida, 'Pessoa adicionada.');
    mostrarSenhaGerada(r.usuario.nome, r.usuario.login, r.senhaTemporaria);
    await carregarUsuarios();
  } catch (err) {
    mensagem(saida, err.message, false);
  }
});

if (token) iniciar();
else sair();
