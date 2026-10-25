import 'package:diako_core/diako_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_scope.dart';
import '../data/cores.dart';
import '../sync/server_api.dart';

class RecadoForm extends StatefulWidget {
  const RecadoForm({super.key, this.recado});

  final Recado? recado;

  @override
  State<RecadoForm> createState() => _RecadoFormState();
}

class _RecadoFormState extends State<RecadoForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _titulo;
  late final TextEditingController _texto;
  String? _imagem;
  late Categoria _categoria;
  DateTime? _validoAte;
  late bool _fixo;

  bool get _novo => widget.recado == null;

  @override
  void initState() {
    super.initState();
    final r = widget.recado;
    _titulo = TextEditingController(text: r?.titulo);
    _texto = TextEditingController(text: r?.texto);
    _imagem = r?.imagemHolyrics;
    _categoria = r?.categoria ?? Categoria.aviso;
    _validoAte = r?.validoAte;
    _fixo = r?.fixo ?? false;
  }

  @override
  void dispose() {
    _titulo.dispose();
    _texto.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    final repo = AppScope.of(context).repo;
    // Cópia: o original só muda quando o servidor confirmar.
    final r = Recado.fromJson({...?widget.recado?.toJson(), 'id': widget.recado?.id ?? ''})
      ..titulo = _titulo.text.trim()
      ..texto = _texto.text.trim()
      ..imagemHolyrics = _imagem
      ..categoria = _categoria
      ..validoAte = _validoAte
      ..fixo = _fixo;
    Recado? salvo;
    await executar(context, () async => salvo = _novo ? await repo.criar(r) : await repo.atualizar(r));
    if (salvo != null && mounted) Navigator.pop(context, salvo);
  }

  Future<void> _excluir() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir recado?'),
        content: Text('"${widget.recado!.titulo}" será removido.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final repo = AppScope.of(context).repo;
    if (await executar(context, () => repo.excluir(widget.recado!.id)) && mounted) Navigator.pop(context);
  }

  Future<void> _escolherData() async {
    final hoje = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _validoAte ?? hoje,
      firstDate: DateTime(hoje.year - 1),
      lastDate: DateTime(hoje.year + 3),
    );
    if (d != null) setState(() => _validoAte = d);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_novo ? 'Novo recado' : 'Editar recado'),
        actions: [
          if (!_novo) IconButton(tooltip: 'Excluir', icon: const Icon(Icons.delete_outline), onPressed: _excluir),
          const SizedBox(width: 8),
          FilledButton(onPressed: _salvar, child: const Text('Salvar')),
          const SizedBox(width: 16),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          children: [
            TextFormField(
              controller: _titulo,
              autofocus: _novo,
              decoration: const InputDecoration(labelText: 'Título', border: OutlineInputBorder()),
              style: const TextStyle(fontSize: 20),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => v == null || v.trim().isEmpty ? 'Informe o título' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _texto,
              decoration: const InputDecoration(
                labelText: 'Texto',
                hintText: 'Data, horário, local, detalhes…',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              minLines: 4,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final c in Categoria.values)
                  ChoiceChip(
                    label: Text(c.label),
                    avatar: Icon(Icons.circle, size: 12, color: c.cor),
                    selected: _categoria == c,
                    onSelected: (_) => setState(() => _categoria = c),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(_validoAte == null
                  ? 'Sem data de validade'
                  : 'Mostrar até ${MaterialLocalizations.of(context).formatShortDate(_validoAte!)}'),
              subtitle: const Text('Depois dessa data o recado vai para "Expirados".'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_validoAte != null)
                    IconButton(tooltip: 'Remover data', icon: const Icon(Icons.clear), onPressed: () => setState(() => _validoAte = null)),
                  OutlinedButton(onPressed: _escolherData, child: const Text('Escolher data')),
                ],
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.push_pin_outlined),
              title: const Text('Fixo'),
              subtitle: const Text('Sempre no topo da lista (ex: Boas-vindas).'),
              value: _fixo,
              onChanged: (v) => setState(() => _fixo = v),
            ),
            const SizedBox(height: 8),
            _SeletorCartaz(valor: _imagem, aoMudar: (v) => setState(() => _imagem = v)),
          ],
        ),
      ),
    );
  }
}

/// Escolhe um cartaz já enviado ao servidor ou envia uma foto do tablet.
class _SeletorCartaz extends StatefulWidget {
  const _SeletorCartaz({required this.valor, required this.aoMudar});

  /// Caminho no Holyrics (ex: "Diako/retiro.jpg") ou null.
  final String? valor;
  final ValueChanged<String?> aoMudar;

  @override
  State<_SeletorCartaz> createState() => _SeletorCartazState();
}

class _SeletorCartazState extends State<_SeletorCartaz> {
  List<Cartaz> _cartazes = [];
  bool _enviando = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final lista = await AppScope.of(context).api.cartazes();
      if (mounted) setState(() => _cartazes = lista);
    } on ErroAmigavel {
      // Sem conexão: o seletor fica vazio, o resto do formulário continua funcionando.
    }
  }

  Future<void> _enviarFoto() async {
    final api = AppScope.of(context).api;
    final foto = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1920, maxHeight: 1920, imageQuality: 88);
    if (foto == null || !mounted) return;
    setState(() => _enviando = true);
    await executar(context, () async {
      final caminho = await api.enviarCartaz(foto.name, await foto.readAsBytes());
      widget.aoMudar(caminho);
      await _carregar();
    }, sucesso: 'Foto enviada ao Holyrics');
    if (mounted) setState(() => _enviando = false);
  }

  Future<void> _escolher() async {
    final escolhido = await showModalBottomSheet<Cartaz>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.7,
        child: _cartazes.isEmpty
            ? const Center(child: Text('Nenhum cartaz enviado ainda.'))
            : GridView.extent(
                maxCrossAxisExtent: 260,
                padding: const EdgeInsets.all(16),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 16 / 11,
                children: [
                  for (final c in _cartazes)
                    InkWell(
                      onTap: () => Navigator.pop(ctx, c),
                      borderRadius: BorderRadius.circular(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(c.url, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(c.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
    if (escolhido != null) widget.aoMudar(escolhido.holyrics);
  }

  @override
  Widget build(BuildContext context) {
    final atual = _cartazes.where((c) => c.holyrics == widget.valor).firstOrNull;
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Cartaz (opcional)',
        helperText: 'Com um cartaz escolhido, o recado é projetado como imagem.',
        border: OutlineInputBorder(),
      ),
      child: Row(
        children: [
          if (atual != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(atual.url, width: 112, height: 63, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined)),
              ),
            ),
          Expanded(child: Text(widget.valor ?? 'Nenhum — projeta o texto')),
          if (_enviando) const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)),
          TextButton.icon(onPressed: _escolher, icon: const Icon(Icons.collections_outlined), label: const Text('Escolher')),
          TextButton.icon(
              onPressed: _enviando ? null : _enviarFoto,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Enviar foto')),
          if (widget.valor != null)
            IconButton(tooltip: 'Remover cartaz', icon: const Icon(Icons.clear), onPressed: () => widget.aoMudar(null)),
        ],
      ),
    );
  }
}
