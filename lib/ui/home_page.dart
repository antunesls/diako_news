import 'package:diako_core/diako_core.dart';
import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/modo_culto.dart';
import 'agenda_panel.dart';
import 'escala_panel.dart';
import 'mensagem_panel.dart';
import 'modo_culto_page.dart';
import 'oracao_panel.dart';
import 'palco_panel.dart';
import 'preview_panel.dart';
import 'recado_form.dart';
import 'recado_list.dart';
import 'settings_page.dart';
import 'visitantes_panel.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

enum _Secao { recados, oracao, visitantes, agenda, escala, mensagens }

class _HomePageState extends State<HomePage> {
  final Set<String> _selecionados = {};
  String? _focadoId;
  _Secao _secao = _Secao.recados;
  Set<String>? _aguardandoConhecidos;
  Set<String>? _visitasConhecidas;
  late AppScope _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope = AppScope.of(context);
    _scope.motivos.removeListener(_avisarPedidosNovos);
    _scope.motivos.addListener(_avisarPedidosNovos);
    _scope.visitas.removeListener(_avisarVisitantesNovos);
    _scope.visitas.addListener(_avisarVisitantesNovos);
  }

  @override
  void dispose() {
    _scope.motivos.removeListener(_avisarPedidosNovos);
    _scope.visitas.removeListener(_avisarVisitantesNovos);
    super.dispose();
  }

  /// Avisa quando a recepção (ou o QR) cadastra um visitante novo hoje.
  void _avisarVisitantesNovos() {
    if (!_scope.conta.pode('visitantes')) return;
    final hoje = _scope.visitas.hoje;
    final atuais = {for (final v in hoje) v.id};
    final conhecidas = _visitasConhecidas;
    _visitasConhecidas = atuais;
    if (conhecidas == null || !mounted) return;
    final novas = hoje.where((v) => !conhecidas.contains(v.id)).toList();
    if (novas.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(novas.length == 1
          ? 'Visitante chegou: ${novas.first.nome}${novas.first.mencionar ? ' (pode citar)' : ''}'
          : '${novas.length} visitantes chegaram: ${novas.map((v) => v.nome).join(', ')}'),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(label: 'Ver', onPressed: () => setState(() => _secao = _Secao.visitantes)),
    ));
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

  /// Abre o Modo Culto com os recados selecionados aqui (sem seleção, ele usa os que estão valendo).
  Future<void> _abrirModoCulto() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ModoCultoPage(recadosSelecionados: {..._selecionados})),
    );
    // O aviso "Voltar ao Modo Culto" depende do que ficou salvo.
    if (mounted) setState(() {});
  }

  /// Item do trilho lateral, com o número de pendências no ícone.
  NavigationRailDestination _destino(IconData icone, IconData selecionado, String label, [int pendentes = 0]) {
    Widget comAviso(IconData i) => Badge(isLabelVisible: pendentes > 0, label: Text('$pendentes'), child: Icon(i));
    return NavigationRailDestination(icon: comAviso(icone), selectedIcon: comAviso(selecionado), label: Text(label));
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    return ListenableBuilder(
      listenable: Listenable.merge([scope.repo, scope.motivos, scope.agenda, scope.escalas, scope.mensagens, scope.visitas, scope.conta, scope.projecao]),
      builder: (context, _) {
        final conta = scope.conta;
        // Seções que o perfil vê; se a atual saiu (perfil trocado), volta para Recados.
        final permitidas = {
          _Secao.recados,
          if (conta.pode('motivosVer')) _Secao.oracao,
          if (conta.pode('visitantes')) _Secao.visitantes,
          if (conta.pode('agendaVer')) _Secao.agenda,
          if (conta.pode('escalasVer')) _Secao.escala,
          if (conta.pode('mensagens')) _Secao.mensagens,
        };
        if (!permitidas.contains(_secao)) _secao = _Secao.recados;
        final todos = scope.repo.todos;
        // Remove seleções de recados que foram excluídos.
        _selecionados.removeWhere((id) => !todos.any((r) => r.id == id));
        final focado = todos.where((r) => r.id == _focadoId).firstOrNull;
        final selecionados = ordenarParaExibicao(todos.where((r) => _selecionados.contains(r.id)));
        final aguardando = scope.motivos.aguardando.length;
        final paraCitar = scope.visitas.pendentes.length;
        // Perfis sem acesso aos pedidos não sincronizam os motivos: não conta como "sem conexão".
        final online = scope.repo.online && (!conta.pode('motivosVer') || scope.motivos.online);

        final secoes = _Secao.values.where(permitidas.contains).toList();
        final esquema = Theme.of(context).colorScheme;
        // A agenda é editada no Google: sem botão de criar.
        final podeCriar = online &&
            (_secao == _Secao.recados && conta.pode('recados') || _secao == _Secao.oracao && conta.pode('motivosEditar'));
        // Sugere o Modo Culto perto da hora do culto de hoje, ou para voltar a um culto em andamento.
        final agora = DateTime.now();
        final emAndamento = ModoCultoController.emAndamento(scope.settings.modoCulto, agora);
        final cultoPerto = scope.escalas.hoje
            ? scope.escalas.cultos.where((c) => cultoProximo(c.data, c.hora, agora)).firstOrNull
            : null;
        final avisoCulto = !conta.pode('projetar')
            ? null
            : emAndamento
                ? 'Culto em andamento · Voltar ao Modo Culto'
                : cultoPerto == null
                    ? null
                    : '${cultoPerto.nome} às ${cultoPerto.horaTexto} · Entrar no Modo Culto';

        return Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: esquema.surfaceContainerLow,
                child: SafeArea(
                  right: false,
                  child: Column(
                    children: [
                      Expanded(
                        child: NavigationRail(
                          backgroundColor: Colors.transparent,
                          labelType: NavigationRailLabelType.all,
                          minWidth: 96,
                          leading: Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 12),
                            child: Column(
                              children: [
                                Image.asset('assets/logo/simbolo_claro.png',
                                    width: 64, semanticLabel: 'Igreja Diakonia Tulipas'),
                                if (conta.pode('projetar')) ...[
                                  const SizedBox(height: 14),
                                  IconButton.filled(
                                    tooltip: 'Modo Culto',
                                    iconSize: 28,
                                    icon: const Icon(Icons.church_outlined),
                                    onPressed: _abrirModoCulto,
                                  ),
                                  const Text('Modo Culto', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                                ],
                              ],
                            ),
                          ),
                          selectedIndex: secoes.indexOf(_secao),
                          onDestinationSelected: (i) => setState(() => _secao = secoes[i]),
                          destinations: [
                            for (final s in secoes)
                              switch (s) {
                                _Secao.recados => _destino(Icons.campaign_outlined, Icons.campaign, 'Recados'),
                                _Secao.oracao =>
                                  _destino(Icons.volunteer_activism_outlined, Icons.volunteer_activism, 'Oração', aguardando),
                                _Secao.visitantes =>
                                  _destino(Icons.waving_hand_outlined, Icons.waving_hand, 'Visitantes', paraCitar),
                                _Secao.agenda => _destino(Icons.event_outlined, Icons.event, 'Agenda'),
                                _Secao.escala => _destino(Icons.groups_outlined, Icons.groups, 'Escala'),
                                _Secao.mensagens =>
                                  _destino(Icons.mail_outline, Icons.mail, 'Mensagens', scope.mensagens.novas),
                              },
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Column(
                          children: [
                            Text(
                              scope.projecao.value ? 'Projeção' : 'Projeção\ndesligada',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                color: scope.projecao.value ? null : esquema.error,
                              ),
                            ),
                            Switch(
                              key: const Key('chave-projecao'),
                              value: scope.projecao.value,
                              onChanged: (value) => scope.projecao.value = value,
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: IconButton(
                          tooltip: 'Configurações',
                          iconSize: 28,
                          icon: const Icon(Icons.settings_outlined),
                          onPressed: _abrirConfiguracoes,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: SafeArea(
                  left: false,
                  right: false,
                  child: Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!online)
                            _AvisoOffline(
                                erro: scope.repo.erro ?? scope.motivos.erro ?? scope.mensagens.erro,
                                onConfigurar: _abrirConfiguracoes),
                          if (avisoCulto != null) _AvisoModoCulto(texto: avisoCulto, onTap: _abrirModoCulto),
                          if (_secao == _Secao.recados && scope.agenda.proximo != null)
                            _ProximoEvento(
                                evento: scope.agenda.proximo!, onTap: () => setState(() => _secao = _Secao.agenda)),
                          Expanded(
                            child: switch (_secao) {
                              _Secao.oracao => const OracaoPanel(),
                              _Secao.visitantes => const VisitantesPanel(),
                              _Secao.agenda => AgendaPanel(onVirarRecado: _recadoDoEvento),
                              _Secao.escala => const EscalaPanel(),
                              _Secao.mensagens => const MensagemPanel(),
                              _Secao.recados => RecadoList(
                                  selecionados: _selecionados,
                                  focadoId: _focadoId,
                                  onFocar: (r) => setState(() => _focadoId = r.id),
                                  onAlternarSelecao: (r) => setState(() {
                                    if (!_selecionados.remove(r.id)) _selecionados.add(r.id);
                                  }),
                                  onLimparSelecao: () => setState(_selecionados.clear),
                                  onEditar: _editar,
                                ),
                            },
                          ),
                        ],
                      ),
                      if (podeCriar)
                        Positioned(
                          left: 16,
                          bottom: 16,
                          child: FloatingActionButton.extended(
                            onPressed: () => _secao == _Secao.oracao ? editarMotivo(context, null) : _editar(null),
                            icon: const Icon(Icons.add),
                            label: Text(_secao == _Secao.oracao ? 'Novo motivo' : 'Novo recado'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // Coluna do palco: sempre visível; mais estreita em telas menores que o A9+.
              SizedBox(
                width: MediaQuery.sizeOf(context).width >= 1100 ? 380 : 320,
                child: PalcoPanel(
                  previa: _secao == _Secao.recados ? PreviewPanel(recado: focado, selecionados: selecionados) : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Faixa de destaque que leva ao Modo Culto (culto de hoje perto da hora, ou em andamento).
class _AvisoModoCulto extends StatelessWidget {
  const _AvisoModoCulto({required this.texto, required this.onTap});

  final String texto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Material(
      color: esquema.primaryContainer,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.church_outlined, color: esquema.onPrimaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(texto,
                    style: TextStyle(color: esquema.onPrimaryContainer, fontWeight: FontWeight.w500, fontSize: 16)),
              ),
              Icon(Icons.chevron_right, color: esquema.onPrimaryContainer),
            ],
          ),
        ),
      ),
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
