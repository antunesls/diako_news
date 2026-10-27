import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../holyrics/agente_local.dart';
import '../sync/server_api.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _servidor;
  final _usuario = TextEditingController();
  final _senha = TextEditingController();
  late final TextEditingController _tema;
  late final TextEditingController _pin;
  late final TextEditingController _ipLocal;
  final _nomeTablet = TextEditingController(text: 'Tablet do telão');
  bool _pareando = false;
  String? _resultadoLocal;
  late int _segundos;
  late bool _repetir;
  late bool _negrito;
  late int _motivosPorSlide;
  bool _iniciado = false;
  bool _entrando = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciado) return;
    _iniciado = true;
    final s = AppScope.of(context).settings;
    _servidor = TextEditingController(text: s.servidor);
    _tema = TextEditingController(text: s.tema);
    _pin = TextEditingController(text: s.pin);
    _ipLocal = TextEditingController(text: s.agenteLocal);
    _segundos = s.segundosPorSlide;
    _repetir = s.repetirSequencia;
    _negrito = s.negritoTitulo;
    _motivosPorSlide = s.motivosPorSlide;
  }

  @override
  void dispose() {
    for (final c in [_servidor, _usuario, _senha, _tema, _pin, _ipLocal, _nomeTablet]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _salvar() => AppScope.of(context).settings.atualizar(
        tema: _tema.text,
        segundosPorSlide: _segundos,
        repetirSequencia: _repetir,
        negritoTitulo: _negrito,
        motivosPorSlide: _motivosPorSlide,
        pin: _pin.text,
      );

  Future<void> _entrar() async {
    final scope = AppScope.of(context);
    final base = normalizarServidor(_servidor.text);
    if (base.isEmpty) return;
    setState(() => _entrando = true);
    final ok = await executar(context, () async {
      final sessao = await scope.api.login(base, _senha.text, usuario: _usuario.text);
      await scope.settings.atualizar(servidor: base, sessao: sessao);
      _servidor.text = base;
      _senha.clear();
      scope.tempoReal.reiniciar();
      await scope.sincronizarTudo();
    }, sucesso: 'Conectado ao servidor da igreja');
    if (!mounted) return;
    setState(() => _entrando = false);
    if (ok) FocusScope.of(context).unfocus();
  }

  Future<void> _sair() async {
    final scope = AppScope.of(context);
    await _desfazerPareamento(); // o pareamento é da conta que está saindo
    await scope.settings.atualizar(sessao: '');
    await scope.conta.limpar();
    scope.tempoReal.reiniciar();
    await scope.sincronizarTudo();
    if (mounted) setState(() {});
  }

  /// Pede ao servidor (com a sessão atual, precisa de internet) um token para este tablet;
  /// o servidor o repassa ao agente, que passa a aceitar o tablet mesmo sem internet.
  Future<void> _parear() async {
    final scope = AppScope.of(context);
    final base = normalizarAgenteLocal(_ipLocal.text);
    if (base.isEmpty) return;
    setState(() {
      _pareando = true;
      _resultadoLocal = null;
    });
    await executar(context, () async {
      final r = await scope.api.parearAgenteLocal(_nomeTablet.text.trim());
      await scope.settings.atualizar(
          agenteLocal: base, agenteLocalToken: r['token'] as String, agenteLocalId: r['id'] as String);
      _ipLocal.text = base;
      scope.agenteLocal.reiniciar();
      _resultadoLocal = await _testarLocal(esperarPareamento: true);
    }, sucesso: 'Tablet pareado com o PC da igreja');
    if (mounted) setState(() => _pareando = false);
  }

  /// Texto com o resultado do teste. [esperarPareamento]: o agente recebe a lista pelo servidor
  /// logo depois do pareamento, então o primeiro "não reconhece" pode ser só questão de segundos.
  Future<String> _testarLocal({bool esperarPareamento = false}) async {
    final local = AppScope.of(context).agenteLocal;
    ServidorException? erro;
    for (var i = 0; i < (esperarPareamento ? 6 : 1); i++) {
      try {
        final ms = await local.testar();
        return 'O PC da igreja respondeu em $ms ms pela rede local.';
      } on ServidorException catch (e) {
        erro = e;
        if (!e.naoAutorizado) break;
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    return '${erro!.message} Enquanto isso, o tablet usa a internet.';
  }

  Future<void> _testar() async {
    setState(() => _resultadoLocal = 'Testando...');
    final texto = await _testarLocal();
    if (mounted) setState(() => _resultadoLocal = texto);
  }

  /// Avisa o servidor (se houver internet) e esquece o pareamento neste tablet.
  Future<void> _desfazerPareamento() async {
    final scope = AppScope.of(context);
    final id = scope.settings.agenteLocalId;
    if (id.isNotEmpty) {
      try {
        await scope.api.desparearAgenteLocal(id);
      } on ErroAmigavel {
        // Sem internet: o administrador pode remover depois em Administração › Usuários.
      }
    }
    await scope.settings.atualizar(agenteLocal: '', agenteLocalToken: '', agenteLocalId: '');
    scope.agenteLocal.reiniciar();
    if (mounted) setState(() => _resultadoLocal = null);
  }

  Widget _secaoAgenteLocal(BuildContext context) {
    final scope = AppScope.of(context);
    final esquema = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([scope.settings, scope.agenteLocal]),
      builder: (context, _) {
        final s = scope.settings;
        final local = scope.agenteLocal;
        final resultado = _resultadoLocal == null
            ? const SizedBox.shrink()
            : Padding(padding: const EdgeInsets.only(top: 8), child: Text(_resultadoLocal!));
        if (s.agenteLocalPareado) {
          final ultimo = local.ultimoCaminho == null ? 'Nenhum comando enviado ainda.' : 'Último comando: ${local.ultimoCaminho}, ${local.ultimoMs} ms.';
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(local.recusado ? Icons.link_off : Icons.lan_outlined,
                  color: local.recusado ? esquema.error : Colors.greenAccent),
              title: Text(s.agenteLocal),
              subtitle: Text(local.recusado
                  ? 'O PC da igreja não aceita mais este tablet (pareamento removido). Desfaça e pareie de novo.'
                  : 'Pareado. $ultimo'),
              trailing: Wrap(spacing: 8, children: [
                OutlinedButton(onPressed: _testar, child: const Text('Testar')),
                OutlinedButton(onPressed: _desfazerPareamento, child: const Text('Desfazer')),
              ]),
            ),
            resultado,
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _ipLocal,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                    labelText: 'IP do PC da igreja', hintText: '192.168.0.20', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _nomeTablet,
                maxLength: 60,
                decoration: const InputDecoration(labelText: 'Nome deste tablet', border: OutlineInputBorder(), counterText: ''),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                onPressed: _pareando || !s.configurado ? null : _parear,
                icon: const Icon(Icons.lan_outlined),
                label: const Text('Parear'),
              ),
            ),
          ]),
          if (!s.configurado)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Entre no servidor primeiro: o pareamento usa o seu login e precisa de internet.',
                  style: TextStyle(color: esquema.outline)),
            ),
          resultado,
        ]);
      },
    );
  }

  Future<void> _buscarTemas() async {
    final api = AppScope.of(context).api;
    try {
      final dados = await api.temas();
      final temas = (dados['temas'] as List? ?? const []).whereType<Map>();
      if (!mounted) return;
      final escolhido = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Temas do Holyrics'),
          content: SizedBox(width: 460, height: 400, child: Column(children: [
            if (dados['desatualizado'] == true) const Text('Lista salva: Holyrics desconectado. Confirme antes de projetar.'),
            if (dados['miniaturasDisponiveis'] == false && temas.isNotEmpty)
              const Text('Sem miniaturas: libere GetThumbnail no token do Holyrics.'),
            Expanded(child: ListView(children: [
              ListTile(title: const Text('(Tema padrão)'), onTap: () => Navigator.pop(ctx, '')),
              for (final t in temas)
                ListTile(
                  leading: t['thumbnail'] is String ? Image.memory(base64Decode(t['thumbnail'] as String),
                      width: 88, height: 50, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.palette))
                      : const Icon(Icons.palette),
                  title: Text(t['name'] as String? ?? ''),
                  onTap: () => Navigator.pop(ctx, t['name'] as String? ?? ''),
                ),
            ])),
          ])),
        ),
      );
      if (escolhido != null) setState(() => _tema.text = escolhido);
    } on ErroAmigavel catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${e.message}\nSe o Holyrics for anterior à v2.27, digite o nome do tema manualmente.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final esquema = Theme.of(context).colorScheme;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _salvar();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Configurações')),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          children: [
            Text('Servidor da igreja', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Endereço do servidor DiakoNews (ex: diako.minhaigreja.com.br ou 192.168.0.10:8080) e o '
              'usuário e a senha criados em Administração › Usuários e perfis. Usuário em branco entra com a senha principal.',
              style: TextStyle(color: esquema.outline),
            ),
            const SizedBox(height: 16),
            ListenableBuilder(
              listenable: Listenable.merge([scope.settings, scope.tempoReal, scope.conta]),
              builder: (context, _) => scope.settings.configurado
                  ? ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(scope.tempoReal.conectado ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                          color: scope.tempoReal.conectado ? Colors.greenAccent : esquema.error),
                      title: Text(scope.settings.servidor),
                      subtitle: Text([
                        if (scope.conta.nome.isNotEmpty) '${scope.conta.nome} · ${scope.conta.perfil}',
                        scope.tempoReal.conectado ? 'Conectado, recebendo atualizações ao vivo' : 'Sem conexão no momento',
                      ].join('\n')),
                      trailing: OutlinedButton(onPressed: _sair, child: const Text('Sair')),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _servidor,
                            keyboardType: TextInputType.url,
                            decoration: const InputDecoration(
                                labelText: 'Endereço do servidor', hintText: '192.168.0.10:8080', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _usuario,
                            autocorrect: false,
                            enableSuggestions: false,
                            textCapitalization: TextCapitalization.none,
                            decoration: const InputDecoration(
                                labelText: 'Usuário', hintText: 'ex.: telao (vazio = conta principal)', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _senha,
                            obscureText: true,
                            onSubmitted: (_) => _entrar(),
                            decoration: const InputDecoration(labelText: 'Senha', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          height: 56,
                          child: FilledButton.icon(
                            onPressed: _entrando ? null : _entrar,
                            icon: const Icon(Icons.login),
                            label: const Text('Entrar'),
                          ),
                        ),
                      ],
                    ),
            ),
            const Divider(height: 48),
            Text('PC da igreja (rede local)', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Com o tablet no mesmo Wi-Fi do PC do Holyrics, os comandos vão direto para ele: mais rápido e '
              'funciona mesmo se a internet cair. Parear precisa de internet uma vez. Fora da igreja, o tablet usa a internet sozinho. '
              'O IP aparece no fim da instalação do agente.',
              style: TextStyle(color: esquema.outline),
            ),
            const SizedBox(height: 16),
            _secaoAgenteLocal(context),
            const Divider(height: 48),
            Text('Projeção', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tema,
                    decoration: const InputDecoration(
                      labelText: 'Tema do Holyrics (opcional)',
                      helperText: 'Fundo e fonte usados nos recados',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(onPressed: _buscarTemas, icon: const Icon(Icons.palette_outlined), label: const Text('Buscar temas')),
              ],
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tempo por slide na sequência'),
              subtitle: Slider(
                value: _segundos.toDouble(),
                min: 3,
                max: 60,
                divisions: 57,
                label: '$_segundos s',
                onChanged: (v) => setState(() => _segundos = v.round()),
              ),
              trailing: Text('$_segundos s', style: Theme.of(context).textTheme.titleMedium),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Motivos de oração por slide'),
              subtitle: Slider(
                value: _motivosPorSlide.toDouble(),
                min: 1,
                max: 8,
                divisions: 7,
                label: '$_motivosPorSlide',
                onChanged: (v) => setState(() => _motivosPorSlide = v.round()),
              ),
              trailing: Text('$_motivosPorSlide', style: Theme.of(context).textTheme.titleMedium),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Repetir a sequência (loop)'),
              value: _repetir,
              onChanged: (v) => setState(() => _repetir = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Título em negrito'),
              subtitle: const Text('Desligue se aparecer "<b>" no telão.'),
              value: _negrito,
              onChanged: (v) => setState(() => _negrito = v),
            ),
            const Divider(height: 48),
            Text('Segurança', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'PIN para abrir as configurações (vazio = sem PIN)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'O backup dos recados, motivos e aniversariantes é feito pelo servidor, todos os dias.',
              style: TextStyle(color: esquema.outline),
            ),
          ],
        ),
      ),
    );
  }
}
