import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:diako_core/diako_core.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'agenda.dart';
import 'agenda_google_api.dart';
import 'agente_hub.dart';
import 'auth.dart';
import 'backup.dart';
import 'cartazes.dart';
import 'config.dart';
import 'configuracoes.dart';
import 'historico.dart';
import 'holyrics.dart';
import 'email_mensagens.dart';
import 'fotos_membros.dart';
import 'galeria.dart';
import 'pagina_inicial.dart';
import 'permissoes.dart';
import 'usuarios.dart';
import 'qr_oracao.dart';
import 'store.dart';

/// Monta todas as rotas do servidor.
class Servidor {
  Servidor({
    required this.store,
    required this.auth,
    required this.holyrics,
    required this.cartazes,
    required this.backup,
    required this.pastaWeb,
    required String urlOracao,
    required this.cartazesNoHolyrics,
    required this.historico,
    this.versao = 'dev',
    this.agente,
    String chaveAgente = '',
    String chaveMural = '',
    this.confiarProxy = false,
    this.cfg,
    this.restauracao,
    this.agenda,
    this.clienteAgenda,
    this.enviarAvisoMensagem,
    this.senhaMinima = 6,
    DateTime Function()? relogio,
    LimiteTaxa? limitePedidos,
    Galeria? galeria,
    FotosMembros? fotosMembros,
  })  : galeria = galeria ?? Galeria(store.pasta),
        fotosMembros = fotosMembros ?? FotosMembros(store.pasta),
        _urlOracaoFixa = urlOracao,
        _chaveAgenteFixa = chaveAgente,
        _chaveMuralFixa = chaveMural,
        _agora = relogio ?? DateTime.now,
         _limitePedidos = limitePedidos ?? LimiteTaxa(maximo: 5, janela: const Duration(minutes: 10)) {
    // No modo agente, cada mudança nos cartazes é copiada para o PC da igreja.
    if (agente != null) {
      store.mudancas.where((t) => t == 'cartazes').listen((_) => agente!.pedirSincronizacao());
    }
  }

  final Historico historico;
  final String versao;
  final Store store;
  final Auth auth;
  final PonteHolyrics holyrics;

  /// Presente no modo agente (servidor na internet).
  final HolyricsViaAgente? agente;
  final bool confiarProxy;
  final Cartazes cartazes;

  /// Fotos do carrossel da página inicial (data/galeria).
  final Galeria galeria;

  /// Fotos do cadastro de membros (data/fotos-membros) — nunca públicas.
  final FotosMembros fotosMembros;
  final Backup backup;
  final String pastaWeb;

  /// Configurações editáveis pela página /admin. Sem elas, valem os valores fixos do construtor.
  final Configuracoes? cfg;
  final Restauracao? restauracao;

  /// Agenda do Google (endereço iCal); null desativa.
  final AgendaGoogle? agenda;

  /// Cliente HTTP do teste de endereço da agenda (substituível nos testes).
  final http.Client? clienteAgenda;
  final Future<void> Function(Mensagem mensagem, String urlPainel)? enviarAvisoMensagem;

  /// Tamanho mínimo da senha ao trocar pelo painel (10 quando o servidor está na internet).
  final int senhaMinima;

  final String _urlOracaoFixa;
  final String _chaveAgenteFixa;
  final String _chaveMuralFixa;

  String get urlOracao => cfg?.urlOracao ?? _urlOracaoFixa;
  String get chaveAgente => cfg?.chaveAgente ?? _chaveAgenteFixa;
  String get chaveMural => cfg?.chaveMural ?? _chaveMuralFixa;
  String get nomeIgreja => cfg?.nomeIgreja ?? Configuracoes.nomeIgrejaPadrao;

  /// false quando "pastaImagensHolyrics" não foi configurada (cartazes ficam em data/cartazes).
  final bool cartazesNoHolyrics;
  final DateTime Function() _agora;
  final LimiteTaxa _limitePedidos;
  final LimiteTaxa _limiteMensagens = LimiteTaxa(maximo: 5, janela: const Duration(minutes: 10));

  /// Caminho do QR para o ShowImage do Holyrics.
  static const qrHolyrics = '${Config.subpastaHolyrics}/$arquivoQr';

  Handler get handler {
    final r = Router()
      // Página inicial pública (desligada no /admin: vai direto ao painel, como antes).
      ..get('/', (Request _) => cfg?.siteAtivo == true ? _pagina('inicio.html') : Response.found('/painel'))
      ..get('/api/public/inicio', _inicio)
      ..get('/api/public/eventos/<arquivo>', _icsEvento)
      ..get('/pix.png', _pngPix)
      ..get('/oracao', (Request _) => _pagina('oracao.html'))
      ..get('/mensagens', (Request _) => _pagina('mensagens.html'))
      ..get(ajudaAgenda, (Request _) => _pagina('ajuda-agenda.html'))
      ..get('/ajuda/usuarios', (Request _) => _pagina('ajuda-usuarios.html'))
      // Perfis e permissões (só a descrição da matriz, para a página de ajuda).
      ..get('/api/public/perfis', (Request _) => _json({
            'perfis': [for (final p in Perfil.values) p.toJson()],
            'permissoes': [
              for (final p in Permissao.values)
                if (p != Permissao.sessao) {'id': p.name, 'descricao': p.descricao}
            ],
          }))
      ..get('/painel', (Request _) => _pagina('painel.html'))
      ..get('/mural', (Request req) => _chaveMuralOk(req) ? _pagina('mural.html') : _semChaveMural())
      ..get('/api/public/mural', (Request req) => _chaveMuralOk(req) ? _mural(req) : _semChaveMural())
      // Agente do PC da igreja (modo agente)
      ..get('/agente/ws', _agenteWs)
      ..get('/agente/cartazes', _agenteListarCartazes)
      ..get('/agente/cartazes/<nome>', _agenteBaixarCartaz)
      ..get('/qr-oracao.png', (Request _) => _arquivo(File(p.join(cartazes.pasta, arquivoQr))))
      ..get('/qr-mensagens.png', (Request _) => _arquivo(File(p.join(cartazes.pasta, arquivoQrMensagens))))
      ..get('/cartazes/<nome>', (Request _, String nome) => _arquivo(cartazes.arquivo(nome)))
      ..get('/galeria/<arquivo>', _fotoGaleria)
      ..post('/api/login', _login)
      ..post('/api/logout', _logout)
      ..get('/api/eu', _eu)
      ..post('/api/eu/senha', _minhaSenha)
      ..get('/api/admin/usuarios', _listarUsuarios)
      ..post('/api/admin/usuarios', _criarUsuario)
      ..put('/api/admin/usuarios/<id>', _atualizarUsuario)
      ..post('/api/admin/usuarios/<id>/senha', _redefinirSenhaUsuario)
      ..delete('/api/admin/usuarios/<id>', _excluirUsuario)
      ..post('/api/public/pedidos', _novoPedido)
      ..post('/api/public/mensagens', _novaMensagem)
      ..get('/api/estado', _estado)
      ..get('/api/mensagens', _listarMensagens)
      ..put('/api/mensagens/<id>', _atualizarMensagem)
      ..post('/api/mensagens/<id>/avisar', _reenviarAviso)
      // Recados
      ..get('/api/recados', _listarRecados)
      ..post('/api/recados', _criarRecado)
      ..put('/api/recados/ordem', _ordenarRecados)
      ..put('/api/recados/<id>', _atualizarRecado)
      ..delete('/api/recados/<id>', (Request _, String id) => _excluir('recados', id))
      // Motivos de oração
      ..get('/api/motivos', _listarMotivos)
      ..post('/api/motivos', _criarMotivo)
      ..put('/api/motivos/<id>', _atualizarMotivo)
      ..post('/api/motivos/<id>/aprovar', _aprovarMotivo)
      ..delete('/api/motivos/<id>', _excluirMotivo)
      // Membros / aniversariantes (exportar antes das rotas com <id>)
      ..get('/api/membros', (Request _) => _json([for (final m in _listaMembros()) m.toJson()]))
      ..get('/api/membros/exportar', _exportarMembros)
      ..post('/api/membros', _criarMembro)
      ..post('/api/membros/importar', _importarMembros)
      ..put('/api/membros/<id>', _atualizarMembro)
      ..delete('/api/membros/<id>', _excluirMembro)
      ..post('/api/membros/<id>/foto', _enviarFotoMembro)
      ..delete('/api/membros/<id>/foto', _removerFotoMembro)
      ..get('/api/membros/<id>/foto', (Request _, String id) => _fotoMembro(id, miniatura: false))
      ..get('/api/membros/<id>/foto-miniatura', (Request _, String id) => _fotoMembro(id, miniatura: true))
      // Cartazes
      ..get('/api/cartazes', _listarCartazes)
      ..post('/api/cartazes', _enviarCartaz)
      ..delete('/api/cartazes/<nome>', _excluirCartaz)
      // Galeria do site (carrossel da página inicial)
      ..get('/api/galeria', (Request _) => _json([for (final f in _fotos()) _fotoJson(f)]))
      ..post('/api/galeria', _enviarFoto)
      ..put('/api/galeria/ordem', _ordenarGaleria)
      ..put('/api/galeria/<id>', _atualizarFoto)
      ..delete('/api/galeria/<id>', _excluirFoto)
      // Holyrics e manutenção
      ..post('/api/holyrics/<acao>', _holyrics)
      ..post('/api/projetar/oracoes-respondidas', _projetarRespondidas)
      ..get('/api/historico', _historico)
      ..get('/api/resumo-semanal', _resumoSemanal)
      ..post('/api/backup', _backupAgora)
      ..get('/api/backups', _listarBackups)
      ..get('/api/backups/agora/download', _baixarBackupAgora)
      ..get('/api/backups/<nome>/download', _baixarBackup)
      ..delete('/api/backups/<nome>', _excluirBackup)
      ..post('/api/backups/restaurar', _restaurarDeArquivo)
      ..post('/api/backups/<nome>/restaurar', _restaurarDaLista)
      // Administração
      ..get('/admin', (Request _) => _pagina('admin.html'))
      ..get('/api/public/site', _site)
      ..get('/api/admin/configuracoes', _adminConfiguracoes)
      ..put('/api/admin/configuracoes', _adminSalvar)
      ..post('/api/admin/chave', _adminNovaChave)
      ..post('/api/admin/senha', _adminSenha)
      ..post('/api/admin/sessoes/encerrar', _adminEncerrarSessoes)
      ..post('/api/admin/testar-holyrics', _adminTestarHolyrics)
      ..post('/api/admin/testar-email', _adminTestarEmail)
      ..get('/api/agenda', _agenda)
      ..post('/api/agenda/eventos', _criarEvento)
      ..put('/api/agenda/eventos/<id>', _atualizarEvento)
      ..delete('/api/agenda/eventos/<id>', _excluirEvento)
      ..post('/api/admin/agenda/atualizar', _adminAgendaAtualizar)
      ..post('/api/admin/agenda/testar', _adminAgendaTestar)
      ..post('/api/admin/agenda/conta-servico', _adminContaServico)
      ..post('/api/admin/agenda/conta-servico/testar', _adminTestarContaServico)
      ..delete('/api/admin/agenda/conta-servico', _adminRemoverContaServico)
      ..get('/ws', webSocketHandler(_conectarWs));

    final estaticos = createStaticHandler(pastaWeb);
    final cascata = Cascade().add(r.call).add(estaticos).handler;
    return const Pipeline()
        .addMiddleware(_cabecalhosSeguranca)
        .addMiddleware(_tratarErros)
        .addMiddleware(auth.middleware(_rotaPublica))
        .addMiddleware(_verificarPermissao)
        .addHandler(cascata);
  }

