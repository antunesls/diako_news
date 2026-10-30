'use strict';
// Ensaio da Palavra no painel: as contas do tempo por tópico, testáveis no Node.

/**
 * Tempo de cada tópico no ensaio. [marcas] são as trocas de trecho, em ordem ({trecho, em} com o
 * índice do trecho e o instante em ms); [fim] é quando o ensaio terminou. Voltar a um trecho soma
 * de novo no tópico dele. Trechos antes do primeiro tópico contam como "Início".
 */
function tempoPorTopico(trechos, marcas, fim) {
  const segundos = new Map();
  for (let i = 0; i < marcas.length; i++) {
    const ate = i + 1 < marcas.length ? marcas[i + 1].em : fim;
    const topico = trechos[marcas[i].trecho].topico || 'Início';
    segundos.set(topico, (segundos.get(topico) || 0) + Math.max(0, ate - marcas[i].em) / 1000);
  }
  // Na ordem do texto, não na ordem em que o pastor passou.
  const ordem = [...new Set(trechos.map((t) => t.topico || 'Início'))];
  return ordem.filter((t) => segundos.has(t)).map((topico) => ({ topico, segundos: Math.round(segundos.get(topico)) }));
}

/** Resumo para a tabela: previsto, ensaio e diferença (segundos; positivo = passou do previsto). */
function resumoDoEnsaio(trechos, marcas, fim, minutosTopicos) {
  const linhas = tempoPorTopico(trechos, marcas, fim).map(({ topico, segundos }) => {
    const previsto = minutosTopicos[topico];
    return { topico, previsto: previsto ?? null, segundos, diferenca: previsto ? segundos - previsto * 60 : null };
  });
  return { linhas, totalSegundos: marcas.length ? Math.round((fim - marcas[0].em) / 1000) : 0 };
}

/** "3:05", "1:02:30", "-0:45" */
function duracaoLegivel(segundos) {
  const sinal = segundos < 0 ? '-' : '';
  const s = Math.abs(Math.round(segundos));
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = s % 60;
  return sinal + (h ? `${h}:${String(m).padStart(2, '0')}` : String(m)) + ':' + String(r).padStart(2, '0');
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { tempoPorTopico, resumoDoEnsaio, duracaoLegivel };
}
