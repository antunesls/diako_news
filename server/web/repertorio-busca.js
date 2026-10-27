'use strict';

const NOTAS_REPERTORIO = [
  ['C', 'C'], ['C#', 'C♯ / D♭'], ['D', 'D'], ['D#', 'D♯ / E♭'],
  ['E', 'E'], ['F', 'F'], ['F#', 'F♯ / G♭'], ['G', 'G'],
  ['G#', 'G♯ / A♭'], ['A', 'A'], ['A#', 'A♯ / B♭'], ['B', 'B'],
];
const TONS_REPERTORIO = [
  ['', 'Não definido'],
  ...NOTAS_REPERTORIO.map(([valor, texto]) => [valor, `${texto} maior`]),
  ...NOTAS_REPERTORIO.map(([valor, texto]) => [`${valor}m`, `${texto} menor`]),
];

function normalizarBusca(texto) {
  return String(texto || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase('pt-BR');
}

function statusParaFiltro(m) {
  if (m.ativo) return 'OK';
  return normalizarBusca(m.status).includes('analise') ? 'Em análise' : 'Inativo';
}

function tomCanonico(tom) {
  const valor = String(tom || '').trim().replaceAll('♯', '#').replaceAll('♭', 'b');
  const encontrado = /^([A-G])([#b]?)(m?)$/i.exec(valor);
  if (!encontrado) return '';
  const [, letra, acidente, menor] = encontrado;
  const nota = letra.toUpperCase() + acidente;
  const equivalentes = { Db: 'C#', Eb: 'D#', Gb: 'F#', Ab: 'G#', Bb: 'A#' };
  return (equivalentes[nota] || nota) + menor.toLowerCase();
}

function tomDaMusica(m) {
  if (m.tomSelecionado !== undefined && m.tomSelecionado !== null) return tomCanonico(m.tomSelecionado);
  const primeiraLinha = String(m.tomDiakonia || '').split(/\r?\n/)[0];
  const encontrado = primeiraLinha.match(/(?:^|[^A-Za-z])([A-G](?:#|b)?m?)(?=$|[^A-Za-z#])/i);
  return tomCanonico(encontrado?.[1]);
}

function distanciaAteDuas(a, b) {
  if (Math.abs(a.length - b.length) > 2) return 3;
  let anterior = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i++) {
    const atual = [i];
    for (let j = 1; j <= b.length; j++) {
      atual[j] = Math.min(atual[j - 1] + 1, anterior[j] + 1, anterior[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    }
    anterior = atual;
  }
  return anterior[b.length];
}

function pontuacao(m, termos) {
  const texto = normalizarBusca(`${m.titulo} ${m.cantor} ${m.compositor}`);
  const palavras = texto.split(/[^a-z0-9]+/).filter(Boolean);
  let total = 0;
  for (const termo of termos) {
    if (texto.includes(termo)) continue;
    const tolerancia = termo.length >= 6 ? 2 : termo.length >= 4 ? 1 : 0;
    if (!tolerancia || !palavras.some((palavra) => distanciaAteDuas(termo, palavra) <= tolerancia)) return null;
    total++;
  }
  return total;
}

function buscarRepertorio(musicas, { busca = '', status = '', tom = '' } = {}) {
  const termos = normalizarBusca(busca).split(/\s+/).filter(Boolean);
  return musicas.filter((m) => (!status || statusParaFiltro(m) === status) && (!tom || tomDaMusica(m) === tom))
    .map((m) => ({ m, pontos: pontuacao(m, termos) }))
    .filter(({ pontos }) => pontos !== null)
    .sort((a, b) => a.pontos - b.pontos || a.m.titulo.localeCompare(b.m.titulo, 'pt-BR'))
    .map(({ m }) => m);
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { buscarRepertorio, statusParaFiltro, tomCanonico, tomDaMusica, TONS_REPERTORIO };
}
