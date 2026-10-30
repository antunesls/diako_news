import 'package:diako_core/diako_core.dart';
import 'package:test/test.dart';

List<String> refs(String texto) => [for (final r in acharReferencias(texto)) r.ref.abreviada];

void main() {
  group('achar referências', () {
    test('abreviações e nomes, com ponto ou dois-pontos', () {
      expect(refs('Leia Jo 3.16 e depois João 3:17.'), ['Jo 3.16', 'Jo 3.17']);
      expect(refs('Paulo repete em 1Co 11.23-24 e em 1 Coríntios 13:4-7.'), ['1Co 11.23-24', '1Co 13.4-7']);
      expect(refs('Veja I Coríntios 13.13'), ['1Co 13.13']);
      expect(refs('Gênesis 1.1, Genesis 1.2 e Êxodo 20.3'), ['Gn 1.1', 'Gn 1.2', 'Êx 20.3']);
    });

    test('listas e intervalos de versículos', () {
      expect(refs('Rm 8.28,31'), ['Rm 8.28,31']);
      expect(refs('Rm 8.28-30, 31'), ['Rm 8.28-30,31']);
      expect(acharReferencias('Sl 23.1-3').single.ref.ids, ['19023001', '19023002', '19023003']);
    });

    test('Jó e João não se confundem', () {
      expect([for (final r in acharReferencias('Jó 19.25 e Jo 1.1')) r.ref.livro.nome], ['Jó', 'João']);
      expect(acharReferencias('1Jo 4.8').single.ref.livro.nome, '1 João');
    });

    test('abreviação precisa de maiúscula e versículo: "os 3 irmãos" não é Oseias', () {
      expect(refs('Chamou os 3 irmãos. At 2 dias dali.'), isEmpty);
      expect(refs('Os 6.6'), ['Os 6.6']);
    });

    test('nome completo só com o capítulo fica incompleto', () {
      final r = acharReferencias('Lemos o Salmo 23 juntos.').single;
      expect(r.original, 'Salmo 23');
      expect(r.ref.completa, isFalse);
      expect(r.ref.nome, 'Salmos 23');
    });

    test('posição no texto e nome completo para o telão', () {
      const texto = 'como diz Romanos 5.8, Deus prova';
      final r = acharReferencias(texto).single;
      expect(texto.substring(r.inicio, r.fim), 'Romanos 5.8');
      expect(r.ref.nome, 'Romanos 5.8');
    });

    test('ler referência digitada no ajuste', () {
      expect(lerReferencia(' Jo 5.24 ')?.abreviada, 'Jo 5.24');
      expect(lerReferencia('qualquer coisa'), isNull);
      expect(lerReferencia('Jo 5.24 e mais'), isNull);
    });
  });

  group('trechos', () {
    test('linha em branco separa, # é tópico, quebras simples juntam', () {
      final t = dividirEmTrechos('Introdução curta.\n\n# 1 · A mesa\nPrimeira linha\nsegunda linha.\n\nOutro parágrafo.');
      expect([for (final x in t) (x.numero, x.topico, x.texto)], [
        (1, '', 'Introdução curta.'),
        (2, '1 · A mesa', 'Primeira linha segunda linha.'),
        (3, '1 · A mesa', 'Outro parágrafo.'),
      ]);
    });

    test('parágrafo longo é cortado nas frases', () {
      final frase = 'Esta é uma frase de exemplo com algumas palavras. ';
      final t = dividirEmTrechos(frase * 20, maximo: 200);
      expect(t.length, greaterThan(1));
      expect(t.every((x) => x.texto.length <= 200), isTrue);
      expect(t.map((x) => x.texto).join(' '), (frase * 20).trim());
    });
  });

  group('análise com as decisões do pastor', () {
    const texto = 'Como diz Romanos 5.8.\n\nLemos o Salmo 23 e Jo 3.16.';

    test('sem decisão: pendente ou incompleta', () {
      final t = analisarPalavra(texto, {});
      expect(t[0].referencias.single.status, StatusReferencia.pendente);
      expect(t[1].referencias.map((r) => r.status), [StatusReferencia.incompleta, StatusReferencia.pendente]);
      expect(t[1].referencias.first.projetavel, isFalse);
    });

    test('confirmar, ignorar e ajustar', () {
      final t = analisarPalavra(texto, {
        'Romanos 5.8': const DecisaoReferencia(StatusReferencia.confirmada),
        'Salmo 23': const DecisaoReferencia(StatusReferencia.confirmada, 'Sl 23.1-6'),
        'Jo 3.16': const DecisaoReferencia(StatusReferencia.ignorada),
      });
      expect(t[0].referencias.single.projetavel, isTrue);
      expect(t[1].referencias.first.ref?.abreviada, 'Sl 23.1-6');
      expect(t[1].referencias.first.status, StatusReferencia.confirmada);
      expect(t[1].referencias.last.projetavel, isFalse);
    });

    test('pendências para marcar como pronta', () {
      final p = Palavra(id: 'p', titulo: 'Em memória de mim', autorId: 'u', texto: texto);
      expect(p.pendencias(), containsAll(['Falta a data do culto.', 'Há versículos para conferir.']));
      final ok = Palavra(id: 'p', titulo: 'T', autorId: 'u', data: '2026-11-02', texto: 'Só texto, sem versículos.');
      expect(ok.pendencias(), isEmpty);
    });

    test('a do culto leva só o que dá para projetar, e os tópicos', () {
      final p = Palavra(id: 'p', titulo: 'T', autorId: 'u', texto: '# Abertura\n$texto\n\n# Apelo\nVenha.');
      final c = PalavraDoCulto.fromJson(PalavraDoCulto.de(p).toJson());
      expect(c.trechos.expand((t) => t.referencias).map((r) => r.ref!.abreviada), ['Rm 5.8', 'Jo 3.16']);
      expect(c.topicos, [('Abertura', 0), ('Apelo', 2)]);
    });
  });

  test('situação: rascunho, pronta e pregada', () {
    Palavra p(bool pronta, String data) => Palavra(id: 'p', titulo: 'T', autorId: 'u', pronta: pronta, data: data);
    expect(p(false, '2026-11-02').situacao('2026-11-02'), 'rascunho');
    expect(p(true, '2026-11-02').situacao('2026-11-02'), 'pronta');
    expect(p(true, '2026-11-01').situacao('2026-11-02'), 'pregada');
  });

  test('json ida e volta, com decisões e versões', () {
    final p = Palavra(
      id: 'p',
      titulo: 'T',
      autorId: 'u',
      data: '2026-11-02',
      decisoes: {'Salmo 23': const DecisaoReferencia(StatusReferencia.confirmada, 'Sl 23.1')},
      versoes: [VersaoPalavra(em: DateTime(2026, 10, 30), por: 'Pr. Marcos', titulo: 'T0', texto: 'antes')],
    );
    final volta = Palavra.fromJson(p.toJson());
    expect(volta.decisoes['Salmo 23']!.ajuste, 'Sl 23.1');
    expect(volta.versoes.single.texto, 'antes');
    expect(() => Palavra.fromJson({...p.toJson(), 'data': '02/11'}), throwsFormatException);
  });
}
