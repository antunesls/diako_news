import 'package:diako_core/diako_core.dart';
import 'package:flutter/material.dart';

import '../app_scope.dart';

enum _Aba { aguardando, pendentes, atendidos }

/// Corpo da tela no modo "Motivos de oração": lista à esquerda, prévia e projeção à direita.
class OracaoPanel extends StatefulWidget {
  const OracaoPanel({super.key});

  @override
  State<OracaoPanel> createState() => _OracaoPanelState();
}

class _OracaoPanelState extends State<OracaoPanel> {
  _Aba? _aba;
  String? _focadoId;

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).motivos;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        // Abre em "Aguardando" quando há pedidos novos para aprovar.
        final aba = _aba ?? (repo.aguardando.isNotEmpty ? _Aba.aguardando : _Aba.pendentes);
        final lista = switch (aba) {
          _Aba.aguardando => repo.aguardando,
          _Aba.pendentes => repo.pendentes,
          _Aba.atendidos => repo.atendidos,
        };
        final focado = repo.todos.where((m) => m.id == _focadoId).firstOrNull;
        final vazio = switch (aba) {
          _Aba.aguardando => 'Nenhum pedido esperando aprovação.',
          _Aba.pendentes => 'Nenhum motivo.\nToque em "Novo motivo".',
          _Aba.atendidos => 'Nenhuma oração atendida ainda.',
        };
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        _filtro(aba, _Aba.aguardando, 'Aguardando (${repo.aguardando.length})', Icons.mark_email_unread_outlined),
                        _filtro(aba, _Aba.pendentes, 'Lista de oração (${repo.pendentes.length})', null),
                        _filtro(aba, _Aba.atendidos, 'Atendidos (${repo.atendidos.length})', Icons.check_circle_outline),
                      ],
                    ),
                  ),
                  Expanded(
                    child: lista.isEmpty
                        ? Center(
                            child: Text(vazio,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 88),
                            itemCount: lista.length,
                            itemBuilder: (context, i) => _tile(context, lista[i]),
                          ),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(flex: 4, child: _Previa(focado: focado, projetaveis: repo.projetaveis)),
          ],
        );
      },
    );
  }

  Widget _filtro(_Aba atual, _Aba aba, String texto, IconData? icone) => FilterChip(
        avatar: icone == null ? null : Icon(icone, size: 18),
        label: Text(texto),
        selected: atual == aba,
        onSelected: (_) => setState(() => _aba = aba),
      );

  Widget _tile(BuildContext context, Motivo m) {
    final esquema = Theme.of(context).colorScheme;
    final repo = AppScope.of(context).motivos;
    final online = repo.online;
    final detalhes = [
      if (m.para.trim().isNotEmpty) m.motivo,
      m.tipo.label,
      if (m.origem == OrigemMotivo.site) 'pelo site${m.enviadoPor.isNotEmpty ? ' · ${m.enviadoPor}' : ''}',
      if (m.atendidoEm != null) 'atendido em ${_data(m.atendidoEm!)}',
      if (m.testemunho.trim().isNotEmpty) '“${m.testemunho.trim()}”',
    ].where((s) => s.trim().isNotEmpty).join(' · ');

    final Widget leading;
    final List<Widget> acoes;
    if (m.aguardando) {
      leading = const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.mark_email_unread_outlined));
      acoes = [
        FilledButton.tonal(
          onPressed: online ? () => executar(context, () => repo.aprovar(m), sucesso: 'Pedido aprovado') : null,
          child: const Text('Aprovar'),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Recusar',
          icon: const Icon(Icons.close),
          onPressed: online ? () => _recusar(context, m) : null,
        ),
      ];
    } else {
      leading = IconButton(
        tooltip: m.atendido ? 'Voltar para a lista' : 'Marcar como atendido',
        icon: Icon(m.atendido ? Icons.check_circle : Icons.radio_button_unchecked, color: m.atendido ? Colors.greenAccent : null),
        onPressed: online ? () => executar(context, () => repo.alternarAtendido(m)) : null,
      );
      acoes = [
        IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined), onPressed: online ? () => editarMotivo(context, m) : null),
      ];
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: m.id == _focadoId ? esquema.secondaryContainer : null,
      child: ListTile(
        leading: leading,
        title: Row(
          children: [
            Flexible(child: Text(m.para.trim().isEmpty ? m.motivo : m.para, maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (!m.publico)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Tooltip(
                  message: 'Particular: não vai para o telão',
                  child: Icon(Icons.lock_outline, size: 16, color: esquema.outline),
                ),
              ),
          ],
        ),
        subtitle: Text(detalhes, maxLines: 2, overflow: TextOverflow.ellipsis),
        onTap: () => setState(() => _focadoId = m.id),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: acoes),
      ),
    );
  }

  Future<void> _recusar(BuildContext context, Motivo m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recusar pedido?'),
        content: const Text('O pedido será apagado.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Recusar')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await executar(context, () => AppScope.of(context).motivos.excluir(m.id));
    }
  }
}