  /// Confere a permissão do perfil para a rota (tabela em permissoes.dart; rota nova sem regra = só admin).
  static Middleware get _verificarPermissao => (inner) => (req) {
        final conta = Auth.contaDa(req);
        if (conta == null) return inner(req); // rota pública
        final precisa = permissaoDaRota(req.method, req.url.path);
        if (conta.pode(precisa)) return inner(req);
        return _erro(403, 'Seu perfil (${conta.perfil.nome}) não permite: ${precisa.descricao}.');
      };

  String _ip(Request req) => ipDe(req, confiarProxy: confiarProxy);

  bool _chaveMuralOk(Request req) =>
      chaveMural.isEmpty || iguaisSeguro(req.url.queryParameters['chave'] ?? '', chaveMural);

  static Response _semChaveMural() =>
      Response.forbidden('Mural protegido: use o link com a chave (aba Status do painel).',
          headers: {'content-type': 'text/plain; charset=utf-8'});

  static Middleware get _cabecalhosSeguranca => (inner) => (req) async {
        final r = await inner(req);
        return r.change(headers: {
          'x-content-type-options': 'nosniff',
          'referrer-policy': 'same-origin',
          'content-security-policy': "frame-ancestors 'none'",
        });
      };

  static bool _rotaPublica(Request req) {
    final caminho = req.url.path;
    if (caminho == 'ws') return false;
    if (!caminho.startsWith('api/')) return true;
    return caminho == 'api/login' || caminho.startsWith('api/public/');
  }

  // ---------- Autenticação ----------

  Future<Response> _login(Request req) async {
    final corpo = await _corpo(req);
    try {
      final usuario = corpo['usuario'] as String? ?? '';
      final token = await auth.login(corpo['senha'] as String? ?? '', _ip(req), usuario: usuario);
      if (token == null) return _erro(401, usuario.trim().isEmpty ? 'Senha incorreta.' : 'Usuário ou senha incorretos.');
      return _json({'token': token});
    } on LimiteExcedido {
      return _erro(429, 'Muitas tentativas. Aguarde um minuto.');
    }
  }

  Future<Response> _logout(Request req) async {
    final t = Auth.tokenDe(req);
    if (t != null) await auth.logout(t);
    return _json({'ok': true});
  }

  // ---------- Usuários e perfis ----------

  /// GET /api/eu — quem está logado e o que pode fazer (o painel e o app escondem o resto).
  Response _eu(Request req) {
    final c = Auth.contaDa(req)!;
    return _json({
      'id': c.id,
      'nome': c.nome,
      'login': c.login,
      'principal': c.ehPrincipal,
      'perfil': c.perfil.name,
      'perfilNome': c.perfil.nome,
      'permissoes': [for (final p in c.perfil.permissoes) p.name],
      'site': {'ativo': cfg?.siteAtivo ?? false, 'galeria': cfg?.siteGaleria ?? false},
    });
  }

  /// Corpo: {"atual": "...", "nova": "..."} — cada pessoa troca a própria senha.
  /// A conta principal usa a mesma senha do /admin › Senha e aparelhos.
  Future<Response> _minhaSenha(Request req) async {
    final c = Auth.contaDa(req)!;
    final corpo = await _corpo(req);
    final atual = corpo['atual'] as String? ?? '', nova = (corpo['nova'] as String? ?? '').trim();
    if (c.ehPrincipal) {
      if (!auth.conferir(atual)) return _erro(403, 'Senha atual incorreta.');
      final config = cfg;
      if (config == null) return _erro(501, 'Configurações indisponíveis.');
      try {
        await config.trocarSenha(nova, minimo: senhaMinima);
      } on FormatException catch (e) {
        return _erro(400, e.message);
      }
    } else {
      final usuarios = auth.usuarios!;
      if (!usuarios.conferirSenha(c.id, atual)) return _erro(403, 'Senha atual incorreta.');
      if (nova.length < senhaMinima) return _erro(400, 'A senha precisa ter pelo menos $senhaMinima caracteres.');
      await usuarios.definirSenha(c.id, nova);
    }
    final saiu = await auth.encerrarDoUsuario(c.id, manter: Auth.tokenDe(req));
    return _json({'ok': true, 'sessoesEncerradas': saiu});
  }

  Usuarios? get _usuarios => auth.usuarios;

  Response _listarUsuarios(Request _) => _json({
        'usuarios': [for (final u in _usuarios?.lista ?? const <Usuario>[]) u.toJson()],
        'perfis': [for (final p in Perfil.values) p.toJson()],
        'permissoes': [
          for (final p in Permissao.values)
            if (p != Permissao.sessao) {'id': p.name, 'descricao': p.descricao}
        ],
      });

  /// Corpo: {"nome", "login", "perfil"} — devolve a senha temporária (mostrada uma única vez).
  Future<Response> _criarUsuario(Request req) async {
    final usuarios = _usuarios;
    if (usuarios == null) return _erro(501, 'Usuários indisponíveis.');
    final corpo = await _corpo(req);
    final perfil = Perfil.porNome(corpo['perfil'] as String? ?? '');
    if (perfil == null) return _erro(400, 'Escolha o perfil.');
    final senha = gerarSenhaTemporaria(senhaMinima < 10 ? 10 : senhaMinima);
    try {
      final u = await usuarios.criar(
          nome: corpo['nome'] as String? ?? '', login: corpo['login'] as String? ?? '', perfil: perfil, senha: senha);
      return _json({'usuario': u.toJson(), 'senhaTemporaria': senha}, status: 201);
    } on FormatException catch (e) {
      return _erro(400, e.message);
    }
  }

  /// Corpo: {"nome", "perfil", "ativo"} (só o que mudar). Trocar perfil ou desativar desconecta a pessoa.
  Future<Response> _atualizarUsuario(Request req, String id) async {
    final usuarios = _usuarios;
    final atual = usuarios?.buscar(id);
    if (usuarios == null || atual == null) return _erro(404, 'Usuário não encontrado.');
    final corpo = await _corpo(req);
    final perfil = corpo['perfil'] == null ? null : Perfil.porNome(corpo['perfil'] as String);
    if (corpo['perfil'] != null && perfil == null) return _erro(400, 'Perfil inválido.');
    if (corpo.containsKey('ativo') && corpo['ativo'] is! bool) return _erro(400, '"ativo" deve ser verdadeiro ou falso.');
    final perfilAntes = atual.perfil, ativoAntes = atual.ativo;
    try {
      final u = await usuarios.atualizar(id, nome: corpo['nome'] as String?, perfil: perfil, ativo: corpo['ativo'] as bool?);
      if (u.perfil != perfilAntes || u.ativo != ativoAntes) await auth.encerrarDoUsuario(id);
      return _json(u.toJson());
    } on FormatException catch (e) {
      return _erro(400, e.message);
    }
  }

  /// Gera uma senha temporária nova (mostrada uma única vez) e desconecta a pessoa.
  Future<Response> _redefinirSenhaUsuario(Request _, String id) async {
    final usuarios = _usuarios;
    if (usuarios?.buscar(id) == null) return _erro(404, 'Usuário não encontrado.');
    final senha = gerarSenhaTemporaria(senhaMinima < 10 ? 10 : senhaMinima);
    await usuarios!.definirSenha(id, senha);
    await auth.encerrarDoUsuario(id);
    return _json({'senhaTemporaria': senha});
  }

  Future<Response> _excluirUsuario(Request _, String id) async {
    if (!(await _usuarios?.excluir(id) ?? false)) return _erro(404, 'Usuário não encontrado.');
    await auth.encerrarDoUsuario(id);
    return _json({'ok': true});
  }

  // ---------- Estado ----------

  Future<Response> _estado(Request _) async {
    final ultimo = await backup.ultimo();
    return _json({
      'versao': versao,
      'versoes': store.versoes,
      'holyricsConectado': await holyrics.conectado(),
      'urlOracao': urlOracao,
      'qrHolyrics': qrHolyrics,
      'urlMensagens': cfg?.urlMensagens ?? urlOracao.replaceFirst(RegExp(r'/oracao$'), '/mensagens'),
      'qrMensagensHolyrics': '${Config.subpastaHolyrics}/$arquivoQrMensagens',
      'mensagensNovas': store.listar('mensagens').where((m) => m['status'] == 'nova').length,
      'cartazesNoHolyrics': agente != null ? agente!.agenteConectado : cartazesNoHolyrics,
      'modo': agente != null ? 'agente' : 'local',
      'agenteConectado': agente?.agenteConectado,
      'agenteVistoEm': agente?.vistoEm?.toIso8601String(),
      'agenteVersao': agente?.versaoAgente,
      'chaveMural': chaveMural.isEmpty ? null : chaveMural,
      'backupConfigurado': backup.configurado,
      'ultimoBackup': ultimo?.toIso8601String(),
      'aguardandoAprovacao':
          store.listar('motivos').where((m) => m['status'] == StatusMotivo.aguardando.name).length,
      'agenda': agenda?.estado(),
    });
  }

