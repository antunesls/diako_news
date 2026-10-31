import 'package:flutter/material.dart';

import '../app_scope.dart';
import 'frases_palco.dart';

void mostrarFerramentas(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (_) => const _Ferramentas(),
  );
}

/// Janela central das ferramentas do culto: abre no meio da tela, ocupa até 900
/// de largura e rola quando a tela é baixa. Separada do conteúdo para ser
/// testada sem o AppScope.
class ToolsDialog extends StatelessWidget {
  const ToolsDialog({super.key, required this.contagem, required this.palco});

  final Widget contagem;
  final Widget palco;

  @override
  Widget build(BuildContext context) {
    final tela = MediaQuery.sizeOf(context);
    final tema = Theme.of(context);
    return Dialog(
      // Com o teclado aberto, a janela sobe para o campo continuar visível.
      insetPadding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        key: const ValueKey('janela-ferramentas'),
        constraints: BoxConstraints(maxWidth: 900, maxHeight: tela.height * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 18, 12, 10),
              child: Row(
                children: [
                  Icon(Icons.campaign_outlined, color: tema.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Ferramentas do culto', style: tema.textTheme.titleLarge)),
                  IconButton(
                    tooltip: 'Fechar',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(child: ToolsLayout(contagem: contagem, palco: palco)),
          ],
        ),
      ),
    );
  }
}

class _Ferramentas extends StatefulWidget {
  const _Ferramentas();

  @override
  State<_Ferramentas> createState() => _FerramentasState();
}

class _FerramentasState extends State<_Ferramentas> {
  final _tempoTela = TextEditingController(text: '05:00');
  final _textoAntes = TextEditingController(text: 'O culto começa em');
  bool _horaExata = false;
  int _minutosPalco = 5;
  final _mensagem = TextEditingController();

  @override
  void dispose() {
    _tempoTela.dispose();
    _textoAntes.dispose();
    _mensagem.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final client = scope.client;
    final titulo = Theme.of(context).textTheme.titleMedium;

    return ToolsDialog(
      contagem: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Contagem no telão', style: titulo),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Duração (MM:SS)')),
              ButtonSegment(value: true, label: Text('Até a hora (HH:MM)')),
            ],
            selected: {_horaExata},
            onSelectionChanged: (s) => setState(() {
              _horaExata = s.first;
              _tempoTela.text = _horaExata ? '19:30' : '05:00';
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tempoTela,
            keyboardType: TextInputType.datetime,
            decoration: InputDecoration(labelText: _horaExata ? 'Hora' : 'Tempo', border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _textoAntes,
            decoration: const InputDecoration(labelText: 'Texto antes', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.timer),
            label: const Text('Mostrar contagem'),
            onPressed: () => executar(
              context,
              () => client.contagemTela(_tempoTela.text.trim(),
                  horaExata: _horaExata, textoAntes: _textoAntes.text.trim(), tema: scope.settings.tema),
              sucesso: 'Contagem no telão iniciada',
            ),
          ),
        ],
      ),
      palco: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Palco (painel de comunicação)', style: titulo),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton.outlined(
                icon: const Icon(Icons.remove),
                onPressed: _minutosPalco > 1 ? () => setState(() => _minutosPalco--) : null,
              ),
              Expanded(child: Text('$_minutosPalco min', textAlign: TextAlign.center, style: titulo)),
              IconButton.outlined(icon: const Icon(Icons.add), onPressed: () => setState(() => _minutosPalco++)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: () => executar(context, () => client.contagemPalco(_minutosPalco),
                      sucesso: 'Contagem no palco iniciada'),
                  child: const Text('Iniciar contagem'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => executar(context, client.pararContagemPalco, sucesso: 'Contagem parada'),
                child: const Text('Parar'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Frases prontas (um toque envia)', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          const SizedBox(height: 8),
          FrasesPalco(
            frases: scope.settings.frasesPalco,
            onEnviar: (frase) => executar(context, () => scope.status.mensagemPalco(frase, tema: scope.settings.tema, papelDeParede: scope.settings.papelDeParedePalco),
                sucesso: 'Mensagem enviada ao palco: "$frase"'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _mensagem,
            decoration: const InputDecoration(
              labelText: 'Mensagem para o palco',
              hintText: 'Ex: Pastor, faltam 5 minutos',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: () => executar(context, () => scope.status.mensagemPalco(_mensagem.text.trim(), tema: scope.settings.tema, papelDeParede: scope.settings.papelDeParedePalco),
                      sucesso: 'Mensagem enviada ao palco'),
                  child: const Text('Enviar'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => executar(context, () => client.mensagemPalco('', mostrar: false),
                    sucesso: 'Mensagem ocultada'),
                child: const Text('Ocultar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ferramentas do culto (contagem no telão e palco): lado a lado quando cabe,
/// empilhadas e roláveis quando a tela é baixa — nada fica cortado.
class ToolsLayout extends StatelessWidget {
  const ToolsLayout({super.key, required this.contagem, required this.palco});

  final Widget contagem;
  final Widget palco;

  @override
  Widget build(BuildContext context) {
    final tela = MediaQuery.sizeOf(context);
    final ladoALado = tela.width >= 640;
    Widget conteudo = ladoALado
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: contagem),
            const SizedBox(width: 32),
            Expanded(child: palco),
          ])
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            contagem,
            const SizedBox(height: 28),
            palco,
          ]);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: tela.height * 0.85),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
        child: conteudo,
      ),
    );
  }
}
