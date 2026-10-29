'use strict';

let membrosAcesso = [];
let usuariosAcesso = [];

function preencherPessoas(select, pessoas) {
  select.replaceChildren(new Option('Escolha…', ''), ...pessoas.map((m) => new Option(m.nome, m.id)));
}

async function carregarAcessosEscala() {
  try {
    [membrosAcesso, { usuarios: usuariosAcesso }] = await Promise.all([
      api('GET', '/api/membros'), api('GET', '/api/acessos-escala'),
    ]);
    const disponiveis = membrosAcesso.filter((m) => !usuariosAcesso.some((u) => u.membroId === m.id));
    preencherPessoas($('acesso-membro'), disponiveis);
    preencherPessoas($('acesso-pastor-membro'), disponiveis);
    $('acesso-pastor').replaceChildren(new Option('Escolha…', ''),
      ...usuariosAcesso.filter((u) => (u.perfil === 'pastor' || u.perfil === 'ministro' || u.perfil === 'louvor') && !u.membroId)
        .map((u) => new Option(`${u.nome} (${u.login})`, u.id)));
    const lista = $('acessos-lista');
    lista.replaceChildren();
    for (const u of usuariosAcesso.filter((u) => u.membroId)) {
      const linha = document.createElement('p');
      linha.textContent = `${u.nome} · ${u.login} · ${u.perfil === 'pastor' ? 'Pastor' : u.perfil === 'ministro' ? 'Ministro' : u.perfil === 'louvor' ? 'Louvor' : 'Integrante'}`;
      if (u.perfil === 'integrante') {
        const redefinir = document.createElement('button');
        redefinir.type = 'button'; redefinir.className = 'botao secundario pequeno';
        redefinir.style.marginLeft = '10px'; redefinir.textContent = 'Nova senha';
        redefinir.addEventListener('click', async () => {
          if (!confirm(`Redefinir a senha de ${u.nome}? A sessão atual da pessoa será encerrada.`)) return;
          try {
            const r = await api('POST', `/api/acessos-escala/${encodeURIComponent(u.id)}/senha`);
            mensagem($('acesso-resultado'), `Senha temporária de ${u.nome}: ${r.senhaTemporaria}. Anote agora; ela não será mostrada novamente.`);
          } catch (err) { mensagem($('acesso-resultado'), err.message, false); }
        });
        linha.append(redefinir);
      }
      lista.append(linha);
    }
    if (!lista.children.length) lista.textContent = 'Nenhuma conta vinculada ainda.';
  } catch (err) { mensagem($('acesso-resultado'), err.message, false); }
}

carregar.acessos = carregarAcessosEscala;

$('form-acesso-escala').addEventListener('submit', async (e) => {
  e.preventDefault();
  const id = $('acesso-membro').value;
  const membro = membrosAcesso.find((m) => m.id === id);
  if (!membro) return;
  try {
    const r = await api('POST', '/api/acessos-escala', { membroId: id, nome: membro.nome, login: $('acesso-login').value.trim() });
    await carregarAcessosEscala();
    mensagem($('acesso-resultado'), `Usuário ${r.usuario.login} criado. Senha temporária: ${r.senhaTemporaria}. Anote agora; ela não será mostrada novamente.`);
    $('acesso-login').value = '';
  } catch (err) { mensagem($('acesso-resultado'), err.message, false); }
});

$('form-vinculo-escala').addEventListener('submit', async (e) => {
  e.preventDefault();
  try {
    await api('POST', '/api/acessos-escala/vincular', { usuarioId: $('acesso-pastor').value, membroId: $('acesso-pastor-membro').value });
    await carregarAcessosEscala();
    mensagem($('vinculo-resultado'), 'Conta vinculada. A pessoa já pode entrar com a senha atual.');
  } catch (err) { mensagem($('vinculo-resultado'), err.message, false); }
});