class _Previa extends StatelessWidget {
  const _Previa({required this.focado, required this.projetaveis});

  final Motivo? focado;
  final List<Motivo> projetaveis;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final s = scope.settings;
    final esquema = Theme.of(context).colorScheme;
    final slides = montarSlidesOracao(projetaveis, porSlide: s.motivosPorSlide, negritoTitulo: false);
    final focadoProjetavel = focado != null && focado!.projetavel;
    final exemplo = focadoProjetavel
        ? montarSlidesOracao([focado!], negritoTitulo: false).first
        : (slides.isEmpty ? null : slides.first);

    Future<void> projetarTodos() => executar(context, () async {
          final textos = montarSlidesOracao(projetaveis, porSlide: s.motivosPorSlide, negritoTitulo: s.negritoTitulo);
          if (textos.length == 1) {
            await scope.client.projetarTexto(textos.first, tema: s.tema);
          } else {
            await scope.client.projetarSequencia(textos,
                tema: s.tema, segundos: s.segundosPorSlide, repetir: s.repetirSequencia);
          }
          scope.status.atualizar();
        }, sucesso: 'Projetando ${projetaveis.length} motivo(s) em ${slides.length} slide(s)');

    Future<void> projetarEste() => executar(context, () async {
          await scope.client.projetarTexto(
            montarSlidesOracao([focado!], negritoTitulo: s.negritoTitulo).first,
            tema: s.tema,
          );
          scope.status.atualizar();
        }, sucesso: 'Projetando motivo');

    final respondidas = oracoesRespondidas(scope.motivos.todos, DateTime.now());
    Future<void> projetarRespondidas() => executar(context, () async {
          final textos = montarSlidesGratidao(respondidas, negritoTitulo: s.negritoTitulo);
          if (textos.length == 1) {
            await scope.client.projetarTexto(textos.first, tema: s.tema);
          } else {
            await scope.client.projetarSequencia(textos,
                tema: s.tema, segundos: s.segundosPorSlide, repetir: s.repetirSequencia);
          }
          scope.status.atualizar();
        }, sucesso: 'Projetando ${respondidas.length} oração(ões) respondida(s)');

    Future<void> projetarQr() => executar(context, () async {
          final estado = await scope.api.estado();
          await scope.client.mostrarImagem(estado['qrHolyrics'] as String);
          scope.status.atualizar();
        }, sucesso: 'QR code dos pedidos de oração no telão');

