import 'package:diako_core/diako_core.dart';
import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/agenda_repo.dart';

/// Cria ou edita um evento do Google Agenda (o servidor grava direto na agenda da igreja).
class EventoForm extends StatefulWidget {
  const EventoForm({super.key, this.evento});

  /// Evento a editar; null cria um novo.
  final Evento? evento;

  @override
  State<EventoForm> createState() => _EventoFormState();
}

class _EventoFormState extends State<EventoForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _titulo;
  late final TextEditingController _local;
  late final TextEditingController _descricao;
  late bool _diaInteiro;
  late DateTime _dia;
  late DateTime _ultimoDia;
  late TimeOfDay _horaInicio;
  late TimeOfDay _horaFim;
  String? _erro;
  bool _salvando = false;

  bool get _novo => widget.evento == null;

  @override
  void initState() {
    super.initState();
    final e = widget.evento;
    final hoje = DateTime.now();
    _titulo = TextEditingController(text: e?.titulo);
    _local = TextEditingController(text: e?.local);
    _descricao = TextEditingController(text: e?.descricao);
    _diaInteiro = e?.diaInteiro ?? false;
    _dia = _soData(e?.inicio ?? hoje);
    // No dia inteiro o fim é exclusivo (o dia seguinte ao último).
    _ultimoDia = e != null && e.diaInteiro ? _soData(e.fim).subtract(const Duration(days: 1)) : _dia;
    _horaInicio = e != null && !e.diaInteiro ? TimeOfDay.fromDateTime(e.inicio) : const TimeOfDay(hour: 19, minute: 0);
    _horaFim = e != null && !e.diaInteiro ? TimeOfDay.fromDateTime(e.fim) : const TimeOfDay(hour: 21, minute: 0);
  }

  @override
  void dispose() {
    _titulo.dispose();
    _local.dispose();
    _descricao.dispose();
    super.dispose();
  }

  static DateTime _soData(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _com(DateTime dia, TimeOfDay h) => DateTime(dia.year, dia.month, dia.day, h.hour, h.minute);

  Map<String, dynamic>? _dados() {
    final inicio = _diaInteiro ? _dia : _com(_dia, _horaInicio);
    final fim = _diaInteiro ? _ultimoDia.add(const Duration(days: 1)) : _com(_dia, _horaFim);
    final erro = validarEvento(
      titulo: _titulo.text,
      inicio: inicio,
      fim: fim,
      diaInteiro: _diaInteiro,
      local: _local.text,
      descricao: _descricao.text,
    );
    setState(() => _erro = erro);
    if (erro != null) return null;
    return AgendaRepo.dadosEvento(
        titulo: _titulo.text, inicio: inicio, fim: fim, diaInteiro: _diaInteiro, local: _local.text, descricao: _descricao.text);
  }

  Future<void> _salvar() async {
    final dados = _dados();
    if (dados == null || _salvando) return;
    final agenda = AppScope.of(context).agenda;
    setState(() => _salvando = true);
    Evento? salvo;
    await executar(context, () async {
      salvo = _novo ? await agenda.criar(dados) : await agenda.atualizar(widget.evento!.id, dados);
    }, sucesso: _novo ? 'Evento criado no Google Agenda' : 'Evento atualizado');
    if (!mounted) return;
    setState(() => _salvando = false);
    if (salvo != null) Navigator.pop(context, salvo);
  }

  Future<void> _excluir() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir evento?'),
        content: Text('"${widget.evento!.titulo}" será removido do Google Agenda da igreja.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final agenda = AppScope.of(context).agenda;
    final excluiu = await executar(context, () => agenda.excluir(widget.evento!.id), sucesso: 'Evento excluído');
    if (excluiu && mounted) Navigator.pop(context);
  }

  Future<void> _escolherDia({required bool ultimo}) async {
    final hoje = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: ultimo ? _ultimoDia : _dia,
      firstDate: DateTime(hoje.year - 1),
      lastDate: DateTime(hoje.year + 3),
    );
    if (d == null) return;
    setState(() {
      if (ultimo) {
        _ultimoDia = d;
      } else {
        // Mantém a duração de eventos de vários dias ao mudar o primeiro dia.
        final dias = _ultimoDia.difference(_dia).inDays;
        _dia = d;
        _ultimoDia = d.add(Duration(days: dias < 0 ? 0 : dias));
      }
    });
  }

  Future<void> _escolherHora({required bool fim}) async {
    final h = await showTimePicker(context: context, initialTime: fim ? _horaFim : _horaInicio);
    if (h == null) return;
    setState(() {
      if (fim) {
        _horaFim = h;
      } else {
        // Mantém a duração ao mudar o início.
        final duracao = (_horaFim.hour * 60 + _horaFim.minute) - (_horaInicio.hour * 60 + _horaInicio.minute);
        _horaInicio = h;
        final novoFim = h.hour * 60 + h.minute + (duracao > 0 ? duracao : 60);
        if (novoFim < 24 * 60) _horaFim = TimeOfDay(hour: novoFim ~/ 60, minute: novoFim % 60);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    String data(DateTime d) => '${diaCurto(d)}/${d.year}';
    return Scaffold(
      appBar: AppBar(
        title: Text(_novo ? 'Novo evento' : 'Editar evento'),
        actions: [
          if (!_novo) IconButton(tooltip: 'Excluir', icon: const Icon(Icons.delete_outline), onPressed: _salvando ? null : _excluir),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _salvando ? null : _salvar,
            child: _salvando
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Salvar'),
          ),
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
              maxLength: maxTituloEvento,
              decoration: const InputDecoration(labelText: 'Título', border: OutlineInputBorder(), counterText: ''),
              style: const TextStyle(fontSize: 20),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.wb_sunny_outlined),
              title: const Text('Dia inteiro'),
              subtitle: const Text('Sem horário (ex.: retiro, feriado). Pode durar vários dias.'),
              value: _diaInteiro,
              onChanged: (v) => setState(() => _diaInteiro = v),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(_diaInteiro ? 'Primeiro dia' : 'Data'),
              subtitle: Text(data(_dia)),
              trailing: OutlinedButton(onPressed: () => _escolherDia(ultimo: false), child: const Text('Escolher')),
            ),
            if (_diaInteiro)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_available),
                title: const Text('Último dia'),
                subtitle: Text(data(_ultimoDia)),
                trailing: OutlinedButton(onPressed: () => _escolherDia(ultimo: true), child: const Text('Escolher')),
              )
            else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: const Text('Início'),
                subtitle: Text(loc.formatTimeOfDay(_horaInicio, alwaysUse24HourFormat: true)),
                trailing: OutlinedButton(onPressed: () => _escolherHora(fim: false), child: const Text('Escolher')),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule_outlined),
                title: const Text('Término'),
                subtitle: Text(loc.formatTimeOfDay(_horaFim, alwaysUse24HourFormat: true)),
                trailing: OutlinedButton(onPressed: () => _escolherHora(fim: true), child: const Text('Escolher')),
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _local,
              maxLength: maxLocalEvento,
              decoration: const InputDecoration(labelText: 'Local (opcional)', border: OutlineInputBorder(), counterText: ''),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descricao,
              maxLength: maxDescricaoEvento,
              decoration: const InputDecoration(
                labelText: 'Descrição (opcional)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
                counterText: '',
              ),
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
            ),
            if (_erro != null) ...[
              const SizedBox(height: 12),
              Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 12),
            Text('O evento vai direto para o Google Agenda da igreja.',
                style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          ],
        ),
      ),
    );
  }
}
