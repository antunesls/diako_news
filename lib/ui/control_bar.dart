import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../holyrics/status_controller.dart';
import 'tools_sheet.dart';

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
              grande: true,
              onPressed: conectado ? () => cmd(() => client.anterior(rapida: rapida)) : null,
            ),
            _Botao(
              icone: Icons.stop,
              label: 'Parar',
              grande: true,
              cor: Colors.redAccent,
              onPressed: conectado ? () => cmd(client.encerrar) : null,
            ),
            _Botao(
              icone: Icons.skip_next,
              label: 'Próximo',
              grande: true,
              ativo: true,
              onPressed: conectado ? () => cmd(() => client.proximo(rapida: rapida)) : null,
            ),
            _Botao(
              icone: Icons.crop_square,
              label: 'Vazia',
              ativo: status.telaVazia,
              onPressed: conectado
                  ? () => cmd(() async {
                        await client.telaVazia(!status.telaVazia, tema: scope.settings.tema);
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
            if (scope.conta.pode('projetar'))
              _Botao(
                icone: Icons.timer_outlined,
                label: 'Contagem',
                onPressed: () => mostrarFerramentas(context),
              ),
          ],
        );
      },
    );
  }
}

/// Controles de projeção da coluna do palco: o que está no ar fica numa linha
/// própria, acima dos botões, sem ser cortado por eles. Os botões ficam numa
/// grade de três colunas de mesma largura, que acompanha a largura da coluna.
class ProjectionControls extends StatelessWidget {
  const ProjectionControls({super.key, required this.status, required this.actions});

  final String status;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          status,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: tema.textTheme.titleSmall,
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < actions.length; i += 3)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
            child: Row(
              children: [
                for (var j = i; j < i + 3; j++) ...[
                  if (j > i) const SizedBox(width: 10),
                  Expanded(child: j < actions.length ? actions[j] : const SizedBox.shrink()),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _Botao extends StatelessWidget {
  const _Botao({required this.icone, required this.label, this.onPressed, this.cor, this.ativo = false, this.grande = false});

  final IconData icone;
  final String label;
  final VoidCallback? onPressed;
  final Color? cor;
  final bool ativo;

  /// Anterior, Parar e Próximo: mais altos, para acertar sem olhar durante o culto.
  final bool grande;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: grande ? 96 : 72,
      child: ativo
          ? FilledButton(onPressed: onPressed, style: _estilo, child: _conteudo())
          : OutlinedButton(onPressed: onPressed, style: _estilo, child: _conteudo()),
    );
  }

  ButtonStyle get _estilo => ButtonStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6, horizontal: 4)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
        foregroundColor: cor != null && !ativo ? WidgetStatePropertyAll(cor) : null,
      );

  Widget _conteudo() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: grande ? 40 : 28),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
        ],
      );
}
