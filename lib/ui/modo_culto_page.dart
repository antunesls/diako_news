import 'dart:async';
import 'dart:math' as math;

import 'package:diako_core/diako_core.dart';
import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../data/modo_culto.dart';
import '../holyrics/status_controller.dart';
import 'home_page.dart';
import 'palco_panel.dart';

/// Segunda interface do tablet, só para o horário do culto: o roteiro do dia, o momento atual
/// e um Avançar grande. Nada de edição aqui. Sai segurando o botão Sair (e o PIN, se houver).
class ModoCultoPage extends StatefulWidget {
  const ModoCultoPage({super.key, this.recadosSelecionados = const {}});

  /// Recados escolhidos na tela de organizar; vazio usa todos os que não expiraram.
  final Set<String> recadosSelecionados;

  @override
  State<ModoCultoPage> createState() => _ModoCultoPageState();
}

IconData iconeDoMomento(TipoMomento t) => switch (t) {
      TipoMomento.contagem => Icons.timer_outlined,
      TipoMomento.boasVindas => Icons.waving_hand_outlined,
      TipoMomento.louvor => Icons.music_note_outlined,
      TipoMomento.recados => Icons.campaign_outlined,
      TipoMomento.ofertas => Icons.volunteer_activism_outlined,
      TipoMomento.ceia => Icons.wine_bar_outlined,
      TipoMomento.motivos => Icons.favorite_outline,
      TipoMomento.palavra => Icons.menu_book_outlined,
      TipoMomento.oracaoFinal => Icons.front_hand_outlined,
      TipoMomento.encerramento => Icons.qr_code_2,
    };

String _dd(int n) => n.toString().padLeft(2, '0');
String _hm(DateTime d) => '${_dd(d.hour)}:${_dd(d.minute)}';
String _mmss(Duration d) => '${_dd(d.inMinutes)}:${_dd(d.inSeconds % 60)}';

class _ModoCultoPageState extends State<ModoCultoPage> {
  ModoCultoController? _controller;
  late final Timer _relogio;

  ModoCultoController get _c => _controller!;
  AppScope get _scope => _c.scope;

  @override
  void initState() {
    super.initState();
    // Relógio, tempo de cada momento e cronômetro da Palavra.
    _relogio = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= ModoCultoController(AppScope.of(context), recadosSelecionados: widget.recadosSelecionados);
  }

