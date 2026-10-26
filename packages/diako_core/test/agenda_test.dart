import 'package:diako_core/diako_core.dart';
import 'package:test/test.dart';

// Formato parecido com o exportado pelo Google Agenda (CRLF, VTIMEZONE, VALARM, linhas dobradas).
final ics = [
  'BEGIN:VCALENDAR',
  'PRODID:-//Google Inc//Google Calendar 70.9054//EN',
  'VERSION:2.0',
  'X-WR-TIMEZONE:America/Sao_Paulo',
  'BEGIN:VTIMEZONE',
  'TZID:America/Sao_Paulo',
  'BEGIN:STANDARD',
  'DTSTART:19700101T000000',
  'TZOFFSETFROM:-0300',
  'TZOFFSETTO:-0300',
  'END:STANDARD',
  'END:VTIMEZONE',
  // Culto semanal sáb e dom, com exclusão, uma ocorrência editada e uma cancelada.
  'BEGIN:VEVENT',
  'DTSTART;TZID=America/Sao_Paulo:20261101T193000',
  'DTEND;TZID=America/Sao_Paulo:20261101T210000',
  'RRULE:FREQ=WEEKLY;BYDAY=SA,SU;UNTIL=20261130T225959Z',
  'EXDATE;TZID=America/Sao_Paulo:20261108T193000',
  'UID:culto@google.com',
  'SUMMARY:Culto de Celebração',
  'LOCATION:Templo\\, Rua A 123',
  'DESCRIPTION:Traga um amigo!\\nHaverá Santa Ceia neste domingo e todos são bem-vind',
  ' os.',
  'BEGIN:VALARM',
  'ACTION:DISPLAY',
  'DESCRIPTION:Isto é um alarme e não a descrição',
  'TRIGGER:-P0DT0H30M0S',
  'END:VALARM',
  'END:VEVENT',
  'BEGIN:VEVENT',
  'DTSTART;TZID=America/Sao_Paulo:20261114T180000',
  'DTEND;TZID=America/Sao_Paulo:20261114T200000',
  'RECURRENCE-ID;TZID=America/Sao_Paulo:20261114T193000',
  'UID:culto@google.com',
  'SUMMARY:Culto especial',
  'END:VEVENT',
  'BEGIN:VEVENT',
  'DTSTART;TZID=America/Sao_Paulo:20261121T193000',
  'DTEND;TZID=America/Sao_Paulo:20261121T210000',
  'RECURRENCE-ID;TZID=America/Sao_Paulo:20261121T193000',
  'STATUS:CANCELLED',
  'UID:culto@google.com',
  'SUMMARY:Culto de Celebração',
  'END:VEVENT',
  // Dia inteiro.
  'BEGIN:VEVENT',
  'DTSTART;VALUE=DATE:20261105',
  'DTEND;VALUE=DATE:20261106',
  'UID:retiro@google.com',
  'SUMMARY:Retiro de Casais',
  'END:VEVENT',
  // Em UTC: 22h UTC = 19h em Brasília.
  'BEGIN:VEVENT',
  'DTSTART:20261103T220000Z',
  'DTEND:20261103T233000Z',
  'UID:ensaio@google.com',
  'SUMMARY:Ensaio do louvor',
  'DESCRIPTION:<b>Repertório</b><br>Hino 1<br>Hino 2',
  'END:VEVENT',
  // Mensal no 2º domingo, 3 vezes.
  'BEGIN:VEVENT',
  'DTSTART;TZID=America/Sao_Paulo:20261108T090000',
  'DTEND;TZID=America/Sao_Paulo:20261108T100000',
  'RRULE:FREQ=MONTHLY;BYDAY=2SU;COUNT=3',
  'UID:cafe@google.com',
  'SUMMARY:Café dos homens',
  'END:VEVENT',
  // Mensal na última sexta.
  'BEGIN:VEVENT',
  'DTSTART;TZID=America/Sao_Paulo:20261030T200000',
  'DURATION:PT2H',
  'RRULE:FREQ=MONTHLY;BYDAY=-1FR',
  'UID:vigilia@google.com',
  'SUMMARY:Vigília',
  'END:VEVENT',
  // Cancelado por inteiro.
  'BEGIN:VEVENT',
  'DTSTART;TZID=America/Sao_Paulo:20261110T200000',
  'UID:cancelado@google.com',
  'STATUS:CANCELLED',
  'SUMMARY:Não vai acontecer',
  'END:VEVENT',
  'END:VCALENDAR',
].join('\r\n');

