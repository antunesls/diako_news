import 'package:flutter/material.dart';

import '../app_scope.dart';

void mostrarFerramentas(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: const _Ferramentas(),
    ),
  );
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

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Contagem no telão
          Expanded(
            child: Column(
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
          ),
          const SizedBox(width: 24),
          // Painel de comunicação (palco)
          Expanded(
            child: Column(
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
                        onPressed: () => executar(context, () => client.mensagemPalco(_mensagem.text.trim()),
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
          ),
        ],
      ),
    );
  }
}
