import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:diako_core/diako_core.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'auth.dart';
import 'backup.dart';
import 'cartazes.dart';
import 'config.dart';
import 'historico.dart';
import 'holyrics.dart';
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
    required this.urlOracao,
    required this.cartazesNoHolyrics,
    required this.historico,
    DateTime Function()? relogio,
    LimiteTaxa? limitePedidos,
  })  : _agora = relogio ?? DateTime.now,
        _limitePedidos = limitePedidos ?? LimiteTaxa(maximo: 5, janela: const Duration(minutes: 10));

  final Historico historico;
  final Store store;
  final Auth auth;
  final HolyricsProxy holyrics;
  final Cartazes cartazes;
  final Backup backup;
  final String pastaWeb;
  final String urlOracao;

  /// false quando "pastaImagensHolyrics" não foi configurada (cartazes ficam em data/cartazes).
  final bool cartazesNoHolyrics;
  final DateTime Function() _agora;
  final LimiteTaxa _limitePedidos;

  /// Caminho do QR para o ShowImage do Holyrics.
  static const qrHolyrics = '${Config.subpastaHolyrics}/$arquivoQr';

  Handler get handler {
    final r = Router()
      ..get('/', (Request _) => Response.found('/painel'))
      ..get('/oracao', (Request _) => _pagina('oracao.html'))
      ..get('/painel', (Request _) => _pagina('painel.html'))
      ..get('/mural', (Request _) => _pagina('mural.html'))
      ..get('/api/public/mural', _mural)
      ..get('/qr-oracao.png', (Request _) => _arquivo(File(p.join(cartazes.pasta, arquivoQr))))
      ..get('/cartazes/<nome>', (Request _, String nome) => _arquivo(cartazes.arquivo(nome)))
      ..post('/api/login', _login)
      ..post('/api/logout', _logout)
      ..post('/api/public/pedidos', _novoPedido)
      ..get('/api/estado', _estado)
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
      ..get('/ws', webSocketHandler(_conectarWs));

    final estaticos = createStaticHandler(pastaWeb);
    final cascata = Cascade().add(r.call).add(estaticos).handler;
    return const Pipeline()
        .addMiddleware(_tratarErros)
        .addMiddleware(auth.middleware(_rotaPublica))
        .addHandler(cascata);
  }

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
      final token = await auth.login(corpo['senha'] as String? ?? '', ipDe(req));
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
      'versoes': store.versoes,
      'holyricsConectado': await holyrics.conectado(),
      'urlOracao': urlOracao,
      'qrHolyrics': qrHolyrics,
      'cartazesNoHolyrics': cartazesNoHolyrics,
      'backupConfigurado': backup.configurado,
      'ultimoBackup': ultimo?.toIso8601String(),
      'aguardandoAprovacao':
          store.listar('motivos').where((m) => m['status'] == StatusMotivo.aguardando.name).length,
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
    if (!_limitePedidos.permitir(ipDe(req))) {
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
    final respondidas = oracoesRespondidas(_motivos(), _agora(), dias: (corpo['dias'] as num?)?.toInt() ?? 30);
    if (respondidas.isEmpty) return _erro(400, 'Nenhuma oração respondida (pública) nos últimos dias.');
    final slides = montarSlidesGratidao(respondidas, porSlide: (corpo['porSlide'] as num?)?.toInt() ?? 3);
    final segundos = (corpo['segundos'] as num?)?.toInt() ?? 10;
    final tema = corpo['tema'] as String? ?? '';
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
          urlPedidos: urlOracao,
        ),
      });

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
    );
    return _json({'atualizado': _agora().toIso8601String(), 'slides': [for (final s in slides) s.toJson()]});
  }

  Future<Response> _backupAgora(Request _) async {
    if (!backup.configurado) return _erro(400, 'Defina "pastaBackup" no config.json do servidor.');
    final f = await backup.executar();
    return _json({'arquivo': f.path});
  }

  void _conectarWs(WebSocketChannel canal, String? _) {
    final sub = store.mudancas.listen((tipo) {
      canal.sink.add(jsonEncode({'tipo': tipo, 'versoes': store.versoes}));
    });
    canal.stream.listen((_) {}, onDone: sub.cancel, onError: (_) => sub.cancel());
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
