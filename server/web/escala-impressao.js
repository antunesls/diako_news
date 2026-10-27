'use strict';

/** Só cultos com ao menos uma pessoa escalada na aba impressa. */
function cultosParaImpressao(cultos, tipo) {
  return cultos.filter((culto) => (culto.funcoes?.[tipo] || []).some((funcao) => (culto[tipo]?.[funcao] || []).length > 0));
}

if (typeof module !== 'undefined' && module.exports) module.exports = { cultosParaImpressao };