void main() {
  final janela = lerIcs(ics, de: DateTime(2026, 10, 28), ate: DateTime(2026, 12, 1));
  List<String> de(String titulo) =>
      [for (final e in janela) if (e.titulo == titulo) '${e.inicio.month}/${e.inicio.day} ${horaCurta(e.inicio)}'];

  test('recorrência semanal com EXDATE, ocorrência editada e cancelada', () {
    expect(de('Culto de Celebração'), ['11/1 19h30', '11/7 19h30', '11/15 19h30', '11/22 19h30', '11/28 19h30', '11/29 19h30']);
    expect(de('Culto especial'), ['11/14 18h']);
  });

  test('texto: escapes, linha dobrada, local e alarme ignorado', () {
    final culto = janela.firstWhere((e) => e.titulo == 'Culto de Celebração');
    expect(culto.local, 'Templo, Rua A 123');
    expect(culto.descricao, 'Traga um amigo!\nHaverá Santa Ceia neste domingo e todos são bem-vindos.');
    expect(horario(culto), '19h30–21h');
  });

  test('dia inteiro, UTC e HTML na descrição', () {
    final retiro = janela.firstWhere((e) => e.titulo == 'Retiro de Casais');
    expect(retiro.diaInteiro, isTrue);
    expect(retiro.inicio, DateTime(2026, 11, 5));
    expect(retiro.fim, DateTime(2026, 11, 6));
    expect(horario(retiro), 'Dia inteiro');
    final doisDias = Evento(id: 'x', titulo: 'Retiro', inicio: DateTime(2026, 10, 29), fim: DateTime(2026, 10, 31), diaInteiro: true);
    expect(horario(doisDias), 'Até sex 30/10');

    final ensaio = janela.firstWhere((e) => e.titulo == 'Ensaio do louvor');
    expect(ensaio.inicio, DateTime(2026, 11, 3, 19));
    expect(ensaio.fim, DateTime(2026, 11, 3, 20, 30));
    expect(ensaio.descricao, 'Repertório\nHino 1\nHino 2');
  });

  test('mensal: 2º domingo com COUNT e última sexta com DURATION', () {
    final cafe = lerIcs(ics, de: DateTime(2026, 10, 1), ate: DateTime(2027, 6, 1)).where((e) => e.titulo == 'Café dos homens');
    expect(cafe.map((e) => e.inicio), [DateTime(2026, 11, 8, 9), DateTime(2026, 12, 13, 9), DateTime(2027, 1, 10, 9)]);
    expect(de('Vigília'), ['10/30 20h', '11/27 20h']);
    expect(janela.firstWhere((e) => e.titulo == 'Vigília').fim, DateTime(2026, 10, 30, 22));
  });

  test('cancelados e fora da janela não aparecem; ordem por início; ids únicos', () {
    expect(janela.any((e) => e.titulo == 'Não vai acontecer'), isFalse);
    expect(janela.every((e) => e.inicio.isBefore(DateTime(2026, 12, 1))), isTrue);
    for (var i = 1; i < janela.length; i++) {
      expect(janela[i].inicio.isBefore(janela[i - 1].inicio), isFalse);
    }
    expect(janela.map((e) => e.id).toSet().length, janela.length);
  });

  test('evento que já começou ainda aparece se termina dentro da janela', () {
    final r = lerIcs(ics, de: DateTime(2026, 11, 3, 20), ate: DateTime(2026, 11, 4));
    expect(r.map((e) => e.titulo), ['Ensaio do louvor']);
  });

  test('ICS vazio ou inválido não quebra', () {
    expect(lerIcs('', de: DateTime(2026), ate: DateTime(2027)), isEmpty);
    expect(lerIcs('lixo\nBEGIN:VEVENT\nSUMMARY:sem data\nEND:VEVENT', de: DateTime(2026), ate: DateTime(2027)), isEmpty);
  });

  test('textos para slide e recado', () {
    final e = Evento(id: '1', titulo: 'Culto de Jovens', inicio: DateTime(2026, 11, 7, 19, 30), fim: DateTime(2026, 11, 7, 21), local: 'Salão');
    expect(montarSlideEvento(e), '<b>Culto de Jovens</b>\nSábado, 07/11 · 19h30–21h\nSalão');
    expect(textoRecadoDoEvento(e), 'Sábado, 07/11 · 19h30–21h\nSalão');
    expect(diaCurto(e.inicio), 'sáb 07/11');
    expect(Evento.fromJson(e.toJson()).toJson(), e.toJson());
  });

  group('mural e resumo com agenda', () {
    final agora = DateTime(2026, 11, 7, 10); // sábado
    final eventos = lerIcs(ics, de: DateTime(2026, 11, 7), ate: DateTime(2026, 11, 30));

    test('"Hoje" só com eventos de hoje; próximos a partir de amanhã', () {
      final slides = montarMural(recados: [], motivos: [], agora: agora, urlCartaz: (_) => null, eventos: eventos, diasEventos: 7);
      expect(slides.first.tipo, 'hoje');
      expect(slides.first.eventos.single['titulo'], 'Culto de Celebração');
      expect(slides.first.eventos.single['quando'], '19h30–21h');
      expect(slides.first.eventos.single['descricao'], startsWith('Traga um amigo!'));
      final proximos = slides.where((s) => s.tipo == 'agenda').expand((s) => s.eventos).map((e) => e['titulo']).toList();
      // 08/11 a 14/11: o culto de 08/11 foi excluído (EXDATE) e o de 15/11 fica fora dos 7 dias.
      expect(proximos, ['Café dos homens', 'Culto especial']);
      expect(slides[1].eventos.first['quando'], 'dom 08/11 · 9h–10h');
    });

    test('sem descrição quando desligado; sem slide "Hoje" quando não há evento hoje', () {
      final slides = montarMural(
          recados: [], motivos: [], agora: DateTime(2026, 11, 10, 8), urlCartaz: (_) => null, eventos: eventos, mostrarDescricao: false);
      expect(slides.any((s) => s.tipo == 'hoje'), isFalse);
      expect(slides.expand((s) => s.eventos).any((e) => e.containsKey('descricao')), isFalse);
    });

    test('resumo semanal com a agenda de hoje até sábado', () {
      final texto = montarResumoSemanal(recados: [], motivos: [], membros: [], agora: DateTime(2026, 11, 9, 10), eventos: eventos);
      expect(texto, contains('📅 *Agenda da semana*'));
      expect(texto, contains('• *Culto especial* — sáb 14/11 18h–20h'));
      expect(texto, isNot(contains('dom 08/11'))); // antes de hoje
      expect(texto, isNot(contains('15/11'))); // semana seguinte
    });
  });

  group('criar e editar eventos', () {
    test('editavel vai e volta no JSON e é falso em caches antigos', () {
      final e = Evento(id: 'a', titulo: 'Ensaio', inicio: DateTime(2026, 11, 10, 20), fim: DateTime(2026, 11, 10, 22), editavel: true);
      expect(Evento.fromJson(e.toJson()).editavel, isTrue);
      final antigo = e.toJson()..remove('editavel');
      expect(Evento.fromJson(antigo).editavel, isFalse);
    });

    test('validarEvento', () {
      final d = DateTime(2026, 11, 10, 20);
      final umaHora = d.add(const Duration(hours: 1));
      expect(validarEvento(titulo: 'Ensaio', inicio: d, fim: umaHora, diaInteiro: false), isNull);
      expect(validarEvento(titulo: '  ', inicio: d, fim: umaHora, diaInteiro: false), contains('título'));
      expect(validarEvento(titulo: 'x' * (maxTituloEvento + 1), inicio: d, fim: umaHora, diaInteiro: false), contains('longo'));
      expect(validarEvento(titulo: 'x', inicio: d, fim: d, diaInteiro: false), contains('término'));
      expect(validarEvento(titulo: 'x', inicio: d, fim: d, diaInteiro: true), contains('último dia'));
      expect(validarEvento(titulo: 'x', inicio: d, fim: d.add(const Duration(days: 400)), diaInteiro: true), contains('um ano'));
    });
  });
}
