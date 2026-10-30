import 'package:diako_core/diako_core.dart';
import 'package:test/test.dart';

Visita visita(String nome, {bool mencionar = true, String? membroId}) => Visita(
      id: 'v-$nome',
      membroId: membroId ?? 'm-$nome',
      nome: nome,
      data: '2026-11-02',
      criadoEm: DateTime(2026, 11, 2, 18, 50),
      origem: OrigemVisita.recepcao,
      mencionar: mencionar,
    );

List<Momento> roteiro({
  String hora = '19:00',
  bool ceia = false,
  List<String> musicas = const ['Bondade de Deus · G'],
  List<Recado>? recados,
  List<Motivo> motivos = const [],
  List<Motivo> respondidas = const [],
  List<Visita> visitas = const [],
  Evento? proximo,
}) =>
    montarRoteiro(
      horaCulto: hora,
      ceia: ceia,
      musicas: musicas,
      louvor: {'Ministro': ['Lucas'], 'Vocal': []},
      pastoral: {'Pregação': ['Pr. Marcos'], 'Oração e ofertas': ['Elaine']},
      tema: 'Em memória de mim',
      recados: recados ?? [Recado(id: 'r1', titulo: 'Retiro', texto: 'De 14 a 16/11'), Recado(id: 'r2', titulo: 'Quilo')],
      motivos: motivos,
      respondidas: respondidas,
      visitas: visitas,
      proximoEvento: proximo,
    );

void main() {
  test('roteiro padrão na ordem, sem os momentos vazios', () {
    final r = roteiro();
    expect(r.map((m) => m.tipo), [
      TipoMomento.contagem,
      TipoMomento.louvor,
      TipoMomento.recados,
      TipoMomento.ofertas,
      TipoMomento.palavra,
      TipoMomento.oracaoFinal,
      TipoMomento.encerramento,
    ]);
  });

  test('Santa Ceia, boas-vindas e motivos entram quando há conteúdo', () {
    final r = roteiro(
      ceia: true,
      visitas: [visita('Renata'), visita('Caio', mencionar: false)],
      motivos: [Motivo(id: 'm1', motivo: 'Saúde do Antônio')],
    );
    expect(r.map((m) => m.tipo), containsAllInOrder([
      TipoMomento.boasVindas,
      TipoMomento.recados,
      TipoMomento.ofertas,
      TipoMomento.ceia,
      TipoMomento.motivos,
      TipoMomento.palavra,
    ]));
    final bv = r.firstWhere((m) => m.tipo == TipoMomento.boasVindas);
    expect(bv.passos.single.ids, ['v-Renata'], reason: 'só quem autorizou ser citado');
    expect(bv.linhas, ['Renata']);
  });

  test('sem hora válida não há contagem', () {
    expect(roteiro(hora: '').map((m) => m.tipo), isNot(contains(TipoMomento.contagem)));
  });

  test('cada recado é um passo; imagem vira passo de imagem', () {
    final r = roteiro(recados: [
      Recado(id: 'a', titulo: 'Retiro', texto: 'De 14 a 16/11'),
      Recado(id: 'b', titulo: 'Cartaz do bazar', imagemHolyrics: 'DiakoNews/bazar.jpg'),
    ]);
    final passos = r.firstWhere((m) => m.tipo == TipoMomento.recados).passos;
    expect(passos.map((p) => p.acao), [AcaoPasso.texto, AcaoPasso.imagem]);
    expect(passos.first.valor, '<b>Retiro</b>\nDe 14 a 16/11');
    expect(passos.last.valor, 'DiakoNews/bazar.jpg');
  });

  test('palavra traz pregador e tema; encerramento termina no próximo evento', () {
    final evento = Evento(id: 'e', titulo: 'Retiro de Jovens', inicio: DateTime(2026, 11, 14, 8), fim: DateTime(2026, 11, 16, 18));
    final r = roteiro(proximo: evento);
    expect(r.firstWhere((m) => m.tipo == TipoMomento.palavra).detalhe, 'Pr. Marcos · “Em memória de mim”');
    final fim = r.last.passos;
    expect(fim.map((p) => p.acao), [AcaoPasso.qrOracao, AcaoPasso.qrMensagens, AcaoPasso.texto]);
    expect(fim.last.valor, startsWith('<b>Retiro de Jovens</b>'));
  });

  test('ofertas e ceia com o título em negrito', () {
    final r = roteiro(ceia: true);
    expect(r.firstWhere((m) => m.tipo == TipoMomento.ofertas).passos.single.valor, startsWith('<b>Dízimos e ofertas</b>\n'));
    expect(r.firstWhere((m) => m.tipo == TipoMomento.ceia).passos.first.valor, startsWith('<b>Santa Ceia</b>\n'));
  });

  group('navegação', () {
    final r = roteiro();

    test('avança dentro do momento e depois para o próximo', () {
      expect(proximaPosicao(r, const PosicaoRoteiro(TipoMomento.recados, 0)), const PosicaoRoteiro(TipoMomento.recados, 1));
      expect(proximaPosicao(r, const PosicaoRoteiro(TipoMomento.recados, 1)), const PosicaoRoteiro(TipoMomento.ofertas, 0));
      expect(proximaPosicao(r, PosicaoRoteiro(TipoMomento.encerramento, r.last.passos.length - 1)), isNull);
    });

    test('volta para o último passo do momento anterior', () {
      expect(posicaoAnterior(r, const PosicaoRoteiro(TipoMomento.ofertas, 0)), const PosicaoRoteiro(TipoMomento.recados, 1));
      expect(posicaoAnterior(r, const PosicaoRoteiro(TipoMomento.contagem, 0)), isNull);
    });

    test('momento que saiu do roteiro: segue para o seguinte na ordem padrão', () {
      expect(localizar(r, const PosicaoRoteiro(TipoMomento.ceia, 1)), const PosicaoRoteiro(TipoMomento.palavra, 0));
      expect(proximaPosicao(r, const PosicaoRoteiro(TipoMomento.motivos, 0)), const PosicaoRoteiro(TipoMomento.palavra, 0),
          reason: 'motivos sumiu: localiza em Palavra e avança dali');
    });

    test('passo além do fim fica no último do momento', () {
      expect(localizar(r, const PosicaoRoteiro(TipoMomento.recados, 9)), const PosicaoRoteiro(TipoMomento.recados, 1));
    });
  });

  test('prévia sem as marcações do Holyrics', () {
    expect(textoSemMarcacao('<b>Retiro</b>\nDe 14 a 16/11'), 'Retiro\nDe 14 a 16/11');
  });

  test('culto próximo: de 1 h antes até 3 h depois', () {
    expect(cultoProximo('2026-11-02', '19:00', DateTime(2026, 11, 2, 17, 59)), isFalse);
    expect(cultoProximo('2026-11-02', '19:00', DateTime(2026, 11, 2, 18, 0)), isTrue);
    expect(cultoProximo('2026-11-02', '19:00', DateTime(2026, 11, 2, 21, 59)), isTrue);
    expect(cultoProximo('2026-11-02', '19:00', DateTime(2026, 11, 2, 22, 0)), isFalse);
    expect(cultoProximo('2026-11-02', '', DateTime(2026, 11, 2, 19)), isFalse);
  });
}