    final particulares = scope.motivos.pendentes.where((m) => !m.publico).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('PRÉ-VISUALIZAÇÃO', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: esquema.outline)),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFAB47BC), width: 2),
              ),
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              child: exemplo == null
                  ? Text('Nenhum motivo para o telão', style: TextStyle(color: esquema.outline))
                  : FittedBox(fit: BoxFit.scaleDown, child: _SlideOracao(texto: exemplo)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${projetaveis.length} motivo(s) para o telão · ${slides.length} slide(s) de até ${s.motivosPorSlide}'
            '${particulares > 0 ? '\n$particulares particular(es) ficam fora da projeção' : ''}',
            style: TextStyle(color: esquema.outline),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 64,
            child: FilledButton.icon(
              onPressed: projetaveis.isEmpty ? null : projetarTodos,
              icon: const Icon(Icons.play_arrow, size: 32),
              label: const Text('PROJETAR MOTIVOS', style: TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: FilledButton.tonalIcon(
              onPressed: focadoProjetavel ? projetarEste : null,
              icon: const Icon(Icons.person_outline),
              label: const Text('Projetar só o selecionado'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: respondidas.isEmpty ? null : projetarRespondidas,
              icon: const Icon(Icons.celebration_outlined),
              label: Text('Orações respondidas (${respondidas.length}) — últimos 30 dias'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: projetarQr,
              icon: const Icon(Icons.qr_code_2),
              label: const Text('Projetar QR para pedidos de oração'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Prévia aproximada de um slide: primeira linha como título, demais como itens.
class _SlideOracao extends StatelessWidget {
  const _SlideOracao({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final linhas = texto.split('\n');
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(linhas.first,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          for (final l in linhas.skip(1))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(l, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 20)),
            ),
        ],
      ),
    );
  }
}

String _data(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

/// Abre o formulário de motivo (novo quando [motivo] é null).
Future<void> editarMotivo(BuildContext context, Motivo? motivo) {
  return showDialog(context: context, builder: (_) => _MotivoForm(motivo: motivo));
}

class _MotivoForm extends StatefulWidget {
  const _MotivoForm({this.motivo});

  final Motivo? motivo;

  @override
  State<_MotivoForm> createState() => _MotivoFormState();
}

class _MotivoFormState extends State<_MotivoForm> {
  late final TextEditingController _para = TextEditingController(text: widget.motivo?.para);
  late final TextEditingController _motivo = TextEditingController(text: widget.motivo?.motivo);
  late final TextEditingController _testemunho = TextEditingController(text: widget.motivo?.testemunho);
  bool get _atendido => widget.motivo?.atendido ?? false;
  late TipoMotivo _tipo = widget.motivo?.tipo ?? TipoMotivo.saude;
  late bool _publico = widget.motivo?.publico ?? true;
  String? _erro;
  bool _salvando = false;

  @override
  void dispose() {
    _para.dispose();
    _motivo.dispose();
    _testemunho.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (_motivo.text.trim().isEmpty && _para.text.trim().isEmpty) {
      setState(() => _erro = 'Informe o motivo');
      return;
    }
    final repo = AppScope.of(context).motivos;
    final original = widget.motivo;
    final m = (original == null ? Motivo(id: '', motivo: '') : Motivo.fromJson(original.toJson()))
      ..para = _para.text.trim()
      ..motivo = _motivo.text.trim()
      ..tipo = _tipo
      ..publico = _publico
      ..testemunho = _atendido ? _testemunho.text.trim() : (original?.testemunho ?? '');
    setState(() => _salvando = true);
    final ok = await executar(context, () => original == null ? repo.criar(m) : repo.atualizar(m));
    if (!mounted) return;
    setState(() => _salvando = false);
    if (ok) Navigator.pop(context);
  }

  Future<void> _excluir() async {
    final repo = AppScope.of(context).motivos;
    if (await executar(context, () => repo.excluir(widget.motivo!.id)) && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.motivo == null ? 'Novo motivo de oração' : 'Editar motivo'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _para,
              autofocus: widget.motivo == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Por quem orar (opcional)',
                hintText: 'Ex: Irmã Maria, Família Souza',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _motivo,
              textCapitalization: TextCapitalization.sentences,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: 'Motivo',
                hintText: 'Ex: Cirurgia na quinta-feira',
                errorText: _erro,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in TipoMotivo.values)
                  ChoiceChip(label: Text(t.label), selected: _tipo == t, onSelected: (_) => setState(() => _tipo = t)),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Pode ser lido no telão'),
              subtitle: const Text('Desligado: fica só na lista do pastor.'),
              value: _publico,
              onChanged: (v) => setState(() => _publico = v),
            ),
            if (_atendido) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _testemunho,
                textCapitalization: TextCapitalization.sentences,
                minLines: 2,
                maxLines: 3,
                maxLength: 300,
                decoration: const InputDecoration(
                  labelText: 'Testemunho (opcional)',
                  hintText: 'Como a oração foi respondida',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.motivo != null) TextButton(onPressed: _salvando ? null : _excluir, child: const Text('Excluir')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _salvando ? null : _salvar, child: const Text('Salvar')),
      ],
    );
  }
}
