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
import 'agente_hub.dart';
import 'auth.dart';
import 'backup.dart';
import 'cartazes.dart';
import 'config.dart';
import 'configuracoes.dart';
import 'historico.dart';
import 'holyrics.dart';
import 'email_mensagens.dart';
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
  })  : _urlOracaoFixa = urlOracao,
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
      ..get('/', (Request _) => Response.found('/painel'))
      ..get('/oracao', (Request _) => _pagina('oracao.html'))
      ..get('/mensagens', (Request _) => _pagina('mensagens.html'))
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
      ..post('/api/login', _login)
      ..post('/api/logout', _logout)
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
      ..get('/api/motivos', (Request _) => _json(store.listar('motivos')))
      ..post('/api/motivos', _criarMotivo)
      ..put('/api/motivos/<id>', _atualizarMotivo)
      ..post('/api/motivos/<id>/aprovar', _aprovarMotivo)
      ..delete('/api/motivos/<id>', (Request _, String id) => _excluir('motivos', id))
      // Membros / aniversariantes
      ..get('/api/membros', (Request _) => _json(store.listar('membros')))
      ..post('/api/membros', _criarMembro)
      ..post('/api/membros/importar', _importarMembros)
      ..put('/api/membros/<id>', _atualizarMembro)
      ..delete('/api/membros/<id>', (Request _, String id) => _excluir('membros', id))
      // Cartazes
      ..get('/api/cartazes', _listarCartazes)
      ..post('/api/cartazes', _enviarCartaz)
      ..delete('/api/cartazes/<nome>', _excluirCartaz)
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
      ..post('/api/admin/agenda/atualizar', _adminAgendaAtualizar)
      ..post('/api/admin/agenda/testar', _adminAgendaTestar)
      ..get('/ws', webSocketHandler(_conectarWs));

    final estaticos = createStaticHandler(pastaWeb);
    final cascata = Cascade().add(r.call).add(estaticos).handler;
    return const Pipeline()
        .addMiddleware(_cabecalhosSeguranca)
        .addMiddleware(_tratarErros)
        .addMiddleware(auth.middleware(_rotaPublica))
        .addHandler(cascata);
  }

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
      final token = await auth.login(corpo['senha'] as String? ?? '', _ip(req));
      if (token == null) return _erro(401, 'Senha incorreta.');
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
    final corpo = await _corpo(req);
    // Origem e data de criação não mudam; a data de atendimento é do servidor.
    final motivo = Motivo.fromJson({
      ...atual,
      ...corpo,
      'id': id,
      'origem': atual['origem'],
      'criadoEm': atual['criadoEm'],
      'atendidoEm': atual['atendidoEm'],
    });
    final antes = StatusMotivo.fromName(atual['status'] as String?);
    if (motivo.atendido && antes != StatusMotivo.atendido) motivo.atendidoEm = _agora();
    if (!motivo.atendido) motivo.atendidoEm = null;
    final erro = _validarMotivo(motivo);
    if (erro != null) return _erro(400, erro);
    await store.salvar('motivos', motivo.toJson());
    return _json(motivo.toJson());
  }

  Future<Response> _aprovarMotivo(Request _, String id) async {
    final atual = store.buscar('motivos', id);
    if (atual == null) return _erro(404, 'Motivo não encontrado.');
    final m = Motivo.fromJson(atual)..status = StatusMotivo.pendente;
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

  Future<Response> _criarMembro(Request req) async {
    final corpo = await _corpo(req);
    final m = Membro.fromJson({...corpo, 'id': novoId()});
    final erro = _validarMembro(m);
    if (erro != null) return _erro(400, erro);
    await store.salvar('membros', m.toJson());
    return _json(m.toJson(), status: 201);
  }

  Future<Response> _atualizarMembro(Request req, String id) async {
    final atual = store.buscar('membros', id);
    if (atual == null) return _erro(404, 'Membro não encontrado.');
    final m = Membro.fromJson({...atual, ...await _corpo(req), 'id': id});
    final erro = _validarMembro(m);
    if (erro != null) return _erro(400, erro);
    await store.salvar('membros', m.toJson());
    return _json(m.toJson());
  }

  /// Corpo em texto: uma linha "Nome;dd/mm" por membro. Não duplica nome + data já cadastrados.
  Future<Response> _importarMembros(Request req) async {
    final lido = lerCsvMembros(await req.readAsString());
    final existentes = store.listar('membros').map((m) => '${(m['nome'] as String).toLowerCase()}|${m['dia']}|${m['mes']}').toSet();
    final novos = <Map<String, dynamic>>[];
    for (final m in lido.membros) {
      final chave = '${m.nome.toLowerCase()}|${m.dia}|${m.mes}';
      if (!existentes.add(chave)) continue;
      novos.add(Membro(id: novoId(), nome: m.nome, dia: m.dia, mes: m.mes).toJson());
    }
    if (novos.isNotEmpty) await store.salvarVarios('membros', novos);
    return _json({'importados': novos.length, 'linhasComErro': lido.linhasComErro});
  }

  static String? _validarMembro(Membro m) {
    if (m.nome.trim().isEmpty) return 'Informe o nome.';
    if (m.nome.length > 100) return 'Nome muito longo.';
    if (!Membro.dataValida(m.dia, m.mes)) return 'Data de aniversário inválida.';
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

  // ---------- Holyrics / backup / tempo real ----------

  Future<Response> _holyrics(Request req, String acao) async {
    if (!acoesPermitidas.contains(acao)) return _erro(403, 'Ação não permitida: $acao');
    return _chamarHolyrics(acao, await req.readAsString());
  }

  /// Chama o Holyrics e, se deu certo, registra no histórico.
  Future<Response> _chamarHolyrics(String acao, String corpo) async {
    final r = await holyrics.chamar(acao, corpo);
    if (_ok(r.corpo) && Historico.acoes.contains(acao)) {
      await historico.registrar(acao, corpo);
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
      'eventos': [
        for (final e in a?.proximos(dias: dias) ?? const <Evento>[])
          {
            ...e.toJson(),
            // Textos prontos para o painel web.
            'dia': diaPorExtenso(e.inicio),
            'horario': horario(e),
            'textoRecado': textoRecadoDoEvento(e),
          },
      ],
    });
  }

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
      urlCartaz: (caminho) {
        const prefixo = '${Config.subpastaHolyrics}/';
        if (!caminho.startsWith(prefixo)) return null;
        final nome = caminho.substring(prefixo.length);
        return cartazes.arquivo(nome)?.existsSync() == true ? '/cartazes/${Uri.encodeComponent(nome)}' : null;
      },
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
    final agendaAntes = c.agendaUrl;
    try {
      await c.atualizar(corpo);
    } on FormatException catch (e) {
      return _erro(400, e.message);
    }
    // Agenda trocada ou removida: busca na hora (e descarta a cópia antiga).
    if (c.agendaUrl != agendaAntes) await agenda?.atualizarAgora();
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