  // ---------- Recados ----------

  Response _listarRecados(Request _) => _json([for (final r in _recadosComAuto()) r.toJson()]);

  /// Recados cadastrados mais o automático de aniversariantes (quando houver).
  List<Recado> _recadosComAuto() {
    final auto = recadoAniversariantes(_membros(), _agora());
    return [if (auto != null) auto, ...store.listar('recados').map(Recado.fromJson)];
  }

  List<Membro> _membros() => store.listar('membros').map(Membro.fromJson).toList();
  List<Motivo> _motivos() => store.listar('motivos').map(Motivo.fromJson).toList();

  Future<Response> _criarRecado(Request req) async {
    final corpo = await _corpo(req);
    final existentes = store.listar('recados');
    final ordem = existentes.isEmpty
        ? 0
        : existentes.map((r) => (r['ordem'] as num?)?.toInt() ?? 0).reduce((a, b) => a > b ? a : b) + 1;
    final recado = Recado.fromJson({...corpo, 'id': novoId(), 'ordem': ordem, 'auto': false});
    final erro = _validarRecado(recado);
    if (erro != null) return _erro(400, erro);
    await store.salvar('recados', recado.toJson());
    return _json(recado.toJson(), status: 201);
  }

  Future<Response> _atualizarRecado(Request req, String id) async {
    if (id == idRecadoAniversariantes) {
      return _erro(400, 'O recado de aniversariantes é automático. Edite os membros.');
    }
    final atual = store.buscar('recados', id);
    if (atual == null) return _erro(404, 'Recado não encontrado.');
    final recado = Recado.fromJson({...atual, ...await _corpo(req), 'id': id, 'auto': false});
    final erro = _validarRecado(recado);
    if (erro != null) return _erro(400, erro);
    await store.salvar('recados', recado.toJson());
    return _json(recado.toJson());
  }

  /// Corpo: lista de ids na nova ordem.
  Future<Response> _ordenarRecados(Request req) async {
    final ids = jsonDecode(await req.readAsString());
    if (ids is! List) return _erro(400, 'Envie a lista de ids.');
    final docs = <Map<String, dynamic>>[];
    for (var i = 0; i < ids.length; i++) {
      final atual = store.buscar('recados', ids[i] as String);
      if (atual != null) docs.add({...atual, 'ordem': i});
    }
    await store.salvarVarios('recados', docs);
    return _json({'ok': true});
  }

  static String? _validarRecado(Recado r) {
    if (r.titulo.trim().isEmpty) return 'Informe o título.';
    if (r.titulo.length > 120) return 'Título muito longo.';
    if (r.texto.length > 1000) return 'Texto muito longo.';
    return null;
  }

  // ---------- Motivos ----------

  /// Pode ver/mexer neste pedido: públicos para todos com acesso; particulares só com a permissão.
  static bool _podeMotivo(Request req, Map<String, dynamic> m) =>
      m['publico'] != false || (Auth.contaDa(req)?.pode(Permissao.motivosParticulares) ?? false);

  static Response get _semAcessoParticular =>
      _erro(403, 'Pedido particular: só o pastor e o administrador têm acesso.');

  /// Sem a permissão de particulares: só os públicos e sem o nome de quem enviou.
  Response _listarMotivos(Request req) {
    final completo = Auth.contaDa(req)?.pode(Permissao.motivosParticulares) ?? false;
    return _json([
      for (final m in store.listar('motivos'))
        if (completo) m else if (m['publico'] != false) {...m, 'enviadoPor': ''},
    ]);
  }

  Future<Response> _excluirMotivo(Request req, String id) async {
    final atual = store.buscar('motivos', id);
    if (atual == null) return _erro(404, 'Não encontrado.');
    if (!_podeMotivo(req, atual)) return _semAcessoParticular;
    return _excluir('motivos', id);
  }

  Future<Response> _criarMotivo(Request req) async {
    final corpo = await _corpo(req);
    final origem = OrigemMotivo.fromName(corpo['origem'] as String?);
    final motivo = Motivo.fromJson({
      ...corpo,
      'id': novoId(),
      'criadoEm': _agora().toIso8601String(),
      'origem': origem == OrigemMotivo.site ? OrigemMotivo.app.name : origem.name,
      'status': corpo['status'] ?? StatusMotivo.pendente.name,
    });
    motivo.atendidoEm = motivo.atendido ? _agora() : null;
    final erro = _validarMotivo(motivo);
    if (erro != null) return _erro(400, erro);
    await store.salvar('motivos', motivo.toJson());
    return _json(motivo.toJson(), status: 201);
  }

  Future<Response> _atualizarMotivo(Request req, String id) async {
    final atual = store.buscar('motivos', id);
    if (atual == null) return _erro(404, 'Motivo não encontrado.');
    if (!_podeMotivo(req, atual)) return _semAcessoParticular;
    final corpo = await _corpo(req);
    // Origem e data de criação não mudam; a data de atendimento é do servidor. Quem não vê o nome
    // de quem enviou (recebeu vazio) não pode apagá-lo sem querer.
    final motivo = Motivo.fromJson({
      ...atual,
      ...corpo,
      'id': id,
      'origem': atual['origem'],
      'criadoEm': atual['criadoEm'],
      'atendidoEm': atual['atendidoEm'],
      'aprovadoPor': atual['aprovadoPor'],
      if (!(Auth.contaDa(req)?.pode(Permissao.motivosParticulares) ?? false)) 'enviadoPor': atual['enviadoPor'],
    });
    final antes = StatusMotivo.fromName(atual['status'] as String?);
    if (motivo.atendido && antes != StatusMotivo.atendido) motivo.atendidoEm = _agora();
    if (!motivo.atendido) motivo.atendidoEm = null;
    final erro = _validarMotivo(motivo);
    if (erro != null) return _erro(400, erro);
    await store.salvar('motivos', motivo.toJson());
    return _json(motivo.toJson());
  }

  Future<Response> _aprovarMotivo(Request req, String id) async {
    final atual = store.buscar('motivos', id);
    if (atual == null) return _erro(404, 'Motivo não encontrado.');
    if (!_podeMotivo(req, atual)) return _semAcessoParticular;
    final m = Motivo.fromJson(atual)
      ..status = StatusMotivo.pendente
      ..aprovadoPor = Auth.contaDa(req)?.nome ?? '';
    await store.salvar('motivos', m.toJson());
    return _json(m.toJson());
  }

