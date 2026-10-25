import 'package:diako_core/diako_core.dart';
import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/cores.dart';

/// Filtro da lista: todos, uma categoria ou expirados.
sealed class _Filtro {
  const _Filtro();
}

class _Todos extends _Filtro {
  const _Todos();
}

class _PorCategoria extends _Filtro {
  const _PorCategoria(this.categoria);
  final Categoria categoria;
}

class _Expirados extends _Filtro {
  const _Expirados();
}

class RecadoList extends StatefulWidget {
  const RecadoList({
    super.key,
    required this.selecionados,
    required this.focadoId,
    required this.onFocar,
    required this.onAlternarSelecao,
    required this.onLimparSelecao,
    required this.onEditar,
  });

  final Set<String> selecionados;
  final String? focadoId;
  final ValueChanged<Recado> onFocar;
  final ValueChanged<Recado> onAlternarSelecao;
  final VoidCallback onLimparSelecao;
  final ValueChanged<Recado> onEditar;

  @override
  State<RecadoList> createState() => _RecadoListState();
}

class _RecadoListState extends State<RecadoList> {
  _Filtro _filtro = const _Todos();

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).repo;
    final agora = DateTime.now();
    final validos = repo.todos.where((r) => !r.expirado(agora));
    final visiveis = ordenarParaExibicao(switch (_filtro) {
      _Todos() => validos,
      _PorCategoria(:final categoria) => validos.where((r) => r.categoria == categoria),
      _Expirados() => repo.todos.where((r) => r.expirado(agora)),
    });
    final podeReordenar = _filtro is _Todos && repo.online;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              _chip('Todos', const _Todos()),
              for (final c in Categoria.values) _chip(c.label, _PorCategoria(c), cor: c.cor),
              _chip('Expirados', const _Expirados(), icone: Icons.history),
            ],
          ),
        ),
        if (widget.selecionados.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('${widget.selecionados.length} selecionado(s)'),
                const Spacer(),
                TextButton(onPressed: widget.onLimparSelecao, child: const Text('Limpar seleção')),
              ],
            ),
          ),
        Expanded(
          child: visiveis.isEmpty
              ? Center(
                  child: Text(
                    _filtro is _Expirados ? 'Nenhum recado expirado.' : 'Nenhum recado.\nToque em "Novo recado".',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.outline),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  buildDefaultDragHandles: false,
                  itemCount: visiveis.length,
                  // onReorderItem já entrega o índice final ajustado.
                  onReorderItem: (de, para) {
                    final lista = [...visiveis];
                    lista.insert(para, lista.removeAt(de));
                    executar(context, () => repo.reordenar(lista));
                  },
                  itemBuilder: (context, i) => _tile(context, visiveis[i], i, podeReordenar, agora),
                ),
        ),
      ],
    );
  }

  Widget _chip(String label, _Filtro filtro, {Color? cor, IconData? icone}) {
    final ativo = _filtro.runtimeType == filtro.runtimeType &&
        (filtro is! _PorCategoria || (_filtro as _PorCategoria).categoria == filtro.categoria);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: ativo,
        avatar: icone != null ? Icon(icone, size: 18) : (cor != null ? Icon(Icons.circle, size: 12, color: cor) : null),
        onSelected: (_) => setState(() => _filtro = filtro),
      ),
    );
  }

  Widget _tile(BuildContext context, Recado r, int index, bool podeReordenar, DateTime agora) {
    final esquema = Theme.of(context).colorScheme;
    final focado = r.id == widget.focadoId;
    final subtitulo = [
      if (r.ehImagem) 'Imagem: ${r.imagemHolyrics}' else r.texto.split('\n').first,
      if (r.validoAte != null) 'até ${_data(r.validoAte!)}',
    ].where((s) => s.isNotEmpty).join(' · ');

    return Card(
      key: ValueKey(r.id),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: focado ? esquema.secondaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 6, color: r.categoria.cor),
            Expanded(
              child: ListTile(
                contentPadding: const EdgeInsets.only(left: 4, right: 4),
                leading: Checkbox(
                  value: widget.selecionados.contains(r.id),
                  onChanged: (_) => widget.onAlternarSelecao(r),
                ),
                title: Row(
                  children: [
                    if (r.auto)
                      const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.auto_awesome, size: 16))
                    else if (r.fixo)
                      const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.push_pin, size: 16)),
                    if (r.ehImagem) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.image_outlined, size: 16)),
                    Expanded(child: Text(r.titulo, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                ),
                subtitle: subtitulo.isEmpty ? null : Text(subtitulo, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => widget.onFocar(r),
                onLongPress: () => widget.onEditar(r),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!r.auto)
                      IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined), onPressed: () => widget.onEditar(r)),
                    if (podeReordenar && !r.auto)
                      ReorderableDragStartListener(
                        index: index,
                        child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle)),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _data(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
