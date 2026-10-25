import 'membro.dart';
import 'recado.dart';

const idRecadoAniversariantes = 'auto-aniversariantes';

/// Domingo a sábado da semana de [hoje].
List<DateTime> diasDaSemana(DateTime hoje) {
  final base = DateTime(hoje.year, hoje.month, hoje.day);
  final domingo = base.subtract(Duration(days: base.weekday % 7));
  return [for (var i = 0; i < 7; i++) DateTime(domingo.year, domingo.month, domingo.day + i)];
}

bool _bissexto(int ano) => (ano % 4 == 0 && ano % 100 != 0) || ano % 400 == 0;

/// Membros ativos que fazem aniversário na semana de [hoje], em ordem de data.
/// Quem nasceu em 29/02 comemora em 28/02 nos anos não bissextos.
List<({Membro membro, DateTime data})> aniversariantesDaSemana(List<Membro> membros, DateTime hoje) {
  final resultado = <({Membro membro, DateTime data})>[];
  for (final dia in diasDaSemana(hoje)) {
    for (final m in membros) {
      if (!m.ativo) continue;
      var (d, mes) = (m.dia, m.mes);
      if (d == 29 && mes == 2 && !_bissexto(dia.year)) d = 28;
      if (d == dia.day && mes == dia.month) resultado.add((membro: m, data: dia));
    }
  }
  return resultado;
}

/// Recado automático "Aniversariantes da semana", ou null se não houver ninguém.
Recado? recadoAniversariantes(List<Membro> membros, DateTime hoje) {
  final lista = aniversariantesDaSemana(membros, hoje);
  if (lista.isEmpty) return null;
  String dm(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  return Recado(
    id: idRecadoAniversariantes,
    titulo: 'Aniversariantes da semana',
    texto: lista.map((a) => '${a.membro.nome} (${dm(a.data)})').join('\n'),
    categoria: Categoria.aniversario,
    fixo: true,
    ordem: -1,
    auto: true,
  );
}
