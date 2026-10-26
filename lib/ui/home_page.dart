import 'package:diako_core/diako_core.dart';
import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../holyrics/status_controller.dart';
import 'agenda_panel.dart';
import 'mensagem_panel.dart';
import 'control_bar.dart';
import 'oracao_panel.dart';
import 'preview_panel.dart';
import 'recado_form.dart';
import 'recado_list.dart';
import 'settings_page.dart';
import 'tools_sheet.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

enum _Secao { recados, oracao, agenda, mensagens }

class _HomePageState extends State<HomePage> {
  final Set<String> _selecionados = {};
  String? _focadoId;
  _Secao _secao = _Secao.recados;
  Set<String>? _aguardandoConhecidos;
  late AppScope _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope = AppScope.of(context);
    _scope.motivos.removeListener(_avisarPedidosNovos);
    _scope.motivos.addListener(_avisarPedidosNovos);
  }

  @override
  void dispose() {
    _scope.motivos.removeListener(_avisarPedidosNovos);
    super.dispose();
  }

  /// Mostra um aviso quando chega pedido de oração novo pelo site.
  void _avisarPedidosNovos() {
    final atuais = {for (final m in _scope.motivos.aguardando) m.id};
    final conhecidos = _aguardandoConhecidos;
    _aguardandoConhecidos = atuais;
    // Na primeira carga não avisa (seriam pedidos antigos).
    if (conhecidos == null || !mounted) return;
    final novos = atuais.difference(conhecidos).length;
    if (novos == 0) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(novos == 1 ? 'Novo pedido de oração aguardando aprovação' : '$novos novos pedidos de oração'),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(label: 'Ver', onPressed: () => setState(() => _secao = _Secao.oracao)),
    ));
  }

  Future<void> _editar(Recado? recado) async {
    if (recado != null && recado.auto) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Esse recado é automático. Edite os aniversariantes no painel web.')));
      return;
    }
    final salvo = await Navigator.of(context).push<Recado>(
      MaterialPageRoute(builder: (_) => RecadoForm(recado: recado), fullscreenDialog: true),
    );
    if (salvo != null) setState(() => _focadoId = salvo.id);
  }

  /// Abre o formulário de recado já preenchido com um evento da agenda.
  Future<void> _recadoDoEvento(Evento e) async {
    final modelo = Recado(
      id: '',
      titulo: e.titulo,
      texto: textoRecadoDoEvento(e),
      categoria: Categoria.evento,
      validoAte: DateTime(e.inicio.year, e.inicio.month, e.inicio.day),
    );
    final salvo = await Navigator.of(context).push<Recado>(
      MaterialPageRoute(builder: (_) => RecadoForm(modelo: modelo), fullscreenDialog: true),
    );
    if (salvo != null && mounted) {
      setState(() {
        _focadoId = salvo.id;
        _secao = _Secao.recados;
      });
    }
  }

  Future<void> _abrirConfiguracoes() async {
    if (!await confirmarPin(context, _scope.settings.pin)) return;
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
    _scope.status.atualizar();
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    return ListenableBuilder(
      listenable: Listenable.merge([scope.repo, scope.motivos, scope.agenda, scope.mensagens, scope.conta]),
      builder: (context, _) {
        final conta = scope.conta;
        // Seções que o perfil vê; se a atual saiu (perfil trocado), volta para Recados.
        final permitidas = {
          _Secao.recados,
          if (conta.pode('motivosVer')) _Secao.oracao,
          if (conta.pode('agendaVer')) _Secao.agenda,
          if (conta.pode('mensagens')) _Secao.mensagens,
        };
        if (!permitidas.contains(_secao)) _secao = _Secao.recados;
        final todos = scope.repo.todos;
        // Remove seleções de recados que foram excluídos.
        _selecionados.removeWhere((id) => !todos.any((r) => r.id == id));
        final focado = todos.where((r) => r.id == _focadoId).firstOrNull;
        final selecionados = ordenarParaExibicao(todos.where((r) => _selecionados.contains(r.id)));
        final aguardando = scope.motivos.aguardando.length;
        // Perfis sem acesso aos pedidos não sincronizam os motivos: não conta como "sem conexão".
        final online = scope.repo.online && (!conta.pode('motivosVer') || scope.motivos.online);

        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 72,
            title: Row(
              children: [
                Image.asset('assets/logo/logo_claro.png', height: 44, semanticLabel: 'Igreja Diakonia Tulipas'),
                const SizedBox(width: 24),
                SegmentedButton<_Secao>(
                  showSelectedIcon: false,
                  segments: [
                    const ButtonSegment(value: _Secao.recados, icon: Icon(Icons.campaign_outlined), label: Text('Recados')),
                    if (permitidas.contains(_Secao.oracao))
                    ButtonSegment(
                      value: _Secao.oracao,
                      icon: Badge(
                        isLabelVisible: aguardando > 0,
                        label: Text('$aguardando'),
                        child: const Icon(Icons.volunteer_activism_outlined),
                      ),
                      label: const Text('Motivos de oração'),
                    ),
                    if (permitidas.contains(_Secao.agenda))
                      const ButtonSegment(value: _Secao.agenda, icon: Icon(Icons.event_outlined), label: Text('Agenda')),
                    if (permitidas.contains(_Secao.mensagens))
                    ButtonSegment(value: _Secao.mensagens,
                      icon: Badge(isLabelVisible: scope.mensagens.novas > 0,
                        label: Text('${scope.mensagens.novas}'), child: const Icon(Icons.mail_outline)),
                      label: const Text('Mensagens')),
                  ],
                  selected: {_secao},
                  onSelectionChanged: (s) => setState(() => _secao = s.first),
                ),
              ],
            ),
            actions: [
              const _StatusChip(),
              const SizedBox(width: 8),
              if (conta.pode('projetar'))
                IconButton(
                  tooltip: 'Contagem e mensagem no palco',
                  icon: const Icon(Icons.timer_outlined),
                  onPressed: () => mostrarFerramentas(context),
                ),
              IconButton(
                tooltip: 'Configurações',
                icon: const Icon(Icons.settings_outlined),
                onPressed: _abrirConfiguracoes,
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!online) _AvisoOffline(erro: scope.repo.erro ?? scope.motivos.erro ?? scope.mensagens.erro, onConfigurar: _abrirConfiguracoes),
              if (_secao == _Secao.recados && scope.agenda.proximo != null)
                _ProximoEvento(evento: scope.agenda.proximo!, onTap: () => setState(() => _secao = _Secao.agenda)),
              Expanded(
                child: switch (_secao) {
                  _Secao.oracao => const OracaoPanel(),
                  _Secao.agenda => AgendaPanel(onVirarRecado: _recadoDoEvento),
                  _Secao.mensagens => const MensagemPanel(),
                  _Secao.recados => Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 5,
                            child: RecadoList(
                              selecionados: _selecionados,
                              focadoId: _focadoId,
                              onFocar: (r) => setState(() => _focadoId = r.id),
                              onAlternarSelecao: (r) => setState(() {
                                if (!_selecionados.remove(r.id)) _selecionados.add(r.id);
                              }),
                              onLimparSelecao: () => setState(_selecionados.clear),
                              onEditar: _editar,
                            ),
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(
                            flex: 4,
                            child: PreviewPanel(recado: focado, selecionados: selecionados),
                          ),
                        ],
                      ),
                },
              ),
            ],
          ),
          // A agenda é editada no Google: sem botão de criar.
          floatingActionButton: online &&
                  (_secao == _Secao.recados && conta.pode('recados') ||
                      _secao == _Secao.oracao && conta.pode('motivosEditar'))
              ? FloatingActionButton.extended(
                  onPressed: () => _secao == _Secao.oracao ? editarMotivo(context, null) : _editar(null),
                  icon: const Icon(Icons.add),
                  label: Text(_secao == _Secao.oracao ? 'Novo motivo' : 'Novo recado'),
                )
              : null,
          floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
          bottomNavigationBar: const ControlBar(),
        );
      },
    );
  }
}

