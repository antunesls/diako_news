import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Culto já resolvido para o PDF: datas e nomes prontos, sem depender do servidor.
class FuncaoEscalaPdf {
  const FuncaoEscalaPdf(this.nome, this.pessoas);
  final String nome;
  final List<String> pessoas;
}

class MusicaEscalaPdf {
  const MusicaEscalaPdf(this.titulo, this.tom);
  final String titulo;
  final String tom;
}

class CultoEscalaPdf {
  const CultoEscalaPdf({
    required this.rotulo,
    required this.hora,
    required this.nome,
    required this.ceia,
    required this.funcoes,
    required this.musicas,
  });
  final String rotulo;
  final String hora;
  final String nome;
  final bool ceia;
  final List<FuncaoEscalaPdf> funcoes;
  final List<MusicaEscalaPdf> musicas;
}

// Cores do site (estilo.css): o impresso mantém a identidade da igreja.
final _verde = PdfColor.fromHex('1F5F5B');
final _verdeEscuro = PdfColor.fromHex('172C29');
final _cinza = PdfColor.fromHex('52615E');
final _borda = PdfColor.fromHex('BBC9C6');
final _bordaClara = PdfColor.fromHex('E0E8E6');
final _fundoCabecalho = PdfColor.fromHex('E4EFED');
final _linhaAlternada = PdfColor.fromHex('F3F7F6');

const _ordemFuncoes = <String, List<String>>{
  'pastoral': ['Direção', 'Pregação', 'Oração e ofertas', 'Santa Ceia'],
  'louvor': ['Ministro', 'Vocal', 'Teclado', 'Violão', 'Guitarra', 'Baixo', 'Bateria', 'Técnico de som', 'Projeção'],
};

/// A fonte base do PDF só desenha latin1: acentos passam direto e o resto
/// (travessão, aspas curvas, reticências, emojis) vira um equivalente legível.
String textoLatin1(String texto) {
  final saida = StringBuffer();
  for (final rune in texto.runes) {
    if (rune <= 0xFF) {
      saida.writeCharCode(rune);
    } else {
      saida.write(switch (rune) {
        0x2010 || 0x2011 || 0x2012 || 0x2013 || 0x2014 || 0x2015 || 0x2212 => '-',
        0x2018 || 0x2019 || 0x201A || 0x201B => "'",
        0x201C || 0x201D || 0x201E || 0x201F => '"',
        0x2026 => '...',
        _ => '?',
      });
    }
  }
  return saida.toString();
}

/// Gera o PDF da escala: paisagem = quadro mensal; retrato = cartões por culto.
/// Só entram cultos com pelo menos uma pessoa escalada (filtro feito pelo chamador).
Future<Uint8List> gerarEscalaPdf({
  required List<CultoEscalaPdf> cultos,
  required String tipo,
  required String formato,
  required String tituloMes,
  required String igreja,
  Uint8List? logo,
}) async {
  final ordem = _ordemFuncoes[tipo];
  if (ordem == null || (formato != 'paisagem' && formato != 'retrato')) {
    throw ArgumentError('Escala ou formato inválido.');
  }
  final paisagem = formato == 'paisagem';
  final titulo = tipo == 'pastoral' ? 'Escala pastoral' : 'Escala do louvor';
  final nomeIgreja = textoLatin1(igreja);
  final mes = textoLatin1(tituloMes);
  final imagem = logo == null ? null : pw.MemoryImage(logo);
  final limpos = [
    for (final c in cultos)
      CultoEscalaPdf(
        rotulo: textoLatin1(c.rotulo),
        hora: textoLatin1(c.hora),
        nome: textoLatin1(c.nome),
        ceia: c.ceia,
        funcoes: [
          for (final f in c.funcoes)
            FuncaoEscalaPdf(textoLatin1(f.nome), [for (final nome in f.pessoas) textoLatin1(nome)]),
        ],
        musicas: [
          for (final m in c.musicas) MusicaEscalaPdf(textoLatin1(m.titulo), textoLatin1(m.tom)),
        ],
      ),
  ];

  final doc = pw.Document(title: '$titulo · $mes', author: nomeIgreja);
  doc.addPage(pw.MultiPage(
    pageFormat: paisagem ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
    margin: paisagem
        ? const pw.EdgeInsets.fromLTRB(34, 34, 34, 30)
        : const pw.EdgeInsets.fromLTRB(40, 40, 40, 36),
    header: (ctx) => ctx.pageNumber == 1
        ? _cabecalho(nomeIgreja, titulo, mes, imagem, paisagem)
        : _cabecalhoCompacto(nomeIgreja, titulo, mes),
    footer: (ctx) => _rodape(nomeIgreja, titulo, mes, limpos.length, ctx.pageNumber, ctx.pagesCount),
    build: (ctx) => [paisagem ? _quadroMensal(limpos, tipo, ordem) : _cartoes(limpos, tipo)],
  ));
  return doc.save();
}

