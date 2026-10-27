import 'package:diako_core/diako_core.dart';
import 'package:test/test.dart';

CultoEscala _culto(String data, {bool ceia = false, Map<String, List<String>>? pastoral, Map<String, List<String>>? louvor}) =>
    CultoEscala(id: data, data: data, hora: '19:00', ceia: ceia, pastoral: pastoral, louvor: louvor);

void main() {
  final nomes = {'a': 'Ana Maria Souza', 'b': 'Bruno Reis', 'c': 'Carla Dias'};
  String nomeDe(String id) => nomes[id] ?? '?';

  group('horários e cultos do mês', () {
    test('lê os horários da página inicial', () {
      final h = horariosDosCultos('Domingo — 19h\nQuarta-feira | 20h30 — Culto de oração\nSábado - 9:00\nHorário a combinar\nSegunda — tarde');
      expect(h, [
        (diaSemana: DateTime.sunday, hora: '19:00', nome: 'Culto'),
        (diaSemana: DateTime.wednesday, hora: '20:30', nome: 'Culto de oração'),
        (diaSemana: DateTime.saturday, hora: '09:00', nome: 'Culto'),
      ]);
    });

    test('gera os cultos de novembro de 2026; Santa Ceia no primeiro domingo', () {
      final c = cultosDoMes(2026, 11, horariosDosCultos('Domingo — 19h\nQuarta — 20h'));
      expect(c.map((x) => x.data), [
        '2026-11-01', '2026-11-04', '2026-11-08', '2026-11-11', '2026-11-15',
        '2026-11-18', '2026-11-22', '2026-11-25', '2026-11-29',
      ]);
      expect(c.where((x) => x.ceia).map((x) => x.data), ['2026-11-01']);
      expect(ocorrenciaNoMes('2026-11-18'), 3);
    });

    test('horas e rótulos', () {
      expect([horaEscala('19h'), horaEscala('19h30'), horaEscala('9:05'), horaEscala('25h'), horaEscala('noite')],
          ['19:00', '19:30', '09:05', null, null]);
      expect([horaCurtaEscala('19:00'), horaCurtaEscala('19:30')], ['19h', '19h30']);
      expect(rotuloDia('2026-11-01'), 'Dom 01/11');
    });
  });

  group('CultoEscala', () {
    test('json ida e volta; Santa Ceia só no culto de ceia', () {
      final c = CultoEscala.fromJson({
        'id': 'x', 'data': '01/11/2026', 'hora': '19h', 'nome': 'Culto da família', 'ceia': true, 'tema': 'Graça',
        'pastoral': {'Pregação': ['a', 'a'], 'Direção': []},
        'louvor': {'Violão': ['b']},
        'musicas': [{'titulo': 'Abertura', 'tom': 'G'}],
      });
      expect(c.data, '2026-11-01');
      expect(c.hora, '19:00');
      expect(c.pastoral, {'Pregação': ['a']});
      expect(CultoEscala.fromJson(c.toJson()).toJson(), c.toJson());
      expect(c.funcoes(TipoEscala.pastoral), contains(funcaoCeia));
      expect(c.copiar(ceia: false).funcoes(TipoEscala.pastoral), isNot(contains(funcaoCeia)));
    });

    test('recusa função desconhecida, data e hora inválidas', () {
      expect(() => CultoEscala.fromJson({'id': 'x', 'data': '2026-11-01', 'hora': '19h', 'louvor': {'Sax': ['a']}}),
          throwsFormatException);
      expect(() => CultoEscala.fromJson({'id': 'x', 'data': '31/02/2026', 'hora': '19h'}), throwsFormatException);
      expect(() => CultoEscala.fromJson({'id': 'x', 'data': '2026-11-01', 'hora': '99h'}), throwsFormatException);
      expect(() => Indisponibilidade.fromJson({'id': 'i', 'membroId': 'a', 'de': '2026-11-10', 'ate': '2026-11-01'}),
          throwsFormatException);
    });
  });

  test('quem pode servir em cada escala', () {
    Membro m(List<String> ministerios, {String? funcao, bool ativo = true}) =>
        Membro(id: 'm', nome: 'X', dia: 1, mes: 1, ativo: ativo, ministerios: ministerios, funcao: funcao);
    expect(podeServir(m(['Louvor']), TipoEscala.louvor), isTrue);
    expect(podeServir(m(['Música']), TipoEscala.louvor), isTrue);
    expect(podeServir(m(['Louvor'], ativo: false), TipoEscala.louvor), isFalse);
    expect(podeServir(m(['Infantil'], funcao: 'Presbítero'), TipoEscala.pastoral), isTrue);
    expect(podeServir(m(['Liderança']), TipoEscala.pastoral), isTrue);
    expect(podeServir(m(['Louvor'], funcao: 'Líder'), TipoEscala.pastoral), isFalse);
  });

  group('avisos', () {
    final cultos = [
      _culto('2026-11-08', pastoral: {'Pregação': ['b']}, louvor: {'Violão': ['b'], 'Ministro': ['a'], 'Vocal': ['a']}),
      _culto('2026-11-15', louvor: {'Vocal': ['c']}),
    ];
    final indisponiveis = [Indisponibilidade(id: 'i', membroId: 'c', de: '2026-11-14', ate: '2026-11-16', motivo: 'viagem')];

    test('aviso de cada pessoa na grade', () {
      expect(avisoDaPessoa(cultos[0], TipoEscala.louvor, 'Violão', 'b', indisponiveis), 'Também na pregação');
      expect(avisoDaPessoa(cultos[0], TipoEscala.pastoral, 'Pregação', 'b', indisponiveis), 'Também no violão');
      expect(avisoDaPessoa(cultos[0], TipoEscala.louvor, 'Vocal', 'a', indisponiveis), 'Também como ministro');
      expect(avisoDaPessoa(cultos[1], TipoEscala.louvor, 'Vocal', 'c', indisponiveis), 'Indisponível');
    });

    test('quadro do mês: conflito uma vez, indisponível com motivo e funções vazias', () {
      final a = avisosDoMes(cultos, TipoEscala.louvor, nomeDe, indisponiveis);
      expect(a.map((x) => x.tipo), ['conflito', 'conflito', 'indisponivel', 'vazias']);
      expect(a[0].titulo, 'Ana Maria Souza em duas funções no dia 08/11');
      expect(a[0].texto, 'Escalado(a) como ministro e no vocal do mesmo culto.');
      expect(a[1].texto, 'Escalado(a) no violão e na pregação do mesmo culto.');
      expect(a[2].texto, 'Motivo: viagem. Está escalado(a) no vocal.');
      expect(a[3].texto, startsWith('Ministro em 15/11 · Teclado em 08/11, 15/11'));
    });
  });

  test('texto do WhatsApp com nomes curtos, ceia, tema e músicas', () {
    final cultos = [
      CultoEscala(id: '1', data: '2026-11-01', hora: '19:00', nome: 'Culto da família', ceia: true, tema: 'Graça',
          pastoral: {'Pregação': ['a'], funcaoCeia: ['b']},
          louvor: {'Violão': ['b']}, musicas: [Musica('Abertura', tom: 'G'), Musica('Final')]),
      CultoEscala(id: '2', data: '2026-11-04', hora: '20:30'),
    ];
    expect(textoEscalaWhatsapp(cultos, TipoEscala.pastoral, 11, nomeDe),
        '*Escala pastoral — novembro*\n\n*Dom 01/11 · 19h* (Santa Ceia) — Culto da família\nPregação: Ana Souza · Santa Ceia: Bruno Reis\nTema: Graça');
    expect(textoEscalaWhatsapp(cultos, TipoEscala.louvor, 11, nomeDe),
        '*Escala do louvor — novembro*\n\n*Dom 01/11 · 19h* (Santa Ceia) — Culto da família\nViolão: Bruno Reis\nMúsicas: Abertura (G); Final');
  });
}
