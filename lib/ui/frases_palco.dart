import 'package:flutter/material.dart';

/// Frases prontas do painel de comunicação: um toque envia a mensagem.
///
/// Fica separado da janela de ferramentas para poder ser testado sem o AppScope.
class FrasesPalco extends StatelessWidget {
  const FrasesPalco({super.key, required this.frases, required this.onEnviar});

  final List<String> frases;
  final ValueChanged<String> onEnviar;

  @override
  Widget build(BuildContext context) {
    if (frases.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final frase in frases)
          ActionChip(
            label: Text(frase),
            avatar: const Icon(Icons.send_outlined, size: 18),
            onPressed: () => onEnviar(frase),
          ),
      ],
    );
  }
}