/// Faixa discreta com o próximo evento da agenda (toque abre a aba Agenda).
class _ProximoEvento extends StatelessWidget {
  const _ProximoEvento({required this.evento, required this.onTap});

  final Evento evento;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final agora = DateTime.now();
    final hoje = evento.inicio.year == agora.year && evento.inicio.month == agora.month && evento.inicio.day == agora.day;
    return Material(
      color: esquema.surfaceContainerHigh,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.event_outlined, size: 20, color: esquema.primary),
              const SizedBox(width: 12),
              Text('Próximo: ', style: TextStyle(color: esquema.outline)),
              Flexible(
                child: Text(
                  '${evento.titulo} · ${hoje ? 'hoje' : diaCurto(evento.inicio)} ${horario(evento)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: esquema.outline),
            ],
          ),
        ),
      ),
    );
  }
}

/// Faixa mostrada quando o servidor não responde: os dados vêm da cópia local.
class _AvisoOffline extends StatelessWidget {
  const _AvisoOffline({required this.erro, required this.onConfigurar});

  final String? erro;
  final VoidCallback onConfigurar;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final esquema = Theme.of(context).colorScheme;
    final semConfig = !scope.settings.configurado;
    return Material(
      color: esquema.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.cloud_off, color: esquema.onErrorContainer),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                semConfig
                    ? 'Configure o endereço do servidor da igreja para começar.'
                    : 'Sem conexão com o servidor — mostrando a última cópia salva. Edição desativada.\n${erro ?? ''}',
                style: TextStyle(color: esquema.onErrorContainer),
              ),
            ),
            if (semConfig)
              FilledButton(onPressed: onConfigurar, child: const Text('Configurar'))
            else
              TextButton(onPressed: scope.sincronizarTudo, child: const Text('Tentar de novo')),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip();

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

/// Pede o PIN quando houver um configurado. Retorna true se liberado.
Future<bool> confirmarPin(BuildContext context, String pin) async {
  if (pin.isEmpty) return true;
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Digite o PIN'),
      content: TextField(
        controller: controller,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        onSubmitted: (v) => Navigator.pop(ctx, v == pin),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text == pin), child: const Text('OK')),
      ],
    ),
  );
  if (ok == false && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN incorreto.')));
  }
  return ok ?? false;
}
