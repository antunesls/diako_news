import 'agenda.dart';
import 'aniversariantes.dart';
import 'membro.dart';
import 'motivo.dart';
import 'recado.dart';
import 'visita.dart';

String _dm(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

/// Texto do resumo da semana no formato do WhatsApp (*negrito*), só com informações públicas.
String montarResumoSemanal({
  required List<Recado> recados,
  required List<Motivo> motivos,
  required List<Membro> membros,
  required DateTime agora,
  String igreja = 'Igreja Diakonia Tulipas',
  String? urlPedidos,
  List<Evento> eventos = const [],
  List<Visita> visitas = const [],
}) {
  final semana = diasDaSemana(agora);
  final b = StringBuffer('*$igreja — Avisos da semana*\n_${_dm(semana.first)} a ${_dm(semana.last)}_\n');

  void secao(String titulo, List<String> linhas) {
    if (linhas.isEmpty) return;
    b
      ..writeln()
      ..writeln(titulo);
    for (final l in linhas) {
      b.writeln('• $l');
    }
  }

  // Agenda: de hoje até o sábado.
  final hoje = DateTime(agora.year, agora.month, agora.day);
  final fimSemana = semana.last.add(const Duration(days: 1));
  secao('📅 *Agenda da semana*', [
    for (final e in eventos)
      if (e.fim.isAfter(hoje) && e.inicio.isBefore(fimSemana))
        '*${e.titulo}* — ${diaCurto(e.inicio)} ${e.diaInteiro ? '(${horario(e).toLowerCase()})' : horario(e)}${e.local.isEmpty ? '' : ' · ${e.local}'}',
  ]);

  final validos = ordenarParaExibicao(recados.where((r) => !r.auto && !r.expirado(agora)));
  secao('📢 *Recados*', [
    for (final r in validos)
      r.texto.trim().isEmpty
          ? '*${r.titulo.trim()}*'
          : '*${r.titulo.trim()}* — ${r.texto.trim().split(RegExp(r'\s*\n\s*')).join(' · ')}',
  ]);

  secao('🎂 *Aniversariantes da semana*', [
    for (final a in aniversariantesDaSemana(membros, agora)) '${a.membro.nome} (${_dm(a.data)})',
  ]);

  secao('🙏 *Motivos de oração*', [for (final m in motivos.where((m) => m.projetavel)) m.linha]);

  secao('🙌 *Orações respondidas*', [
    for (final m in oracoesRespondidas(motivos, agora, dias: 7))
      m.testemunho.trim().isEmpty ? m.linha : '${m.linha} — ${m.testemunho.trim()}',
  ]);

  // Só a contagem (o resumo é público): quantos visitaram nos últimos 7 dias.
  final desde = diaIso(hoje.subtract(const Duration(days: 6)));
  final daSemana = visitas.where((v) => v.data.compareTo(desde) >= 0 && v.data.compareTo(diaIso(hoje)) <= 0).toList();
  if (daSemana.isNotEmpty) {
    final primeira = daSemana.where((v) => v.primeiraVez).length;
    b
      ..writeln()
      ..writeln('👋 *Recebemos ${daSemana.length} visitante${daSemana.length == 1 ? '' : 's'} nos últimos 7 dias*'
          '${primeira > 0 && primeira < daSemana.length ? ' ($primeira pela primeira vez)' : ''}. Que alegria!');
  }

  if (urlPedidos != null && urlPedidos.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Pedidos de oração: $urlPedidos');
  }
  return b.toString().trimRight();
}
