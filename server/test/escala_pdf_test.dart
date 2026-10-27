import 'dart:convert';
import 'dart:typed_data';

import 'package:diako_server/escala_pdf.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

void main() {
  final cultos = [
    CultoEscalaPdf(
      rotulo: 'Dom 01/11',
      hora: '19h',
      nome: 'Culto de celebração',
      ceia: true,
      funcoes: const [
        FuncaoEscalaPdf('Vocal', ['Ana Márcia “Bia”']),
        FuncaoEscalaPdf('Violão', []),
      ],
      musicas: const [
        MusicaEscalaPdf('Deus Proverá — Ao vivo…', 'Bb'),
        MusicaEscalaPdf('Santo', ''),
      ],
    ),
  ];

  test('gera os dois formatos e aceita caracteres fora do latin1 sem quebrar', () async {
    final logo = Uint8List.fromList(img.encodePng(img.Image(width: 12, height: 12)));
    for (final formato in ['paisagem', 'retrato']) {
      final Uint8List pdf = await gerarEscalaPdf(
        cultos: cultos,
        tipo: 'louvor',
        formato: formato,
        tituloMes: 'novembro de 2026',
        igreja: 'Igreja Diakonia Tulipas',
        logo: formato == 'retrato' ? logo : null,
      );
      expect(latin1.decode(pdf.take(5).toList()), '%PDF-');
      expect(pdf.length, greaterThan(1000));
    }
  });

  test('rejeita escala ou formato inválido', () async {
    await expectLater(
        gerarEscalaPdf(cultos: cultos, tipo: 'louvor', formato: 'quadro', tituloMes: 'x', igreja: 'x'),
        throwsArgumentError);
    await expectLater(
        gerarEscalaPdf(cultos: cultos, tipo: 'jack', formato: 'retrato', tituloMes: 'x', igreja: 'x'),
        throwsArgumentError);
  });

  test('textoLatin1 preserva acentos e troca o que a fonte não desenha', () {
    expect(textoLatin1('çãõéíóúâêôàüÇ'), 'çãõéíóúâêôàüÇ');
    expect(textoLatin1('Deus Proverá — Ao vivo…'), 'Deus Proverá - Ao vivo...');
    expect(textoLatin1('Ana \u201CBia\u201D e \u201912\u2019'), 'Ana "Bia" e \'12\'');
    expect(textoLatin1('louvor \u2764\uFE0F'), 'louvor ??');
    expect(textoLatin1(''), '');
  });
}