  /// Pedido enviado pelo formulário público /oracao.
  Future<Response> _novoPedido(Request req) async {
    final corpo = await _corpo(req);
    // Campo escondido: só robôs preenchem. Responde "ok" para não dar pista.
    if ((corpo['website'] as String? ?? '').isNotEmpty) return _json({'ok': true});
    if (!_limitePedidos.permitir(_ip(req))) {
      return _erro(429, 'Você enviou vários pedidos seguidos. Tente novamente em alguns minutos.');
    }
    String texto(String campo) => (corpo[campo] as String? ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    final motivo = Motivo(
      id: novoId(),
      para: texto('para'),
      motivo: texto('motivo'),
      tipo: TipoMotivo.fromName(corpo['tipo'] as String?),
      criadoEm: _agora(),
      status: StatusMotivo.aguardando,
      origem: OrigemMotivo.site,
      publico: corpo['publico'] == true,
      enviadoPor: texto('enviadoPor'),
    );
    if (motivo.motivo.isEmpty) return _erro(400, 'Escreva o motivo de oração.');
    final erro = _validarMotivo(motivo) ?? (motivo.enviadoPor.length > 80 ? 'Nome muito longo.' : null);
    if (erro != null) return _erro(400, erro);
    await store.salvar('motivos', motivo.toJson());
    return _json({'ok': true}, status: 201);
  }

  static String? _validarMotivo(Motivo m) {
    if (m.motivo.trim().isEmpty && m.para.trim().isEmpty) return 'Informe o motivo.';
    if (m.para.length > 100) return 'Nome muito longo.';
    if (m.motivo.length > 500) return 'Motivo muito longo (máximo 500 caracteres).';
    return null;
  }

  // ---------- Caixa de mensagens ----------

  Response _listarMensagens(Request _) {
    final lista = store.listar('mensagens').toList()
      ..sort((a, b) => (b['criadoEm'] as String).compareTo(a['criadoEm'] as String));
    return _json(lista);
  }

  Future<Response> _novaMensagem(Request req) async {
    final corpo = await _corpo(req);
    if ((corpo['website'] as String? ?? '').isNotEmpty) return _json({'ok': true});
    String texto(String chave) => (corpo[chave] as String? ?? '').trim();
    final tipo = texto('tipo');
    final conteudo = texto('texto');
    final nome = texto('nome');
    final contato = texto('contato');
    if (!Mensagem.tipos.contains(tipo) || conteudo.isEmpty || conteudo.length > 2000 || nome.length > 80 || contato.length > 120) {
      return _erro(400, 'Confira o tipo, a mensagem (até 2000 caracteres), o nome e o contato.');
    }
    if (!_limiteMensagens.permitir(_ip(req))) return _erro(429, 'Muitas mensagens. Tente novamente em alguns minutos.');
    final m = Mensagem(id: novoId(), tipo: tipo, texto: conteudo, nome: nome, contato: contato,
      criadoEm: _agora(), avisoEmail: 'pendente');
    await store.salvar('mensagens', m.toJson());
    await _avisarMensagem(m);
    return _json({'ok': true}, status: 201);
  }

  Future<void> _avisarMensagem(Mensagem m) async {
    final enviar = enviarAvisoMensagem ?? (cfg?.smtpConfigurado == true
      ? (Mensagem mensagem, String url) => enviarEmailMensagem(cfg!, mensagem, url)
      : null);
    if (enviar == null) return;
    var resultado = 'enviado';
    try {
      await enviar(m, '${cfg?.urlBase ?? urlOracao.replaceFirst(RegExp(r'/oracao$'), '')}/painel')
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      stderr.writeln('Falha ao enviar aviso de mensagem ${m.id}: ${e.runtimeType}');
      resultado = 'falhou';
    }
    final atual = store.buscar('mensagens', m.id);
    if (atual != null) await store.salvar('mensagens', {...atual, 'avisoEmail': resultado});
  }

  Future<Response> _reenviarAviso(Request _, String id) async {
    final atual = store.buscar('mensagens', id);
    if (atual == null) return _erro(404, 'Mensagem não encontrada.');
    if (enviarAvisoMensagem == null && cfg?.smtpConfigurado != true) return _erro(400, 'Configure o SMTP primeiro.');
    await _avisarMensagem(Mensagem.fromJson(atual));
    return _json(store.buscar('mensagens', id));
  }

  Future<Response> _atualizarMensagem(Request req, String id) async {
    final atual = store.buscar('mensagens', id);
    if (atual == null) return _erro(404, 'Mensagem não encontrada.');
    final corpo = await _corpo(req);
    if (corpo.length != 1 || !corpo.containsKey('status') || !Mensagem.statusValidos.contains(corpo['status'])) {
      return _erro(400, 'Informe apenas um status válido.');
    }
    final novo = {...atual, 'status': corpo['status']};
    await store.salvar('mensagens', novo);
    return _json(novo);
  }

  // ---------- Membros ----------

  /// Membros normalizados: documentos antigos (só nome/dia/mês/ativo) ganham status.
  List<Membro> _listaMembros() => store.listar('membros').map(Membro.fromJson).toList();

  /// Valida o corpo e monta o membro pronto para gravar. [base] é o documento atual
  /// (edição) ou vazio (criação). Lança [FormatException] com a mensagem para o painel.
  Membro _montarMembro(Map<String, dynamic> corpo, Map<String, dynamic> base, String id) {
    if (corpo.containsKey('status') && StatusMembro.porNome(corpo['status'] as String?) == null) {
      throw const FormatException('Status inválido.');
    }
    for (final campo in ['dataChegada', 'dataBatismo', 'dataMembresia', 'consentimentoEm']) {
      final v = corpo[campo];
      if (v is String && v.trim().isNotEmpty && Membro.dataDe(v) == null) {
        throw FormatException('Data inválida em "$campo": use dd/mm/aaaa.');
      }
    }
    final anterior = base.isEmpty ? null : Membro.fromJson(base);
    // Foto (rotas próprias), histórico e datas de controle são do servidor, não do corpo.
    final editavel = {...corpo}
      ..remove('foto')
      ..remove('historicoStatus')
      ..remove('criadoEm')
      ..remove('atualizadoEm');
    final m = Membro.fromJson({...base, ...editavel, 'id': id});
    final erro = _validarMembro(m);
    if (erro != null) throw FormatException(erro);
    if (m.conjugeId != null && store.buscar('membros', m.conjugeId!) == null) {
      throw const FormatException('Cônjuge não encontrado (foi excluído?).');
    }
    for (final paisId in m.paisIds) {
      if (store.buscar('membros', paisId) == null) {
        throw const FormatException('Vínculo de pais não encontrado (foi excluído?).');
      }
    }
    // Mudança de status entra no histórico.
    final historico = [...?anterior?.historicoStatus];
    if (anterior == null || m.status != anterior.status) {
      historico.add(MudancaStatus(m.status, _agora()));
    }
    final agora = _agora();
    return Membro.fromJson({
      ...m.toJson(),
      'historicoStatus': [for (final h in historico) h.toJson()],
      'criadoEm': anterior?.criadoEm?.toIso8601String() ?? agora.toIso8601String(),
      'atualizadoEm': agora.toIso8601String(),
    });
  }

  Future<Response> _criarMembro(Request req) async {
    try {
      final m = _montarMembro(await _corpo(req), {}, novoId());
      await store.salvar('membros', m.toJson());
      await _sincronizarConjuge(null, m);
      return _json(m.toJson(), status: 201);
    } on FormatException catch (e) {
      return _erro(400, e.message);
    }
  }

  Future<Response> _atualizarMembro(Request req, String id) async {
    final atual = store.buscar('membros', id);
    if (atual == null) return _erro(404, 'Membro não encontrado.');
    try {
      final m = _montarMembro(await _corpo(req), atual, id);
      await store.salvar('membros', m.toJson());
      await _sincronizarConjuge(Membro.fromJson(atual), m);
      return _json(m.toJson());
    } on FormatException catch (e) {
      return _erro(400, e.message);
    }
  }

  /// Mantém o vínculo de cônjuge nos dois lados (o painel edita um lado de cada vez).
  Future<void> _sincronizarConjuge(Membro? anterior, Membro novo) async {
    final docs = <Map<String, dynamic>>[];
    final idAntigo = anterior?.conjugeId;
    if (idAntigo != null && idAntigo != novo.conjugeId && idAntigo != novo.id) {
      final doc = store.buscar('membros', idAntigo);
      if (doc != null && doc['conjugeId'] == novo.id) {
        docs.add({...doc}..remove('conjugeId'));
      }
    }
    final idNovo = novo.conjugeId;
    if (idNovo != null && idNovo != novo.id) {
      final doc = store.buscar('membros', idNovo);
      if (doc != null && doc['conjugeId'] != novo.id) {
        // O novo cônjuge era casado com outra pessoa no cadastro: desfaz o vínculo antigo
        // (o painel pede confirmação antes), senão essa pessoa continuaria apontando para ele.
        final outroId = doc['conjugeId'] as String?;
        if (outroId != null && outroId != idAntigo) {
          final outro = store.buscar('membros', outroId);
          if (outro != null && outro['conjugeId'] == idNovo) docs.add({...outro}..remove('conjugeId'));
        }
        docs.add({...doc, 'conjugeId': novo.id});
      }
    }
    if (docs.isNotEmpty) await store.salvarVarios('membros', docs);
  }

  Future<Response> _excluirMembro(Request _, String id) async {
    final atual = store.buscar('membros', id);
    if (atual == null) return _erro(404, 'Membro não encontrado.');
    final m = Membro.fromJson(atual);
    // Limpa os vínculos nos outros membros (cônjuge e filhos que apontam para este).
    final docs = <Map<String, dynamic>>[];
    if (m.conjugeId != null) {
      final doc = store.buscar('membros', m.conjugeId!);
      if (doc != null && doc['conjugeId'] == id) docs.add({...doc}..remove('conjugeId'));
    }
    for (final outro in store.listar('membros')) {
      if (outro['id'] == id) continue;
      final pais = (outro['paisIds'] as List?)?.map((e) => e.toString()).toList();
      if (pais != null && pais.contains(id)) {
        final restantes = pais.where((p) => p != id).toList();
        // Passa pelo modelo: lista vazia sai do documento em vez de virar "paisIds": [].
        docs.add(Membro.fromJson({...outro, 'paisIds': restantes}).toJson());
      }
    }
    if (docs.isNotEmpty) await store.salvarVarios('membros', docs);
    await store.excluir('membros', id);
    if (m.foto != null) await _apagarFotoMembro(m.foto!);
    return _json({'ok': true});
  }

  Future<void> _apagarFotoMembro(String arquivo) =>
      fotosMembros.excluir([arquivo, arquivo.replaceFirst('.jpg', '-m.jpg')]);

  /// Corpo em texto: "Nome;dd/mm" por linha (formato antigo) ou CSV com cabeçalho
  /// (Nome;Aniversário;Telefone;Email;Status…). Não duplica nome + aniversário já cadastrados.
  /// Campos inválidos de uma linha (ex.: CPF digitado errado) entram como aviso, sem perder a pessoa.
  Future<Response> _importarMembros(Request req) async {
    final lido = lerCsvMembros(await req.readAsString());
    final existentes = store
        .listar('membros')
        .map((m) => '${(m['nome'] as String).toLowerCase()}|${m['dia']}|${m['mes']}')
        .toSet();
    final agora = _agora();
    final detalhes = [...lido.detalhes];
    final novos = <Map<String, dynamic>>[];
    for (final linha in lido.membros) {
      final chave = '${linha.nome.toLowerCase()}|${linha.dia}|${linha.mes}';
      if (!existentes.add(chave)) continue;
      final j = {...linha.toJson(), 'id': novoId(), 'criadoEm': agora.toIso8601String()};
      final m = Membro.fromJson(j);
      if (m.cpf != null && !Membro.cpfValido(m.cpf!)) {
        j.remove('cpf');
        detalhes.add('${m.nome}: CPF inválido — importado sem o CPF.');
      }
      if (m.email != null && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(m.email!)) {
        j.remove('email');
        detalhes.add('${m.nome}: e-mail inválido — importado sem o e-mail.');
      }
      novos.add(Membro.fromJson(j).toJson());
    }
    if (novos.isNotEmpty) await store.salvarVarios('membros', novos);
    return _json({'importados': novos.length, 'linhasComErro': lido.linhasComErro, 'detalhes': detalhes});
  }

  /// GET /api/membros/exportar?status=&ministerio=&aniversariantes=mes&busca=&semConsentimento=1&novasDias=90 — CSV com BOM,
  /// pronto para abrir no Excel, respeitando os filtros do painel (a busca casa como na tela).
  Future<Response> _exportarMembros(Request req) async {
    final qs = req.url.queryParameters;
    final busca = semAcento((qs['busca'] ?? '').trim().toLowerCase()) ?? '';
    final soAtivos = qs['status'] == 'ativos';
    final status = soAtivos ? null : StatusMembro.porNome(qs['status']);
    final ministerio = (qs['ministerio'] ?? '').trim().toLowerCase();
    final soAniversariantes = (qs['aniversariantes'] ?? '') == 'mes';
    final agora = _agora();
    var lista = _listaMembros();
    if (soAtivos) lista = lista.where((m) => m.ativo).toList();
    if (status != null) lista = lista.where((m) => m.status == status).toList();
    if (ministerio.isNotEmpty) {
      lista = lista.where((m) => m.ministerios.any((x) => x.toLowerCase() == ministerio)).toList();
    }
    if (soAniversariantes) lista = lista.where((m) => m.ativo && m.mes == agora.month).toList();
    if (qs['semConsentimento'] == '1') lista = lista.where((m) => m.consentimentoEm == null).toList();
    final novasDias = int.tryParse(qs['novasDias'] ?? '');
    if (novasDias != null && novasDias > 0) {
      final desde = agora.subtract(Duration(days: novasDias));
      lista = lista.where((m) => m.criadoEm != null && !m.criadoEm!.isBefore(desde)).toList();
    }
    if (busca.isNotEmpty) {
      lista = lista.where((m) {
        final alvo = [m.nome, m.telefone, m.whatsapp, m.email, m.cidade, m.bairro, m.funcao]
            .whereType<String>()
            .join(' ')
            .toLowerCase();
        return (semAcento(alvo) ?? '').contains(busca);
      }).toList();
    }
    lista.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));

