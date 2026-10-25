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

        return BottomAppBar(
          height: 88,
          child: Row(
            children: [
              Expanded(
                child: Text(noAr, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
              ),
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
              const SizedBox(width: 16),
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
          ),
        );
      },
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
