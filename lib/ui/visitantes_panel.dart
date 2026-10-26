import 'package:diako_core/diako_core.dart';
import 'package:flutter/material.dart';

import '../app_scope.dart';

/// Seção "Visitantes": quem chegou hoje e as pendências do pastor (quem pode ser
/// citado no culto). Projeta "Sejam bem-vindos!" no telão e dá baixa.
class VisitantesPanel extends StatefulWidget {
  const VisitantesPanel({super.key});

  @override
  State<VisitantesPanel> createState() => _VisitantesPanelState();
}

class _VisitantesPanelState extends State<VisitantesPanel> {
  /// Pendentes marcados para projetar só alguns (vazio: projeta todos os pendentes).
  final Set<String> _selecionados = {};
  bool _projetando = false;

  static const _interesses = {
    InteresseVisita.visitaPastoral: 'quer visita',
    InteresseVisita.oracao: 'quer oração',
    InteresseVisita.batismo: 'batismo',
    InteresseVisita.celula: 'grupo/célula',
  };
  static const _origens = {OrigemVisita.qr: 'pelo QR', OrigemVisita.recepcao: 'na recepção', OrigemVisita.painel: 'pela secretaria'};

  Future<void> _projetar() async {
    final scope = AppScope.of(context);
    final ids = _selecionados.isEmpty ? null : _selecionados.toList();
    setState(() => _projetando = true);
    final ok = await executar(context, () => scope.visitas.projetarBoasVindas(ids: ids), sucesso: 'Boas-vindas no telão');
    if (!mounted) return;
    setState(() {
      _projetando = false;
      if (ok) _selecionados.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final repo = scope.visitas;
    final podeProjetar = scope.conta.pode('projetar');
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final hoje = repo.hoje;
        final pendentes = repo.pendentes;
        _selecionados.removeWhere((id) => !pendentes.any((v) => v.id == id));
        final tema = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Visitantes de hoje', style: tema.textTheme.titleLarge),
                        Text(
                          hoje.isEmpty
                              ? 'Ninguém cadastrado ainda'
                              : '${hoje.length} ${hoje.length == 1 ? 'visitante' : 'visitantes'} · '
                                  '${pendentes.length} para citar',
                          style: tema.textTheme.bodyMedium?.copyWith(color: tema.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (podeProjetar && pendentes.isNotEmpty)
                    FilledButton.icon(
                      onPressed: _projetando ? null : _projetar,
                      icon: const Icon(Icons.waving_hand_outlined),
                      label: Text(_selecionados.isEmpty
                          ? 'Projetar boas-vindas (${pendentes.length})'
                          : 'Projetar selecionados (${_selecionados.length})'),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: hoje.isEmpty
                  ? Center(
                      child: Text(
                        'Quando a recepção cadastrar um visitante,\nele aparece aqui na hora.',
                        textAlign: TextAlign.center,
                        style: tema.textTheme.bodyLarge?.copyWith(color: tema.colorScheme.onSurfaceVariant),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: hoje.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                      itemBuilder: (context, i) => _item(context, hoje[i], podeProjetar),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _item(BuildContext context, Visita v, bool podeProjetar) {
    final repo = AppScope.of(context).visitas;
    final tema = Theme.of(context);
    final detalhes = [
      v.primeiraVez ? '1ª visita' : 'voltou',
      _origens[v.origem] ?? '',
      for (final i in v.interesses) _interesses[i] ?? i.name,
    ].where((t) => t.isNotEmpty).join(' · ');
    final Widget acao;
    if (!v.mencionar) {
      acao = const Chip(label: Text('Não citar'), avatar: Icon(Icons.do_not_disturb_on_outlined, size: 18));
    } else if (v.mencionadaEm != null) {
      acao = TextButton.icon(
        onPressed: () => executar(context, () => repo.marcarMencionada(v, desfazer: true)),
        icon: const Icon(Icons.check_circle, color: Colors.green),
        label: const Text('Citado'),
      );
    } else {
      acao = OutlinedButton(
        onPressed: () => executar(context, () => repo.marcarMencionada(v), sucesso: '${v.nome} marcado como citado'),
        child: const Text('Já citei'),
      );
    }
    final pendente = v.pendente && podeProjetar;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: pendente
          ? Checkbox(
              value: _selecionados.contains(v.id),
              onChanged: (s) => setState(() => s == true ? _selecionados.add(v.id) : _selecionados.remove(v.id)),
            )
          : CircleAvatar(child: Text(v.nome.trim().isEmpty ? '?' : v.nome.trim()[0].toUpperCase())),
      title: Text(v.nome, style: tema.textTheme.titleMedium),
      subtitle: Text(detalhes),
      trailing: acao,
    );
  }
}