  @override
  void dispose() {
    _relogio.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<bool> _acao(Future<void> Function() acao, {String? sucesso}) => executar(context, acao, sucesso: sucesso);

  void _avisar(String texto) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto), duration: const Duration(seconds: 3)));

  Future<void> _avancar() async {
    var fim = false;
    await _acao(() async => fim = !await _c.avancar());
    if (fim && mounted) _avisar('Fim do roteiro. Segure Sair para encerrar o Modo Culto.');
  }

  Future<void> _sair() async {
    final escolha = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair do Modo Culto?'),
        content: const Text('Voltar depois guarda o ponto do roteiro. Encerrar esquece o progresso deste culto.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          OutlinedButton(onPressed: () => Navigator.pop(ctx, 'pausar'), child: const Text('Voltar depois')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'encerrar'), child: const Text('Encerrar o culto')),
        ],
      ),
    );
    if (escolha == null || !mounted) return;
    if (!await confirmarPin(context, _scope.settings.pin)) return;
    if (escolha == 'encerrar') await _c.encerrar();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _alternarTela({required bool preta}) => _acao(() async {
        final status = _scope.status;
        final client = _scope.client;
        if (preta) {
          await client.telaPreta(!status.telaPreta);
          status.telaPreta = !status.telaPreta;
        } else {
          await client.telaVazia(!status.telaVazia);
          status.telaVazia = !status.telaVazia;
        }
        await status.atualizar();
      });

  Future<void> _palco(String frase) =>
      _acao(() => _scope.client.mensagemPalco(frase), sucesso: 'Enviado ao palco: "$frase"');

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _avisar('Segure o botão Sair para sair do Modo Culto.');
      },
      child: Scaffold(
        body: SafeArea(
          child: ListenableBuilder(
            listenable: Listenable.merge([_c, scope.status, scope.motivos, scope.visitas]),
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _topo(context),
                Expanded(child: _c.iniciado && _c.posicao != null ? _durante(context) : _antes(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------- Topo ----------

  Widget _topo(BuildContext context) {
    final tema = Theme.of(context);
    final esquema = tema.colorScheme;
    final culto = _c.culto;
    final agora = DateTime.now();
    final pregador = (culto?.pastoral['Pregação'] ?? const <String>[]).join(', ');
    final subtitulo = [
      if (culto != null) '${culto.rotulo} · ${culto.horaTexto}',
      if (pregador.isNotEmpty) 'Ministração: $pregador',
    ].join(' · ');

    String relogio = '';
    final inicio = _c.inicioDoCulto;
    if (inicio != null) {
      relogio = '${agora.difference(inicio).inMinutes} min de culto';
    } else if (RegExp(r'^\d{2}:\d{2}$').hasMatch(culto?.hora ?? '')) {
      final p = culto!.hora.split(':');
      final hora = DateTime(agora.year, agora.month, agora.day, int.parse(p[0]), int.parse(p[1]));
      final falta = hora.difference(agora);
      relogio = falta.isNegative ? 'hora do culto' : 'começa em ${falta.inMinutes + 1} min';
    }

    return Material(
      color: esquema.surfaceContainerLow,
      child: SizedBox(
        height: 76,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Image.asset('assets/logo/simbolo_claro.png', width: 52, semanticLabel: 'Igreja Diakonia Tulipas'),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      culto == null ? 'Culto de hoje' : '${culto.nome}${culto.ceia ? ' · Santa Ceia' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tema.textTheme.titleLarge,
                    ),
                    if (subtitulo.isNotEmpty)
                      Text(subtitulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: esquema.outline)),
                  ],
                ),
              ),
              if (_c.iniciado) ...[
                Chip(
                  avatar: const Icon(Icons.circle, size: 12, color: Colors.redAccent),
                  label: const Text('MODO CULTO', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: .5)),
                  backgroundColor: esquema.errorContainer,
                ),
                const SizedBox(width: 12),
              ],
              const StatusHolyricsChip(),
              const SizedBox(width: 18),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_hm(agora),
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w500)),
                  if (relogio.isNotEmpty) Text(relogio, style: TextStyle(fontSize: 12, color: esquema.outline)),
                ],
              ),
              const SizedBox(width: 16),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () => _avisar('Segure o botão Sair para sair do Modo Culto.'),
                  onLongPress: _sair,
                  icon: const Icon(Icons.logout),
                  label: const Text('Sair'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- Antes do culto ----------

  Widget _antes(BuildContext context) {
    final scope = _scope;
    final tema = Theme.of(context);
    final culto = _c.culto;
    final rotulo = tema.textTheme.labelLarge?.copyWith(color: tema.colorScheme.outline);
    final recados = _c.recados;
    final aguardando = scope.motivos.aguardando.length;
    final aprovados = scope.motivos.projetaveis.length;
    final visitantes = scope.visitas.pendentes;
    final conectado = scope.status.conexao == Conexao.conectado;
    final temContagem = _c.roteiro.any((m) => m.tipo == TipoMomento.contagem);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 18, 12, 24),
            children: [
              Text('PRONTO PARA COMEÇAR?', style: rotulo),
              const SizedBox(height: 10),
              _Conferencia(
                icone: Icons.link,
                ok: conectado,
                titulo: conectado ? 'Holyrics conectado' : 'Holyrics desconectado',
                detalhe: conectado ? 'Telão e TV do palco respondendo' : (scope.status.erro ?? 'Confira o PC da igreja.'),
              ),
              if (culto == null)
                const _Conferencia(
                  icone: Icons.event_busy_outlined,
                  ok: false,
                  titulo: 'Sem culto na escala de hoje',
                  detalhe: 'O roteiro sai sem contagem e sem louvor.',
                ),
              _Conferencia(
                icone: Icons.campaign_outlined,
                ok: recados.isNotEmpty,
                titulo: recados.isEmpty ? 'Nenhum recado para hoje' : '${recados.length} recado(s) para hoje',
                detalhe: recados.isEmpty
                    ? 'Selecione recados na tela de organizar.'
                    : recados.map((r) => r.titulo).join(', '),
              ),
              if (culto != null)
                _Conferencia(
                  icone: Icons.music_note_outlined,
                  ok: culto.musicas.isNotEmpty,
                  titulo: culto.musicas.isEmpty ? 'Músicas ainda não escolhidas' : 'Louvor com ${culto.musicas.length} música(s)',
                  detalhe: culto.musicas.isEmpty
                      ? 'O ministro escolhe as músicas pelo painel.'
                      : culto.musicas.map((m) => m.tom.isEmpty ? m.titulo : '${m.titulo} (${m.tom})').join(', '),
                ),
              _Conferencia(
                icone: Icons.volunteer_activism_outlined,
                ok: aguardando == 0,
                titulo: aguardando == 0 ? '$aprovados motivo(s) aprovado(s)' : '$aguardando pedido(s) aguardando aprovação',
                detalhe: aguardando == 0 ? 'Vão ao telão no momento de oração.' : '$aprovados motivo(s) já aprovado(s) vão ao telão.',
                acao: aguardando == 0
                    ? null
                    : FilledButton.tonal(onPressed: () => _revisarPedidos(context), child: const Text('Revisar')),
              ),
              _Conferencia(
                icone: Icons.waving_hand_outlined,
                ok: true,
                titulo: visitantes.isEmpty ? 'Nenhum visitante para citar ainda' : '${visitantes.length} visitante(s) para citar',
                detalhe: [
                  if (visitantes.isNotEmpty) visitantes.map((v) => v.nome).join(', '),
                  'A lista atualiza sozinha',
                ].join(' · '),
              ),
              if (culto?.ceia ?? false)
                const _Conferencia(
                  icone: Icons.wine_bar_outlined,
                  ok: true,
                  titulo: 'Santa Ceia hoje',
                  detalhe: 'O momento da Ceia entra no roteiro.',
                ),
            ],
          ),
        ),
        SizedBox(
          width: 420,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 18, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Cartao(children: [
                  Text('CONTAGEM NO TELÃO', style: rotulo),
                  Text(
                    temContagem ? culto!.hora : '--:--',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    temContagem ? '“O culto começa em” até a hora da escala' : 'Sem hora do culto na escala de hoje',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: tema.colorScheme.outline),
                  ),
                  SizedBox(
                    height: 76,
                    child: FilledButton.icon(
                      onPressed: temContagem ? () => _acao(_c.iniciarContagem, sucesso: 'Contagem no telão') : null,
                      icon: const Icon(Icons.timer_outlined, size: 32),
                      label: const Text('Iniciar contagem', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                _Cartao(children: [
                  Text('ROTEIRO DE HOJE · ${_c.roteiro.length} MOMENTOS', style: rotulo),
                  Text(_c.roteiro.map((m) => m.tipo.titulo).join(' · '), style: TextStyle(color: tema.colorScheme.outline)),
                  SizedBox(
                    height: 60,
                    child: FilledButton.tonalIcon(
                      onPressed: _c.roteiro.isEmpty ? null : () => _acao(_c.comecarCulto),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Começar o culto agora', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _revisarPedidos(BuildContext context) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Pedidos aguardando'),
          content: SizedBox(
            width: 560,
            child: ListenableBuilder(
              listenable: _scope.motivos,
              builder: (ctx, _) => _ChegouAgora(scope: _scope, soPedidos: true, acao: _acao),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar'))],
        ),
      );

  // ---------- Durante o culto ----------

  Widget _durante(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 290, child: _trilha(context)),
          Expanded(child: _centro(context)),
          SizedBox(width: 330, child: _comando(context)),
        ],
      );

  Widget _trilha(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final roteiro = _c.roteiro;
    final atual = roteiro.indexWhere((m) => m.tipo == _c.posicao!.tipo);
    return Material(
      color: esquema.surfaceContainerLow,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: roteiro.length,
        itemBuilder: (context, i) {
          final m = roteiro[i];
          final feito = i < atual, agora = i == atual;
          final inicio = _c.inicioDe(m.tipo);
          return Opacity(
            opacity: feito ? .5 : 1,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Material(
                color: agora ? esquema.primaryContainer.withAlpha(115) : Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: agora ? BorderSide(color: esquema.primary, width: 2) : BorderSide.none,
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _acao(() => _c.irPara(PosicaoRoteiro(m.tipo, 0))),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 46,
                          child: Text(inicio == null ? '' : _hm(inicio),
                              style: TextStyle(fontSize: 13, color: esquema.outline)),
                        ),
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: agora ? esquema.primary : esquema.surfaceContainerHighest,
                          foregroundColor: agora ? esquema.onPrimary : (feito ? Colors.greenAccent : esquema.outline),
                          child: Icon(feito ? Icons.check : iconeDoMomento(m.tipo), size: 16),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.tipo.titulo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                              if (m.detalhe.isNotEmpty)
                                Text(m.detalhe,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12, color: esquema.outline)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _centro(BuildContext context) {
    final tema = Theme.of(context);
    final esquema = tema.colorScheme;
    final momento = _c.momentoAtual!;
    final inicio = _c.inicioDe(momento.tipo);
    final previsto = _c.previsto(momento.tipo);
    final decorrido = inicio == null ? Duration.zero : DateTime.now().difference(inicio);
    final passou = previsto > 0 && decorrido.inMinutes >= previsto;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: esquema.primaryContainer, borderRadius: BorderRadius.circular(16)),
                child: Icon(iconeDoMomento(momento.tipo), size: 30, color: esquema.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(momento.tipo.titulo, style: tema.textTheme.headlineSmall),
                    if (momento.detalhe.isNotEmpty)
                      Text(momento.detalhe, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: esquema.outline)),
                  ],
                ),
              ),
              if (previsto > 0)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text.rich(TextSpan(children: [
                      TextSpan(
                          text: _mmss(decorrido),
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500)),
                      TextSpan(text: '  / $previsto min', style: TextStyle(color: esquema.outline)),
                    ])),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: 160,
                      child: LinearProgressIndicator(
                        value: math.min(1, decorrido.inSeconds / (previsto * 60)),
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                        color: passou ? Colors.amber : Colors.greenAccent.shade400,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: switch (momento.tipo) {
              TipoMomento.louvor => _louvor(context, momento),
              TipoMomento.palavra => _palavra(context),
              _ => _slides(context, momento),
            },
          ),
        ],
      ),
    );
  }

  Widget _slides(BuildContext context, Momento momento) {
    final esquema = Theme.of(context).colorScheme;
    final p = _c.posicao!;
    final prox = _c.proxima;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const _Rotulo('No telão', cor: Colors.redAccent),
                SlideDoPasso(passo: momento.passos[p.passo], momento: momento),
              ]),
            ),
            const SizedBox(width: 14),
            SizedBox(
              width: 250,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _Rotulo(prox != null && prox.tipo != p.tipo ? 'A seguir · ${prox.tipo.titulo}' : 'A seguir'),
                if (prox == null)
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Center(child: Text('Fim do roteiro', style: TextStyle(color: esquema.outline))),
                  )
                else
                  SlideDoPasso(passo: _c.passoDe(prox), momento: _c.momentoDe(prox)),
              ]),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (momento.passos.length > 1)
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.3,
              ),
              itemCount: momento.passos.length,
              itemBuilder: (context, i) => Opacity(
                opacity: i < p.passo ? .5 : 1,
                child: Material(
                  color: esquema.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: i == p.passo ? const BorderSide(color: Colors.redAccent, width: 2) : BorderSide.none,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _acao(() => _c.irPara(PosicaoRoteiro(momento.tipo, i))),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SlideDoPasso(passo: momento.passos[i], momento: momento),
                          const SizedBox(height: 4),
                          Text('${i + 1} · ${momento.passos[i].rotulo}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: esquema.outline)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          )
        else if (momento.linhas.isNotEmpty)
          Wrap(spacing: 8, runSpacing: 8, children: [for (final l in momento.linhas) Chip(label: Text(l))]),
      ],
    );
  }

  Widget _louvor(BuildContext context, Momento momento) {
    final esquema = Theme.of(context).colorScheme;
    final culto = _c.culto;
    final musicas = culto?.musicas ?? const <Musica>[];
    final escalados = [
      for (final e in (culto?.louvor ?? const <String, List<String>>{}).entries)
        if (e.value.isNotEmpty) (funcao: e.key, nomes: e.value.join(', ')),
    ];
    final rotulo = Theme.of(context).textTheme.labelLarge?.copyWith(color: esquema.outline);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Cartao(children: [
                  Text('MÚSICAS', style: rotulo),
                  if (musicas.isEmpty) Text('Ainda não escolhidas.', style: TextStyle(color: esquema.outline)),
                  for (var i = 0; i < musicas.length; i++)
                    Row(children: [
                      SizedBox(width: 28, child: Text('${i + 1}', style: TextStyle(color: esquema.outline))),
                      Expanded(child: Text(musicas[i].titulo, style: const TextStyle(fontSize: 18))),
                      if (musicas[i].tom.isNotEmpty)
                        Chip(label: Text(musicas[i].tom), visualDensity: VisualDensity.compact),
                    ]),
                ]),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _Cartao(children: [
                  Text('LOUVOR', style: rotulo),
                  for (final e in escalados)
                    Text.rich(TextSpan(children: [
                      TextSpan(text: '${e.funcao}: ', style: TextStyle(color: esquema.outline)),
                      TextSpan(text: e.nomes),
                    ])),
                ]),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text('No telão: tela vazia. A letra fica com o operador do Holyrics.', style: TextStyle(color: esquema.outline)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final frase in const ['Encerrar o louvor', 'Mais uma música', 'Pastor, pode se dirigir ao palco'])
            ActionChip(avatar: const Icon(Icons.send_outlined, size: 18), label: Text(frase), onPressed: () => _palco(frase)),
        ]),
      ],
    );
  }

  Widget _palavra(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final settings = _scope.settings;
    final inicio = _c.inicioDe(TipoMomento.palavra) ?? DateTime.now();
    final previsto = Duration(minutes: settings.minutosPregacao);
    final resta = previsto - DateTime.now().difference(inicio);
    final rotulo = Theme.of(context).textTheme.labelLarge?.copyWith(color: esquema.outline);
    return _Cartao(children: [
      const SizedBox(height: 8),
      FittedBox(
        child: Text(
          '${resta.isNegative ? '+' : ''}${_mmss(resta.abs())}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 120,
            fontWeight: FontWeight.w500,
            color: resta.isNegative ? Colors.redAccent : null,
          ),
        ),
      ),
      Text(
        resta.isNegative
            ? 'passou do tempo previsto'
            : 'restam da pregação · termina por volta das ${_hm(inicio.add(previsto))}',
        textAlign: TextAlign.center,
        style: TextStyle(color: esquema.outline, fontSize: 16),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton.outlined(
            tooltip: 'Menos 5 minutos',
            onPressed: previsto.inMinutes > 5 ? () => settings.atualizarMinutosPregacao(previsto.inMinutes - 5) : null,
            icon: const Icon(Icons.remove),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Previsto: ${previsto.inMinutes} min'),
          ),
          IconButton.outlined(
            tooltip: 'Mais 5 minutos',
            onPressed: () => settings.atualizarMinutosPregacao(previsto.inMinutes + 5),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text('AVISAR O PALCO', textAlign: TextAlign.center, style: rotulo),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final frase in const ['Faltam 10 minutos', 'Faltam 5 minutos', 'Favor encerrar a ministração'])
            ActionChip(avatar: const Icon(Icons.send_outlined, size: 18), label: Text(frase), onPressed: () => _palco(frase)),
          ActionChip(
            avatar: const Icon(Icons.timer_outlined, size: 18),
            label: const Text('Contagem de 5 min no palco'),
            onPressed: () => _acao(() => _scope.client.contagemPalco(5), sucesso: 'Contagem no palco iniciada'),
          ),
        ],
      ),
    ]);
  }

  Widget _comando(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final status = _scope.status;
    final atual = _c.posicao!;
    final prox = _c.proxima;
    final horaDoCulto = atual.tipo == TipoMomento.contagem && _c.horaDoCulto;
    final rotuloProx = prox == null
        ? 'Fim do roteiro'
        : prox.tipo != atual.tipo
            ? '${prox.tipo.titulo} · ${_c.passoDe(prox).rotulo}'
            : _c.passoDe(prox).rotulo;
    final rotulo = Theme.of(context).textTheme.labelLarge?.copyWith(color: esquema.outline);

    return Material(
      color: esquema.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 150,
              child: FilledButton(
                onPressed: prox == null ? null : _avancar,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                  backgroundColor: horaDoCulto ? Colors.amber : null,
                  foregroundColor: horaDoCulto ? Colors.black : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.skip_next, size: 56),
                    Text(horaDoCulto ? 'Hora do culto · Avançar' : 'Avançar',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    Text(rotuloProx, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _BotaoQuadrado(icone: Icons.skip_previous, label: 'Voltar', onPressed: () => _acao(_c.voltar))),
                const SizedBox(width: 10),
                Expanded(
                  child: _BotaoQuadrado(
                    icone: Icons.crop_square,
                    label: 'Vazia',
                    ativo: status.telaVazia,
                    onPressed: () => _alternarTela(preta: false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _BotaoQuadrado(
                    icone: Icons.square,
                    label: 'Preta',
                    ativo: status.telaPreta,
                    onPressed: () => _alternarTela(preta: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () => _acao(() async {
                  await _scope.client.encerrar();
                  await status.atualizar();
                }, sucesso: 'Projeção encerrada'),
                icon: const Icon(Icons.stop, color: Colors.redAccent),
                label: const Text('Parar projeção'),
              ),
            ),
            const SizedBox(height: 16),
            Text('CHEGOU AGORA', style: rotulo),
            const SizedBox(height: 8),
            Expanded(child: _ChegouAgora(scope: _scope, acao: _acao)),
          ],
        ),
      ),
    );
  }
}

