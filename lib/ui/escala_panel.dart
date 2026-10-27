import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/escala_repo.dart';

/// Seção "Escala": quem serve no culto de hoje (pastoral e louvor) e as músicas na ordem do ministro.
/// Sem culto hoje, mostra o próximo (em até 7 dias).
class EscalaPanel extends StatelessWidget {
  const EscalaPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).escalas;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        if (repo.cultos.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                repo.erro ?? 'Nenhum culto com escala hoje nem nos próximos 7 dias.\nA escala é montada no painel, na aba Escalas.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: repo.sincronizar,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              for (final c in repo.cultos) ...[
                _CultoEscala(culto: c, hoje: repo.hoje),
                const SizedBox(height: 28),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _CultoEscala extends StatelessWidget {
  const _CultoEscala({required this.culto, required this.hoje});

  final CultoDoDia culto;
  final bool hoje;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cor = tema.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('${hoje ? 'Hoje' : 'Próximo culto'} · ${culto.rotulo} · ${culto.horaTexto}', style: tema.textTheme.headlineSmall),
            Chip(
              label: Text(culto.ceia ? '${culto.nome} · Santa Ceia' : culto.nome),
              backgroundColor: cor.secondaryContainer,
              side: BorderSide.none,
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, limites) {
            final cartoes = [
              _Cartao(
                titulo: 'Pastoral',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in culto.pastoral.entries)
                      _Funcao(
                        funcao: e.key,
                        nomes: e.value,
                        grande: true,
                        detalhe: e.key == 'Pregação' && culto.tema.isNotEmpty ? 'Tema: ${culto.tema}' : null,
                      ),
                  ],
                ),
              ),
              _Cartao(
                titulo: 'Louvor',
                child: Wrap(
                  spacing: 16,
                  children: [
                    for (final e in culto.louvor.entries)
                      SizedBox(width: 140, child: _Funcao(funcao: e.key, nomes: e.value)),
                  ],
                ),
              ),
              _Cartao(
                titulo: 'Músicas',
                child: culto.musicas.isEmpty
                    ? Text('Sem músicas cadastradas.', style: TextStyle(color: cor.onSurfaceVariant))
                    : Column(
                        children: [
                          for (final (i, m) in culto.musicas.indexed)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(radius: 15, child: Text('${i + 1}', style: const TextStyle(fontSize: 14))),
                              title: Text(m.titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
                              trailing: m.tom.isEmpty ? null : Chip(label: Text('Tom ${m.tom}'), visualDensity: VisualDensity.compact),
                            ),
                        ],
                      ),
              ),
            ];
            // Tablet deitado: três colunas; estreito: um embaixo do outro.
            if (limites.maxWidth < 900) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final c in cartoes) Padding(padding: const EdgeInsets.only(bottom: 16), child: c)],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: cartoes[0]),
                const SizedBox(width: 16),
                Expanded(flex: 3, child: cartoes[1]),
                const SizedBox(width: 16),
                Expanded(flex: 4, child: cartoes[2]),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Cartao extends StatelessWidget {
  const _Cartao({required this.titulo, required this.child});

  final String titulo;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      );
}

class _Funcao extends StatelessWidget {
  const _Funcao({required this.funcao, required this.nomes, this.grande = false, this.detalhe});

  final String funcao;
  final List<String> nomes;
  final bool grande;
  final String? detalhe;

  @override
  Widget build(BuildContext context) {
    final cor = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(funcao.toUpperCase(),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: .8, color: cor.onSurfaceVariant)),
          Text(
            nomes.isEmpty ? '—' : nomes.join(', '),
            style: TextStyle(fontSize: grande ? 18 : 16, fontWeight: FontWeight.w600, color: nomes.isEmpty ? cor.onSurfaceVariant : null),
          ),
          if (detalhe != null) Text(detalhe!, style: TextStyle(fontSize: 14, color: cor.onSurfaceVariant)),
        ],
      ),
    );
  }
}
