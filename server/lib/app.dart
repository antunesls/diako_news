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
import 'backup_cifrado.dart';
import 'cartazes.dart';
import 'config.dart';
import 'configuracoes.dart';
import 'escala_pdf.dart';
import 'historico.dart';
import 'holyrics.dart';
import 'email_mensagens.dart';
import 'fotos_membros.dart';
import 'galeria.dart';
import 'lgpd.dart';
import 'pagina_inicial.dart';
import 'permissoes.dart';
import 'repertorio.dart';
import 'usuarios.dart';
import 'qr_oracao.dart';
import 'store.dart';
import 'tablets_locais.dart';

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
    TermosAssinados? termosAssinados,
    TabletsLocais? tabletsLocais,
    SenhaBackup? senhaBackup,
  })  : galeria = galeria ?? Galeria(store.pasta),
        senhaBackup = senhaBackup ?? SenhaBackup(backup.pastaDados),
        fotosMembros = fotosMembros ?? FotosMembros(store.pasta),
        termosAssinados = termosAssinados ?? TermosAssinados(store.pasta),
        tabletsLocais = tabletsLocais ?? TabletsLocais(store.pasta),
        _urlOracaoFixa = urlOracao,
        _chaveAgenteFixa = chaveAgente,
        _chaveMuralFixa = chaveMural,
        _agora = relogio ?? DateTime.now,
         _limitePedidos = limitePedidos ?? LimiteTaxa(maximo: 5, janela: const Duration(minutes: 10)) {
    // No modo agente, cada mudança nos cartazes é copiada para o PC da igreja.
    if (agente != null) {
      store.mudancas.where((t) => t == 'cartazes').listen((_) => agente!.pedirSincronizacao());
      agente!
        ..tablets = _tabletsParaAgente
        ..aoReceberHistorico = _historicoDoAgente
        ..aoCopiarBackup = backup.registrarCopiaPc;
      // Cada backup gravado também vai para o PC da igreja (fora do servidor).
      backup.aoGravar = (_) => agente!.pedirCopiaBackup();
    }
  }

  /// Tablets pareados com o agente da rede local (data/tablets-locais.json).
  final TabletsLocais tabletsLocais;

  /// Senha da cópia cifrada do backup no PC da igreja (sem ela, a cópia fica desligada).
  final SenhaBackup senhaBackup;

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

  /// Termos da LGPD assinados em papel (data/termos-lgpd) — nunca públicos.
  final TermosAssinados termosAssinados;
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
  final LimiteTaxa _limiteLgpd = LimiteTaxa(maximo: 20, janela: const Duration(minutes: 10));
  final LimiteTaxa _limiteVisitantes = LimiteTaxa(maximo: 5, janela: const Duration(minutes: 10));
  List<Map<String, String>> _temasCache = [];
  DateTime? _temasAtualizados;

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
      // LGPD: autorização pelo link (token no #, nunca na URL) e cadastro de visitante pelo QR.
      ..get('/autorizar', (Request _) => _pagina('autorizar.html'))
      ..get('/minha-escala', (Request _) => _pagina('minha-escala.html'))
      ..get('/recepcao', (Request _) => _pagina('recepcao.html'))
      ..get('/visitante', (Request _) => cfg?.visitanteQrAtivo == false ? _paginaDesligada() : _pagina('visitante.html'))
      ..get('/qr-visitante.png', _qrVisitante)
      ..get('/qr-minha-escala.png', (Request _) => Response.ok(gerarPngQr('$_urlBase/minha-escala', rotulo: 'MINHA ESCALA'),
          headers: {'content-type': 'image/png', 'cache-control': 'no-cache'}))
      ..post('/api/public/autorizacao', _verAutorizacao)
      ..post('/api/public/autorizacao/aceitar', _aceitarAutorizacao)
      ..get('/api/public/visitante', _infoVisitante)
      ..get('/api/public/termo-lgpd', (Request _) => _json({'versao': _termo.versao, 'texto': _termo.texto, 'igreja': _termo.igreja}))
      ..post('/api/public/visitante', _novoVisitantePublico)
      ..get(ajudaAgenda, (Request _) => _pagina('ajuda-agenda.html'))
      ..get('/ajuda/usuarios', (Request _) => _pagina('ajuda-usuarios.html'))
      ..get('/ajuda/rede-local', (Request _) => _pagina('ajuda-rede-local.html'))
      ..get('/ajuda/visitantes', (Request _) => _pagina('ajuda-visitantes.html'))
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
      ..get('/agente/backups', _agenteListarBackups)
      ..get('/agente/backups/<nome>', _agenteBaixarBackup)
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
      ..get('/api/acessos-escala', _listarAcessosEscala)
      ..post('/api/acessos-escala', _criarAcessoEscala)
      ..post('/api/acessos-escala/vincular', _vincularAcessoEscala)
      ..post('/api/acessos-escala/<id>/senha', _senhaAcessoEscala)
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
      ..get('/api/membros', (Request _) => _json([for (final m in _listaMembros()) _membroParaPainel(m.toJson())]))
      ..get('/api/membros/exportar', _exportarMembros)
      ..get('/api/membros/termo-lgpd', (Request _) => _json({'versao': _termo.versao, 'texto': _termo.texto, 'igreja': _termo.igreja}))
      ..post('/api/membros', _criarMembro)
      ..post('/api/membros/importar', _importarMembros)
      ..put('/api/membros/<id>', _atualizarMembro)
      ..delete('/api/membros/<id>', _excluirMembro)
      ..post('/api/membros/<id>/foto', _enviarFotoMembro)
      ..delete('/api/membros/<id>/foto', _removerFotoMembro)
      ..get('/api/membros/<id>/foto', (Request _, String id) => _fotoMembro(id, miniatura: false))
      ..get('/api/membros/<id>/foto-miniatura', (Request _, String id) => _fotoMembro(id, miniatura: true))
      ..post('/api/membros/<id>/lgpd/link', _linkLgpd)
      ..post('/api/membros/<id>/lgpd/termo', _anexarTermo)
      ..get('/api/membros/<id>/lgpd/termo', _verTermoAssinado)
      ..post('/api/membros/<id>/lgpd/revogar', _revogarLgpd)
      // Visitas (QR, obreiro da recepção, painel) e boas-vindas no culto
      ..get('/api/visitas', _listarVisitas)
      ..post('/api/visitas', _criarVisita)
      ..post('/api/visitas/<id>/mencionada', _visitaMencionada)
      ..put('/api/visitas/<id>/contato', _contatoVisita)
      ..post('/api/projetar/boas-vindas', _projetarBoasVindas)
      // Escalas dos pastores e do louvor (rotas fixas antes das com <id>)
      ..get('/api/repertorio', _listarRepertorio)
      ..post('/api/repertorio/importar/previa', _previaRepertorio)
      ..post('/api/repertorio/importar', _importarRepertorio)
      ..post('/api/repertorio', _criarMusicaRepertorio)
      ..put('/api/repertorio/<id>', _editarMusicaRepertorio)
      ..get('/api/escalas', _listarEscalas)
      ..get('/api/escalas/hoje', _escalaDeHoje)
      ..get('/api/escalas/pdf', _escalaPdf)
      ..post('/api/escalas', _criarCulto)
      ..post('/api/escalas/gerar', _gerarCultos)
       ..post('/api/escalas/repetir', _repetirEscala)
       ..get('/api/escalas/indisponibilidades', _listarTodasIndisponibilidades)
       ..post('/api/escalas/indisponibilidades', _criarIndisponibilidade)
      ..delete('/api/escalas/indisponibilidades/<id>', _excluirIndisponibilidade)
      ..put('/api/escalas/<id>', _atualizarCulto)
      ..delete('/api/escalas/<id>', _excluirCulto)
      ..get('/api/minha-escala', _minhaEscala)
      ..post('/api/minha-escala/indisponivel', _minhaIndisponibilidade)
      ..post('/api/minha-escala/indisponivel/remover', _removerMinhaIndisponibilidade)
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
      // Tablet falando direto com o agente na rede da igreja (pareamento feito com internet)
      ..post('/api/agente-local/parear', _parearTablet)
      ..delete('/api/agente-local/<id>', _desparearTablet)
      ..get('/api/admin/tablets-locais', _listarTabletsLocais)
      ..delete('/api/admin/tablets-locais/<id>', _removerTabletLocal)
       ..get('/api/temas', _adminTemas)
       ..get('/api/admin/temas', _adminTemas)
      ..post('/api/projetar/oracoes-respondidas', _projetarRespondidas)
      ..get('/api/historico', _historico)
      ..get('/api/resumo-semanal', _resumoSemanal)
      ..post('/api/backup', _backupAgora)
      ..put('/api/backup/senha', _definirSenhaBackup)
      ..delete('/api/backup/senha', _removerSenhaBackup)
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
      if (u.perfil != perfilAntes || u.ativo != ativoAntes) {
        await auth.encerrarDoUsuario(id);
        agente?.enviarTablets(); // sem "projetar" ou desativado: o tablet perde o acesso local
      }
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
    await tabletsLocais.removerDoUsuario(id);
    agente?.enviarTablets();
    return _json({'ok': true});
  }

  // A Secretaria administra somente contas de integrantes e pode vincular uma
  // conta pastoral já existente. Jamais devolvemos hashes ou contas de outros perfis.
  Response _listarAcessosEscala(Request _) => _json({
        'usuarios': [
          for (final u in _usuarios?.lista ?? const <Usuario>[])
            if (u.perfil == Perfil.integrante || u.perfil == Perfil.pastor)
              {'id': u.id, 'nome': u.nome, 'login': u.login, 'perfil': u.perfil.name, 'membroId': u.membroId, 'ativo': u.ativo},
        ],
      });

  Future<Response> _criarAcessoEscala(Request req) async {
    final usuarios = _usuarios;
    if (usuarios == null) return _erro(501, 'Usuários indisponíveis.');
    final corpo = await _corpo(req);
    final id = corpo['membroId'] as String? ?? '';
    if (store.buscar('membros', id) == null) return _erro(404, 'Membro não encontrado.');
    if (usuarios.porMembro(id) != null) return _erro(400, 'Este membro já tem acesso.');
    final senha = gerarSenhaTemporaria(senhaMinima < 10 ? 10 : senhaMinima);
    try {
      final u = await usuarios.criar(nome: corpo['nome'] as String? ?? '', login: corpo['login'] as String? ?? '',
          perfil: Perfil.integrante, senha: senha, membroId: id);
      return _json({'usuario': u.toJson(), 'senhaTemporaria': senha}, status: 201);
    } on FormatException catch (e) {
      return _erro(400, e.message);
    }
  }

  Future<Response> _vincularAcessoEscala(Request req) async {
    final usuarios = _usuarios;
    final corpo = await _corpo(req);
    final id = corpo['membroId'] as String? ?? '';
    final u = usuarios?.buscar(corpo['usuarioId'] as String? ?? '');
    if (store.buscar('membros', id) == null || u == null) return _erro(404, 'Membro ou usuário não encontrado.');
    if (u.perfil != Perfil.pastor && u.perfil != Perfil.integrante) return _erro(403, 'Não é uma conta de escalas.');
    if (u.membroId != null && u.membroId != id) return _erro(400, 'Esta conta já está vinculada a outro membro.');
    try {
      return _json((await usuarios!.vincular(u.id, id)).toJson());
    } on FormatException catch (e) {
      return _erro(400, e.message);
    }
  }

  Future<Response> _senhaAcessoEscala(Request req, String id) async {
    final u = _usuarios?.buscar(id);
    if (u == null || u.perfil != Perfil.integrante || u.membroId == null || store.buscar('membros', u.membroId!) == null) {
      return _erro(404, 'Acesso não encontrado.');
    }
    return _redefinirSenhaUsuario(req, id);
  }

  // ---------- Tablets na rede local ----------

  /// Conta ativa dona do pareamento, ou null (excluída, desativada ou sem "projetar").
  Conta? _contaDoTablet(TabletLocal t) {
    if (t.usuario == Auth.idPrincipal) return Conta.principal;
    final u = _usuarios?.buscar(t.usuario);
    if (u == null || !u.ativo || !u.perfil.pode(Permissao.projetar)) return null;
    return Conta(id: u.id, nome: u.nome, login: u.login, perfil: u.perfil);
  }

  /// O que o agente precisa para conferir os tablets sem internet: só o hash do token.
  List<Map<String, dynamic>> _tabletsParaAgente() => [
        for (final t in tabletsLocais.lista)
          if (_contaDoTablet(t) case final c?) {'id': t.id, 'hash': t.hash, 'nome': '${c.nome} (${t.aparelho})'},
      ];

  /// Corpo: {"aparelho": "Tablet do púlpito"}. Devolve o token uma única vez.
  Future<Response> _parearTablet(Request req) async {
    if (agente == null) return _erro(400, 'O servidor não está no modo agente: o tablet já fala com ele pela rede.');
    final conta = Auth.contaDa(req)!;
    final corpo = await _corpo(req);
    try {
      final r = await tabletsLocais.parear(usuario: conta.id, aparelho: corpo['aparelho'] as String? ?? '');
      agente!.enviarTablets();
      return _json({'id': r.tablet.id, 'token': r.token, 'agenteConectado': agente!.agenteConectado}, status: 201);
    } on FormatException catch (e) {
      return _erro(400, e.message);
    }
  }

  /// O próprio tablet desfaz o pareamento (ou o administrador).
  Future<Response> _desparearTablet(Request req, String id) async {
    final conta = Auth.contaDa(req)!;
    final t = tabletsLocais.buscar(id);
    if (t == null) return _json({'ok': true});
    if (t.usuario != conta.id && !conta.pode(Permissao.admin)) return _erro(403, 'Este pareamento é de outra conta.');
    await tabletsLocais.remover(id);
    agente?.enviarTablets();
    return _json({'ok': true});
  }

  Response _listarTabletsLocais(Request _) => _json({
        'modoAgente': agente != null,
        'tablets': [
          for (final t in tabletsLocais.lista)
            {
              'id': t.id,
              'aparelho': t.aparelho,
              'conta': _contaDoTablet(t)?.nome ?? _usuarios?.buscar(t.usuario)?.nome ?? '(conta excluída)',
              'ativo': _contaDoTablet(t) != null,
              'criadoEm': t.criadoEm.toIso8601String(),
            },
        ],
      });

  Future<Response> _removerTabletLocal(Request _, String id) async {
    if (!await tabletsLocais.remover(id)) return _erro(404, 'Tablet não encontrado.');
    agente?.enviarTablets();
    return _json({'ok': true});
  }

  /// Projeções feitas pela rede local enquanto o servidor não via; [eventos] vêm do agente.
  Future<List<String>> _historicoDoAgente(List<Map<String, dynamic>> eventos) async {
    final aceitos = <String>[];
    final agora = _agora();
    for (final e in eventos.take(200)) {
      final id = e['id'];
      if (id is! String || id.isEmpty || id.length > 64) continue;
      aceitos.add(id); // inválidos também saem da fila: reenviar não os conserta
      final acao = e['acao'], corpo = e['corpo'];
      var quando = DateTime.tryParse(e['quando'] as String? ?? '');
      if (acao is! String || corpo is! String || corpo.length > 100000 || !acoesPermitidas.contains(acao) || quando == null) continue;
      if (quando.isAfter(agora)) quando = agora;
      final t = tabletsLocais.buscar(e['tablet'] as String? ?? '');
      final nome = t == null ? '' : (_contaDoTablet(t)?.nome ?? _usuarios?.buscar(t.usuario)?.nome ?? '');
      await historico.registrar(acao, corpo, usuario: nome, quando: quando.toLocal(), via: 'rede local');
    }
    if (aceitos.isNotEmpty) store.avisar('historico');
    return aceitos;
  }

  // ---------- Estado ----------

  Future<Response> _estado(Request _) async {
    final ultimo = await backup.ultimo();
    final situacao = await _situacaoBackup();
    return _json({
      'versao': versao,
      'versoes': store.versoes,
      'holyricsConectado': await holyrics.conectado(),
      'urlOracao': urlOracao,
      'qrHolyrics': qrHolyrics,
      'urlMensagens': cfg?.urlMensagens ?? urlOracao.replaceFirst(RegExp(r'/oracao$'), '/mensagens'),
      'urlVisitante': '$_urlBase/visitante',
      'visitanteQrAtivo': cfg?.visitanteQrAtivo ?? true,
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
      'alertasBackup': situacao.alertas,
      'copiaBackupPc': situacao.copiaPc,
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
    final notaInterna = Auth.contaDa(req)?.pode(Permissao.motivosEditar) ?? false;
    return _json([
      for (final m in store.listar('motivos'))
        if (completo) m else if (m['publico'] != false) {
          for (final entry in m.entries) if (entry.key != 'observacao' || notaInterna) entry.key: entry.key == 'enviadoPor' ? '' : entry.value,
        },
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
    if (m.observacao.length > 500) return 'Observação muito longa (máximo 500 caracteres).';
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
    if (corpo.isEmpty || corpo.keys.any((k) => k != 'status' && k != 'observacao') ||
        (corpo.containsKey('status') && !Mensagem.statusValidos.contains(corpo['status'])) ||
        (corpo.containsKey('observacao') && (corpo['observacao'] is! String || (corpo['observacao'] as String).length > 500))) {
      return _erro(400, 'Informe um status válido ou uma observação de até 500 caracteres.');
    }
    final novo = {...atual, ...corpo};
    await store.salvar('mensagens', novo);
    return _json(novo);
  }

  // ---------- Membros ----------

  /// Membros normalizados: documentos antigos (só nome/dia/mês/ativo) ganham status.
  List<Membro> _listaMembros() => store.listar('membros').map(Membro.fromJson).toList();

  /// O que o painel recebe: sem o hash do link de autorização, só até quando ele vale.
  Map<String, dynamic> _membroParaPainel(Map<String, dynamic> doc) {
    final convite = doc['conviteLgpd'] as Map?;
    final expira = DateTime.tryParse(convite?['expiraEm'] as String? ?? '');
    return {
      for (final e in doc.entries)
        if (e.key != 'conviteLgpd') e.key: e.value,
      if (expira != null && expira.isAfter(_agora())) 'linkLgpdValidoAte': expira.toIso8601String(),
    };
  }

  /// Valida o corpo e monta o membro pronto para gravar. [base] é o documento atual
  /// (edição) ou vazio (criação). Lança [FormatException] com a mensagem para o painel.
  Membro _montarMembro(Map<String, dynamic> corpo, Map<String, dynamic> base, String id, {String? por}) {
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
    // Foto (rotas próprias), histórico, datas de controle e a prova da LGPD são do servidor, não do corpo.
    final editavel = {...corpo}
      ..remove('foto')
      ..remove('historicoStatus')
      ..remove('criadoEm')
      ..remove('atualizadoEm')
      ..remove('consentimentoVia')
      ..remove('consentimentoRegistro')
      ..remove('termoAssinado')
      ..remove('consentimentoRevogado')
      ..remove('conviteLgpd');
    // Data da autorização digitada pela secretaria: vale como registro manual, com quem digitou.
    if (editavel.containsKey('consentimentoEm')) {
      final nova = Membro.dataDe(editavel['consentimentoEm']);
      if (nova != anterior?.consentimentoEm) {
        final via = anterior?.consentimentoVia;
        if (anterior?.consentimentoEm != null && via != null && via != ViaConsentimento.manual) {
          throw const FormatException(
              'Esta autorização foi dada pela própria pessoa (link, termo assinado ou recepção) e não pode ser editada. '
              'Para desfazer, use "Registrar revogação" na ficha.');
        }
        if (nova != null && !Membro.dataIsoValida(nova)) {
          throw const FormatException('Data da autorização inválida: não pode ser no futuro.');
        }
        editavel['consentimentoVia'] = nova == null ? null : ViaConsentimento.manual;
        editavel['consentimentoRegistro'] = nova == null
            ? null
            : {'em': _agora().toUtc().toIso8601String(), if (por != null) 'por': por, 'versaoTermo': _termo.versao};
      }
    }
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
      final m = _montarMembro(await _corpo(req), {}, novoId(), por: Auth.contaDa(req)?.nome);
      await store.salvar('membros', m.toJson());
      await _sincronizarConjuge(null, m);
      return _json(_membroParaPainel(m.toJson()), status: 201);
    } on FormatException catch (e) {
      return _erro(400, e.message);
    }
  }

  Future<Response> _atualizarMembro(Request req, String id) async {
    final atual = store.buscar('membros', id);
    if (atual == null) return _erro(404, 'Membro não encontrado.');
    try {
      final m = _montarMembro(await _corpo(req), atual, id, por: Auth.contaDa(req)?.nome);
      await store.salvar('membros', m.toJson());
      await _sincronizarConjuge(Membro.fromJson(atual), m);
      return _json(_membroParaPainel(m.toJson()));
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
    await termosAssinados.excluir(m.termoAssinado);
    // As visitas da pessoa saem junto (o histórico de visitas é dela).
    for (final v in store.listar('visitas').where((v) => v['membroId'] == id).toList()) {
      await store.excluir('visitas', v['id'] as String);
    }
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
      return _json(_membroParaPainel(doc), status: 201);
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
    return _json(_membroParaPainel(doc));
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

  // ---------- LGPD: autorização pelo link, termo assinado e cadastro pelo QR ----------

  static const _validadeLinkLgpd = Duration(days: 7);

  /// Termo em vigor (com a versão que vai junto de cada autorização).
  ({String texto, int versao, String igreja}) get _termo {
    final c = cfg;
    if (c == null) {
      const igreja = Configuracoes.nomeIgrejaPadrao;
      return (texto: termoLgpdPadrao(igreja), versao: 1, igreja: igreja);
    }
    return (texto: c.termoLgpdTexto, versao: c.termoLgpdVersao, igreja: c.nomeIgreja);
  }

  String get _urlBase => cfg?.urlBase ?? urlOracao.replaceFirst(RegExp(r'/oracao$'), '');

  String _hoje() {
    final d = _agora();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// De onde veio o aceite (fica na prova): IP e navegador, cortado para caber.
  Map<String, dynamic> _origem(Request req) {
    final navegador = req.headers['user-agent'] ?? '';
    return {'ip': _ip(req), if (navegador.isNotEmpty) 'navegador': navegador.length > 200 ? navegador.substring(0, 200) : navegador};
  }

  /// POST /api/membros/<id>/lgpd/link — link de uso único (7 dias) para a pessoa autorizar.
  /// Gerar outro invalida o anterior. O token vai depois do "#" e só o hash fica guardado.
  Future<Response> _linkLgpd(Request req, String id) async {
    final atual = store.buscar('membros', id);
    if (atual == null) return _erro(404, 'Membro não encontrado.');
    final token = novoTokenLgpd();
    final agora = _agora();
    final expira = agora.add(_validadeLinkLgpd);
    await store.salvar('membros', {
      ...atual,
      'conviteLgpd': {
        'hash': hashTokenLgpd(token),
        'criadoEm': agora.toIso8601String(),
        'expiraEm': expira.toUtc().toIso8601String(),
        if (Auth.contaDa(req)?.nome case final por?) 'por': por,
      },
    });
    return _json({'url': '$_urlBase/autorizar#$token', 'validoAte': expira.toUtc().toIso8601String()}, status: 201);
  }

  /// Membro dono do token (null: não existe, já foi usado ou outro link foi gerado depois).
  ({Map<String, dynamic> doc, bool vencido})? _conviteDo(Object? token) {
    if (token is! String || token.length < 20 || token.length > 100) return null;
    final hash = hashTokenLgpd(token);
    for (final doc in store.listar('membros')) {
      final convite = doc['conviteLgpd'];
      if (convite is Map && convite['hash'] == hash) {
        final expira = DateTime.tryParse(convite['expiraEm'] as String? ?? '');
        return (doc: doc, vencido: expira == null || !expira.isAfter(_agora()));
      }
    }
    return null;
  }

  Response? _problemaNoConvite(({Map<String, dynamic> doc, bool vencido})? achado) {
    if (achado == null) {
      // 410 e não 404: o Cascade trata 404 como "rota inexistente" e a mensagem se perderia.
      return _erro(410, 'Este link não vale mais: já foi usado ou a secretaria gerou um novo. Peça outro à secretaria da igreja.');
    }
    if (achado.vencido) return _erro(410, 'Este link venceu. Peça um novo à secretaria da igreja.');
    return null;
  }

  /// O que a pessoa vê antes de autorizar: o termo e quais dados a igreja guarda dela.
  /// Os valores vão mascarados: o link pode ser repassado sem querer.
  static List<Map<String, String>> _dadosGuardados(Membro m) {
    String? fimTelefone(String? t) {
      final d = (t ?? '').replaceAll(RegExp(r'\D'), '');
      return d.length < 4 ? null : 'terminado em ${d.substring(d.length - 4)}';
    }

    String? emailMascarado(String? e) {
      if (e == null || !e.contains('@')) return null;
      final [usuario, dominio] = e.split('@');
      return '${usuario.isEmpty ? '' : usuario[0]}•••@$dominio';
    }

    final itens = <String, String?>{
      'Nome': m.nome,
      'Aniversário': m.aniversario,
      'Telefone': fimTelefone(m.telefone),
      'WhatsApp': fimTelefone(m.whatsapp),
      'E-mail': emailMascarado(m.email),
      'Endereço': [m.bairro, m.cidade].whereType<String>().join(', ').isEmpty
          ? (m.rua != null || m.cep != null ? 'cadastrado' : null)
          : [m.bairro, m.cidade].whereType<String>().join(', '),
      'CPF': m.cpf == null ? null : 'cadastrado',
      'RG': m.rg == null ? null : 'cadastrado',
      'Foto': m.foto == null ? null : 'cadastrada',
      'Situação na igreja': m.status.nome,
      'Ministérios': m.ministerios.isEmpty ? null : m.ministerios.join(', '),
      'Família': m.conjugeId != null || m.paisIds.isNotEmpty ? 'vínculos com outras pessoas cadastradas' : null,
      'Contato de emergência': m.emergenciaNome == null ? null : 'cadastrado',
    };
    return [
      for (final e in itens.entries)
        if (e.value != null && e.value!.isNotEmpty) {'rotulo': e.key, 'valor': e.value!},
    ];
  }

  /// POST /api/public/autorizacao  {token} — dados da página /autorizar.
  Future<Response> _verAutorizacao(Request req) async {
    if (!_limiteLgpd.permitir(_ip(req))) return _erro(429, 'Muitas tentativas. Aguarde alguns minutos.');
    final achado = _conviteDo((await _corpo(req))['token']);
    final problema = _problemaNoConvite(achado);
    if (problema != null) return problema;
    final m = Membro.fromJson(achado!.doc);
    final idade = m.idadeEm(_agora());
    return _json({
      'igreja': _termo.igreja,
      'termo': {'versao': _termo.versao, 'texto': _termo.texto},
      'nome': m.nome,
      'menor': idade != null && idade < 18,
      'dados': _dadosGuardados(m),
      'jaAutorizou': m.consentimentoEm != null,
    });
  }

  /// POST /api/public/autorizacao/aceitar  {token, autorizo: true, responsavel?}
  Future<Response> _aceitarAutorizacao(Request req) async {
    if (!_limiteLgpd.permitir(_ip(req))) return _erro(429, 'Muitas tentativas. Aguarde alguns minutos.');
    final corpo = await _corpo(req);
    final achado = _conviteDo(corpo['token']);
    final problema = _problemaNoConvite(achado);
    if (problema != null) return problema;
    if (corpo['autorizo'] != true) return _erro(400, 'Marque "Li e autorizo" para confirmar.');
    final m = Membro.fromJson(achado!.doc);
    final idade = m.idadeEm(_agora());
    final responsavel = (corpo['responsavel'] as String? ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (responsavel.length > 100) return _erro(400, 'Nome do responsável muito longo.');
    if (idade != null && idade < 18 && responsavel.isEmpty) {
      return _erro(400, 'Como ${m.nome} tem menos de 18 anos, informe o nome do pai, da mãe ou do responsável que autoriza.');
    }
    final atual = store.buscar('membros', m.id)!;
    await store.salvar('membros', {
      for (final e in atual.entries)
        if (e.key != 'conviteLgpd') e.key: e.value, // uso único
      'consentimentoEm': _hoje(),
      'consentimentoVia': ViaConsentimento.link,
      'consentimentoRegistro': {
        'em': _agora().toUtc().toIso8601String(),
        'versaoTermo': _termo.versao,
        ..._origem(req),
        if (responsavel.isNotEmpty) 'responsavel': responsavel,
        if ((atual['conviteLgpd'] as Map?)?['por'] case final por?) 'linkGeradoPor': por,
      },
      'atualizadoEm': _agora().toIso8601String(),
    });
    return _json({'ok': true, 'igreja': _termo.igreja});
  }

  /// POST /api/membros/<id>/lgpd/termo?data=aaaa-mm-dd&responsavel=  (corpo: foto ou PDF do termo assinado)
  Future<Response> _anexarTermo(Request req, String id) async {
    final atual = store.buscar('membros', id);
    if (atual == null) return _erro(404, 'Membro não encontrado.');
    final qs = req.url.queryParameters;
    final data = (qs['data'] ?? '').isEmpty ? _hoje() : Membro.dataDe(qs['data']);
    if (data == null || !Membro.dataIsoValida(data)) return _erro(400, 'Data da assinatura inválida.');
    final responsavel = (qs['responsavel'] ?? '').trim();
    if (responsavel.length > 100) return _erro(400, 'Nome do responsável muito longo.');
    final versao = int.tryParse(qs['versao'] ?? '') ?? _termo.versao;
    final tamanho = req.contentLength;
    if (tamanho != null && tamanho > TermosAssinados.tamanhoMaximo) return _erro(413, 'Arquivo maior que 15 MB.');
    final bytes = await _lerBytes(req, TermosAssinados.tamanhoMaximo);
    if (bytes == null) return _erro(413, 'Arquivo maior que 15 MB.');
    try {
      final nome = await termosAssinados.salvar(bytes);
      await termosAssinados.excluir(atual['termoAssinado'] as String?);
      final doc = {
        for (final e in atual.entries)
          if (e.key != 'conviteLgpd') e.key: e.value,
        'termoAssinado': nome,
        'consentimentoEm': data,
        'consentimentoVia': ViaConsentimento.termo,
        'consentimentoRegistro': {
          'em': _agora().toUtc().toIso8601String(),
          'versaoTermo': versao,
          'dataAssinatura': data,
          if (Auth.contaDa(req)?.nome case final por?) 'por': por,
          if (responsavel.isNotEmpty) 'responsavel': responsavel,
        },
        'atualizadoEm': _agora().toIso8601String(),
      };
      await store.salvar('membros', doc);
      return _json(_membroParaPainel(doc), status: 201);
    } on FormatException catch (e) {
      return _erro(400, e.message);
    }
  }

  /// GET /api/membros/<id>/lgpd/termo — o termo assinado (atrás de login).
  Response _verTermoAssinado(Request _, String id) {
    final nome = store.buscar('membros', id)?['termoAssinado'] as String?;
    final f = nome == null ? null : termosAssinados.arquivo(nome);
    if (f == null || !f.existsSync()) return _erro(404, 'Nenhum termo assinado anexado.');
    return Response.ok(f.openRead(), headers: {
      'content-type': TermosAssinados.tipo(nome!),
      'content-disposition': 'inline; filename="termo-lgpd.${nome.split('.').last}"',
      'cache-control': 'private, no-store',
    });
  }

  /// POST /api/membros/<id>/lgpd/revogar — a pessoa pediu para retirar a autorização.
  /// Apaga o termo assinado e guarda só quando foi e quem registrou.
  Future<Response> _revogarLgpd(Request req, String id) async {
    final atual = store.buscar('membros', id);
    if (atual == null) return _erro(404, 'Membro não encontrado.');
    if (atual['consentimentoEm'] == null) return _erro(400, 'Esta pessoa não tem autorização registrada.');
    await termosAssinados.excluir(atual['termoAssinado'] as String?);
    const removidos = {'consentimentoEm', 'consentimentoVia', 'consentimentoRegistro', 'termoAssinado', 'conviteLgpd'};
    final doc = {
      for (final e in atual.entries)
        if (!removidos.contains(e.key)) e.key: e.value,
      'consentimentoRevogado': {
        'em': _agora().toUtc().toIso8601String(),
        if (Auth.contaDa(req)?.nome case final por?) 'por': por,
        'autorizadoEm': atual['consentimentoEm'],
        if (atual['consentimentoVia'] != null) 'via': atual['consentimentoVia'],
      },
      'atualizadoEm': _agora().toIso8601String(),
    };
    await store.salvar('membros', doc);
    return _json(_membroParaPainel(doc));
  }

  Response _paginaDesligada() => Response.notFound('O cadastro pela recepção está desligado.',
      headers: {'content-type': 'text/plain; charset=utf-8'});

  /// GET /api/public/visitante — texto do termo para a página /visitante.
  Response _infoVisitante(Request _) {
    if (cfg?.visitanteQrAtivo == false) return _erro(403, 'O cadastro pela recepção está desligado.');
    return _json({'igreja': _termo.igreja, 'termo': {'versao': _termo.versao, 'texto': _termo.texto}});
  }

  /// POST /api/public/visitante — a própria pessoa se cadastra pelo QR da recepção (corpo: ver [_registrarVisita]).
  Future<Response> _novoVisitantePublico(Request req) async {
    if (cfg?.visitanteQrAtivo == false) return _erro(403, 'O cadastro pela recepção está desligado.');
    final corpo = await _corpo(req);
    if ((corpo['website'] as String? ?? '').isNotEmpty) return _json({'ok': true}); // robô
    if (!_limiteVisitantes.permitir(_ip(req))) {
      return _erro(429, 'Vários cadastros seguidos deste aparelho. Tente de novo em alguns minutos.');
    }
    return _registrarVisita(req, corpo, origem: OrigemVisita.qr);
  }

  // ---------- Visitas (QR, obreiro da recepção e painel) ----------

  List<Visita> _visitas() => store.listar('visitas').map(Visita.fromJson).toList();

  static String _nomeComparavel(String nome) =>
      semAcento(nome.toLowerCase())!.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Cadastro de quem já veio: mesmo nome e (mesmo telefone ou mesmo aniversário).
  Map<String, dynamic>? _cadastroExistente(String nome, String telefone, int dia, int mes) {
    final alvo = _nomeComparavel(nome);
    final fone = telefone.replaceAll(RegExp(r'\D'), '');
    for (final doc in store.listar('membros')) {
      if (_nomeComparavel(doc['nome'] as String? ?? '') != alvo) continue;
      final foneDoc = '${doc['telefone'] ?? ''}${doc['whatsapp'] ?? ''}'.replaceAll(RegExp(r'\D'), '');
      if ((fone.isNotEmpty && foneDoc.contains(fone)) || (doc['dia'] == dia && doc['mes'] == mes)) return doc;
    }
    return null;
  }

  /// Cadastro de visita usado pelos três caminhos. Corpo:
  /// `{pessoas: [{nome, aniversario: "dd/mm[/aaaa]", telefone?, parentesco?: conjuge|filho|outro, autorizo?}],
  ///   comoConheceu?, mencionar: true|false, interesses?: [...], pedidoOracao?, responsavel?, autorizo}`.
  /// O primeiro de `pessoas` é quem preenche; os demais vieram junto. Também aceita o formato antigo
  /// do QR (nome, aniversario e telefone no próprio corpo).
  Future<Response> _registrarVisita(Request req, Map<String, dynamic> corpo, {required String origem, String? por}) async {
    String limpo(Object? v) => (v is String ? v : '').trim().replaceAll(RegExp(r'\s+'), ' ');
    final brutas = corpo['pessoas'] is List
        ? [for (final p in corpo['pessoas'] as List) if (p is Map) Map<String, dynamic>.from(p)]
        : [{'nome': corpo['nome'], 'aniversario': corpo['aniversario'], 'telefone': corpo['telefone']}];
    if (brutas.isEmpty || limpo(brutas.first['nome']).isEmpty) return _erro(400, 'Escreva o nome do visitante.');
    if (brutas.length > 10) return _erro(400, 'No máximo 10 pessoas por cadastro.');
    final mencionar = corpo['mencionar'];
    if (mencionar is! bool) return _erro(400, 'Responda se o pastor pode mencionar a visita durante o culto.');
    final viaPropria = origem != OrigemVisita.painel; // QR e obreiro: a própria pessoa toca em "autorizo"
    if (viaPropria && corpo['autorizo'] != true) {
      return _erro(400, 'Para enviar, leia e marque a autorização de uso dos dados.');
    }
    final comoConheceu = limpo(corpo['comoConheceu']);
    final responsavel = limpo(corpo['responsavel']);
    final pedidoOracao = limpo(corpo['pedidoOracao']);
    final interesses = {
      if (corpo['interesses'] is List)
        for (final i in corpo['interesses'] as List)
          if (InteresseVisita.porNome(i) case final interesse?) interesse,
      if (pedidoOracao.isNotEmpty) InteresseVisita.oracao,
    };
    if (comoConheceu.length > 200 || responsavel.length > 100 || pedidoOracao.length > 500) {
      return _erro(400, 'Algum campo ficou longo demais.');
    }

    // 1. Valida todo mundo antes de gravar qualquer coisa.
    final agora = _agora();
    final hoje = diaIso(agora);
    final pessoas = <({String nome, int dia, int mes, int? ano, String telefone, String parentesco, bool autorizo})>[];
    for (final (i, p) in brutas.indexed) {
      final nome = limpo(p['nome']);
      final quem = i == 0 ? 'Aniversário' : 'Aniversário de ${nome.isEmpty ? 'acompanhante' : nome}';
      if (nome.isEmpty) return _erro(400, 'Falta o nome de um acompanhante.');
      final aniv = RegExp(r'^(\d{1,2})/(\d{1,2})(?:/(\d{4}))?$').firstMatch(limpo(p['aniversario']));
      if (aniv == null) return _erro(400, '$quem: use dia/mês, por exemplo 05/03.');
      final dia = int.parse(aniv.group(1)!), mes = int.parse(aniv.group(2)!);
      if (!Membro.dataValida(dia, mes)) return _erro(400, '$quem: essa data não existe.');
      final telefone = limpo(p['telefone']);
      if (telefone.length > 20 || nome.length > 100) return _erro(400, 'Algum campo ficou longo demais.');
      final parentesco = i == 0 ? '' : (const {'conjuge', 'filho', 'outro'}.contains(p['parentesco']) ? p['parentesco'] as String : 'outro');
      pessoas.add((
        nome: nome, dia: dia, mes: mes, ano: aniv.group(3) == null ? null : int.parse(aniv.group(3)!),
        telefone: telefone, parentesco: parentesco, autorizo: i == 0 ? corpo['autorizo'] == true : p['autorizo'] == true,
      ));
    }
    int? idade(int? ano, int dia, int mes) {
      if (ano == null) return null;
      final aniversarioEsteAno = DateTime(agora.year, mes, dia);
      return agora.year - ano - (aniversarioEsteAno.isAfter(agora) ? 1 : 0);
    }

    final titular = pessoas.first;
    final idadeTitular = idade(titular.ano, titular.dia, titular.mes);
    if (idadeTitular != null && idadeTitular < 18 && responsavel.isEmpty && titular.autorizo) {
      return _erro(400, 'Para menores de 18 anos, escreva o nome do pai, da mãe ou do responsável que autoriza.');
    }

    // 2. Cadastro de cada pessoa: liga a quem já veio, ou cria.
    final registro = {
      'em': agora.toUtc().toIso8601String(),
      'versaoTermo': _termo.versao,
      if (viaPropria) ..._origem(req),
      if (por != null) 'por': por,
    };
    final idsDoDia = {for (final v in store.listar('visitas')) if (v['data'] == hoje) v['membroId']};
    final jaVisitaram = {for (final v in store.listar('visitas')) v['membroId']};
    final grupoId = pessoas.length > 1 ? novoId() : null;
    final ids = <String>[];
    final visitas = <Map<String, dynamic>>[];
    try {
      for (final (i, p) in pessoas.indexed) {
        final existente = _cadastroExistente(p.nome, p.telefone, p.dia, p.mes);
        final menor = (idade(p.ano, p.dia, p.mes) ?? 99) < 18;
        // Quem autoriza: o próprio adulto; menor acompanhante, o titular; titular menor, o responsável informado.
        final autoriza = i == 0 ? p.autorizo : (menor && titular.autorizo) || p.autorizo;
        final responsavelDele = i == 0 ? responsavel : (menor ? titular.nome : '');
        final consentimento = !autoriza
            ? const <String, dynamic>{}
            : {
                'consentimentoEm': hoje,
                'consentimentoVia': viaPropria ? ViaConsentimento.recepcao : ViaConsentimento.manual,
                'consentimentoRegistro': {...registro, if (responsavelDele.isNotEmpty) 'responsavel': responsavelDele},
              };
        final fone = p.telefone.replaceAll(RegExp(r'\D'), '');
        Map<String, dynamic> doc;
        if (existente != null) {
          // Só completa o que estava vazio; uma autorização da própria pessoa (link, termo) é mantida.
          final viaAtual = existente['consentimentoVia'] as String?;
          final podeTrocarConsentimento = existente['consentimentoEm'] == null || viaAtual == ViaConsentimento.manual;
          doc = {
            ...existente,
            if (existente['telefone'] == null && p.telefone.isNotEmpty) 'telefone': p.telefone,
            if (existente['whatsapp'] == null && fone.length == 11) 'whatsapp': p.telefone,
            if (existente['ano'] == null && p.ano != null) 'ano': p.ano,
            if (existente['comoConheceu'] == null && comoConheceu.isNotEmpty) 'comoConheceu': comoConheceu,
            if (podeTrocarConsentimento) ...consentimento,
            'atualizadoEm': agora.toIso8601String(),
          };
        } else {
          final m = _montarMembro({
            'nome': p.nome,
            'dia': p.dia,
            'mes': p.mes,
            if (p.ano != null) 'ano': p.ano,
            if (p.telefone.isNotEmpty) 'telefone': p.telefone,
            if (fone.length == 11) 'whatsapp': p.telefone,
            if (comoConheceu.isNotEmpty) 'comoConheceu': comoConheceu,
            'status': StatusMembro.visitante.name,
            'dataChegada': hoje,
          }, {}, novoId());
          doc = {...m.toJson(), ...consentimento};
        }
        await store.salvar('membros', doc);
        ids.add(doc['id'] as String);
        // Mesmo cadastro duas vezes no dia (clique duplo, QR e obreiro): uma visita só.
        if (idsDoDia.contains(doc['id'])) continue;
        visitas.add(Visita(
          id: novoId(),
          membroId: doc['id'] as String,
          nome: doc['nome'] as String,
          data: hoje,
          criadoEm: agora,
          origem: origem,
          registradoPor: por,
          primeiraVez: !jaVisitaram.contains(doc['id']),
          mencionar: mencionar,
          grupoId: grupoId,
          interesses: i == 0 ? interesses : null,
        ).toJson());
      }
    } on FormatException catch (e) {
      return _erro(400, e.message);
    }
    if (visitas.isNotEmpty) await store.salvarVarios('visitas', visitas);

    // 3. Família: cônjuge nos dois lados (se ninguém já tinha) e filhos ligados ao titular (e ao cônjuge).
    final titularId = ids.first;
    String? conjugeId;
    for (final (i, p) in pessoas.indexed) {
      if (p.parentesco != 'conjuge') continue;
      final a = store.buscar('membros', titularId)!, b = store.buscar('membros', ids[i])!;
      if (a['conjugeId'] == null && b['conjugeId'] == null && ids[i] != titularId) {
        await store.salvarVarios('membros', [{...a, 'conjugeId': ids[i]}, {...b, 'conjugeId': titularId}]);
        conjugeId = ids[i];
      }
    }
    for (final (i, p) in pessoas.indexed) {
      if (p.parentesco != 'filho' || ids[i] == titularId) continue;
      final filho = store.buscar('membros', ids[i])!;
      final pais = {...(filho['paisIds'] as List? ?? const []).map((e) => '$e'), titularId, if (conjugeId != null) conjugeId};
      await store.salvar('membros', {...filho, 'paisIds': pais.take(2).toList()});
    }

    // 4. Pedido de oração escrito no cadastro: vai para a aprovação, particular (só o pastor vê).
    if (pedidoOracao.isNotEmpty) {
      await store.salvar('motivos', Motivo(
        id: novoId(),
        para: '',
        motivo: pedidoOracao,
        tipo: TipoMotivo.fromName('outro'),
        criadoEm: agora,
        status: StatusMotivo.aguardando,
        origem: OrigemMotivo.site,
        publico: false,
        enviadoPor: '${titular.nome} (visitante)',
      ).toJson());
    }

    return _json({
      'ok': true,
      'igreja': _termo.igreja,
      'pessoas': [
        for (final (i, id) in ids.indexed)
          {'id': id, 'nome': pessoas[i].nome, 'primeiraVez': !jaVisitaram.contains(id)},
      ],
    }, status: 201);
  }

  /// GET /api/visitas?desde=aaaa-mm-dd (padrão: últimos 30 dias), mais novas primeiro.
  /// Quem não cuida do cadastro (recepção, telão) não vê as anotações do acompanhamento.
  Response _listarVisitas(Request req) {
    final conta = Auth.contaDa(req);
    // A Recepção só vê as visitas de hoje, seja qual for o "desde" pedido.
    final desde = conta?.perfil == Perfil.recepcao
        ? _hoje()
        : req.url.queryParameters['desde'] ?? diaIso(_agora().subtract(const Duration(days: 30)));
    final completo = conta?.pode(Permissao.membros) ?? false;
    final lista = [
      for (final v in store.listar('visitas'))
        if ((v['data'] as String? ?? '').compareTo(desde) >= 0)
          completo ? v : {for (final e in v.entries) if (!e.key.startsWith('contato')) e.key: e.value},
    ]..sort((a, b) => (b['criadoEm'] as String? ?? '').compareTo(a['criadoEm'] as String? ?? ''));
    return _json(lista);
  }

  /// POST /api/visitas — obreiro (/recepcao) ou secretaria (painel). Corpo: ver [_registrarVisita].
  Future<Response> _criarVisita(Request req) async {
    final conta = Auth.contaDa(req)!;
    final corpo = await _corpo(req);
    final origem = conta.perfil == Perfil.recepcao || corpo['origem'] == OrigemVisita.recepcao
        ? OrigemVisita.recepcao
        : OrigemVisita.painel;
    return _registrarVisita(req, corpo, origem: origem, por: conta.nome);
  }

  /// POST /api/visitas/<id>/mencionada  {desfazer?: true} — o pastor já deu as boas-vindas.
  Future<Response> _visitaMencionada(Request req, String id) async {
    final atual = store.buscar('visitas', id);
    if (atual == null) return _erro(404, 'Visita não encontrada.');
    final desfazer = (await _corpo(req))['desfazer'] == true;
    final doc = {
      for (final e in atual.entries)
        if (e.key != 'mencionadaEm' && e.key != 'mencionadaPor') e.key: e.value,
      if (!desfazer) 'mencionadaEm': _agora().toIso8601String(),
      if (!desfazer && Auth.contaDa(req)?.nome != null) 'mencionadaPor': Auth.contaDa(req)!.nome,
    };
    await store.salvar('visitas', doc);
    return _json(doc);
  }

  /// PUT /api/visitas/<id>/contato  {status: aContatar|contatado|semResposta, nota?}
  Future<Response> _contatoVisita(Request req, String id) async {
    final atual = store.buscar('visitas', id);
    if (atual == null) return _erro(404, 'Visita não encontrada.');
    final corpo = await _corpo(req);
    final status = StatusContato.values.where((s) => s.name == corpo['status']).firstOrNull;
    if (status == null) return _erro(400, 'Situação do contato inválida.');
    final nota = (corpo['nota'] as String? ?? '').trim();
    if (nota.length > 500) return _erro(400, 'Anotação muito longa (máximo 500 caracteres).');
    final doc = {
      for (final e in atual.entries)
        if (!e.key.startsWith('contato')) e.key: e.value,
      'contato': status.name,
      if (status != StatusContato.aContatar) 'contatoEm': _agora().toIso8601String(),
      if (status != StatusContato.aContatar && Auth.contaDa(req)?.nome != null) 'contatoPor': Auth.contaDa(req)!.nome,
      if (nota.isNotEmpty) 'contatoNota': nota,
    };
    await store.salvar('visitas', doc);
    return _json(doc);
  }

  /// POST /api/projetar/boas-vindas  {ids?: [...], tema?, segundos?} — "Sejam bem-vindos!" no telão.
  /// Sem ids: os pendentes de hoje. Só entra quem autorizou a menção. Deu certo: dá baixa.
  Future<Response> _projetarBoasVindas(Request req) async {
    final corpo = await _corpo(req);
    final ids = corpo['ids'] is List ? {for (final i in corpo['ids'] as List) '$i'} : null;
    final hoje = diaIso(_agora());
    final escolhidas = ids == null
        ? pendenciasDoPastor(_visitas(), _agora())
        : _visitas().where((v) => ids.contains(v.id) && v.mencionar && v.data == hoje).toList();
    final nomes = <String>[];
    final vistos = <String>{};
    for (final v in escolhidas) {
      if (vistos.add(v.membroId)) nomes.add(v.nome);
    }
    if (nomes.isEmpty) return _erro(400, 'Nenhum visitante de hoje para citar (só entra quem autorizou).');
    final segundos = (corpo['segundos'] as num?)?.toInt() ?? cfg?.segundosPorSlide ?? 10;
    final tema = corpo['tema'] as String? ?? cfg?.temaPadrao ?? '';
    final slides = montarSlidesBoasVindas(nomes);
    final acao = 'ShowQuickPresentation';
    final pedido = jsonEncode({
      'slides': [for (final s in slides) {'text': s, 'duration': segundos}],
      if (slides.length > 1) 'automatic': {'seconds': segundos, 'repeat': true},
      if (tema.isNotEmpty) 'theme': {'name': tema},
    });
    final usuario = Auth.contaDa(req)?.nome ?? '';
    final r = await holyrics.chamar(acao, pedido);
    if (_ok(r.corpo)) {
      await historico.registrar(acao, pedido, usuario: usuario);
      store.avisar('historico');
      final quando = _agora().toIso8601String();
      await store.salvarVarios('visitas', [
        for (final v in escolhidas)
          {...v.toJson(), 'mencionadaEm': quando, if (usuario.isNotEmpty) 'mencionadaPor': usuario},
      ]);
    }
    return Response(r.status, body: r.corpo, headers: jsonHeaders);
  }

  Uint8List? _qrVisitantePng;
  String? _qrVisitanteUrl;

  /// QR code da página /visitante, para imprimir e deixar na recepção (gerado na hora).
  Response _qrVisitante(Request _) {
    if (cfg?.visitanteQrAtivo == false) return Response.notFound('O cadastro pela recepção está desligado.');
    final url = '$_urlBase/visitante';
    if (_qrVisitanteUrl != url) {
      _qrVisitantePng = gerarPngQr(url, rotulo: 'CADASTRO DE VISITANTE');
      _qrVisitanteUrl = url;
    }
    return Response.ok(_qrVisitantePng, headers: {'content-type': 'image/png', 'cache-control': 'no-cache'});
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

  // ---------- Escalas (pastoral e louvor) ----------

  bool _podeEditarRepertorio(Request req) => Auth.contaDa(req)?.pode(Permissao.escalaLouvor) ?? false;

  Response _listarRepertorio(Request _) => _json([
    for (final m in store.listar('repertorio')) m,
  ]);

  Map<String, dynamic> _statusEditadoRepertorio(Map<String, dynamic> corpo, {Map<String, dynamic>? anterior}) {
    if (!corpo.containsKey('status')) return corpo;
    final status = corpo['status'];
    if (status != 'OK' && status != 'Inativo' && status != 'Em análise') {
      // Edições por clientes antigos que reenviam o registro inteiro não reclassificam o CSV.
      if (anterior != null && status == anterior['status']) return corpo;
      throw const FormatException('Escolha um status válido: OK, Inativo ou Em análise.');
    }
    return {...corpo, 'ativo': status == 'OK'};
  }

  Future<Response> _criarMusicaRepertorio(Request req) async {
    if (!_podeEditarRepertorio(req)) return _semPermissaoEscala(TipoEscala.louvor);
    try {
      final musica = RepertorioMusica.fromJson({..._statusEditadoRepertorio(await _corpo(req)), 'id': novoId()});
      final chave = chaveRepertorio(musica.titulo, musica.cantor);
      if (store.listar('repertorio').any((m) => chaveRepertorio(m['titulo'] as String, m['cantor'] as String) == chave)) {
        return _erro(409, 'Esta música já está no repertório.');
      }
      await store.salvar('repertorio', musica.toJson());
      return _json(musica.toJson(), status: 201);
    } on FormatException catch (e) {
      return _erro(400, e.message);
    }
  }

  Future<Response> _editarMusicaRepertorio(Request req, String id) async {
    if (!_podeEditarRepertorio(req)) return _semPermissaoEscala(TipoEscala.louvor);
    final atual = store.buscar('repertorio', id);
    if (atual == null) return _erro(404, 'Música não encontrada.');
    try {
      final musica = RepertorioMusica.fromJson({...atual, ..._statusEditadoRepertorio(await _corpo(req), anterior: atual), 'id': id});
      final chave = chaveRepertorio(musica.titulo, musica.cantor);
      if (store.listar('repertorio').any((m) => m['id'] != id &&
          chaveRepertorio(m['titulo'] as String, m['cantor'] as String) == chave)) {
        return _erro(409, 'Esta música já está no repertório.');
      }
      await store.salvar('repertorio', musica.toJson());
      return _json(musica.toJson());
    } on FormatException catch (e) {
      return _erro(400, e.message);
    }
  }

  /// Prévia e importação usam a mesma identificação (título + cantor), sem sobrescrever registros existentes.
  Future<Response> _processarImportacaoRepertorio(Request req, {required bool salvar}) async {
    if (!_podeEditarRepertorio(req)) return _semPermissaoEscala(TipoEscala.louvor);
    final csv = (await _corpo(req))['csv'];
    if (csv is! String || csv.length > 2 * 1024 * 1024) return _erro(400, 'CSV inválido ou grande demais.');
    try {
      final lidas = lerRepertorioCsv(csv);
      final chaves = {
        for (final m in store.listar('repertorio'))
          chaveRepertorio(m['titulo'] as String, m['cantor'] as String),
      };
      final novas = <RepertorioMusica>[];
      var repetidas = 0;
      for (final m in lidas) {
        if (!chaves.add(chaveRepertorio(m.titulo, m.cantor))) {
          repetidas++;
        } else {
          novas.add(m.comId(novoId()));
        }
      }
      if (salvar && novas.isNotEmpty) {
        await store.salvarVarios('repertorio', [for (final m in novas) m.toJson()]);
      }
      return _json({
        if (salvar) 'importadas': novas.length else 'novas': novas.length,
        'repetidas': repetidas,
        'musicas': [for (final m in novas) m.toJson()],
      });
    } on FormatException catch (e) {
      return _erro(400, e.message);
    }
  }

  Future<Response> _previaRepertorio(Request req) => _processarImportacaoRepertorio(req, salvar: false);
  Future<Response> _importarRepertorio(Request req) => _processarImportacaoRepertorio(req, salvar: true);

  List<CultoEscala> _cultos() => [for (final d in store.listar('escalas')) CultoEscala.fromJson(d)]
    ..sort((a, b) => '${a.data} ${a.hora}'.compareTo('${b.data} ${b.hora}'));

  List<Indisponibilidade> _indisponibilidades() =>
      [for (final d in store.listar('indisponibilidades')) Indisponibilidade.fromJson(d)];

  Map<String, Membro> _membrosPorId() => {for (final m in _membros()) m.id: m};

  static String Function(String) _nomeDe(Map<String, Membro> membros) => (id) => membros[id]?.nome ?? '(pessoa removida)';

  bool _podeEscala(Request req, TipoEscala tipo) =>
      Auth.contaDa(req)?.pode(tipo == TipoEscala.pastoral ? Permissao.escalaPastoral : Permissao.escalaLouvor) ?? false;

  bool _podeAlgumaEscala(Request req) => TipoEscala.values.any((t) => _podeEscala(req, t));

  static Response _semPermissaoEscala(TipoEscala? tipo) => _erro(403,
      tipo == null ? 'Seu perfil não pode montar escalas.' : 'Seu perfil não pode alterar a escala ${tipo == TipoEscala.pastoral ? 'pastoral' : 'do louvor'}.');

  /// "2026-11" → (2026, 11).
  static ({int ano, int mes})? _mesDe(Object? v) {
    final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(v is String ? v : '');
    if (m == null) return null;
    final mes = int.parse(m.group(2)!);
    return mes < 1 || mes > 12 ? null : (ano: int.parse(m.group(1)!), mes: mes);
  }

  static String _prefixoMes(int ano, int mes) => '$ano-${mes.toString().padLeft(2, '0')}';

  /// Culto como o painel e o tablet mostram: nomes e avisos já resolvidos por função.
  Map<String, dynamic> _cultoParaTela(CultoEscala c, Map<String, Membro> membros, List<Indisponibilidade> ind) => {
        ...c.toJson(),
        'rotulo': rotuloDia(c.data),
        'horaTexto': horaCurtaEscala(c.hora),
        'funcoes': {for (final t in TipoEscala.values) t.name: c.funcoes(t)},
        for (final t in TipoEscala.values)
          t.name: {
            for (final f in c.funcoes(t))
              f: [
                for (final id in c.da(t)[f] ?? const <String>[])
                  {
                    'id': id,
                    'nome': membros[id]?.nome ?? '(pessoa removida)',
                    if (avisoDaPessoa(c, t, f, id, ind) case final aviso?) 'aviso': aviso,
                  },
              ],
          },
      };

  /// GET /api/escalas?mes=aaaa-mm — cultos do mês com as duas escalas, avisos e textos do WhatsApp.
  Response _listarEscalas(Request req) {
    final agora = _agora();
    final mes = _mesDe(req.url.queryParameters['mes']) ?? (ano: agora.year, mes: agora.month);
    final prefixo = _prefixoMes(mes.ano, mes.mes);
    final membros = _membrosPorId();
    final ind = _indisponibilidades();
    final nome = _nomeDe(membros);
    final cultos = _cultos().where((c) => c.data.startsWith(prefixo)).toList();
    final editor = _podeAlgumaEscala(req);
    return _json({
      'mes': prefixo,
      'titulo': '${nomesMeses[mes.mes - 1]} de ${mes.ano}',
      'horariosConfigurados': horariosDosCultos(cfg?.siteCultos ?? '').isNotEmpty,
      'cultos': [for (final c in cultos) _cultoParaTela(c, membros, ind)],
      'avisos': {
        for (final t in TipoEscala.values)
          t.name: [for (final a in avisosDoMes(cultos, t, nome, ind)) {'tipo': a.tipo, 'titulo': a.titulo, 'texto': a.texto}],
      },
      'whatsapp': {for (final t in TipoEscala.values) t.name: textoEscalaWhatsapp(cultos, t, mes.mes, nome)},
      // Nomes de quem pode ser escalado: só para quem monta escala.
      'pessoas': editor
          ? ([
              for (final m in membros.values)
                if (m.ativo) {'id': m.id, 'nome': m.nome, 'pastoral': podeServir(m, TipoEscala.pastoral), 'louvor': podeServir(m, TipoEscala.louvor)},
            ]..sort((a, b) => (a['nome'] as String).compareTo(b['nome'] as String)))
          : const [],
      'indisponibilidades': [
        for (final i in ind)
          if (i.ate.compareTo('$prefixo-01') >= 0 && i.de.compareTo('$prefixo-31') <= 0) {...i.toJson(), 'nome': nome(i.membroId)},
      ],
      'pode': {'pastoral': _podeEscala(req, TipoEscala.pastoral), 'louvor': _podeEscala(req, TipoEscala.louvor)},
    });
  }

  /// GET /api/escalas/hoje — cultos de hoje para o tablet; sem culto hoje, o próximo em até 7 dias.
  Response _escalaDeHoje(Request _) {
    final hoje = diaEscala(_agora());
    final limite = diaEscala(_agora().add(const Duration(days: 7)));
    final cultos = _cultos();
    var lista = cultos.where((c) => c.data == hoje).toList();
    final ehHoje = lista.isNotEmpty;
    if (!ehHoje) {
      final proximo = cultos.where((c) => c.data.compareTo(hoje) > 0 && c.data.compareTo(limite) <= 0).firstOrNull;
      lista = [if (proximo != null) ...cultos.where((c) => c.data == proximo.data)];
    }
    final membros = _membrosPorId();
    final ind = _indisponibilidades();
    return _json({'hoje': ehHoje, 'cultos': [for (final c in lista) _cultoParaTela(c, membros, ind)]});
  }

  /// GET /api/escalas/pdf?mes=aaaa-mm&tipo=...&formato=paisagem|retrato — PDF pronto para baixar.
  /// Valem as regras da impressão: só cultos com pelo menos uma pessoa na escala pedida.
  Future<Response> _escalaPdf(Request req) async {
    final q = req.url.queryParameters;
    final tipo = TipoEscala.porNome(q['tipo']);
    final formato = q['formato'];
    final mes = _mesDe(q['mes']);
    if (tipo == null || mes == null || (formato != 'paisagem' && formato != 'retrato')) {
      return _erro(400, 'Mês, escala ou formato inválidos.');
    }
    final prefixo = _prefixoMes(mes.ano, mes.mes);
    final membros = _membrosPorId();
    final cultos = _cultos()
        .where((c) =>
            c.data.startsWith(prefixo) &&
            c.funcoes(tipo).any((f) => (c.da(tipo)[f] ?? const <String>[]).isNotEmpty))
        .toList()
      ..sort((a, b) => a.data == b.data ? a.hora.compareTo(b.hora) : a.data.compareTo(b.data));
    if (cultos.isEmpty) return _erro(400, 'Nenhuma pessoa escalada nesta escala para gerar o PDF.');
    final logo = File(p.join(pastaWeb, 'logo.png'));
    final pdf = await gerarEscalaPdf(
      cultos: [
        for (final c in cultos)
          CultoEscalaPdf(
            rotulo: rotuloDia(c.data),
            hora: horaCurtaEscala(c.hora),
            nome: c.nome,
            ceia: c.ceia,
            funcoes: [
              for (final f in c.funcoes(tipo))
                FuncaoEscalaPdf(f, [
                  for (final id in c.da(tipo)[f] ?? const <String>[]) membros[id]?.nome ?? '(pessoa removida)',
                ]),
            ],
            musicas: [for (final m in c.musicas) MusicaEscalaPdf(m.titulo, m.tom)],
          ),
      ],
      tipo: tipo.name,
      formato: formato!,
      tituloMes: '${nomesMeses[mes.mes - 1]} de ${mes.ano}',
      igreja: nomeIgreja,
      logo: logo.existsSync() ? logo.readAsBytesSync() : null,
    );
    return Response.ok(pdf, headers: {
      'content-type': 'application/pdf',
      'content-disposition': 'attachment; filename="escala-${tipo.name}-$prefixo-$formato.pdf"',
    });
  }

  /// POST /api/escalas/gerar {mes} — cria os cultos do mês a partir dos horários da página inicial.
  Future<Response> _gerarCultos(Request req) async {
    if (!_podeEscala(req, TipoEscala.pastoral)) return _semPermissaoEscala(TipoEscala.pastoral);
    final mes = _mesDe((await _corpo(req))['mes']);
    if (mes == null) return _erro(400, 'Mês inválido.');
    final horarios = horariosDosCultos(cfg?.siteCultos ?? '');
    if (horarios.isEmpty) {
      return _erro(400, 'Cadastre os horários dos cultos em /admin › Página inicial (um por linha, ex.: "Domingo — 19h").');
    }
    final existentes = {for (final c in _cultos()) '${c.data} ${c.hora}'};
    final novos = [
      for (final c in cultosDoMes(mes.ano, mes.mes, horarios))
        if (!existentes.contains('${c.data} ${c.hora}'))
          CultoEscala(id: novoId(), data: c.data, hora: c.hora, nome: c.nome, ceia: c.ceia).toJson(),
    ];
    if (novos.isNotEmpty) await store.salvarVarios('escalas', novos);
    return _json({'criados': novos.length});
  }

  /// POST /api/escalas/repetir {mes, tipo} — preenche as funções vazias com quem serviu no mesmo
  /// culto do mês anterior (mesmo dia da semana, hora e ocorrência no mês: 1ª quarta com 1ª quarta).
  Future<Response> _repetirEscala(Request req) async {
    final corpo = await _corpo(req);
    final tipo = TipoEscala.porNome(corpo['tipo']);
    final mes = _mesDe(corpo['mes']);
    if (tipo == null || mes == null) return _erro(400, 'Mês ou escala inválidos.');
    if (!_podeEscala(req, tipo)) return _semPermissaoEscala(tipo);
    final anterior = DateTime(mes.ano, mes.mes - 1);
    final prefixoAnterior = _prefixoMes(anterior.year, anterior.month);
    final todos = _cultos();
    final atuais = todos.where((c) => c.data.startsWith(_prefixoMes(mes.ano, mes.mes))).toList();
    if (atuais.isEmpty) return _erro(400, 'Gere os cultos do mês antes de repetir a escala.');
    final anteriores = todos.where((c) => c.data.startsWith(prefixoAnterior)).toList();
    var preenchidas = 0;
    final alterados = <Map<String, dynamic>>[];
    for (final c in atuais) {
      final parecidos = anteriores.where((a) => a.dia.weekday == c.dia.weekday && a.hora == c.hora).toList();
      // 5ª quarta sem par no mês anterior: usa a última.
      final base = parecidos.where((a) => ocorrenciaNoMes(a.data) == ocorrenciaNoMes(c.data)).firstOrNull ?? parecidos.lastOrNull;
      if (base == null) continue;
      final escala = {...c.da(tipo)};
      var mudou = false;
      for (final f in c.funcoes(tipo)) {
        final origem = base.da(tipo)[f] ?? const <String>[];
        if ((escala[f] ?? const []).isNotEmpty || origem.isEmpty) continue;
        escala[f] = [...origem];
        mudou = true;
        preenchidas++;
      }
      if (mudou) alterados.add((tipo == TipoEscala.pastoral ? c.copiar(pastoral: escala) : c.copiar(louvor: escala)).toJson());
    }
    if (alterados.isNotEmpty) await store.salvarVarios('escalas', alterados);
    return _json({'preenchidas': preenchidas});
  }

  /// POST /api/escalas {data, hora, nome?, ceia?} — culto extra (fora dos horários de sempre).
  Future<Response> _criarCulto(Request req) async {
    if (!_podeEscala(req, TipoEscala.pastoral)) return _semPermissaoEscala(TipoEscala.pastoral);
    final corpo = await _corpo(req);
    final CultoEscala culto;
    try {
      culto = CultoEscala.fromJson({'id': novoId(), 'data': corpo['data'], 'hora': corpo['hora'], 'nome': corpo['nome'], 'ceia': corpo['ceia']});
    } on FormatException catch (e) {
      return _erro(400, e.message);
    }
    if (_cultos().any((c) => c.data == culto.data && c.hora == culto.hora)) {
      return _erro(409, 'Já existe um culto nesse dia e horário.');
    }
    await store.salvar('escalas', culto.toJson());
    return _json(_cultoParaTela(culto, _membrosPorId(), _indisponibilidades()), status: 201);
  }

  /// PUT /api/escalas/<id> — {tipo, funcao, membros: [ids]} (quem serve numa função), {musicas} (louvor)
  /// ou {nome, hora, ceia, tema} (dados do culto: pastoral). Cada parte confere a permissão da sua escala.
  Future<Response> _atualizarCulto(Request req, String id) async {
    final atual = store.buscar('escalas', id);
    if (atual == null) return _erro(404, 'Culto não encontrado.');
    final corpo = await _corpo(req);
    final doc = {...atual};
    if (corpo.containsKey('funcao')) {
      final tipo = TipoEscala.porNome(corpo['tipo']);
      if (tipo == null) return _erro(400, 'Escala inválida.');
      if (!_podeEscala(req, tipo)) return _semPermissaoEscala(tipo);
      final membros = corpo['membros'];
      final existentes = _membrosPorId();
      if (membros is! List || membros.any((m) => !existentes.containsKey(m))) return _erro(400, 'Pessoa não encontrada no cadastro.');
      doc[tipo.name] = {...Map<String, dynamic>.from(doc[tipo.name] as Map? ?? const {}), corpo['funcao'] as String: membros};
    }
    if (corpo.containsKey('musicas')) {
      if (!_podeEscala(req, TipoEscala.louvor)) return _semPermissaoEscala(TipoEscala.louvor);
      final entradas = corpo['musicas'];
      if (entradas is! List) return _erro(400, 'Lista de músicas inválida.');
      final anteriores = CultoEscala.fromJson(atual).musicas;
      final selecionadas = <Map<String, dynamic>>[];
      for (final entrada in entradas) {
        if (entrada is! Map) return _erro(400, 'Música inválida.');
        final idMusica = entrada['repertorioId'];
        if (idMusica is! String || idMusica.isEmpty) {
          // Mantém músicas históricas não vinculadas, mas não admite novas sem repertório.
          final titulo = entrada['titulo'];
          final tom = entrada['tom'] ?? '';
          if (titulo is! String || tom is! String || !anteriores.any((m) =>
              m.repertorioId.isEmpty && m.titulo == titulo && m.tom == tom)) {
            return _erro(400, 'Escolha uma música do repertório.');
          }
          selecionadas.add({'titulo': titulo, 'tom': tom});
          continue;
        }
        final musica = store.buscar('repertorio', idMusica);
        if (musica == null) return _erro(400, 'Música não encontrada no repertório.');
        final anterior = anteriores.where((m) => m.repertorioId == idMusica).firstOrNull;
        if (musica['ativo'] != true && anterior == null) return _erro(400, 'Música inativa no repertório.');
        final tom = entrada['tom'] ?? RepertorioMusica.fromJson(musica).tomPadrao;
        if (tom is! String) return _erro(400, 'Tom inválido.');
        selecionadas.add({'repertorioId': idMusica, 'titulo': anterior?.titulo ?? musica['titulo'], 'tom': tom});
      }
      doc['musicas'] = selecionadas;
    }
    for (final k in const ['nome', 'hora', 'ceia', 'tema']) {
      if (!corpo.containsKey(k)) continue;
      if (!_podeEscala(req, TipoEscala.pastoral)) return _semPermissaoEscala(TipoEscala.pastoral);
      doc[k] = corpo[k];
    }
    final CultoEscala culto;
    try {
      culto = CultoEscala.fromJson(doc);
    } on FormatException catch (e) {
      return _erro(400, e.message);
    }
    await store.salvar('escalas', culto.toJson());
    return _json(_cultoParaTela(culto, _membrosPorId(), _indisponibilidades()));
  }

  Future<Response> _excluirCulto(Request req, String id) async {
    if (!_podeEscala(req, TipoEscala.pastoral)) return _semPermissaoEscala(TipoEscala.pastoral);
    return _excluir('escalas', id);
  }

  /// POST /api/escalas/indisponibilidades {membroId, de, ate, motivo?} — avisado à secretaria ou ao líder.
  Response _listarTodasIndisponibilidades(Request req) {
    if (!_podeAlgumaEscala(req)) return _semPermissaoEscala(null);
    final membros = _membrosPorId();
    final lista = store.listar('indisponibilidades').map((d) => {
      ...d,
      'nome': membros[d['membroId']]?.nome ?? '(pessoa removida)',
    }).toList()
      ..sort((a, b) => '${b['de']}'.compareTo('${a['de']}'));
    return _json(lista);
  }

  Future<Response> _criarIndisponibilidade(Request req) async {
    if (!_podeAlgumaEscala(req)) return _semPermissaoEscala(null);
    final corpo = await _corpo(req);
    if (store.buscar('membros', corpo['membroId'] as String? ?? '') == null) return _erro(400, 'Pessoa não encontrada no cadastro.');
    return _salvarIndisponibilidade(req, corpo['membroId'] as String, corpo);
  }

  Future<Response> _salvarIndisponibilidade(Request req, String membroId, Map<String, dynamic> corpo) async {
    final Indisponibilidade ind;
    try {
      ind = Indisponibilidade.fromJson({'id': novoId(), 'membroId': membroId, 'de': corpo['de'], 'ate': corpo['ate'] ?? corpo['de'], 'motivo': corpo['motivo']});
    } on FormatException catch (e) {
      return _erro(400, e.message);
    }
    final doc = {...ind.toJson(), 'enviadoEm': _agora().toUtc().toIso8601String(),
      'enviadoPor': Auth.contaDa(req)?.nome ?? ''};
    await store.salvar('indisponibilidades', doc);
    return _json(doc, status: 201);
  }

  Future<Response> _excluirIndisponibilidade(Request req, String id) async {
    if (!_podeAlgumaEscala(req)) return _semPermissaoEscala(null);
    return _excluir('indisponibilidades', id);
  }

  /// Identifica o membro exclusivamente pela sessão; IDs enviados pelo cliente são ignorados.
  String? _membroDaConta(Request req) {
    final id = _usuarios?.buscar(Auth.contaDa(req)?.id ?? '')?.membroId;
    return id != null && store.buscar('membros', id) != null ? id : null;
  }

  /// GET /api/minha-escala — os cultos da pessoa nos próximos 60 dias (só os dela).
  Future<Response> _minhaEscala(Request req) async {
    final id = _membroDaConta(req);
    if (id == null) return _erro(403, 'Sua conta ainda não está vinculada a um membro. Procure a Secretaria.');
    final hoje = diaEscala(_agora());
    final limite = diaEscala(_agora().add(const Duration(days: 60)));
    final membro = Membro.fromJson(store.buscar('membros', id)!);
    final referencias = {for (final m in store.listar('repertorio')) m['id']: m['referencia']};
    return _json({
      'igreja': _termo.igreja,
      'nome': membro.nome.split(' ').first,
      'cultos': [
        for (final c in _cultos())
          if (c.data.compareTo(hoje) >= 0 && c.data.compareTo(limite) <= 0 && c.servindo.any((s) => s.membroId == id))
            {
              'data': c.data,
              'hora': c.hora,
              'rotulo': rotuloDia(c.data),
              'horaTexto': horaCurtaEscala(c.hora),
              'nome': c.nome,
              'ceia': c.ceia,
              'funcoes': [for (final s in c.servindo) if (s.membroId == id) {'tipo': s.tipo.name, 'funcao': s.funcao}],
              'musicas': [
                for (final m in c.musicas)
                  {
                    ...m.toJson(),
                    if (idVideoYoutube(referencias[m.repertorioId] is String ? referencias[m.repertorioId] as String : '') case final video?)
                      'youtube': 'https://www.youtube.com/watch?v=$video',
                  },
              ],
            },
      ],
      'indisponibilidades': [
        for (final i in _indisponibilidades())
          if (i.membroId == id && i.ate.compareTo(hoje) >= 0) {'id': i.id, 'de': i.de, 'ate': i.ate, 'motivo': i.motivo},
      ],
    });
  }

  /// POST /api/minha-escala/indisponivel {de, ate?, motivo?}
  Future<Response> _minhaIndisponibilidade(Request req) async {
    final corpo = await _corpo(req);
    final id = _membroDaConta(req);
    if (id == null) return _erro(403, 'Sua conta ainda não está vinculada a um membro.');
    if ((dataEscala(corpo['de']) ?? '').compareTo(diaEscala(_agora())) < 0) return _erro(400, 'Escolha uma data a partir de hoje.');
    return _salvarIndisponibilidade(req, id, corpo);
  }

  /// POST /api/minha-escala/indisponivel/remover {id} — só uma indisponibilidade da própria pessoa.
  Future<Response> _removerMinhaIndisponibilidade(Request req) async {
    final corpo = await _corpo(req);
    final id = _membroDaConta(req);
    if (id == null) return _erro(403, 'Sua conta ainda não está vinculada a um membro.');
    final ind = store.buscar('indisponibilidades', corpo['id'] as String? ?? '');
    if (ind == null || ind['membroId'] != id) return _erro(404, 'Aviso não encontrado.');
    await store.excluir('indisponibilidades', ind['id'] as String);
    return _json({'ok': true});
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

  /// Catálogo para o seletor administrativo; nunca inclui token nem objetos de tema completos.
  Future<Response> _adminTemas(Request req) async {
    final forcar = req.url.queryParameters['atualizar'] == '1';
    if (!forcar && _temasAtualizados != null &&
        DateTime.now().difference(_temasAtualizados!) < const Duration(minutes: 5)) {
      return _json({'temas': _temasCache, 'atualizadoEm': _temasAtualizados!.toIso8601String(),
        'desatualizado': false, 'miniaturasDisponiveis': _temasCache.any((t) => t.containsKey('thumbnail'))});
    }
    try {
      final r = await holyrics.chamar('GetThemes', '{}');
      final j = jsonDecode(r.corpo) as Map;
      if (j['status'] != 'ok' || j['data'] is! List) throw const FormatException('Temas indisponíveis');
      final temas = <Map<String, String>>[];
      for (final t in (j['data'] as List).take(80)) {
        if (t is! Map || t['id'] is! String || t['name'] is! String) continue;
        final id = t['id'] as String;
        final name = t['name'] as String;
        if (id.isEmpty || id.length > 100 || name.isEmpty || name.length > 120) continue;
        temas.add({'id': id, 'name': name});
      }
      // Em lotes pequenos para não ultrapassar o timeout da ponte WebSocket.
      for (var i = 0; i < temas.length; i += 10) {
        final grupo = temas.skip(i).take(10).toList();
        try {
          final imagem = await holyrics.chamar('GetThumbnail', jsonEncode({
            'type': 'theme', 'ids': [for (final t in grupo) t['id']]
          }));
          final mini = jsonDecode(imagem.corpo) as Map;
          if (mini['status'] != 'ok' || mini['data'] is! List) continue;
          for (final item in mini['data'] as List) {
            if (item is! Map || item['id'] is! String || item['image'] is! String) continue;
            final base64 = item['image'] as String;
            if (base64.length > 90000 || !RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(base64)) continue;
            try { base64Decode(base64); } catch (_) { continue; }
            for (final t in grupo.where((t) => t['id'] == item['id'])) { t['thumbnail'] = base64; }
          }
        } catch (_) {
          // Sem permissão de miniatura: nomes continuam selecionáveis.
        }
      }
      _temasCache = temas;
      _temasAtualizados = DateTime.now();
      return _json({'temas': temas, 'atualizadoEm': _temasAtualizados!.toIso8601String(),
        'desatualizado': false, 'miniaturasDisponiveis': temas.any((t) => t.containsKey('thumbnail'))});
    } catch (_) {
      return _temasAtualizados == null ? _erro(503, 'Holyrics indisponível ou sem permissão GetThemes.')
          : _json({'temas': _temasCache, 'atualizadoEm': _temasAtualizados!.toIso8601String(),
              'desatualizado': true, 'miniaturasDisponiveis': _temasCache.any((t) => t.containsKey('thumbnail'))});
    }
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
          visitas: _visitas(),
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
  /// `?tela=boas-vindas` é a TV de boas-vindas: só os nomes de hoje de quem autorizou a menção.
  Response _mural(Request req) {
    final nomes = nomesParaBoasVindas(_visitas(), _agora());
    if (req.url.queryParameters['tela'] == 'boas-vindas') {
      return _json({
        'tela': 'boas-vindas',
        'atualizado': _agora().toIso8601String(),
        'igreja': _termo.igreja,
        'nomes': nomes,
        'qr': cfg?.visitanteQrAtivo == false ? null : '/qr-visitante.png',
      });
    }
    final slides = montarMural(
      visitantesHoje: cfg?.muralBoasVindas == true ? nomes : const [],
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

  /// PUT /api/backup/senha {senha}: liga (ou troca) a cópia cifrada no PC da igreja.
  Future<Response> _definirSenhaBackup(Request req) async {
    final senha = (await _corpo(req))['senha'];
    if (senha is! String) return _erro(400, 'Informe a senha do backup.');
    try {
      await senhaBackup.definir(senha);
    } on FormatException catch (e) {
      return _erro(400, e.message);
    }
    agente?.pedirCopiaBackup();
    return _json({'definidaEm': senhaBackup.definidaEm?.toIso8601String()});
  }

  /// DELETE /api/backup/senha: desliga a cópia no PC (as cópias já feitas ficam lá, cifradas).
  Future<Response> _removerSenhaBackup(Request _) async {
    await senhaBackup.remover();
    return _json({'ok': true});
  }

  Future<Response> _listarBackups(Request _) async {
    final lista = await backup.listar();
    final situacao = await _situacaoBackup();
    return _json({
      'pasta': backup.pastaDestino,
      'horario': backup.horario,
      'ultimo': (await backup.ultimo())?.toIso8601String(),
      'modoAgente': agente != null,
      'alertas': situacao.alertas,
      'copiaPc': situacao.copiaPc,
      'senhaDefinidaEm': senhaBackup.definida ? senhaBackup.definidaEm?.toIso8601String() ?? '' : null,
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
    var bytes = await _lerBytes(req, Restauracao.tamanhoMaximo + 64);
    if (bytes == null) return _erro(413, 'Arquivo grande demais.');
    // Cópia do PC da igreja (.cifrado): a senha vem no cabeçalho, nunca na URL.
    if (pareceBackupCifrado(bytes)) {
      final senha = req.headers['x-senha-backup'] ?? '';
      if (senha.isEmpty) return _erro(400, 'Este backup é cifrado: digite a senha do backup.');
      try {
        bytes = await decifrarBackupEmSegundoPlano(bytes, senha);
      } on FormatException catch (e) {
        return _erro(400, e.message);
      }
    }
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
      'termoLgpdEmVigor': c.termoLgpdTexto,
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

  /// Chave no cabeçalho X-Chave-Agente (não vai para logs de proxy). Na URL (?chave=) só nas rotas
  /// antigas, para agentes de versões anteriores; as de backup exigem o cabeçalho.
  bool _chaveAgenteOk(Request req, {bool aceitaUrl = true}) {
    final enviada = req.headers['x-chave-agente'] ?? (aceitaUrl ? req.url.queryParameters['chave'] : null) ?? '';
    return agente != null && chaveAgente.isNotEmpty && iguaisSeguro(enviada, chaveAgente);
  }

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

  static Response get _copiaDesligada => _erro(409,
      'Cópia no PC da igreja desligada: defina a senha do backup em /admin › Backup e restauração.');

  /// Backups gravados no servidor, mais novos primeiro: o agente guarda uma cópia cifrada no PC da igreja.
  Future<Response> _agenteListarBackups(Request req) async {
    if (!_chaveAgenteOk(req, aceitaUrl: false)) return _agenteNegado;
    if (!senhaBackup.definida) return _copiaDesligada;
    return _json([for (final b in await backup.listar()) {'nome': b.nome, 'tamanho': b.tamanho}]);
  }

  /// O backup [nome] cifrado com a senha do backup: o zip aberto nunca sai do servidor por aqui.
  Future<Response> _agenteBaixarBackup(Request req, String nome) async {
    if (!_chaveAgenteOk(req, aceitaUrl: false)) return _agenteNegado;
    if (!senhaBackup.definida) return _copiaDesligada;
    final f = backup.arquivo(Uri.decodeComponent(nome));
    if (f == null) return Response.notFound('Não encontrado');
    final Uint8List cifrado;
    try {
      cifrado = await senhaBackup.cifrarEmSegundoPlano(await f.readAsBytes());
    } on StateError {
      return _copiaDesligada; // a senha foi removida enquanto o arquivo era lido
    }
    return Response.ok(cifrado, headers: {'content-type': 'application/octet-stream', 'cache-control': 'no-store'});
  }

  /// Avisos do backup (falha, atraso, cópia no PC da igreja) para o painel e o /admin.
  Future<({List<String> alertas, String? copiaPc})> _situacaoBackup() async {
    final e = await backup.estado();
    return (
      alertas: alertasBackup(
          ultimo: e.ultimo,
          falha: e.falha,
          copiaPc: e.copiaPcEm,
          modoAgente: agente != null,
          copiaPcLigada: senhaBackup.definida,
          agora: _agora()),
      copiaPc: e.copiaPcEm?.toIso8601String(),
    );
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
        } on FileSystemException catch (e) {
          // Não confirma o que não foi gravado. O caminho fica só no log do servidor.
          stderr.writeln('Falha ao gravar (${req.method} /${req.url.path}): ${e.message} ${e.path ?? ''} ${e.osError ?? ''}');
          return _erro(503, 'Não foi possível gravar os dados no servidor. Tente de novo; se continuar, avise o responsável.');
        }
      };
}