pw.Widget _cabecalho(String igreja, String titulo, String tituloMes, pw.MemoryImage? imagem, bool paisagem) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          if (imagem != null) pw.Image(imagem, width: 54, height: 54, fit: pw.BoxFit.contain),
          if (imagem != null) pw.SizedBox(width: 14),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(igreja.toUpperCase(),
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _verde)),
              pw.Text(titulo,
                  style: pw.TextStyle(
                      fontSize: paisagem ? 26 : 24, fontWeight: pw.FontWeight.bold, color: _verdeEscuro)),
              pw.Text(tituloMes, style: pw.TextStyle(fontSize: 13, color: _cinza)),
            ]),
          ),
        ]),
        pw.Divider(color: _verde, thickness: 1.6, height: 18),
      ],
    );

pw.Widget _cabecalhoCompacto(String igreja, String titulo, String tituloMes) => pw.Column(children: [
      pw.Text('$igreja · $titulo · $tituloMes', style: pw.TextStyle(fontSize: 9, color: _cinza)),
      pw.Divider(color: _borda, thickness: .6, height: 10),
    ]);

pw.Widget _rodape(String igreja, String titulo, String tituloMes, int cultos, int pagina, int paginas) => pw.Column(children: [
      pw.Divider(color: _borda, thickness: .6, height: 8),
      pw.Row(children: [
        pw.Expanded(
          child: pw.Text('$igreja · $titulo · $tituloMes · $cultos ${cultos == 1 ? 'culto' : 'cultos'}',
              style: pw.TextStyle(fontSize: 8.5, color: _cinza)),
        ),
        pw.Text('Página $pagina de $paginas', style: pw.TextStyle(fontSize: 8.5, color: _cinza)),
      ]),
    ]);

// ---------- Quadro mensal (A4 paisagem) ----------

pw.Widget _quadroMensal(List<CultoEscalaPdf> cultos, String tipo, List<String> ordem) {
  final usadas = cultos.expand((c) => c.funcoes.map((f) => f.nome)).toSet();
  final colunas = ordem.where(usadas.contains).toList();
  final comMusicas = tipo == 'louvor';
  return pw.Table(
    border: pw.TableBorder.all(color: _borda, width: .6),
    defaultColumnWidth: const pw.FlexColumnWidth(),
    columnWidths: {
      0: const pw.FixedColumnWidth(105),
      if (comMusicas) colunas.length + 1: const pw.FixedColumnWidth(160),
    },
    children: [
      pw.TableRow(children: [
        _celula('Culto', fundo: _fundoCabecalho, negrito: true, alinhamento: pw.Alignment.centerLeft),
        ...colunas.map((f) => _celula(f, fundo: _fundoCabecalho, negrito: true)),
        if (comMusicas) _celula('Músicas', fundo: _fundoCabecalho, negrito: true, alinhamento: pw.Alignment.centerLeft),
      ]),
      for (final (i, c) in cultos.indexed)
        pw.TableRow(children: [
          _celulaCulto(c, alternada: i.isOdd),
          ...colunas.map((f) {
            final funcao = c.funcoes.where((x) => x.nome == f).firstOrNull;
            return _celula((funcao?.pessoas ?? const []).join(', '), alternada: i.isOdd);
          }),
          if (comMusicas) _celulaMusicas(c, alternada: i.isOdd),
        ]),
    ],
  );
}

