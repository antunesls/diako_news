'use strict';

// Uma única lista para a organização do menu. As permissões continuam sendo
// verificadas pelo servidor; aqui apenas escondemos as páginas não autorizadas.
const MENU_GRUPOS = [
  { nome: 'Início', itens: [
    { id: 'inicio', titulo: 'Visão geral', permissao: 'painel' },
  ] },
  { nome: 'Acompanhamento', itens: [
    { id: 'motivos', titulo: 'Motivos de oração', permissao: 'motivosVer', badge: 'badge' },
    { id: 'mensagens', titulo: 'Mensagens', permissao: 'mensagens', badge: 'badge-mensagens' },
    { id: 'membros', titulo: 'Membros', permissao: 'membros' },
  ] },
  { nome: 'Cultos', itens: [
    { id: 'escalas', titulo: 'Escalas', permissao: 'escalasVer' },
    { id: 'repertorio', titulo: 'Repertório', permissao: 'escalasVer' },
    { id: 'palavras', titulo: 'Palavras', permissao: 'palavras' },
  ] },
  { nome: 'Comunicação', itens: [
    { id: 'agenda', titulo: 'Agenda', permissao: 'agendaVer' },
    { id: 'recados', titulo: 'Recados', permissao: 'recados' },
    { id: 'cartazes', titulo: 'Cartazes', permissao: 'cartazes' },
    { id: 'galeria', titulo: 'Galeria', permissao: 'galeria' },
    { id: 'resumo', titulo: 'Resumo da semana', permissao: 'resumo' },
  ] },
  { nome: 'Operação', itens: [
    { id: 'historico', titulo: 'Histórico', permissao: 'painel' },
    { id: 'status', titulo: 'Status', permissao: 'painel' },
    { id: 'acessos', titulo: 'Acessos às escalas', permissao: 'acessosEscala' },
    { id: 'admin', titulo: 'Administração', permissao: 'admin', href: '/admin' },
  ] },
];

function gruposPermitidos(permissoes) {
  const autorizadas = new Set(permissoes);
  return MENU_GRUPOS.map((grupo) => ({
    nome: grupo.nome,
    itens: grupo.itens.filter((item) => autorizadas.has(item.permissao)),
  })).filter((grupo) => grupo.itens.length);
}

function montarMenuLateral(nav, permissoes) {
  const grupos = gruposPermitidos(permissoes);
  nav.replaceChildren(document.getElementById('fechar-menu'));
  for (const grupo of grupos) {
    const secao = document.createElement('section');
    secao.className = 'menu-grupo';
    const titulo = document.createElement('h2');
    titulo.textContent = grupo.nome;
    secao.append(titulo);
    for (const item of grupo.itens) {
      const elemento = document.createElement(item.href ? 'a' : 'button');
      elemento.className = 'menu-item';
      if (item.href) elemento.href = item.href;
      else {
        elemento.type = 'button';
        elemento.dataset.aba = item.id;
      }
      elemento.append(document.createTextNode(item.titulo));
      if (item.badge) {
        const badge = document.createElement('span');
        badge.id = item.badge;
        badge.className = 'badge';
        badge.hidden = true;
        elemento.append(badge);
      }
      secao.append(elemento);
    }
    nav.append(secao);
  }
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { gruposPermitidos, montarMenuLateral };
}
