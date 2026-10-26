import 'package:diako_core/diako_core.dart';
import 'package:flutter/material.dart';

import '../app_scope.dart';

class MensagemPanel extends StatefulWidget {
  const MensagemPanel({super.key});

  @override
  State<MensagemPanel> createState() => _MensagemPanelState();
}

class _MensagemPanelState extends State<MensagemPanel> {
  String filtro = 'nova';
  static const rotulos = {
    'nova': 'Novas',
    'emAnalise': 'Em análise',
    'resolvida': 'Resolvidas',
    'todas': 'Todas',
  };
  static const tipos = {
    'duvida': 'Dúvida',
    'sugestao': 'Sugestão',
    'critica': 'Crítica',
  };

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).mensagens;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final itens = repo.recentes
            .where((m) => filtro == 'todas' || m.status == filtro)
            .toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final e in rotulos.entries)
                    FilterChip(
                      label: Text(e.value),
                      selected: filtro == e.key,
                      onSelected: (_) => setState(() => filtro = e.key),
                    ),
                ],
              ),
            ),
            Expanded(
              child: itens.isEmpty
                  ? const Center(child: Text('Nenhuma mensagem neste filtro.'))
                  : ListView.builder(
                      itemCount: itens.length,
                      itemBuilder: (context, i) =>
                          _cartao(context, itens[i], repo.online),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _cartao(BuildContext context, Mensagem m, bool online) {
    final repo = AppScope.of(context).mensagens;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${tipos[m.tipo] ?? m.tipo} · ${MaterialLocalizations.of(context).formatShortDate(m.criadoEm)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SelectableText(m.texto),
            const SizedBox(height: 8),
            Text(m.nome.isEmpty ? 'Anônima' : 'Nome: ${m.nome}'),
            if (m.contato.isNotEmpty) SelectableText('Contato: ${m.contato}'),
            Text(
              'E-mail: ${m.avisoEmail == 'enviado'
                  ? 'aviso enviado'
                  : m.avisoEmail == 'falhou'
                  ? 'falhou — tente novamente no painel web'
                  : 'pendente / não configurado'}',
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final e in rotulos.entries.where(
                  (e) => e.key != 'todas' && e.key != m.status,
                ))
                  OutlinedButton(
                    onPressed: online
                        ? () => executar(
                            context,
                            () => repo.mudarStatus(m, e.key),
                          )
                        : null,
                    child: Text(e.value),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