/// Prévia de um passo como ele aparece no telão (sem as marcações do Holyrics).
class SlideDoPasso extends StatelessWidget {
  const SlideDoPasso({super.key, required this.passo, required this.momento});

  final Passo passo;
  final Momento momento;

  @override
  Widget build(BuildContext context) {
    const branco = TextStyle(color: Colors.white, fontSize: 20, height: 1.3);
    const titulo = TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, height: 1.15);
    Widget icone(IconData i, String texto) => Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 56, color: Colors.white70),
          const SizedBox(height: 8),
          Text(texto, textAlign: TextAlign.center, style: branco.copyWith(color: Colors.white70)),
        ]);

    final Widget conteudo = switch (passo.acao) {
      AcaoPasso.texto => () {
          final linhas = textoSemMarcacao(passo.valor).split('\n');
          return Column(mainAxisSize: MainAxisSize.min, children: [
            Text(linhas.first, textAlign: TextAlign.center, style: titulo),
            if (linhas.length > 1) ...[
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Text(linhas.skip(1).join('\n'), textAlign: TextAlign.center, style: branco),
              ),
            ],
          ]);
        }(),
      AcaoPasso.imagem => icone(Icons.image_outlined, passo.valor),
      AcaoPasso.contagem => Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('O culto começa em', style: branco),
          Text(passo.valor, style: titulo.copyWith(fontSize: 56)),
        ]),
      AcaoPasso.boasVindas => Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Sejam bem-vindos!', style: titulo),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(momento.linhas.join(' · '), textAlign: TextAlign.center, style: branco),
          ),
        ]),
      AcaoPasso.telaVazia => icone(Icons.crop_square, 'Tela vazia'),
      AcaoPasso.telaPreta => Text('Tela preta', style: branco.copyWith(color: Colors.white24)),
      AcaoPasso.qrOracao || AcaoPasso.qrMensagens => icone(Icons.qr_code_2, passo.rotulo),
    };

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          gradient: passo.acao == AcaoPasso.telaPreta
              ? null
              : const RadialGradient(colors: [Color(0xFF1D2340), Colors.black], radius: .9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        padding: const EdgeInsets.all(14),
        alignment: Alignment.center,
        child: FittedBox(fit: BoxFit.scaleDown, child: conteudo),
      ),
    );
  }
}

