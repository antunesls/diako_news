import 'package:diako_core/diako_core.dart';
import 'package:test/test.dart';

Visita visita(String nome, {String data = '2026-10-25', bool mencionar = true, int minuto = 0, String? membroId, bool primeiraVez = true}) =>
    Visita(
      id: 'v-$nome-$minuto',
      membroId: membroId ?? 'm-$nome',
      nome: nome,
      data: data,
      criadoEm: DateTime(2026, 10, 25, 19, minuto),
      origem: OrigemVisita.recepcao,
      mencionar: mencionar,
      primeiraVez: primeiraVez,
    );

void main() {
  final domingo = DateTime(2026, 10, 25, 20);

  test('json ida e volta, com interesses e contato', () {
    final v = Visita(
      id: 'v1', membroId: 'm1', nome: 'Rita', data: '2026-10-25', criadoEm: DateTime(2026, 10, 25, 19),
      origem: OrigemVisita.qr, mencionar: true, primeiraVez: false, grupoId: 'g1',
      interesses: {InteresseVisita.oracao, InteresseVisita.batismo},
      contato: StatusContato.contatado, contatoNota: 'Ligou na terça',
    );
    final volta = Visita.fromJson(v.toJson());
    expect(volta.toJson(), v.toJson());
    expect(volta.interesses, {InteresseVisita.oracao, InteresseVisita.batismo});
    expect(volta.primeiraVez, isFalse);
  });

  test('documento sem o essencial é inválido; interesse desconhecido é ignorado', () {
    expect(() => Visita.fromJson({'id': 'x', 'nome': 'A', 'data': '2026-10-25'}), throwsFormatException);
    expect(() => Visita.fromJson({'id': 'x', 'membroId': 'm', 'nome': 'A', 'data': '25/10'}), throwsFormatException);
    final v = Visita.fromJson({'id': 'x', 'membroId': 'm', 'nome': 'A', 'data': '2026-10-25', 'interesses': ['oracao', 'outro']});
    expect(v.interesses, {InteresseVisita.oracao});
    expect(v.mencionar, isFalse); // sem resposta: não cita
    expect(v.contato, StatusContato.aContatar);
  });

  test('pendências do pastor: só hoje, quem autorizou e ainda não foi citado', () {
    final citada = visita('Bia', minuto: 2)..mencionadaEm = domingo;
    final lista = [
      visita('Rita', minuto: 5),
      visita('Caio', minuto: 1),
      visita('Léo', mencionar: false),
      citada,
      visita('Ontem', data: '2026-10-24'),
    ];
    expect(pendenciasDoPastor(lista, domingo).map((v) => v.nome), ['Caio', 'Rita']);
  });

  test('nomes para boas-vindas: ordem de chegada, sem quem não autorizou e sem repetir', () {
    final lista = [
      visita('Rita', minuto: 5),
      visita('Caio', minuto: 1),
      visita('Rita', minuto: 9), // cadastrada duas vezes
      visita('Léo', mencionar: false),
      visita('Ontem', data: '2026-10-24'),
    ];
    expect(nomesParaBoasVindas(lista, domingo), ['Caio', 'Rita']);
  });

  test('slides do telão e páginas da TV', () {
    expect(montarSlidesBoasVindas([]), isEmpty);
    final slides = montarSlidesBoasVindas(['A', 'B', 'C'], porSlide: 2);
    expect(slides, ['<b>Sejam bem-vindos!</b>\nA\nB', '<b>Sejam bem-vindos!</b>\nC']);
    expect(montarSlidesBoasVindas(['A'], negritoTitulo: false).single, 'Sejam bem-vindos!\nA');
    expect(montarTelaBoasVindas(['A', 'B', 'C'], porPagina: 2), [['A', 'B'], ['C']]);
    expect(montarTelaBoasVindas([]), isEmpty);
  });

  test('mural: boas-vindas só quando recebe os nomes', () {
    List<String> titulos(List<String> visitantes) => [
          for (final s in montarMural(
              recados: [], motivos: [], agora: domingo, urlCartaz: (_) => null, visitantesHoje: visitantes))
            s.titulo,
        ];
    expect(titulos([]), isNot(contains('Sejam bem-vindos!')));
    expect(titulos(['Rita']).first, 'Sejam bem-vindos!');
  });

  test('resumo da semana conta visitantes (sem nomes)', () {
    final texto = montarResumoSemanal(
      recados: [], motivos: [], membros: [], agora: domingo,
      visitas: [visita('Rita'), visita('Caio', membroId: 'c', primeiraVez: false), visita('Velho', data: '2026-10-01')],
    );
    expect(texto, contains('Recebemos 2 visitantes nos últimos 7 dias* (1 pela primeira vez)'));
    expect(texto, isNot(contains('Rita')));
    expect(montarResumoSemanal(recados: [], motivos: [], membros: [], agora: domingo), isNot(contains('visitante')));
  });
}