    String celula(Object? v) {
      final s = v?.toString() ?? '';
      return s.contains(';') || s.contains('"') || s.contains('\n') || s.contains('\r')
          ? '"${s.replaceAll('"', '""')}"'
          : s;
    }

    final linhas = [
      for (final m in lista)
        [
          m.nome,
          m.ano == null ? m.aniversario : '${m.dia.toString().padLeft(2, '0')}/${m.mes.toString().padLeft(2, '0')}/${m.ano}',
          m.idadeEm(agora) ?? '',
          m.status.nome,
          m.telefone ?? '',
          m.whatsapp ?? '',
          m.email ?? '',
          m.ministerios.join('|'),
          m.funcao ?? '',
          m.cpf ?? '',
          m.cidade ?? '',
          m.estado ?? '',
          m.consentimentoEm == null ? '' : m.consentimentoEm!.split('-').reversed.join('/'),
        ].map(celula).join(';'),
    ];
    final csv = [
      'Nome;Aniversário;Idade;Status;Telefone;WhatsApp;E-mail;Ministérios;Função;CPF;Cidade;UF;Consentimento',
      ...linhas,
    ].join('\r\n');
    // BOM na mão: o codec UTF-8 do Dart descarta o caractere \uFEFF (o Excel precisa dele).
    final bytes = BytesBuilder()..add([0xEF, 0xBB, 0xBF])..add(utf8.encode(csv));
    return Response.ok(bytes.toBytes(), headers: {
      'content-type': 'text/csv; charset=utf-8',
      'content-disposition': 'attachment; filename="membros.csv"',
    });
  }

  /// Corpo: bytes da foto (JPG ou PNG até 15 MB). Substitui a anterior.
  Future<Response> _enviarFotoMembro(Request req, String id) async {
    final atual = store.buscar('membros', id);
    if (atual == null) return _erro(404, 'Membro não encontrado.');
    final tamanho = req.contentLength;
    if (tamanho != null && tamanho > FotosMembros.tamanhoMaximo) return _erro(413, 'Foto maior que 15 MB.');
    final bytes = await _lerBytes(req, FotosMembros.tamanhoMaximo);
    if (bytes == null) return _erro(413, 'Foto maior que 15 MB.');
    try {
      final r = await fotosMembros.salvar(bytes);
      final antiga = (atual['foto'] as String?)?.trim();
      if (antiga != null && antiga.isNotEmpty) await _apagarFotoMembro(antiga);
      final doc = {...atual, 'foto': r.arquivo, 'atualizadoEm': _agora().toIso8601String()};
      await store.salvar('membros', doc);
      return _json(doc, status: 201);
    } on FormatException catch (e) {
      return _erro(400, e.message);
    }
  }

  Future<Response> _removerFotoMembro(Request _, String id) async {
    final atual = store.buscar('membros', id);
    if (atual == null) return _erro(404, 'Membro não encontrado.');
    final antiga = (atual['foto'] as String?)?.trim();
    if (antiga == null || antiga.isEmpty) return _erro(404, 'Este membro não tem foto.');
    await _apagarFotoMembro(antiga);
    final doc = {...atual}..remove('foto');
    doc['atualizadoEm'] = _agora().toIso8601String();
    await store.salvar('membros', doc);
    return _json(doc);
  }

  /// GET /api/membros/<id>/foto (ou /foto-miniatura) — atrás de login, nunca pública.
  Response _fotoMembro(String id, {required bool miniatura}) {
    final doc = store.buscar('membros', id);
    final nome = (doc?['foto'] as String?)?.trim();
    if (doc == null || nome == null || nome.isEmpty) return Response.notFound('Não encontrado');
    final nomeArquivo = miniatura ? nome.replaceFirst('.jpg', '-m.jpg') : nome;
    final f = fotosMembros.arquivo(nomeArquivo);
    if (f == null || !f.existsSync()) return Response.notFound('Não encontrado');
    // A URL muda a cada foto nova (o painel usa ?v=), mas o login é por token: sem cache agressivo.
    return Response.ok(f.openRead(),
        headers: {'content-type': 'image/jpeg', 'cache-control': 'private, no-cache'});
  }

  static String? _validarMembro(Membro m) {
    if (m.nome.trim().isEmpty) return 'Informe o nome.';
    if (m.nome.length > 100) return 'Nome muito longo.';
    if (!Membro.dataValida(m.dia, m.mes)) return 'Data de aniversário inválida.';
    if (m.ano != null && (m.ano! < 1900 || m.ano! > DateTime.now().year)) return 'Ano de nascimento inválido.';
    if (m.cpf != null && !Membro.cpfValido(m.cpf!)) return 'CPF inválido: confira os números.';
    if (m.email != null && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(m.email!)) return 'E-mail inválido.';
    if (m.conjugeId == m.id) return 'O cônjuge não pode ser a própria pessoa.';
    if (m.paisIds.contains(m.id)) return 'Os pais não podem ser a própria pessoa.';
    if (m.ministerios.length > 12) return 'Muitos ministérios (máximo 12).';
    if ((m.comoConheceu ?? '').length > 200) return '"Como conheceu" muito longo.';
    return null;
  }

  // ---------- Cartazes ----------

  Future<Response> _listarCartazes(Request _) async {
    final lista = await cartazes.listar();
    return _json([
      for (final c in lista)
        {
          'nome': c.nome,
          'holyrics': '${Config.subpastaHolyrics}/${c.nome}',
          'url': '/cartazes/${Uri.encodeComponent(c.nome)}',
          'tamanho': c.tamanho,
          'modificado': c.modificado.toIso8601String(),
        }
    ]);
  }

  /// Corpo: bytes da imagem; nome em ?nome=arquivo.jpg
  Future<Response> _enviarCartaz(Request req) async {
    final tamanho = req.contentLength;
    if (tamanho != null && tamanho > Cartazes.tamanhoMaximo) return _erro(413, 'Imagem maior que 10 MB.');
    final bytes = await _lerBytes(req, Cartazes.tamanhoMaximo);
    if (bytes == null) return _erro(413, 'Imagem maior que 10 MB.');
    try {
      final nome = await cartazes.salvar(req.url.queryParameters['nome'] ?? 'cartaz', bytes);
      store.avisar('cartazes');
      return _json({'nome': nome, 'holyrics': '${Config.subpastaHolyrics}/$nome'}, status: 201);
    } on FormatException catch (e) {
      return _erro(400, e.message);
    }
  }

  Future<Response> _excluirCartaz(Request _, String nome) async {
    if (!await cartazes.excluir(Uri.decodeComponent(nome))) return _erro(404, 'Cartaz não encontrado.');
    store.avisar('cartazes');
    return _json({'ok': true});
  }

  // ---------- Galeria do site (carrossel da página inicial) ----------

  /// Fotos na ordem do carrossel.
  List<Map<String, dynamic>> _fotos() => [...store.listar('galeria')]
    ..sort((a, b) => ((a['ordem'] as num?) ?? 0).compareTo((b['ordem'] as num?) ?? 0));

  static Map<String, dynamic> _fotoJson(Map<String, dynamic> f) => {
        ...f,
        'url': '/galeria/${f['arquivo']}',
        'urlMiniatura': '/galeria/${f['miniatura']}',
      };

  static String? _validarLegenda(Object? v) =>
      v is String && v.trim().length > 140 ? 'Legenda muito longa (máximo 140 letras).' : null;

  static String? _validarLink(Object? v) {
    if (v is! String || v.trim().isEmpty) return null;
    return RegExp(r'^https://\S+$').hasMatch(v.trim()) ? null : 'O link precisa começar com https://';
  }

  /// Corpo: bytes da foto; legenda opcional em ?legenda=
  Future<Response> _enviarFoto(Request req) async {
    if (store.listar('galeria').length >= Galeria.maximoFotos) {
      return _erro(400, 'A galeria já tem ${Galeria.maximoFotos} fotos. Exclua alguma antes de enviar outra.');
    }
    final tamanho = req.contentLength;
    if (tamanho != null && tamanho > Galeria.tamanhoMaximo) return _erro(413, 'Foto maior que 15 MB.');
    final bytes = await _lerBytes(req, Galeria.tamanhoMaximo);
    if (bytes == null) return _erro(413, 'Foto maior que 15 MB.');
    final legenda = (req.url.queryParameters['legenda'] ?? '').trim();
    final erro = _validarLegenda(legenda);
    if (erro != null) return _erro(400, erro);
    try {
      final r = await galeria.salvar(bytes);
      final ordens = [for (final f in store.listar('galeria')) (f['ordem'] as num?)?.toInt() ?? 0];
      final doc = <String, dynamic>{
        'id': novoId(),
        'arquivo': r.arquivo,
        'miniatura': r.miniatura,
        'largura': r.largura,
        'altura': r.altura,
        'legenda': legenda,
        'link': '',
        'ativo': true,
        'ordem': ordens.isEmpty ? 0 : ordens.reduce((a, b) => a > b ? a : b) + 1,
        'criadoEm': _agora().toIso8601String(),
      };
      await store.salvar('galeria', doc);
      return _json(_fotoJson(doc), status: 201);
    } on FormatException catch (e) {
      return _erro(400, e.message);
    }
  }

  /// Corpo: {"legenda", "link", "ativo"} (só os campos a mudar).
  Future<Response> _atualizarFoto(Request req, String id) async {
    final atual = store.buscar('galeria', id);
    if (atual == null) return _erro(404, 'Foto não encontrada.');
    final corpo = await _corpo(req);
    final erro = _validarLegenda(corpo['legenda']) ?? _validarLink(corpo['link']);
    if (erro != null) return _erro(400, erro);
    if (corpo.containsKey('ativo') && corpo['ativo'] is! bool) return _erro(400, '"ativo" deve ser verdadeiro ou falso.');
    final doc = {
      ...atual,
      if (corpo['legenda'] is String) 'legenda': (corpo['legenda'] as String).trim(),
      if (corpo['link'] is String) 'link': (corpo['link'] as String).trim(),
      if (corpo['ativo'] is bool) 'ativo': corpo['ativo'],
    };
    await store.salvar('galeria', doc);
    return _json(_fotoJson(doc));
  }

  /// Corpo: lista de ids na nova ordem (a primeira é a capa).
  Future<Response> _ordenarGaleria(Request req) async {
    final ids = jsonDecode(await req.readAsString());
    if (ids is! List) return _erro(400, 'Envie a lista de ids.');
    final docs = <Map<String, dynamic>>[];
    for (var i = 0; i < ids.length; i++) {
      final atual = store.buscar('galeria', ids[i] as String);
      if (atual != null) docs.add({...atual, 'ordem': i});
    }
    await store.salvarVarios('galeria', docs);
    return _json({'ok': true});
  }

  Future<Response> _excluirFoto(Request _, String id) async {
    final atual = store.buscar('galeria', id);
    if (atual == null) return _erro(404, 'Foto não encontrada.');
    await galeria.excluir([atual['arquivo'] as String, atual['miniatura'] as String]);
    await store.excluir('galeria', id);
    return _json({'ok': true});
  }

  /// GET /galeria/<arquivo> — foto pública (o nome é aleatório e muda a cada envio: cache longo).
  Future<Response> _fotoGaleria(Request _, String arquivo) async {
    final f = galeria.arquivo(arquivo);
    if (f == null || !await f.exists()) return Response.notFound('Não encontrado');
    return Response.ok(f.openRead(),
        headers: {'content-type': 'image/jpeg', 'cache-control': 'public, max-age=31536000, immutable'});
  }

  // ---------- Holyrics / backup / tempo real ----------

  Future<Response> _holyrics(Request req, String acao) async {
    if (!acoesPermitidas.contains(acao)) return _erro(403, 'Ação não permitida: $acao');
    return _chamarHolyrics(acao, await req.readAsString(), usuario: Auth.contaDa(req)?.nome ?? '');
  }

  /// Chama o Holyrics e, se deu certo, registra no histórico (com o nome de quem projetou).
  Future<Response> _chamarHolyrics(String acao, String corpo, {String usuario = ''}) async {
    final r = await holyrics.chamar(acao, corpo);
    if (_ok(r.corpo) && Historico.acoes.contains(acao)) {
      await historico.registrar(acao, corpo, usuario: usuario);
      store.avisar('historico');
    }
    return Response(r.status, body: r.corpo, headers: jsonHeaders);
  }

  static bool _ok(String corpo) {
    try {
      return (jsonDecode(corpo) as Map)['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  /// Corpo opcional: {"tema": "...", "segundos": 10, "porSlide": 3, "dias": 30}
  Future<Response> _projetarRespondidas(Request req) async {
    final corpo = await _corpo(req);
    final dias = (corpo['dias'] as num?)?.toInt() ?? cfg?.diasRespondidas ?? 30;
    final respondidas = oracoesRespondidas(_motivos(), _agora(), dias: dias);
    if (respondidas.isEmpty) return _erro(400, 'Nenhuma oração respondida (pública) nos últimos $dias dias.');
    final slides = montarSlidesGratidao(respondidas, porSlide: (corpo['porSlide'] as num?)?.toInt() ?? 3);
    final segundos = (corpo['segundos'] as num?)?.toInt() ?? cfg?.segundosPorSlide ?? 10;
    final tema = corpo['tema'] as String? ?? cfg?.temaPadrao ?? '';
    return _chamarHolyrics(
      usuario: Auth.contaDa(req)?.nome ?? '',
      'ShowQuickPresentation',
      jsonEncode({
        'slides': [for (final s in slides) {'text': s, 'duration': segundos}],
        if (slides.length > 1) 'automatic': {'seconds': segundos, 'repeat': true},
        if (tema.isNotEmpty) 'theme': {'name': tema},
      }),
    );
  }

  Future<Response> _historico(Request req) async {
    final limite = int.tryParse(req.url.queryParameters['limite'] ?? '') ?? 300;
    return _json(await historico.listar(limite: limite.clamp(1, 2000)));
  }

  Response _resumoSemanal(Request _) => _json({
        'texto': montarResumoSemanal(
          recados: _recadosComAuto(),
          motivos: _motivos(),
          membros: _membros(),
          agora: _agora(),
          igreja: nomeIgreja,
          urlPedidos: urlOracao,
          eventos: _eventosDaSemana(),
        ),
      });

  /// Eventos de hoje até o fim da próxima semana (o resumo filtra até sábado).
  List<Evento> _eventosDaSemana() {
    final a = agenda;
    if (a == null) return const [];
    final hoje = DateTime(_agora().year, _agora().month, _agora().day);
    return a.eventos(de: hoje, ate: hoje.add(const Duration(days: 8)));
  }

  // ---------- Agenda (Google) ----------

  /// GET /api/agenda?dias=30 — próximos eventos e o estado da sincronização.
  Response _agenda(Request req) {
    final a = agenda;
    final dias = (int.tryParse(req.url.queryParameters['dias'] ?? '') ?? 30).clamp(1, 120);
    return _json({
      ...?a?.estado(),
      'configurada': a?.configurada ?? false,
      'eventos': [for (final e in a?.proximos(dias: dias) ?? const <Evento>[]) _eventoJson(e)],
    });
  }

  static Map<String, dynamic> _eventoJson(Evento e) => {
        ...e.toJson(),
        // Textos prontos para o painel web.
        'dia': diaPorExtenso(e.inicio),
        'horario': horario(e),
        'textoRecado': textoRecadoDoEvento(e),
      };

  /// Resposta de erro do Google, com o link da ajuda que explica como resolver.
  static Response _erroGoogle(ErroGoogle e, {Map<String, dynamic> extra = const {}}) =>
      _json({'erro': e.mensagem, 'ajuda': e.ajuda, ...extra}, status: e.status);

  Future<Response> _naAgenda(Future<Response> Function(AgendaGoogle a) acao) async {
    final a = agenda;
    if (a == null) return _erro(501, 'Agenda indisponível.');
    try {
      return await acao(a);
    } on ErroGoogle catch (e) {
      return _erroGoogle(e);
    } on FormatException catch (e) {
      return _erro(400, e.message);
    }
  }

  /// Corpo: {"titulo", "inicio", "fim", "diaInteiro", "local", "descricao"} (fim exclusivo no dia inteiro).
  Future<Response> _criarEvento(Request req) => _naAgenda((a) async {
        final dados = DadosEvento.fromJson(await _corpo(req));
        return _json(_eventoJson(await a.criar(dados)), status: 201);
      });

  Future<Response> _atualizarEvento(Request req, String id) => _naAgenda((a) async {
        final dados = DadosEvento.fromJson(await _corpo(req));
        return _json(_eventoJson(await a.atualizar(Uri.decodeComponent(id), dados)));
      });

  Future<Response> _excluirEvento(Request req, String id) => _naAgenda((a) async {
        await a.excluir(Uri.decodeComponent(id));
        return _json({'ok': true});
      });

  /// Corpo: {"chave": <conteúdo do arquivo JSON>, "calendarioId": "..." (opcional)}.
  /// Testa o acesso à agenda e só então guarda a chave em data/.
  Future<Response> _adminContaServico(Request req) async {
    final a = agenda, c = cfg, conta = agenda?.conta;
    if (a == null || c == null || conta == null) return _erro(501, 'Agenda indisponível.');
    final corpo = await _corpo(req);
    final Map<String, dynamic> chave;
    try {
      final bruta = corpo['chave'];
      chave = ContaServicoGoogle.validar(bruta is String ? bruta : jsonEncode(bruta));
    } on FormatException catch (e) {
      return _json({'erro': e.message, 'ajuda': '$ajudaAgenda#erro-chave'}, status: 400);
    }
    final idInformado = (corpo['calendarioId'] as String? ?? '').trim();
    if (idInformado.contains(RegExp(r'[\s/]')) || idInformado.length > 300) {
      return _json({'erro': 'ID da agenda inválido.', 'ajuda': '$ajudaAgenda#id-agenda'}, status: 400);
    }
    final id = idInformado.isNotEmpty ? idInformado : c.agendaCalendarioId;
    if (id.isEmpty) {
      return _json({
        'erro': 'Informe o ID da agenda (Google Agenda › Configurações e compartilhamento › Integrar agenda).',
        'ajuda': '$ajudaAgenda#id-agenda',
      }, status: 400);
    }
    final email = chave['client_email'] as String;
    try {
      final acesso = await a.testarConta(chave, id);
      if (idInformado.isNotEmpty) await c.atualizar({'agendaCalendarioId': idInformado});
      await conta.salvar(chave);
      await a.atualizarAgora();
      return _json({'agenda': acesso.nome, 'permissao': acesso.permissao, 'contaServico': email, 'estado': a.estado()});
    } on ErroGoogle catch (e) {
      return _erroGoogle(e, extra: {'contaServico': email});
    }
  }

  /// Testa a chave já guardada (útil depois de mudar o compartilhamento da agenda).
  Future<Response> _adminTestarContaServico(Request _) => _naAgenda((a) async {
        final cal = a.calendario;
        if (cal == null) return _erro(400, 'Nenhuma conta de serviço ligada.');
        final acesso = await cal.testarAcesso();
        await a.atualizarAgora();
        return _json({'agenda': acesso.nome, 'permissao': acesso.permissao, 'contaServico': a.conta?.email, 'estado': a.estado()});
      });

  /// Volta para o modo só leitura (iCal, se houver endereço). A chave é apagada do servidor.
  Future<Response> _adminRemoverContaServico(Request _) => _naAgenda((a) async {
        await a.conta?.remover();
        await a.atualizarAgora();
        return _json({'estado': a.estado()});
      });

  Future<Response> _adminAgendaAtualizar(Request req) async {
    final a = agenda;
    if (a == null || !a.configurada) return _erro(400, 'Informe o endereço da agenda primeiro.');
    await a.atualizarAgora();
    return _agenda(req);
  }

  /// Corpo: {"url": "..."} — testa sem salvar.
  Future<Response> _adminAgendaTestar(Request req) async {
    final url = ((await _corpo(req))['url'] as String? ?? '').trim();
    if (!enderecoAgendaValido(url)) return _erro(400, 'Endereço inválido. Cole o "Endereço secreto no formato iCal".');
    try {
      final eventos = await AgendaGoogle.testar(url, cliente: clienteAgenda, agora: _agora());
      return _json({
        'eventos': eventos.length,
        'proximos': [for (final e in eventos.take(5)) '${diaCurto(e.inicio)} ${horario(e)} — ${e.titulo}'],
      });
    } on FormatException catch (e) {
      return _erro(400, e.message);
    }
  }

  /// Slides do mural da recepção: só dados públicos (sem quem enviou, sem pedidos particulares).
  Response _mural(Request _) {
    final slides = montarMural(
      recados: _recadosComAuto(),
      motivos: _motivos(),
      agora: _agora(),
      urlCartaz: _urlCartaz,
      urlQr: '/qr-oracao.png',
      urlQrMensagens: '/qr-mensagens.png',
      motivosPorSlide: cfg?.motivosPorSlide ?? 5,
      eventos: _eventosDoMural(),
      diasEventos: cfg?.agendaDiasMural ?? 7,
      mostrarDescricao: cfg?.agendaMostrarDescricao ?? true,
    );
    return _json({'atualizado': _agora().toIso8601String(), 'slides': [for (final s in slides) s.toJson()]});
  }

  List<Evento> _eventosDoMural() {
    final a = agenda;
    if (a == null) return const [];
    final hoje = DateTime(_agora().year, _agora().month, _agora().day);
    return a.eventos(de: hoje, ate: hoje.add(Duration(days: (cfg?.agendaDiasMural ?? 7) + 1)));
  }

  /// Endereço público da imagem de um cartaz do Holyrics ("Diako/retiro.jpg"), se o arquivo existir.
  String? _urlCartaz(String caminho) {
    const prefixo = '${Config.subpastaHolyrics}/';
    if (!caminho.startsWith(prefixo)) return null;
    final nome = caminho.substring(prefixo.length);
    return cartazes.arquivo(nome)?.existsSync() == true ? '/cartazes/${Uri.encodeComponent(nome)}' : null;
  }

  // ---------- Página inicial pública ----------

  /// Eventos que podem aparecer no site (só com a agenda liberada no /admin).
  List<Evento> _eventosDoSite() =>
      cfg?.siteAgenda == true ? (agenda?.proximos(dias: 30) ?? const <Evento>[]) : const <Evento>[];

  /// GET /api/public/inicio — só dados públicos: recados marcados "no site", agenda (se liberada),
  /// cultos, endereço, PIX e redes. Nada de pedidos de oração, mensagens ou aniversariantes.
  Response _inicio(Request _) {
    final c = cfg;
    if (c == null || !c.siteAtivo) return _erro(404, 'Página inicial desligada.');
    final agora = _agora();
    final noSite = store
        .listar('recados')
        .map(Recado.fromJson)
        .where((r) => (r.site || r.urgente) && !r.expirado(agora))
        .toList()
      // Mesma ordem do tablet: fixos primeiro, depois a ordem da lista.
      ..sort((a, b) => a.fixo != b.fixo ? (a.fixo ? -1 : 1) : a.ordem.compareTo(b.ordem));
    Map<String, dynamic> aviso(Recado r) => {
          'titulo': r.titulo,
          'texto': r.texto,
          if (r.validoAte != null) 'validoAte': r.validoAte!.toIso8601String(),
          if (r.ehImagem && _urlCartaz(r.imagemHolyrics!) != null) 'imagem': _urlCartaz(r.imagemHolyrics!),
        };
    final eventos = _eventosDoSite();
    final pix = c.pixNoSite;
    return _json({
      'igreja': nomeIgreja,
      'urgentes': [for (final r in noSite.where((r) => r.urgente)) aviso(r)],
      'avisos': [for (final r in noSite.where((r) => !r.urgente)) aviso(r)],
      'agenda': c.siteAgenda && agenda?.configurada == true,
      'eventos': [
        for (final e in eventos.take(8))
          {
            'id': e.id,
            'titulo': e.titulo,
            'inicio': e.inicio.toIso8601String(),
            'diaInteiro': e.diaInteiro,
            'horario': horario(e),
            'local': e.local,
            'ics': '/api/public/eventos/${Uri.encodeComponent(e.id)}.ics',
          },
      ],
      'galeria': [
        if (c.siteGaleria)
          for (final f in _fotos().where((f) => f['ativo'] != false))
            {
              'url': '/galeria/${f['arquivo']}',
              'legenda': f['legenda'] ?? '',
              'link': f['link'] ?? '',
              'largura': f['largura'],
              'altura': f['altura'],
            },
      ],
      'cultos': lerCultos(c.siteCultos),
      'endereco': c.siteEndereco,
      if (c.siteEndereco.isNotEmpty) 'mapa': linkMapa(c.siteEndereco),
      if (pix)
        'pix': {
          'chave': c.sitePixChave,
          'chaveFormatada': formatarChavePix(c.sitePixChave),
          'nome': c.sitePixNome,
          'qr': '/pix.png',
          // Código "Pix copia e cola": funciona em qualquer banco (Pix › Pix copia e cola).
          'copiaECola': payloadPix(chave: c.sitePixChave, nome: c.sitePixNome, cidade: c.sitePixCidade),
        },
      'redes': {
        if (c.siteInstagram.isNotEmpty) 'instagram': c.siteInstagram,
        if (c.siteYoutube.isNotEmpty) 'youtube': c.siteYoutube,
        if (c.siteWhatsapp.isNotEmpty) 'whatsapp': linkWhatsapp(c.siteWhatsapp),
      },
    });
  }

  /// GET /api/public/eventos/<id>.ics — convite para a pessoa salvar o evento no próprio calendário.
  Response _icsEvento(Request _, String arquivo) {
    final id = Uri.decodeComponent(arquivo).replaceFirst(RegExp(r'\.ics$'), '');
    final e = _eventosDoSite().where((e) => e.id == id).firstOrNull;
    if (e == null) return Response.notFound('Evento não encontrado.');
    final nome = e.titulo.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    return Response.ok(icsDoEvento(e, igreja: nomeIgreja, agora: _agora().toUtc()), headers: {
      'content-type': 'text/calendar; charset=utf-8',
      'content-disposition': 'attachment; filename="${nome.isEmpty ? 'evento' : nome}.ics"',
      'cache-control': 'no-cache',
    });
  }

  /// GET /pix.png — QR do PIX (copia e cola) para a página inicial.
  Response _pngPix(Request _) {
    final c = cfg;
    if (c == null || !c.siteAtivo || !c.pixNoSite) {
      return Response.notFound('PIX não configurado.');
    }
    final payload = payloadPix(chave: c.sitePixChave, nome: c.sitePixNome, cidade: c.sitePixCidade);
    return Response.ok(gerarPngQrQuadrado(payload), headers: {'content-type': 'image/png', 'cache-control': 'no-cache'});
  }

  /// Textos públicos do site (formulário de pedidos).
  Response _site(Request _) => _json({
        'nomeIgreja': nomeIgreja,
        'pedidoTitulo': cfg?.pedidoTitulo ?? 'Pedido de oração',
        'pedidoIntro': cfg?.pedidoIntro ?? '',
        'pedidoObrigado': cfg?.pedidoObrigado ?? 'Estaremos orando por você.',
      });

  // ---------- Backup e restauração ----------

  Future<Response> _backupAgora(Request _) async {
    final f = await backup.executar(sufixo: '');
    return _json({'arquivo': f.path, 'nome': p.basename(f.path)});
  }

  Future<Response> _listarBackups(Request _) async {
    final lista = await backup.listar();
    return _json({
      'pasta': backup.pastaDestino,
      'horario': backup.horario,
      'ultimo': (await backup.ultimo())?.toIso8601String(),
      'backups': [
        for (final b in lista) {'nome': b.nome, 'tamanho': b.tamanho, 'criado': b.criado.toIso8601String()},
      ],
    });
  }

  /// Gera um backup na hora e devolve o .zip para download (sem gravar no servidor).
  Future<Response> _baixarBackupAgora(Request _) async {
    final agora = _agora();
    final bytes = await backup.gerarZip(agora: agora);
    final nome = 'diako-backup-${agora.toIso8601String().substring(0, 19).replaceAll(':', '')}.zip';
    return _zip(bytes, nome);
  }

  Response _baixarBackup(Request _, String nome) {
    final f = backup.arquivo(Uri.decodeComponent(nome));
    if (f == null) return _erro(404, 'Backup não encontrado.');
    return _zip(f.readAsBytesSync(), p.basename(f.path));
  }

  Future<Response> _excluirBackup(Request _, String nome) async {
    if (!await backup.excluir(Uri.decodeComponent(nome))) return _erro(404, 'Backup não encontrado.');
    return _json({'ok': true});
  }

  /// Restaura um backup da lista do servidor. Corpo: {"configuracoes": true|false}
  Future<Response> _restaurarDaLista(Request req, String nome) async {
    final f = backup.arquivo(Uri.decodeComponent(nome));
    if (f == null) return _erro(404, 'Backup não encontrado.');
    final corpo = await _corpo(req);
    return _restaurar(await f.readAsBytes(), configuracoes: corpo['configuracoes'] == true);
  }

  /// Restaura um .zip enviado. Corpo: bytes; ?configuracoes=1 para restaurar também as configurações.
  Future<Response> _restaurarDeArquivo(Request req) async {
    final bytes = await _lerBytes(req, Restauracao.tamanhoMaximo);
    if (bytes == null) return _erro(413, 'Arquivo grande demais.');
    return _restaurar(bytes, configuracoes: req.url.queryParameters['configuracoes'] == '1');
  }

  Future<Response> _restaurar(List<int> bytes, {required bool configuracoes}) async {
    final r = restauracao;
    if (r == null) return _erro(501, 'Restauração indisponível.');
    try {
      final resumo = await r.restaurar(bytes, configuracoes: configuracoes);
      return _json(resumo.toJson());
    } on FormatException catch (e) {
      return _erro(400, e.message);
    }
  }

  static Response _zip(List<int> bytes, String nome) => Response.ok(bytes, headers: {
        'content-type': 'application/zip',
        'content-disposition': 'attachment; filename="$nome"',
        'cache-control': 'no-store',
      });

  // ---------- Administração ----------

  Future<Response> _adminConfiguracoes(Request _) async {
    final c = cfg;
    if (c == null) return _erro(501, 'Configurações indisponíveis.');
    return _json({
      ...c.publicas(),
      'modo': agente != null ? 'agente' : 'local',
      'chaveAgente': agente != null ? c.chaveAgente : null,
      'urlDetectada': c.urlDetectada,
      'pastaBackup': backup.pastaDestino,
      'sessoes': auth.quantidade,
      'senhaMinima': senhaMinima,
      'agenda': agenda?.estado(),
    });
  }

  /// Corpo: os campos a alterar (ver Configuracoes.atualizar).
  Future<Response> _adminSalvar(Request req) async {
    final c = cfg;
    if (c == null) return _erro(501, 'Configurações indisponíveis.');
    final corpo = await _corpo(req);
    final urlAntes = c.urlOracao;
    final agendaAntes = '${c.agendaUrl}|${c.agendaCalendarioId}';
    try {
      await c.atualizar(corpo);
    } on FormatException catch (e) {
      return _erro(400, e.message);
    }
    // Agenda trocada ou removida: busca na hora (e descarta a cópia antiga).
    if ('${c.agendaUrl}|${c.agendaCalendarioId}' != agendaAntes) await agenda?.atualizarAgora();
    // Holyrics direto: aplica a nova conexão sem reiniciar.
    final h = holyrics;
    if (h is HolyricsDireto) h.atualizar(host: c.holyricsHost, porta: c.holyricsPorta, token: c.holyricsToken);
    // Endereço público mudou: refaz o QR (e o agente o copia para o PC da igreja).
    if (c.urlOracao != urlAntes) {
      await gravarQr(cartazes.pasta, c.urlOracao);
      await gravarQrMensagens(cartazes.pasta, c.urlMensagens);
      store.avisar('cartazes');
    }
    return _adminConfiguracoes(req);
  }

  /// Corpo: {"tipo": "mural" | "mural-desativar" | "agente"}
  Future<Response> _adminNovaChave(Request req) async {
    final c = cfg;
    if (c == null) return _erro(501, 'Configurações indisponíveis.');
    final tipo = (await _corpo(req))['tipo'];
    switch (tipo) {
      case 'mural':
        return _json({'chaveMural': await c.novaChaveMural()});
      case 'mural-desativar':
        await c.novaChaveMural(desativar: true);
        return _json({'chaveMural': null});
      case 'agente':
        if (agente == null) return _erro(400, 'O servidor não está no modo agente.');
        final nova = await c.novaChaveAgente();
        agente!.desconectar(); // o agente antigo perde o acesso na hora
        return _json({'chaveAgente': nova});
    }
    return _erro(400, 'Tipo de chave inválido.');
  }

  /// Corpo: {"atual": "...", "nova": "...", "encerrarSessoes": true}
  Future<Response> _adminSenha(Request req) async {
    final c = cfg;
    if (c == null) return _erro(501, 'Configurações indisponíveis.');
    final corpo = await _corpo(req);
    if (!auth.conferir(corpo['atual'] as String? ?? '')) return _erro(403, 'Senha atual incorreta.');
    try {
      await c.trocarSenha(corpo['nova'] as String? ?? '', minimo: senhaMinima);
    } on FormatException catch (e) {
      return _erro(400, e.message);
    }
    final saiu = corpo['encerrarSessoes'] == false ? 0 : await auth.encerrarOutras(Auth.tokenDe(req));
    return _json({'ok': true, 'sessoesEncerradas': saiu});
  }

  Future<Response> _adminEncerrarSessoes(Request req) async {
    final saiu = await auth.encerrarOutras(Auth.tokenDe(req));
    return _json({'sessoesEncerradas': saiu});
  }

  Future<Response> _adminTestarHolyrics(Request _) async {
    final r = await holyrics.chamar('GetCPInfo', '{}');
    return Response.ok(r.corpo, headers: jsonHeaders);
  }

  Future<Response> _adminTestarEmail(Request _) async {
    if (cfg?.smtpConfigurado != true) return _erro(400, 'Configure o SMTP primeiro.');
    try {
      await enviarEmailTeste(cfg!).timeout(const Duration(seconds: 10));
      return _json({'ok': true});
    } catch (e) {
      stderr.writeln('Falha no teste de SMTP: ${e.runtimeType}');
      return _erro(502, 'Não foi possível enviar. Confira os dados do SMTP e a conexão do servidor.');
    }
  }

  void _conectarWs(WebSocketChannel canal, String? _) {
    final sub = store.mudancas.listen((tipo) {
      canal.sink.add(jsonEncode({'tipo': tipo, 'versoes': store.versoes}));
    });
    canal.stream.listen((_) {}, onDone: sub.cancel, onError: (_) => sub.cancel());
  }

  // ---------- Agente do PC da igreja ----------

  bool _chaveAgenteOk(Request req) =>
      agente != null && chaveAgente.isNotEmpty && iguaisSeguro(req.url.queryParameters['chave'] ?? '', chaveAgente);

  static Response get _agenteNegado => _erro(401, 'Chave do agente inválida.');

  FutureOr<Response> _agenteWs(Request req) {
    if (!_chaveAgenteOk(req)) return _agenteNegado;
    return webSocketHandler((WebSocketChannel canal, String? _) => agente!.conectar(canal),
        pingInterval: const Duration(seconds: 25))(req);
  }

  /// Cartazes e QR que o agente deve manter na pasta de imagens do Holyrics.
  Future<Response> _agenteListarCartazes(Request req) async {
    if (!_chaveAgenteOk(req)) return _agenteNegado;
    final dir = Directory(cartazes.pasta);
    final lista = <Map<String, dynamic>>[];
    if (await dir.exists()) {
      await for (final e in dir.list()) {
        if (e is! File || !Cartazes.extensoes.contains(p.extension(e.path).toLowerCase())) continue;
        final s = await e.stat();
        lista.add({'nome': p.basename(e.path), 'tamanho': s.size, 'modificado': s.modified.toUtc().toIso8601String()});
      }
    }
    return _json(lista);
  }

  Future<Response> _agenteBaixarCartaz(Request req, String nome) async {
    if (!_chaveAgenteOk(req)) return _agenteNegado;
    nome = Uri.decodeComponent(nome);
    // O QR não é um "cartaz" para o painel, mas o agente precisa dele.
    final f = nome == arquivoQr || nome == arquivoQrMensagens ? File(p.join(cartazes.pasta, nome)) : cartazes.arquivo(nome);
    return _arquivo(f);
  }

  // ---------- Utilitários ----------

  Future<Response> _excluir(String colecao, String id) async {
    if (!await store.excluir(colecao, id)) return _erro(404, 'Não encontrado.');
    return _json({'ok': true});
  }

  Response _pagina(String nome) => _arquivo(File(p.join(pastaWeb, nome)), tipo: 'text/html; charset=utf-8');

  static Response _arquivo(File? f, {String? tipo}) {
    if (f == null || !f.existsSync()) return Response.notFound('Não encontrado');
    final ext = p.extension(f.path).toLowerCase();
    final contentType = tipo ??
        switch (ext) {
          '.png' => 'image/png',
          '.jpg' || '.jpeg' => 'image/jpeg',
          _ => 'application/octet-stream',
        };
    return Response.ok(f.openRead(), headers: {'content-type': contentType, 'cache-control': 'no-cache'});
  }

  static Future<Map<String, dynamic>> _corpo(Request req) async {
    final texto = await req.readAsString();
    if (texto.trim().isEmpty) return {};
    final j = jsonDecode(texto);
    if (j is! Map) throw const FormatException('JSON inválido');
    return Map<String, dynamic>.from(j);
  }

  static Future<Uint8List?> _lerBytes(Request req, int maximo) async {
    final b = BytesBuilder(copy: false);
    await for (final parte in req.read()) {
      b.add(parte);
      if (b.length > maximo) return null;
    }
    return b.takeBytes();
  }

  static Response _json(Object? dados, {int status = 200}) =>
      Response(status, body: jsonEncode(dados), headers: jsonHeaders);

  static Response _erro(int status, String mensagem) => _json({'erro': mensagem}, status: status);

  static Middleware get _tratarErros => (inner) => (req) async {
        try {
          return await inner(req);
        } on FormatException {
          return _erro(400, 'Dados inválidos.');
        } on TypeError {
          return _erro(400, 'Dados inválidos.');
        }
      };
}