/// Pedidos e visitantes que chegaram e ainda pedem ação, sem sair do Modo Culto.
class _ChegouAgora extends StatelessWidget {
  const _ChegouAgora({required this.scope, required this.acao, this.soPedidos = false});

  final AppScope scope;
  final Future<bool> Function(Future<void> Function() acao, {String? sucesso}) acao;
  final bool soPedidos;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final pedidos = scope.motivos.aguardando;
    final visitantes = soPedidos ? const <Visita>[] : scope.visitas.pendentes;
    final podeAprovar = scope.motivos.online && scope.conta.pode('motivosEditar');
    if (pedidos.isEmpty && visitantes.isEmpty) {
      return Text(soPedidos ? 'Nenhum pedido aguardando.' : 'Nada novo por enquanto.', style: TextStyle(color: esquema.outline));
    }

    Widget item({required IconData icone, required Color cor, required String titulo, required String sub, required Widget botao}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: esquema.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: cor.withAlpha(46), borderRadius: BorderRadius.circular(10)),
                    child: Icon(icone, color: cor, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titulo, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
                        Text(sub, style: TextStyle(fontSize: 12, color: esquema.outline)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  botao,
                ],
              ),
            ),
          ),
        );

    return ListView(
      shrinkWrap: soPedidos,
      children: [
        for (final m in pedidos)
          item(
            icone: m.publico ? Icons.volunteer_activism_outlined : Icons.lock_outline,
            cor: Colors.amber,
            titulo: m.linha,
            sub: m.publico ? 'Pedido de oração' : 'Pedido particular (não vai ao telão)',
            botao: OutlinedButton(
              onPressed: podeAprovar ? () => acao(() => scope.motivos.aprovar(m), sucesso: 'Pedido aprovado') : null,
              child: const Text('Aprovar'),
            ),
          ),
        for (final v in visitantes)
          item(
            icone: Icons.waving_hand_outlined,
            cor: Colors.lightBlueAccent,
            titulo: v.nome,
            sub: 'Visitante · pode ser citado',
            botao: OutlinedButton(
              onPressed: () => acao(() => scope.visitas.projetarBoasVindas(ids: [v.id]), sucesso: 'Boas-vindas a ${v.nome} no telão'),
              child: const Text('Citar'),
            ),
          ),
      ],
    );
  }
}

