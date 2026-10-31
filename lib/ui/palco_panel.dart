import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../holyrics/status_controller.dart';
import 'control_bar.dart';
import 'frases_palco.dart';

/// Coluna fixa do lado direito, visível em todas as seções: conexão com o
/// Holyrics, prévia do recado (na aba Recados), controles de projeção e frases
/// prontas do palco. Rola quando a tela é baixa.
class PalcoPanel extends StatelessWidget {
  const PalcoPanel({super.key, this.previa});

  final Widget? previa;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final tema = Theme.of(context);
    final frases = scope.settings.frasesPalco;
    final rotulo = tema.textTheme.labelLarge?.copyWith(color: tema.colorScheme.outline);
    return Material(
      color: tema.colorScheme.surfaceContainer,
      child: SafeArea(
        left: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('PALCO', style: rotulo)),
                  const StatusHolyricsChip(),
                ],
              ),
              if (previa != null) ...[const SizedBox(height: 12), previa!],
              const SizedBox(height: 16),
              const ControlBar(),
              if (scope.conta.pode('projetar') && frases.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('MENSAGEM PARA O PALCO', style: rotulo),
                const SizedBox(height: 8),
                FrasesPalco(
                  frases: frases,
                  onEnviar: (frase) => executar(context, () => scope.status.mensagemPalco(frase, tema: scope.settings.tema, papelDeParede: scope.settings.papelDeParedePalco),
                      sucesso: 'Mensagem enviada ao palco: "$frase"'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Indicador da conexão com o Holyrics (cor e texto), com o erro no tooltip.
class StatusHolyricsChip extends StatelessWidget {
  const StatusHolyricsChip({super.key});

  @override
  Widget build(BuildContext context) {
    final status = AppScope.of(context).status;
    return ListenableBuilder(
      listenable: status,
      builder: (context, _) {
        final (cor, texto) = switch (status.conexao) {
          Conexao.conectado => (Colors.greenAccent, 'Holyrics conectado'),
          Conexao.verificando => (Colors.amberAccent, 'Conectando…'),
          Conexao.desconectado => (Colors.redAccent, 'Desconectado'),
        };
        return Tooltip(
          message: status.erro ?? '',
          child: Chip(
            avatar: Icon(Icons.circle, size: 12, color: cor),
            label: Text(texto),
          ),
        );
      },
    );
  }
}
