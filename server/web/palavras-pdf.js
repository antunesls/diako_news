'use strict';
// Texto de um PDF para o editor de Palavras. A extração roda no navegador com a pdf.js (carregada
// só quando alguém escolhe um PDF); aqui ficam as regras para remontar os parágrafos, testáveis no Node.

const PDFJS_VERSAO = '4.10.38';
const PDFJS_BASE = `https://cdn.jsdelivr.net/npm/pdfjs-dist@${PDFJS_VERSAO}/build`;

/**
 * Remonta o texto a partir dos itens de cada página (como a pdf.js entrega: {str, hasEOL, transform}).
 * Linhas próximas formam um parágrafo; um espaço vertical maior separa parágrafos; números de página
 * soltos somem; palavra quebrada com hífen no fim da linha é juntada.
 */
function textoDasPaginasPdf(paginas) {
  const paragrafos = [];
  for (const itens of paginas) {
    // 1. Linhas: junta os pedaços até o fim de linha.
    const linhas = [];
    let atual = '';
    let y = null;
    for (const item of itens) {
      if (y === null && item.str.trim()) y = item.transform[5];
      atual += item.str;
      if (item.hasEOL) {
        linhas.push({ texto: atual.replace(/\s+/g, ' ').trim(), y });
        atual = '';
        y = null;
      }
    }
    if (atual.trim()) linhas.push({ texto: atual.replace(/\s+/g, ' ').trim(), y });

    // 2. Distância normal entre linhas (a mais comum), para achar o espaço entre parágrafos.
    const cheias = linhas.filter((l) => l.texto && l.y !== null);
    const saltos = [];
    for (let i = 1; i < cheias.length; i++) {
      const d = Math.round(cheias[i - 1].y - cheias[i].y);
      if (d > 0) saltos.push(d);
    }
    saltos.sort((a, b) => a - b);
    const normal = saltos.length ? saltos[Math.floor(saltos.length / 2)] : 0;

    // 3. Parágrafos.
    let paragrafo = '';
    let anterior = null;
    const fechar = () => {
      if (paragrafo.trim()) paragrafos.push(paragrafo.trim());
      paragrafo = '';
    };
    for (const l of linhas) {
      if (!l.texto) {
        fechar();
        anterior = null;
        continue;
      }
      if (/^\d{1,4}$/.test(l.texto)) continue; // número de página
      if (anterior && normal && anterior.y - l.y > normal * 1.4) fechar();
      if (!paragrafo) paragrafo = l.texto;
      else if (/[A-Za-zÀ-ÿ]-$/.test(paragrafo) && /^[a-zà-ÿ]/.test(l.texto)) paragrafo = paragrafo.slice(0, -1) + l.texto;
      else paragrafo += ' ' + l.texto;
      anterior = l;
    }
    fechar();
  }
  return paragrafos.join('\n\n');
}

/** Lê o PDF no navegador com a pdf.js e devolve o texto no formato do editor. */
async function textoDoPdf(arquivo) {
  let pdfjs;
  try {
    pdfjs = await import(`${PDFJS_BASE}/pdf.min.mjs`);
  } catch (_) {
    throw new Error('Não foi possível carregar o leitor de PDF (precisa de internet). Copie o texto do PDF e cole no editor.');
  }
  pdfjs.GlobalWorkerOptions.workerSrc = `${PDFJS_BASE}/pdf.worker.min.mjs`;
  let documento;
  try {
    documento = await pdfjs.getDocument({ data: await arquivo.arrayBuffer() }).promise;
  } catch (_) {
    throw new Error('Não foi possível abrir este PDF. Copie o texto e cole no editor.');
  }
  const paginas = [];
  for (let n = 1; n <= documento.numPages; n++) {
    const pagina = await documento.getPage(n);
    paginas.push((await pagina.getTextContent()).items);
  }
  const texto = textoDasPaginasPdf(paginas);
  if (!texto.trim()) throw new Error('Este PDF não tem texto (deve ser uma imagem escaneada). Copie o texto e cole no editor.');
  return texto;
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { textoDasPaginasPdf };
}