class _Conferencia extends StatelessWidget {
  const _Conferencia({required this.icone, required this.ok, required this.titulo, required this.detalhe, this.acao});

  final IconData icone;
  final bool ok;
  final String titulo;
  final String detalhe;
  final Widget? acao;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final cor = ok ? Colors.greenAccent : Colors.amber;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: esquema.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: cor.withAlpha(38), borderRadius: BorderRadius.circular(12)),
                child: Icon(icone, color: cor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                    Text(detalhe, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: esquema.outline)),
                  ],
                ),
              ),
              if (acao != null) ...[const SizedBox(width: 12), acao!],
            ],
          ),
        ),
      ),
    );
  }
}

class _Cartao extends StatelessWidget {
  const _Cartao({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        // Rola quando o conteúdo (músicas, escalados) não cabe na altura.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 12), children[i]],
            ],
          ),
        ),
      );
}

class _Rotulo extends StatelessWidget {
  const _Rotulo(this.texto, {this.cor});

  final String texto;
  final Color? cor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          if (cor != null) ...[Icon(Icons.circle, size: 10, color: cor), const SizedBox(width: 8)],
          Flexible(
            child: Text(texto.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.outline)),
          ),
        ]),
      );
}

class _BotaoQuadrado extends StatelessWidget {
  const _BotaoQuadrado({required this.icone, required this.label, required this.onPressed, this.ativo = false});

  final IconData icone;
  final String label;
  final VoidCallback onPressed;
  final bool ativo;

  @override
  Widget build(BuildContext context) {
    final estilo = ButtonStyle(
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6, horizontal: 4)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
    );
    final conteudo = Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icone, size: 30),
      Text(label, style: const TextStyle(fontSize: 13)),
    ]);
    return SizedBox(
      height: 74,
      child: ativo
          ? FilledButton(onPressed: onPressed, style: estilo, child: conteudo)
          : OutlinedButton(onPressed: onPressed, style: estilo, child: conteudo),
    );
  }
}
