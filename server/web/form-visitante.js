'use strict';
// Formulário de visitante compartilhado: QR público (/visitante), obreiro da recepção (/recepcao)
// e painel. Monta tudo sem innerHTML (o conteúdo vem de usuários) e só depende do estilo.css.
//
// montarFormVisitante(container, {
//   enviar: async (corpo) => resposta,     // POST para a API certa; lança Error com a mensagem
//   termo: {texto, versao} | null,         // texto da LGPD mostrado antes do "autorizo"
//   exigirAutorizacao: true,               // QR e obreiro: a pessoa precisa tocar em "autorizo"
//   textoAutorizo: '…',                    // frase do "autorizo"
//   textoBotao: 'Enviar',
//   publico: false,                        // QR: inclui o campo armadilha contra robôs
//   aoConcluir: (resposta) => {},          // depois de salvar (o formulário já foi limpo)
// }) → { limpar(), definirTermo(termo) }

(function () {
  const INTERESSES = [
    ['visitaPastoral', 'Quero receber uma visita'],
    ['oracao', 'Quero oração'],
    ['batismo', 'Quero saber sobre o batismo'],
    ['celula', 'Quero participar de um grupo/célula'],
  ];
  const PARENTESCOS = [['conjuge', 'Cônjuge'], ['filho', 'Filho(a)'], ['outro', 'Outro (amigo, parente)']];

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
  const soDigitos = (s) => (s || '').replace(/\D/g, '');
  function mascaraData(v) {
    const d = soDigitos(v).slice(0, 8);
    return [d.slice(0, 2), d.slice(2, 4), d.slice(4)].filter(Boolean).join('/');
  }
  function mascaraTelefone(v) {
    const d = soDigitos(v).slice(0, 11);
    if (d.length <= 2) return d.length ? '(' + d : '';
    const meio = d.length === 11 ? 7 : 6;
    return '(' + d.slice(0, 2) + ') ' + d.slice(2, meio) + (d.length > meio ? '-' + d.slice(meio) : '');
  }
  function comMascara(input, mascara) {
    input.addEventListener('input', () => {
      if (input.selectionStart === input.value.length) input.value = mascara(input.value);
    });
    return input;
  }
  /** "05/03" ou "05/03/2015" → idade (null sem o ano). */
  function idadePelo(aniversario) {
    const r = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(aniversario || '');
    if (!r) return null;
    const hoje = new Date();
    let i = hoje.getFullYear() - Number(r[3]);
    if (hoje.getMonth() + 1 < Number(r[2]) || (hoje.getMonth() + 1 === Number(r[2]) && hoje.getDate() < Number(r[1]))) i--;
    return i;
  }

  let estiloPronto = false;
  function estilo() {
    if (estiloPronto) return;
    estiloPronto = true;
    document.head.append(el('style', {}, `
      .fv-grade { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(190px, 100%), 1fr)); gap: 0 16px; }
      .fv-secao { font-size: 17px; margin: 8px 0 12px; }
      .fv-acompanhante { border: 1px solid var(--linha); border-radius: 14px; padding: 12px 14px 2px; margin-bottom: 12px; position: relative; background: var(--campo); }
      .fv-acompanhante .fv-tirar { position: absolute; top: 8px; right: 8px; }
      .fv-pergunta { border: 0; padding: 0; margin: 0 0 18px; }
      .fv-pergunta legend { font-weight: 600; margin-bottom: 8px; }
      .fv-interesses { display: flex; flex-direction: column; gap: 10px; margin-bottom: 18px; }
      .fv-termo { white-space: pre-line; max-height: 34vh; overflow: auto; padding: 12px 14px; border: 1px solid var(--linha); border-radius: 12px; background: var(--campo); font-size: 14.5px; line-height: 1.55; margin-bottom: 14px; }
      .fv-link { border: 0; background: none; padding: 0; color: var(--primaria); font: inherit; font-weight: 600; cursor: pointer; }
    `));
  }

  window.montarFormVisitante = function (container, opcoes) {
    estilo();
    const o = {
      exigirAutorizacao: true,
      textoAutorizo: 'Li e autorizo a igreja a guardar e usar estes dados como descrito acima.',
      textoBotao: 'Enviar',
      publico: false,
      aoConcluir: () => {},
      ...opcoes,
    };
    let termo = o.termo || null;

    const nome = el('input', { type: 'text', id: 'fv-nome', maxlength: '100', autocomplete: o.publico ? 'name' : 'off' });
    const aniversario = comMascara(el('input', { type: 'text', id: 'fv-aniversario', inputmode: 'numeric', maxlength: '10', placeholder: '05/03', autocomplete: 'off' }), mascaraData);
    const telefone = comMascara(el('input', { type: 'tel', id: 'fv-telefone', maxlength: '20', placeholder: '(11) 98888-7777', autocomplete: o.publico ? 'tel' : 'off' }), mascaraTelefone);
    const comoConheceu = el('input', { type: 'text', id: 'fv-como', maxlength: '200', list: 'fv-opcoes-como' });
    const listaComo = el('datalist', { id: 'fv-opcoes-como' },
      ...['Convite de amigo ou parente', 'Redes sociais', 'Passou em frente', 'Evento da igreja'].map((v) => el('option', { value: v })));

    const acompanhantes = el('div', {});
    function adicionarAcompanhante() {
      const n = acompanhantes.children.length + 1;
      const id = 'fv-a' + Date.now() + n;
      const parentesco = el('select', { id: id + '-par' }, ...PARENTESCOS.map(([v, t]) => el('option', { value: v }, t)));
      const autorizo = el('input', { type: 'checkbox', id: id + '-aut' });
      const linhaAutorizo = el('label', { class: 'marcar campo' }, autorizo,
        el('span', {}, 'Esta pessoa também leu e autorizou o uso dos dados', el('br'),
          el('span', { class: 'dica' }, 'Para filhos menores de 18 anos, vale a autorização de quem preencheu.')));
      parentesco.addEventListener('change', () => { linhaAutorizo.hidden = parentesco.value === 'filho'; });
      const bloco = el('div', { class: 'fv-acompanhante', 'data-acompanhante': '' },
        el('button', { type: 'button', class: 'fv-link fv-tirar', 'aria-label': 'Tirar esta pessoa', onclick: () => bloco.remove() }, 'Tirar'),
        el('div', { class: 'fv-grade' },
          el('div', { class: 'campo' }, el('label', { for: id + '-nome' }, 'Nome'), el('input', { type: 'text', id: id + '-nome', maxlength: '100', 'data-campo': 'nome', autocomplete: 'off' })),
          el('div', { class: 'campo' }, el('label', { for: id + '-aniv' }, 'Aniversário ', el('span', { class: 'dica' }, '(dia/mês)')),
            comMascara(el('input', { type: 'text', id: id + '-aniv', inputmode: 'numeric', maxlength: '10', placeholder: '05/03', 'data-campo': 'aniversario', autocomplete: 'off' }), mascaraData)),
          el('div', { class: 'campo' }, el('label', { for: id + '-par' }, 'Parentesco'), parentesco)),
        linhaAutorizo);
      acompanhantes.append(bloco);
      bloco.querySelector('input').focus();
    }

    const mencionarSim = el('input', { type: 'radio', name: 'fv-mencionar', value: 'sim' });
    const mencionarNao = el('input', { type: 'radio', name: 'fv-mencionar', value: 'nao' });

    const interesses = INTERESSES.map(([v, t]) => [v, el('input', { type: 'checkbox', value: v })]);
    const pedidoOracao = el('textarea', { id: 'fv-pedido', maxlength: '500', style: 'min-height:80px', placeholder: 'Se quiser, conte o motivo. Só o pastor vê.' });
    const campoPedido = el('div', { class: 'campo', hidden: true }, el('label', { for: 'fv-pedido' }, 'Pedido de oração ', el('span', { class: 'dica' }, '(opcional)')), pedidoOracao);
    interesses.find(([v]) => v === 'oracao')[1].addEventListener('change', (e) => { campoPedido.hidden = !e.target.checked; });

    const caixaTermo = el('div', { class: 'fv-termo', tabindex: '0', 'aria-label': 'Texto da autorização' });
    const versao = el('span', { class: 'dica' });
    const responsavel = el('input', { type: 'text', id: 'fv-responsavel', maxlength: '100', autocomplete: 'off' });
    const campoResponsavel = el('div', { class: 'campo' },
      el('label', { for: 'fv-responsavel' }, 'Nome do pai, mãe ou responsável ', el('span', { class: 'dica' }, '(só se quem preenche tem menos de 18 anos)')), responsavel);
    const autorizo = el('input', { type: 'checkbox', id: 'fv-autorizo' });
    const blocoTermo = el('div', {},
      el('h2', { class: 'fv-secao' }, 'Uso dos dados ', versao),
      caixaTermo, campoResponsavel,
      el('label', { class: 'marcar campo' }, autorizo, el('span', {}, o.textoAutorizo)));
    function definirTermo(t) {
      termo = t;
      caixaTermo.textContent = t ? t.texto : '';
      versao.textContent = t ? '(versão ' + t.versao + ')' : '';
      blocoTermo.hidden = !t;
    }

    const armadilha = o.publico
      ? el('div', { class: 'escondido', 'aria-hidden': 'true' }, el('label', { for: 'fv-website' }, 'Não preencha'),
        el('input', { type: 'text', id: 'fv-website', tabindex: '-1', autocomplete: 'off' }))
      : null;
    const erro = el('p', { class: 'erro', role: 'alert', hidden: true });
    const botao = el('button', { type: 'submit', class: 'botao', id: 'enviar' }, o.textoBotao);

    const form = el('form', { class: 'cartao', novalidate: true },
      el('div', { class: 'campo' }, el('label', { for: 'fv-nome' }, 'Nome'), nome),
      el('div', { class: 'fv-grade' },
        el('div', { class: 'campo' }, el('label', { for: 'fv-aniversario' }, 'Aniversário ', el('span', { class: 'dica' }, '(dia/mês)')), aniversario),
        el('div', { class: 'campo' }, el('label', { for: 'fv-telefone' }, 'Telefone / WhatsApp ', el('span', { class: 'dica' }, '(opcional)')), telefone)),
      el('div', { class: 'campo' }, el('label', { for: 'fv-como' }, 'Como conheceu a igreja? ', el('span', { class: 'dica' }, '(opcional)')), comoConheceu, listaComo),

      acompanhantes,
      el('p', { class: 'campo' }, el('button', { type: 'button', class: 'botao secundario pequeno', onclick: adicionarAcompanhante }, '+ Adicionar quem veio junto')),

      el('fieldset', { class: 'fv-pergunta' },
        el('legend', {}, 'O pastor pode citar o nome e dar as boas-vindas durante o culto?'),
        el('div', { class: 'chips' }, el('label', {}, mencionarSim, 'Sim, pode'), el('label', {}, mencionarNao, 'Prefiro que não')),
        el('p', { class: 'dica', style: 'margin:8px 0 0' }, 'Com "Sim", o nome também pode aparecer no telão e na TV de boas-vindas.')),

      el('h2', { class: 'fv-secao' }, 'Posso ajudar em algo? ', el('span', { class: 'dica' }, '(opcional)')),
      el('div', { class: 'fv-interesses' }, ...interesses.map(([v, input]) => el('label', { class: 'marcar' }, input, el('span', {}, INTERESSES.find((i) => i[0] === v)[1])))),
      campoPedido,

      blocoTermo, armadilha, erro, botao);
    container.replaceChildren(form);
    definirTermo(termo);

    function mostrarErro(msg, campo) {
      erro.textContent = msg;
      erro.hidden = !msg;
      if (campo) campo.focus();
      return false;
    }

    function limpar() {
      form.reset();
      acompanhantes.replaceChildren();
      campoPedido.hidden = true;
      mostrarErro('');
    }

    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      mostrarErro('');
      const dataOk = (v) => /^\d{2}\/\d{2}(\/\d{4})?$/.test(v);
      if (!nome.value.trim()) return mostrarErro('Escreva o nome.', nome);
      if (!dataOk(aniversario.value)) return mostrarErro('Aniversário: use dia/mês, por exemplo 05/03.', aniversario);
      const pessoas = [{ nome: nome.value, aniversario: aniversario.value, telefone: telefone.value }];
      for (const b of acompanhantes.querySelectorAll('[data-acompanhante]')) {
        const n = b.querySelector('[data-campo=nome]'), a = b.querySelector('[data-campo=aniversario]');
        if (!n.value.trim()) return mostrarErro('Escreva o nome de quem veio junto (ou toque em "Tirar").', n);
        if (!dataOk(a.value)) return mostrarErro(`Aniversário de ${n.value.trim()}: use dia/mês, por exemplo 05/03.`, a);
        pessoas.push({ nome: n.value, aniversario: a.value, parentesco: b.querySelector('select').value,
          autorizo: b.querySelector('input[type=checkbox]').checked });
      }
      if (!mencionarSim.checked && !mencionarNao.checked) return mostrarErro('Responda se o pastor pode citar a visita no culto.', mencionarSim);
      const idade = idadePelo(aniversario.value);
      if (termo && autorizo.checked && idade !== null && idade < 18 && !responsavel.value.trim()) {
        return mostrarErro('Para menores de 18 anos, escreva o nome do pai, da mãe ou do responsável.', responsavel);
      }
      if (termo && o.exigirAutorizacao && !autorizo.checked) return mostrarErro('Para enviar, leia e marque a autorização de uso dos dados.', autorizo);
      const corpo = {
        pessoas,
        comoConheceu: comoConheceu.value,
        mencionar: mencionarSim.checked,
        interesses: interesses.filter(([, i]) => i.checked).map(([v]) => v),
        pedidoOracao: campoPedido.hidden ? '' : pedidoOracao.value,
        responsavel: responsavel.value,
        autorizo: !!termo && autorizo.checked,
        ...(armadilha ? { website: armadilha.querySelector('input').value } : {}),
      };
      botao.disabled = true;
      const textoBotao = botao.textContent;
      botao.textContent = 'Enviando…';
      try {
        const r = await o.enviar(corpo);
        limpar();
        o.aoConcluir(r);
      } catch (err) {
        mostrarErro(err.message === 'Failed to fetch' ? 'Sem conexão com o servidor. Verifique a internet e tente de novo.' : err.message);
      } finally {
        botao.disabled = false;
        botao.textContent = textoBotao;
      }
    });

    return { limpar, definirTermo, focar: () => nome.focus() };
  };
})();
