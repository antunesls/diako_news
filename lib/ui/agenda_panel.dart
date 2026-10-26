import 'package:diako_core/diako_core.dart';
import 'package:flutter/material.dart';

import '../app_scope.dart';

/// Aba "Agenda": próximos eventos do Google Agenda (só leitura), com projeção e "virar recado".
class AgendaPanel extends StatefulWidget {
  const AgendaPanel({super.key, required this.onVirarRecado});

  final ValueChanged<Evento> onVirarRecado;

  @override
  State<AgendaPanel> createState() => _AgendaPanelState();
}

class _AgendaPanelState extends State<AgendaPanel> {
  String? _focadoId;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final agenda = scope.agenda;
    final esquema = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: agenda,
      builder: (context, _) {
        final eventos = agenda.eventos;
        final focado = eventos.where((e) => e.id == _focadoId).firstOrNull ?? eventos.firstOrNull;

        if (!agenda.configurada) {
          return _Vazio(
            icone: Icons.event_busy_outlined,
            texto: 'A agenda do Google ainda não foi ligada.\n'
                'Em Administração (no navegador), cole o "Endereço secreto no formato iCal" da agenda da igreja.',
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            agenda.erro != null
                                ? 'Mostrando a última cópia: ${agenda.erro}'
                                : 'Próximos 30 dias · editados no Google Agenda',
                            style: TextStyle(color: agenda.erro != null ? esquema.error : esquema.outline),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Atualizar',
                          icon: const Icon(Icons.refresh),
                          onPressed: agenda.sincronizar,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: eventos.isEmpty
                        ? const _Vazio(icone: Icons.event_available_outlined, texto: 'Nenhum evento nos próximos 30 dias.')
                        : ListView(
                            padding: const EdgeInsets.only(bottom: 24),
                            children: [
                              for (final grupo in _porDia(eventos)) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                                  child: Text(_rotuloDia(grupo.first.inicio),
                                      style: Theme.of(context).textTheme.titleSmall?.copyWith(color: esquema.primary)),
                                ),
                                for (final e in grupo) _tile(context, e, e.id == focado?.id),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(flex: 4, child: _Previa(evento: focado, onVirarRecado: widget.onVirarRecado)),
          ],
        );
      },
    );
  }

  Widget _tile(BuildContext context, Evento e, bool focado) {
    final esquema = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: focado ? esquema.secondaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _focadoId = e.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 108,
                child: Text(horario(e), style: TextStyle(fontWeight: FontWeight.w600, color: esquema.primary)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                    if (e.local.isNotEmpty)
                      Text(e.local, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: esquema.outline)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static List<List<Evento>> _porDia(List<Evento> eventos) {
    final grupos = <List<Evento>>[];
    for (final e in eventos) {
      final ultimo = grupos.isEmpty ? null : grupos.last.first.inicio;
      if (ultimo != null && ultimo.year == e.inicio.year && ultimo.month == e.inicio.month && ultimo.day == e.inicio.day) {
        grupos.last.add(e);
      } else {
        grupos.add([e]);
      }
    }
    return grupos;
  }

  static String _rotuloDia(DateTime d) {
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final dia = DateTime(d.year, d.month, d.day);
    final diff = dia.difference(hoje).inDays;
    if (diff <= 0) return 'Hoje · ${diaPorExtenso(d)}';
    if (diff == 1) return 'Amanhã · ${diaPorExtenso(d)}';
    return diaPorExtenso(d);
  }
}

class _Previa extends StatelessWidget {
  const _Previa({required this.evento, required this.onVirarRecado});

  final Evento? evento;
  final ValueChanged<Evento> onVirarRecado;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final esquema = Theme.of(context).colorScheme;
    final e = evento;

    Future<void> projetar() => executar(context, () async {
          await scope.client.projetarTexto(
            montarSlideEvento(e!, negritoTitulo: scope.settings.negritoTitulo),
            tema: scope.settings.tema,
          );
          scope.status.atualizar();
        }, sucesso: 'Projetando "${e!.titulo}"');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('PRÉ-VISUALIZAÇÃO', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: esquema.outline)),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF5C6BC0), width: 2),
              ),
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              child: e == null
                  ? Text('Toque em um evento', style: TextStyle(color: esquema.outline))
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(e.titulo,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text(quandoPorExtenso(e), style: const TextStyle(color: Colors.white, fontSize: 20)),
                          if (e.local.isNotEmpty) Text(e.local, style: const TextStyle(color: Colors.white70, fontSize: 18)),
                        ],
                      ),
                    ),
            ),
          ),
          if (e != null && e.descricao.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(e.descricao, maxLines: 6, overflow: TextOverflow.ellipsis, style: TextStyle(color: esquema.outline)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 64,
            child: FilledButton.icon(
              onPressed: e == null ? null : projetar,
              icon: const Icon(Icons.play_arrow, size: 32),
              label: const Text('PROJETAR', style: TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: FilledButton.tonalIcon(
              onPressed: e == null ? null : () => onVirarRecado(e),
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('Virar recado'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Vazio extends StatelessWidget {
  const _Vazio({required this.icone, required this.texto});

  final IconData icone;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 48, color: esquema.outline),
            const SizedBox(height: 12),
            Text(texto, textAlign: TextAlign.center, style: TextStyle(color: esquema.outline)),
          ],
        ),
      ),
    );
  }
}
