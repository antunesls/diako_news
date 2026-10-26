import 'package:diako_core/diako_core.dart';
import 'package:test/test.dart';

Motivo _m(String para, String motivo, {StatusMotivo status = StatusMotivo.pendente, bool publico = true}) =>
    Motivo(id: para + motivo, para: para, motivo: motivo, status: status, publico: publico);

Membro _membro(String nome, int dia, int mes, {bool ativo = true}) =>
    Membro(id: nome, nome: nome, dia: dia, mes: mes, ativo: ativo);

void main() {
  group('Recado', () {
    final r = Recado(id: '1', titulo: 'Retiro', validoAte: DateTime(2026, 11, 10));

    test('vale durante todo o último dia e expira no seguinte', () {
      expect(r.expirado(DateTime(2026, 11, 10, 23, 59)), isFalse);
      expect(r.expirado(DateTime(2026, 11, 11)), isTrue);
      expect(Recado(id: '2', titulo: 'x').expirado(DateTime(2100)), isFalse);
    });

    test('montarSlide', () {
      expect(montarSlide(Recado(id: '1', titulo: ' Retiro ', texto: 'Dia 10\nInscrições ')),
          '<b>Retiro</b>\nDia 10\nInscrições');
      expect(montarSlide(Recado(id: '1', titulo: 'Oi', texto: 'a'), negritoTitulo: false), 'Oi\na');
      expect(montarSlide(Recado(id: '1', titulo: 'Oi')), '<b>Oi</b>');
    });

    test('fixos primeiro, depois pela ordem', () {
      final lista = ordenarParaExibicao([
        Recado(id: 'a', titulo: 'a', ordem: 0),
        Recado(id: 'b', titulo: 'b', ordem: 1, fixo: true),
        Recado(id: 'c', titulo: 'c', ordem: 2),
      ]);
      expect(lista.map((r) => r.id), ['b', 'a', 'c']);
    });

    test('json ida e volta', () {
      final original = Recado(
        id: '1',
        titulo: 'Retiro',
        texto: 'Dia 10',
        categoria: Categoria.evento,
        imagemHolyrics: 'Diako/retiro.jpg',
        validoAte: DateTime(2026, 11, 10),
        fixo: true,
        ordem: 3,
        site: true,
        urgente: true,
      );
      expect(Recado.fromJson(original.toJson()).toJson(), original.toJson());
      // Recados gravados antes do site não aparecem nele.
      final antigo = original.toJson()..remove('site')..remove('urgente');
      expect(Recado.fromJson(antigo).site, isFalse);
      expect(Recado.fromJson(antigo).urgente, isFalse);
    });

    test('categoria desconhecida (ex: antiga "oracao") vira aviso', () {
      expect(Categoria.fromName('oracao'), Categoria.aviso);
    });
  });

  group('Motivo', () {
    test('linha junta pessoa e motivo', () {
      expect(_m('Irmã Maria', 'Cirurgia').linha, 'Irmã Maria — Cirurgia');
      expect(_m('', 'Pela cidade').linha, 'Pela cidade');
      expect(_m('Família Souza', '').linha, 'Família Souza');
    });

    test('só aprovados e públicos vão para o telão', () {
      expect(_m('a', 'b').projetavel, isTrue);
      expect(_m('a', 'b', status: StatusMotivo.aguardando).projetavel, isFalse);
      expect(_m('a', 'b', status: StatusMotivo.atendido).projetavel, isFalse);
      expect(_m('a', 'b', publico: false).projetavel, isFalse);
    });

    test('um slide quando cabe tudo', () {
      expect(montarSlidesOracao([_m('Ana', 'Saúde'), _m('', 'Pela cidade')]),
          ['<b>Motivos de oração</b>\n• Ana — Saúde\n• Pela cidade']);
    });

    test('divide em slides numerados', () {
      final motivos = [for (var i = 1; i <= 5; i++) _m('P$i', 'M$i')];
      final slides = montarSlidesOracao(motivos, porSlide: 2, negritoTitulo: false);
      expect(slides.length, 3);
      expect(slides[0], 'Motivos de oração (1/3)\n• P1 — M1\n• P2 — M2');
      expect(slides[2], 'Motivos de oração (3/3)\n• P5 — M5');
      expect(montarSlidesOracao([]), isEmpty);
    });

    test('json ida e volta e compatibilidade com o formato antigo', () {
      final m = Motivo(
        id: '1',
        para: 'Ana',
        motivo: 'Emprego',
        tipo: TipoMotivo.trabalho,
        criadoEm: DateTime(2026, 10, 25),
        status: StatusMotivo.aguardando,
        origem: OrigemMotivo.site,
        publico: false,
        enviadoPor: 'Ana',
      );
      expect(Motivo.fromJson(m.toJson()).toJson(), m.toJson());
      expect(Motivo.fromJson({'id': 'x', 'motivo': 'y', 'atendido': true}).status, StatusMotivo.atendido);
      expect(Motivo.fromJson({'id': 'x', 'motivo': 'y'}).status, StatusMotivo.pendente);
    });
  });

  group('Aniversariantes', () {
    test('semana vai de domingo a sábado', () {
      final dias = diasDaSemana(DateTime(2026, 10, 28)); // quarta
      expect(dias.first, DateTime(2026, 10, 25));
      expect(dias.last, DateTime(2026, 10, 31));
      expect(diasDaSemana(DateTime(2026, 10, 25)).first, DateTime(2026, 10, 25)); // domingo
    });

    test('pega quem faz aniversário na semana, em ordem de data', () {
      final membros = [_membro('Pedro', 31, 10), _membro('Ana', 26, 10), _membro('Zé', 1, 11), _membro('Inativo', 27, 10, ativo: false)];
      final r = recadoAniversariantes(membros, DateTime(2026, 10, 28))!;
      expect(r.texto, 'Ana (26/10)\nPedro (31/10)');
      expect(r.auto, isTrue);
      expect(r.fixo, isTrue);
    });

    test('semana que atravessa o ano', () {
      // 27/12/2026 é domingo; a semana vai até 02/01/2027.
      final lista = aniversariantesDaSemana([_membro('Ana', 1, 1), _membro('Bia', 28, 12)], DateTime(2026, 12, 30));
      expect(lista.map((a) => a.data), [DateTime(2026, 12, 28), DateTime(2027, 1, 1)]);
    });

    test('29/02 vira 28/02 em ano não bissexto', () {
      expect(aniversariantesDaSemana([_membro('Léo', 29, 2)], DateTime(2027, 2, 28)).single.data, DateTime(2027, 2, 28));
      expect(aniversariantesDaSemana([_membro('Léo', 29, 2)], DateTime(2028, 2, 29)).single.data, DateTime(2028, 2, 29));
    });

    test('sem ninguém, sem recado', () {
      expect(recadoAniversariantes([_membro('Ana', 1, 1)], DateTime(2026, 6, 10)), isNull);
    });
  });

  group('CSV de membros', () {
    test('lê separadores variados e ignora cabeçalho', () {
      final r = lerCsvMembros('Nome;Aniversário\nAna Souza;12/03\nBruno, 5/11\nCarla\t29/02\nErro;31/02\n;01/01\n');
      expect(r.membros.map((m) => '${m.nome}-${m.dia}/${m.mes}'), ['Ana Souza-12/3', 'Bruno-5/11', 'Carla-29/2']);
      expect(r.linhasComErro, [5, 6]); // "Erro;31/02" e ";01/01"
    });
  });
}
