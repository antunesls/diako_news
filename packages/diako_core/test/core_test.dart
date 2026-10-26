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

  group('Membro', () {
    test('status deriva o ativo do formato antigo', () {
      expect(Membro(id: 'a', nome: 'Ana', dia: 1, mes: 1, ativo: false).status, StatusMembro.inativo);
      expect(Membro(id: 'a', nome: 'Ana', dia: 1, mes: 1).status, StatusMembro.membro);
      expect(StatusMembro.visitante.ativo, isTrue);
      expect(StatusMembro.congregado.ativo, isTrue);
      expect(StatusMembro.membro.ativo, isTrue);
      expect(StatusMembro.inativo.ativo, isFalse);
      expect(StatusMembro.transferido.ativo, isFalse);
    });

    test('json antigo vira status, novo mantém os campos de sempre', () {
      // Antes de existir o cadastro completo: só nome, dia, mes e ativo.
      final antigo = Membro.fromJson({'id': 'x', 'nome': 'Ana', 'dia': 5, 'mes': 3, 'ativo': false});
      expect(antigo.status, StatusMembro.inativo);
      expect(antigo.toJson()['ativo'], isFalse);
      expect(antigo.toJson()['status'], 'inativo');

      final m = Membro(
        id: 'x',
        nome: 'Ana Souza',
        dia: 5,
        mes: 3,
        ano: 1990,
        sexo: 'F',
        cpf: '11144477735',
        telefone: '(11) 98888-7777',
        email: 'ana@exemplo.com',
        status: StatusMembro.congregado,
        dataBatismo: '2015-06-14',
        ministerios: const ['Louvor'],
        conjugeId: 'y',
        paisIds: const ['z'],
      );
      final j = m.toJson();
      expect(Membro.fromJson(j).toJson(), j);
      expect(j['ativo'], isTrue); // congregado é ativo
      expect(j['dia'], 5);
      expect(j['mes'], 3);
    });

    test('idade só quando o ano é guardado', () {
      expect(Membro(id: 'a', nome: 'Ana', dia: 10, mes: 2, ano: 1990).idadeEm(DateTime(2026, 10, 26)), 36);
      expect(Membro(id: 'a', nome: 'Ana', dia: 10, mes: 2, ano: 1990).idadeEm(DateTime(2026, 2, 9)), 35);
      expect(Membro(id: 'a', nome: 'Ana', dia: 10, mes: 2).idadeEm(DateTime(2026)), isNull);
    });

    test('CPF confere dígitos e aceita pontuação', () {
      expect(Membro.cpfValido('11144477735'), isTrue);
      expect(Membro.cpfValido('111.444.777-35'), isTrue);
      expect(Membro.cpfValido('11144477736'), isFalse);
      expect(Membro.cpfValido('11111111111'), isFalse);
      expect(Membro.cpfValido('1234567890'), isFalse);
      expect(Membro.soDigitos('111.444.777-35'), '11144477735');
      expect(Membro.soDigitos(''), isNull);
    });

    test('datas aceitam dd/mm/aaaa e ficam aaaa-mm-dd', () {
      final m = Membro.fromJson({'id': 'x', 'nome': 'Ana', 'dia': 1, 'mes': 1, 'dataBatismo': '14/06/2015'});
      expect(m.dataBatismo, '2015-06-14');
      expect(Membro.dataIsoValida('2015-06-14'), isTrue);
      expect(Membro.dataIsoValida('14/06/2015'), isFalse);
      expect(Membro.dataIsoValida('2999-01-01'), isFalse);
      expect(Membro.dataIsoValida(null), isFalse);
      expect(Membro.dataDe('31/02/2015'), isNull);
      expect(Membro.dataDe('2015-13-01'), isNull);
      expect(Membro.dataDe('1/6/2015'), '2015-06-01');
    });

    test('status por nome aceita acento, maiúsculas e feminino', () {
      expect(StatusMembro.porNome('congregado'), StatusMembro.congregado);
      expect(StatusMembro.porNome('Congregada'), StatusMembro.congregado);
      expect(StatusMembro.porNome('Transferido'), StatusMembro.transferido);
      expect(StatusMembro.porNome('inativa'), StatusMembro.inativo);
      expect(StatusMembro.porNome('xyz'), isNull);
      expect(StatusMembro.porNome(''), isNull);
    });
  });

  group('CSV de membros', () {
    test('formato antigo, sem cabeçalho: separadores variados', () {
      final r = lerCsvMembros('Ana Souza;12/03\nBruno, 5/11\nCarla\t29/02\nErro;31/02\n;01/01\n');
      expect(r.membros.map((m) => '${m.nome}-${m.dia}/${m.mes}'), ['Ana Souza-12/3', 'Bruno-5/11', 'Carla-29/2']);
      expect(r.linhasComErro, [4, 5]); // "Erro;31/02" e ";01/01"
    });

    test('formato antigo com colunas a mais avisa o que foi ignorado e guarda o ano', () {
      final r = lerCsvMembros('Ana Souza;05/03/1990;(11) 98888-7777;ana@exemplo.com\nBruno;10/04\n');
      expect(r.membros.map((m) => m.nome), ['Ana Souza', 'Bruno']);
      expect(r.membros.first.ano, 1990);
      expect(r.linhasComErro, isEmpty);
      expect(r.detalhes.single, contains('Linha 1'));
      expect(r.detalhes.single, contains('cabeçalho'));
    });

    test('cabeçalho aceita como conheceu e consentimento', () {
      final r = lerCsvMembros('Nome;Aniversário;Como conheceu;Consentimento\nRita;07/08;Redes sociais;26/10/2026\n');
      final j = r.membros.single.toJson();
      expect(j['comoConheceu'], 'Redes sociais');
      expect(j['consentimentoEm'], '2026-10-26');
    });

    test('cabeçalho com duas colunas conhecidas liga o formato completo', () {
      final r = lerCsvMembros('Nome;Aniversário\nAna Souza;12/03\nAna Souza;32/03\n;12/03\n');
      expect(r.membros.map((m) => m.nome), ['Ana Souza']);
      expect(r.linhasComErro, [3, 4]);
      expect(r.detalhes.length, 2);
    });

    test('cabeçalho completo lê todas as colunas', () {
      const csv = 'Nome;Aniversário;Sexo;Estado civil;CPF;Telefone;WhatsApp;Email;Status;'
          'Data de batismo;Data de membresia;Ministérios;Função;CEP;Rua;Número;Cidade;UF;Observações\n'
          'Ana Souza;05/03/1990;F;Casada;111.444.777-35;(11) 98888-7777;11988887777;ana@exemplo.com;Congregado;'
          '14/06/2015;2016-03-05;Louvor|Infantil;Líder;01234-000;Rua das Flores;120;São Paulo;SP;Chegou pela família\n'
          'Bruno Lima;5/11;;;;;;;;;;;\n';
      final r = lerCsvMembros(csv);
      expect(r.linhasComErro, isEmpty);
      final ana = r.membros.first;
      expect(ana.nome, 'Ana Souza');
      expect(ana.ano, 1990);
      expect(ana.sexo, 'F');
      expect(ana.estadoCivil, 'Casada');
      expect(ana.cpf, '11144477735');
      expect(ana.telefone, '(11) 98888-7777');
      expect(ana.whatsapp, '11988887777');
      expect(ana.email, 'ana@exemplo.com');
      expect(ana.status, StatusMembro.congregado);
      expect(ana.dataBatismo, '2015-06-14');
      expect(ana.dataMembresia, '2016-03-05');
      expect(ana.ministerios, ['Louvor', 'Infantil']);
      expect(ana.funcao, 'Líder');
      expect(ana.cep, '01234000');
      expect(ana.rua, 'Rua das Flores');
      expect(ana.numero, '120');
      expect(ana.cidade, 'São Paulo');
      expect(ana.estado, 'SP');
      expect(ana.observacoes, 'Chegou pela família');
      final bruno = r.membros.last;
      expect(bruno.nome, 'Bruno Lima');
      expect(bruno.status, StatusMembro.membro); // padrão quando vazio
    });

    test('linha sem aniversário no formato completo gera erro explicando', () {
      final r = lerCsvMembros('Nome;Telefone\nAna;988887777\n');
      expect(r.membros, isEmpty);
      expect(r.linhasComErro, [2]);
      expect(r.detalhes.single, contains('aniversário'));
    });
  });
}
