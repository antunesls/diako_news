import 'package:diako_core/diako_core.dart';
import 'package:test/test.dart';

final agora = DateTime(2026, 10, 28, 10); // quarta-feira

Motivo _atendido(String id, String para, String motivo, DateTime quando, {bool publico = true, String testemunho = ''}) =>
    Motivo(
      id: id,
      para: para,
      motivo: motivo,
      status: StatusMotivo.atendido,
      atendidoEm: quando,
      publico: publico,
      testemunho: testemunho,
      criadoEm: DateTime(2026, 9, 1),
    );

void main() {
  group('Orações respondidas', () {
    final motivos = [
      _atendido('a', 'Ana', 'Emprego', DateTime(2026, 10, 20), testemunho: 'Contratada na segunda!'),
      _atendido('b', 'Bia', 'Saúde', DateTime(2026, 10, 27)),
      _atendido('c', 'Caio', 'Particular', DateTime(2026, 10, 27), publico: false),
      _atendido('d', 'Davi', 'Antigo', DateTime(2026, 8, 1)),
      Motivo(id: 'e', motivo: 'Pendente'),
    ];

    test('só públicas, do período, mais recentes primeiro', () {
      expect(oracoesRespondidas(motivos, agora).map((m) => m.id), ['b', 'a']);
      expect(oracoesRespondidas(motivos, agora, dias: 10).map((m) => m.id), ['b', 'a']);
      expect(oracoesRespondidas(motivos, agora, dias: 7).map((m) => m.id), ['b']); // 20/10 fica de fora
    });

    test('slides com testemunho', () {
      final slides = montarSlidesGratidao(oracoesRespondidas(motivos, agora), negritoTitulo: false);
      expect(slides, ['Orações respondidas\n✓ Bia — Saúde\n✓ Ana — Emprego\n   Contratada na segunda!']);
    });

    test('json guarda atendidoEm e testemunho', () {
      final m = motivos.first;
      final volta = Motivo.fromJson(m.toJson());
      expect(volta.atendidoEm, DateTime(2026, 10, 20));
      expect(volta.testemunho, 'Contratada na segunda!');
    });
  });

  group('Resumo semanal', () {
    test('monta seções só com o que é público', () {
      final texto = montarResumoSemanal(
        recados: [
          Recado(id: '1', titulo: 'Culto de Jovens', texto: 'Sábado 19h30\nSalão principal'),
          Recado(id: '2', titulo: 'Santa Ceia', fixo: true),
          Recado(id: '3', titulo: 'Velho', validoAte: DateTime(2026, 10, 1)),
          Recado(id: 'auto-aniversariantes', titulo: 'Aniversariantes da semana', auto: true),
        ],
        motivos: [
          Motivo(id: 'm1', para: 'Irmã Maria', motivo: 'Cirurgia'),
          Motivo(id: 'm2', motivo: 'Segredo', publico: false),
          Motivo(id: 'm3', motivo: 'Do site', status: StatusMotivo.aguardando),
          _atendido('m4', 'Ana', 'Emprego', DateTime(2026, 10, 26), testemunho: 'Contratada!'),
        ],
        membros: [Membro(id: 'x', nome: 'Pedro', dia: 31, mes: 10)],
        agora: agora,
        urlPedidos: 'http://192.168.0.10:8080/oracao',
      );
      expect(texto, '''
*Igreja Diakonia Tulipas — Avisos da semana*
_25/10 a 31/10_

📢 *Recados*
• *Santa Ceia*
• *Culto de Jovens* — Sábado 19h30 · Salão principal

🎂 *Aniversariantes da semana*
• Pedro (31/10)

🙏 *Motivos de oração*
• Irmã Maria — Cirurgia

🙌 *Orações respondidas*
• Ana — Emprego — Contratada!

Pedidos de oração (no Wi-Fi da igreja): http://192.168.0.10:8080/oracao''');
    });

    test('semana vazia tem só o cabeçalho', () {
      expect(montarResumoSemanal(recados: [], motivos: [], membros: [], agora: agora),
          '*Igreja Diakonia Tulipas — Avisos da semana*\n_25/10 a 31/10_');
    });
  });

  group('Mural', () {
    test('recados, cartaz, motivos em blocos, respondidas e QR', () {
      final slides = montarMural(
        recados: [
          Recado(id: '1', titulo: 'Retiro', imagemHolyrics: 'Diako/retiro.jpg', ordem: 1),
          Recado(id: '2', titulo: 'Ceia', texto: 'Domingo', ordem: 0),
          Recado(id: '3', titulo: 'Sem arquivo', imagemHolyrics: 'outra/pasta.jpg', ordem: 2),
          Recado(id: '4', titulo: 'Vencido', validoAte: DateTime(2026, 1, 1)),
        ],
        motivos: [
          for (var i = 0; i < 7; i++) Motivo(id: '$i', motivo: 'M$i'),
          Motivo(id: 'p', motivo: 'Particular', publico: false),
          _atendido('r', 'Ana', 'Emprego', DateTime(2026, 10, 27), testemunho: 'Contratada'),
        ],
        agora: agora,
        urlCartaz: (c) => c.startsWith('Diako/') ? '/cartazes/${c.substring(6)}' : null,
        urlQr: '/qr-oracao.png',
      );
      expect(slides.map((s) => s.tipo), ['texto', 'imagem', 'texto', 'lista', 'lista', 'lista', 'qr']);
      expect(slides[1].imagem, '/cartazes/retiro.jpg');
      expect(slides[3].itens.length, 5);
      expect(slides[4].itens, ['M5', 'M6']);
      expect(slides[5].titulo, 'Orações respondidas');
      expect(slides[5].itens.single, 'Ana — Emprego\nContratada');
      expect(slides[0].toJson()['cor'], '#42a5f5');
      expect(slides.expand((s) => s.itens).any((i) => i.contains('Particular')), isFalse);
    });
  });
}
