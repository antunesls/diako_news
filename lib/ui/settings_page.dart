import 'package:flutter/material.dart';

import '../app_scope.dart';
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
    _segundos = s.segundosPorSlide;
    _repetir = s.repetirSequencia;
    _negrito = s.negritoTitulo;
    _motivosPorSlide = s.motivosPorSlide;
  }

  @override
  void dispose() {
    for (final c in [_servidor, _usuario, _senha, _tema, _pin]) {
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
    await scope.settings.atualizar(sessao: '');
    await scope.conta.limpar();
    scope.tempoReal.reiniciar();
    await scope.sincronizarTudo();
    if (mounted) setState(() {});
  }

  Future<void> _buscarTemas() async {
    final client = AppScope.of(context).client;
    try {
      final temas = await client.temas();
      if (!mounted) return;
      final escolhido = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Temas do Holyrics'),
          children: [
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, ''), child: const Text('(Tema padrão)')),
            for (final t in temas) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, t), child: Text(t)),
          ],
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
