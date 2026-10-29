import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../holyrics/status_controller.dart';

class ControlBar extends StatelessWidget {
  const ControlBar({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final status = scope.status;
    final client = scope.client;

    return ListenableBuilder(
      listenable: status,
      builder: (context, _) {
        final conectado = status.conexao == Conexao.conectado;
        final atual = status.atual;
        final rapida = atual?.rapida ?? false;
        final noAr = atual == null
            ? 'Nada no ar'
            : 'No ar: ${atual.nome.isEmpty ? atual.tipo : atual.nome}'
                '${atual.slide != null && atual.totalSlides != null ? '  (${atual.slide}/${atual.totalSlides})' : ''}';

        Future<void> cmd(Future<void> Function() f) => executar(context, () async {
              await f();
              await status.atualizar();
            });

        return ProjectionControls(
          status: noAr,
          actions: [
            _Botao(
              icone: Icons.skip_previous,
              label: 'Anterior',
              onPressed: conectado ? () => cmd(() => client.anterior(rapida: rapida)) : null,
            ),
            _Botao(
              icone: Icons.stop,
              label: 'Parar',
              cor: Colors.redAccent,
              onPressed: conectado ? () => cmd(client.encerrar) : null,
            ),
            _Botao(
              icone: Icons.skip_next,
              label: 'Próximo',
              onPressed: conectado ? () => cmd(() => client.proximo(rapida: rapida)) : null,
            ),
            _Botao(
              icone: Icons.crop_square,
              label: 'Vazia',
              ativo: status.telaVazia,
              onPressed: conectado
                  ? () => cmd(() async {
                        await client.telaVazia(!status.telaVazia);
                        status.telaVazia = !status.telaVazia;
                      })
                  : null,
            ),
            _Botao(
              icone: Icons.square,
              label: 'Preta',
              ativo: status.telaPreta,
              onPressed: conectado
                  ? () => cmd(() async {
                        await client.telaPreta(!status.telaPreta);
                        status.telaPreta = !status.telaPreta;
                      })
                  : null,
            ),
          ],
        );
      },
    );
  }
}

/// Barra inferior de projeção: o que está no ar fica numa linha própria, acima
/// dos botões, sem ser cortada por eles. Os botões passam para a linha de baixo
/// quando a largura não basta, e a altura acompanha o conteúdo.
class ProjectionControls extends StatelessWidget {
  const ProjectionControls({super.key, required this.status, required this.actions});

  final String status;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Material(
      color: tema.colorScheme.surfaceContainer,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                status,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: tema.textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.center, children: actions),
            ],
          ),
        ),
      ),
    );
  }
}

class _Botao extends StatelessWidget {
  const _Botao({required this.icone, required this.label, this.onPressed, this.cor, this.ativo = false});

  final IconData icone;
  final String label;
  final VoidCallback? onPressed;
  final Color? cor;
  final bool ativo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        width: 88,
        child: ativo
            ? FilledButton(onPressed: onPressed, style: _estilo, child: _conteudo())
            : OutlinedButton(onPressed: onPressed, style: _estilo, child: _conteudo()),
      ),
    );
  }

  ButtonStyle get _estilo => ButtonStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
        foregroundColor: cor != null && !ativo ? WidgetStatePropertyAll(cor) : null,
      );

  Widget _conteudo() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icone, size: 28), Text(label, style: const TextStyle(fontSize: 12))],
      );
}