pw.Widget _celula(String texto,
    {PdfColor? fundo,
    bool negrito = false,
    pw.Alignment alinhamento = pw.Alignment.center,
    bool alternada = false,
    double tamanho = 9}) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 5),
    color: fundo ?? (alternada ? _linhaAlternada : null),
    alignment: alinhamento,
    child: pw.Text(texto,
        style: pw.TextStyle(
            fontSize: tamanho,
            fontWeight: negrito ? pw.FontWeight.bold : null,
            color: negrito ? _verdeEscuro : null)),
  );
}

pw.Widget _celulaCulto(CultoEscalaPdf c, {required bool alternada}) {
  final detalhe = [if (c.nome.isNotEmpty) c.nome, if (c.ceia) 'Santa Ceia'].join(' · ');
  return pw.Container(
    padding: const pw.EdgeInsets.all(6),
    color: alternada ? _linhaAlternada : null,
    alignment: pw.Alignment.centerLeft,
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('${c.rotulo} · ${c.hora}',
          style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _verdeEscuro)),
      if (detalhe.isNotEmpty) pw.Text(detalhe, style: pw.TextStyle(fontSize: 8, color: _cinza)),
    ]),
  );
}

pw.Widget _celulaMusicas(CultoEscalaPdf c, {required bool alternada}) => pw.Container(
      padding: const pw.EdgeInsets.all(6),
      color: alternada ? _linhaAlternada : null,
      alignment: pw.Alignment.centerLeft,
      child: c.musicas.isEmpty
          ? pw.SizedBox()
          : pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (final (i, m) in c.musicas.indexed)
                  pw.Text('${i + 1}. ${m.titulo}${m.tom.isEmpty ? '' : ' (${m.tom})'}',
                      style: const pw.TextStyle(fontSize: 8.5)),
              ],
            ),
    );

// ---------- Cartões por culto (A4 retrato) ----------

pw.Widget _cartoes(List<CultoEscalaPdf> cultos, String tipo) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [for (final c in cultos) _cartao(c, comMusicas: tipo == 'louvor')],
    );

pw.Widget _cartao(CultoEscalaPdf c, {required bool comMusicas}) {
  final detalhe = [if (c.nome.isNotEmpty) c.nome, if (c.ceia) 'Santa Ceia'].join(' · ');
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 10),
    padding: const pw.EdgeInsets.all(14),
    decoration: pw.BoxDecoration(
      border: pw.Border(
        left: pw.BorderSide(color: _verde, width: 3),
        top: pw.BorderSide(color: _borda, width: .7),
        right: pw.BorderSide(color: _borda, width: .7),
        bottom: pw.BorderSide(color: _borda, width: .7),
      ),
    ),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('${c.rotulo} · ${c.hora}',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _verdeEscuro)),
          if (detalhe.isNotEmpty) pw.Text(detalhe, style: pw.TextStyle(fontSize: 9, color: _cinza)),
        ],
      ),
      if (c.funcoes.isNotEmpty)
        pw.Table(
          columnWidths: const {0: pw.FixedColumnWidth(120)},
          children: [
            for (final f in c.funcoes)
              pw.TableRow(children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 5),
                  decoration: pw.BoxDecoration(
                      border: pw.Border(bottom: pw.BorderSide(color: _bordaClara, width: .5))),
                  child: pw.Text(f.nome,
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _verde)),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 5),
                  alignment: pw.Alignment.centerLeft,
                  decoration: pw.BoxDecoration(
                      border: pw.Border(bottom: pw.BorderSide(color: _bordaClara, width: .5))),
                  child: pw.Text(f.pessoas.join(', '), style: const pw.TextStyle(fontSize: 10)),
                ),
              ]),
          ],
        ),
      if (comMusicas && c.musicas.isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Músicas',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _verdeEscuro)),
            for (final (i, m) in c.musicas.indexed)
              pw.Text('${i + 1}. ${m.titulo}${m.tom.isEmpty ? '' : ' (${m.tom})'}',
                  style: const pw.TextStyle(fontSize: 10)),
          ]),
        ),
    ]),
  );
}
