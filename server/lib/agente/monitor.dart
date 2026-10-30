import 'dart:convert';
import 'dart:io';

import '../auth.dart' show conferirHashSenha, gerarSegredo, LimiteTaxa;
import 'agente.dart';

class _SessaoMonitor {
  _SessaoMonitor(this.csrf, this.expira);
  final String csrf;
  final DateTime expira;
  String? ensaioId;
}
const _falha = #falha;

/// Painel de operações do processo do agente; nunca exposto à rede da igreja.
class MonitorAgente {
  MonitorAgente(this.agente);
  final Agente agente;
  HttpServer? _servidor;
  final _sessoes = <String, _SessaoMonitor>{};
  final _tentativas = LimiteTaxa(maximo: 5, janela: const Duration(minutes: 5));
  bool _ensaioOcupado = false;

  int? get porta => _servidor?.port;

  Future<void> iniciar() async {
    final c = agente.config;
    if (c.monitorHash.isEmpty || c.monitorSal.isEmpty) {
      throw StateError('Defina uma senha própria para habilitar o monitor.');
    }
    _servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, c.monitorPorta);
    _servidor!.listen(_atender);
  }

  Future<void> parar() async {
    await _servidor?.close(force: true);
  }

  /// Aceita só o próprio PC, por nome ou IP. Evita "DNS rebinding" com Host estranho.
  bool _hostLocal(String? host) {
    if (host == null) return false;
    final p = porta;
    return p != null && (host == '127.0.0.1:$p' || host == 'localhost:$p');
  }

  Future<void> _atender(HttpRequest req) async {
    final res = req.response;
    res.headers.set('Cache-Control', 'no-store');
    res.headers.set('X-Content-Type-Options', 'nosniff');
    res.headers.set('X-Frame-Options', 'DENY');
    res.headers.set('Referrer-Policy', 'no-referrer');
    res.headers.set('Content-Security-Policy',
        "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; connect-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'");
    try {
      final host = req.headers.value(HttpHeaders.hostHeader);
      if (!_hostLocal(host)) return _json(res, 403, {'erro': 'Apenas acesso local.'});
      if (req.method == 'POST' && !_hostLocal(req.headers.value('origin')?.replaceFirst('http://', ''))) {
        return _json(res, 403, {'erro': 'Origem inválida.'});
      }
      final uri = req.uri;
      if (uri.path == '/api/login' && req.method == 'POST') {
        _sessoes.removeWhere((_, s) => s.expira.isBefore(DateTime.now()));
        if (!_tentativas.permitir(req.connectionInfo?.remoteAddress.address ?? 'local')) {
          return _json(res, 429, {'erro': 'Aguarde antes de tentar novamente.'});
        }
        final j = await _corpo(req);
        final senha = j['senha'] as String? ?? '';
        if (senha.length > 256 || !conferirHashSenha(senha,
            hash: agente.config.monitorHash, sal: agente.config.monitorSal)) {
          return _json(res, 401, {'erro': 'Senha inválida.'});
        }
        final id = gerarSegredo(32);
        final sessao = _SessaoMonitor(gerarSegredo(24), DateTime.now().add(const Duration(minutes: 30)));
        _sessoes[id] = sessao;
        res.headers.add(HttpHeaders.setCookieHeader, 'diako_monitor=$id; HttpOnly; SameSite=Strict; Path=/');
        return _json(res, 200, {'csrf': sessao.csrf});
      }
      if (uri.path == '/' && req.method == 'GET') {
        res.headers.contentType = ContentType.html;
        res.write(_pagina);
        return;
      }
      final cookie = req.cookies.where((c) => c.name == 'diako_monitor').firstOrNull;
      final sessao = cookie == null ? null : _sessoes[cookie.value];
      if (sessao == null || sessao.expira.isBefore(DateTime.now())) {
        if (cookie != null) _sessoes.remove(cookie.value);
        return _json(res, 401, {'erro': 'Faça login.'});
      }
      if (req.method == 'POST' && req.headers.value('x-csrf-token') != sessao.csrf) {
        return _json(res, 403, {'erro': 'Confirmação de sessão inválida.'});
      }
      if (uri.path == '/api/logout' && req.method == 'POST') {
        _sessoes.remove(cookie!.value);
        res.headers.add(HttpHeaders.setCookieHeader, 'diako_monitor=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0');
        return _json(res, 200, {'ok': true});
      }
      if (uri.path == '/api/estado' && req.method == 'GET') {
        return _json(res, 200, {'estado': agente.estado, 'csrf': sessao.csrf});
      }
      if (uri.path == '/api/logs' && req.method == 'GET') {
        final filtro = uri.queryParameters['tipo'];
        final nivel = uri.queryParameters['nivel'];
        return _json(res, 200, {'eventos': agente.eventos.where((e) =>
            (filtro == null || filtro.isEmpty || e['tipo'] == filtro) &&
            (nivel == null || nivel.isEmpty || e['nivel'] == nivel)).toList()});
      }
      if (uri.path == '/api/diagnostico' && req.method == 'POST') {
        final j = await _corpo(req);
        final acao = j['acao'];
        if (acao == 'cartazes') {
          final pasta = Directory(agente.config.pastaCartazes);
          return _json(res, 200, {'ok': await pasta.exists(), 'detalhe':
              await pasta.exists() ? 'Pasta de cartazes acessível.' : 'Pasta ausente; verifique o caminho configurado.'});
        }
        if (acao == 'backend') return _json(res, 200, {'ok': agente.backendConectado,
            'detalhe': agente.backendConectado ? 'WebSocket conectado.' : 'Verifique endereço, rede e chave do agente.'});
        if (!{'GetCPInfo', 'GetCurrentPresentation', 'GetThemes'}.contains(acao)) {
          return _json(res, 400, {'erro': 'Diagnóstico desconhecido.'});
        }
        final dados = await _holyrics(acao as String);
        return _json(res, 200, {'ok': dados != _falha, 'detalhe': dados != _falha
            ? 'Holyrics respondeu com sucesso.' : 'Confira API Server, token e permissão $acao.'});
      }
      if (uri.path == '/api/temas' && req.method == 'GET') {
        final temas = await _holyrics('GetThemes');
        if (temas is! List) return _json(res, 503, {'erro': 'Não foi possível obter temas do Holyrics.'});
        final itens = <Map<String, String>>[];
        for (final t in temas.take(100)) {
          if (t is! Map || t['id'] is! String || t['name'] is! String) continue;
          itens.add({'id': t['id'] as String, 'name': t['name'] as String});
        }
        for (var i = 0; i < itens.length; i += 10) {
          final grupo = itens.skip(i).take(10).toList();
          final miniaturas = await _holyrics('GetThumbnail', {'type': 'theme', 'ids': grupo.map((t) => t['id']).toList()});
          if (miniaturas is! List) continue;
          for (final mini in miniaturas) {
            if (mini is! Map || mini['image'] is! String) continue;
            final image = mini['image'] as String;
            if (image.length > 90000 || !RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(image)) continue;
            try { base64Decode(image); } catch (_) { continue; }
            for (final t in grupo.where((t) => t['id'] == mini['id'])) { t['thumbnail'] = image; }
          }
        }
        return _json(res, 200, {'temas': itens, 'atualizadoEm': DateTime.now().toIso8601String(),
          'miniaturasDisponiveis': itens.any((t) => t.containsKey('thumbnail'))});
      }
      if (uri.path == '/api/ensaio' && req.method == 'POST') {
        final j = await _corpo(req);
        if (j['confirmacao'] != 'SIM') return _json(res, 400, {'erro': 'Digite SIM para cada etapa.'});
        if (_ensaioOcupado) return _json(res, 409, {'erro': 'Outro ensaio está em andamento.'});
        _ensaioOcupado = true;
        try {
          final etapa = j['etapa'];
          final atual = await _holyrics('GetCurrentPresentation');
          if (atual == _falha) return _json(res, 409, {'erro': 'Não foi possível confirmar o estado do telão.'});
          if (etapa == 'iniciar') {
            if (atual != null) return _json(res, 409, {'erro': 'Telão ocupado. Nada foi projetado.'});
            final resposta = await _holyrics('ShowQuickPresentation', {'slides': [
              {'text': 'TESTE DIAKOHUB — 1/2'}, {'text': 'TESTE DIAKOHUB — 2/2'}
            ]});
            if (resposta == _falha) return _json(res, 502, {'erro': 'Holyrics não confirmou o ensaio.'});
            final criado = await _holyrics('GetCurrentPresentation');
            if (criado is! Map || criado['type'] != 'quick_presentation' || criado['id'] == null) {
              return _json(res, 409, {'erro': 'Não foi possível identificar o ensaio; nenhuma navegação será permitida.'});
            }
            sessao.ensaioId = criado['id'].toString();
            agente.registrar('ensaio', 'Texto de teste iniciado');
            return _json(res, 200, {'ok': true, 'etapa': 'iniciado'});
          }
          if (!{'proximo', 'anterior'}.contains(etapa) || sessao.ensaioId == null ||
              atual is! Map || atual['id']?.toString() != sessao.ensaioId || atual['type'] != 'quick_presentation') {
            sessao.ensaioId = null;
            return _json(res, 409, {'erro': 'O telão mudou ou o ensaio expirou; comando bloqueado.'});
          }
          final acao = etapa == 'proximo' ? 'ActionNextQuickPresentation' : 'ActionPreviousQuickPresentation';
          if (await _holyrics(acao) == _falha) return _json(res, 502, {'erro': 'Holyrics não confirmou a navegação.'});
          final depois = await _holyrics('GetCurrentPresentation');
          if (depois is! Map || depois['id']?.toString() != sessao.ensaioId ||
              depois['type'] != 'quick_presentation') {
            sessao.ensaioId = null;
            return _json(res, 409, {'erro': 'O telão mudou após o comando; ensaio interrompido.'});
          }
          if (atual['slide_number'] is num && depois['slide_number'] is num &&
              atual['slide_number'] == depois['slide_number']) {
            return _json(res, 502, {'erro': 'Comando aceito, mas o slide não mudou; confira o telão.'});
          }
          agente.registrar('ensaio', etapa == 'proximo' ? 'Próximo slide de teste' : 'Slide anterior de teste');
          return _json(res, 200, {'ok': true, 'etapa': etapa, 'slide': depois['slide_number']});
        } finally {
          _ensaioOcupado = false;
        }
      }
      _json(res, 404, {'erro': 'Página não encontrada.'});
    } on FormatException {
      _json(res, 400, {'erro': 'Requisição inválida.'});
    } catch (_) {
      _json(res, 500, {'erro': 'Não foi possível concluir a operação.'});
    } finally {
      await res.close();
    }
  }

  Future<dynamic> _holyrics(String acao, [Map<String, dynamic> corpo = const {}]) async {
    final r = await agente.consultarHolyrics(acao, jsonEncode(corpo));
    try {
      final j = jsonDecode(r.corpo) as Map;
      return j['status'] == 'ok' ? (j.containsKey('data') ? j['data'] : true) : _falha;
    } catch (_) { return _falha; }
  }

  Future<Map<String, dynamic>> _corpo(HttpRequest req) async {
    if (req.contentLength > 2048) throw const FormatException('Corpo muito grande');
    final bytes = <int>[];
    await for (final parte in req) {
      bytes.addAll(parte);
      if (bytes.length > 2048) throw const FormatException('Corpo muito grande');
    }
    final texto = utf8.decode(bytes);
    return (jsonDecode(texto) as Map).cast<String, dynamic>();
  }

  void _json(HttpResponse res, int status, Object dados) {
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(dados));
  }
}

const _pagina = r'''<!doctype html><html lang="pt-BR"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Monitor do Agente DiakoHub</title><style>
body{font:16px system-ui;background:#101b29;color:#f4f7fb;max-width:1100px;margin:auto;padding:20px}button,input,select{font:inherit;padding:9px;margin:4px}button{cursor:pointer;background:#227caa;color:white;border:0;border-radius:6px}nav button{background:#283d54}section{background:#192b3e;padding:18px;border-radius:10px;margin:12px 0}pre{white-space:pre-wrap;overflow:auto}small{color:#bbcfdf}.erro{color:#ffb2a9}.ok{color:#9de9b7}img{width:160px;max-height:100px;object-fit:contain}.card{display:inline-grid;padding:12px;border:1px solid #526878;margin:5px;max-width:170px}
</style><h1>Monitor do Agente DiakoHub</h1><section id="login"><label>Senha do monitor <input id="senha" type="password" autocomplete="current-password"></label><button onclick="entrar()">Entrar</button></section>
<main hidden id="painel"><nav><button onclick="aba('geral')">Geral</button><button onclick="aba('diagnosticos')">Diagnósticos</button><button onclick="aba('temas')">Temas</button><button onclick="aba('ensaio')">Ensaio</button><button onclick="aba('logs')">Logs</button><button onclick="sair()">Sair</button></nav>
<section id="geral"><h2>Conexões e sincronização</h2><pre id="estado"></pre><button onclick="atualizar()">Atualizar</button></section>
<section id="diagnosticos" hidden><h2>Diagnósticos de leitura</h2><p>Consultas não alteram o telão.</p><div id="testes"></div><pre id="resultado"></pre></section>
<section id="temas" hidden><h2>Temas Holyrics</h2><p>Miniaturas ilustrativas; não garantem aparência final do texto.</p><button onclick="temas()">Atualizar temas</button><div id="listaTemas"></div></section>
<section id="ensaio" hidden><h2>Ensaio guiado</h2><p>Não execute durante um culto. Exige telão livre e confirmação a cada comando. O ensaio não fecha a apresentação.</p><button onclick="ensaio('iniciar')">Projetar dois slides de teste</button><button onclick="ensaio('proximo')">Próximo</button><button onclick="ensaio('anterior')">Anterior</button><pre id="resultadoEnsaio"></pre></section>
<section id="logs" hidden><h2>Eventos recentes</h2><select id="filtro" onchange="logs()"><option value="">Todos</option><option>backend</option><option>holyrics</option><option>cartazes</option><option>ensaio</option></select><select id="nivel" onchange="logs()"><option value="">Todas as gravidades</option><option value="info">Informação</option><option value="erro">Erro</option></select><button onclick="logs()">Atualizar</button><button onclick="copiar()">Copiar relatório</button><button onclick="baixar()">Baixar relatório</button><pre id="eventos"></pre></section></main><p id="aviso" role="status"></p>
<script>
let csrf='';const $=id=>document.getElementById(id);
async function api(path,body){const r=await fetch('/api/'+path,{method:body===undefined?'GET':'POST',headers:{'Content-Type':'application/json','X-CSRF-Token':csrf},body:body===undefined?undefined:JSON.stringify(body)});const j=await r.json();if(r.status===401&&path!=='login'){$('painel').hidden=true;$('login').hidden=false;csrf=''}if(!r.ok)throw Error(j.erro||'Falha HTTP '+r.status);return j}
function aviso(s){$('aviso').textContent=s}
async function entrar(){try{const j=await api('login',{senha:$('senha').value});$('senha').value='';csrf=j.csrf;$('login').hidden=true;$('painel').hidden=false;atualizar()}catch(e){aviso(e.message)}}
async function sair(){try{await api('logout',{})}catch(e){}csrf='';$('painel').hidden=true;$('login').hidden=false}
function aba(id){for(const s of document.querySelectorAll('main section'))s.hidden=s.id!==id;if(id==='logs')logs();if(id==='temas')temas();if(id==='geral')atualizar()}
async function atualizar(){try{let j=await api('estado');csrf=j.csrf;let e=j.estado;$('estado').textContent=`Backend: ${e.backendConectado?'conectado':'desconectado'} (${e.servidor})\nÚltima mensagem: ${e.ultimaMensagem||'—'} | Reconexões: ${e.reconexoes}\nHolyrics: ${e.holyricsHost}:${e.holyricsPorta} | ${e.holyricsConectado===null?'aguardando verificação':e.holyricsConectado?'conectado':'sem conexão'} | Latência: ${e.holyricsLatenciaMs??'—'} ms | Verificado: ${e.holyricsVerificadoEm||'—'}\nToken configurado: ${e.holyricsConfigurado?'sim':'não'} | Cartazes: ${e.pastaCartazes}\nÚltima sincronização: ${e.ultimaSincronizacao||'—'} | Remotos: ${e.cartazesRemotos} | Baixados: ${e.cartazesBaixados} | Apagados: ${e.cartazesApagados}\nErro: ${e.erroSincronizacao||'nenhum'} | Agente: ${e.versao}\nBackup do servidor: ${e.pastaBackup?e.pastaBackup+' | Última cópia: '+(e.ultimaCopiaBackup||'—')+' | Mais novo: '+(e.ultimoBackupCopiado||'—')+(e.erroBackup?' | Erro: '+e.erroBackup:''):'desligado'}\nRede local: ${e.apiLocalPorta?'porta '+e.apiLocalPorta:'desligada'} | Tablets: ${e.tabletsPareados.length?e.tabletsPareados.join(', '):'nenhum'} | Comandos: ${e.chamadasLocais} | Último: ${e.ultimaLocalMs??'—'} ms em ${e.ultimaLocalEm||'—'} | Histórico a enviar: ${e.historicoPendente}`;aviso('Atualizado');return true}catch(e){aviso(e.message);return false}}
for(const acao of ['backend','GetCPInfo','GetCurrentPresentation','GetThemes','cartazes']){let b=document.createElement('button');b.textContent=acao;b.onclick=async()=>{try{let j=await api('diagnostico',{acao});$('resultado').textContent=acao+': '+(j.ok?'OK':'FALHA')+' — '+j.detalhe}catch(e){aviso(e.message)}};$('testes').append(b)}
async function temas(){try{let j=await api('temas');$('listaTemas').replaceChildren();for(const t of j.temas){let c=document.createElement('div');c.className='card';let n=document.createElement('strong');n.textContent=t.name;c.append(n);if(t.thumbnail){let im=document.createElement('img');let mime=t.thumbnail.startsWith('/9j/')?'image/jpeg':t.thumbnail.startsWith('UklGR')?'image/webp':'image/png';im.src='data:'+mime+';base64,'+t.thumbnail;c.append(im)}$('listaTemas').append(c)}aviso(j.temas.length&&!j.miniaturasDisponiveis?'Sem miniaturas: libere GetThumbnail no token.':'Temas atualizados em '+j.atualizadoEm)}catch(e){aviso(e.message)}}
async function ensaio(etapa){if(prompt('Para '+etapa+', digite SIM (qualquer outra resposta cancela)')!=='SIM')return;try{let j=await api('ensaio',{etapa,confirmacao:'SIM'});$('resultadoEnsaio').textContent='OK: '+j.etapa}catch(e){$('resultadoEnsaio').textContent=e.message}}
async function logs(){try{let j=await api('logs?tipo='+encodeURIComponent($('filtro').value)+'&nivel='+encodeURIComponent($('nivel').value));$('eventos').textContent=j.eventos.map(e=>`${e.quando} [${e.nivel}/${e.tipo}] ${e.mensagem}`).join('\n')||'Sem eventos'}catch(e){aviso(e.message)}}
async function copiar(){await navigator.clipboard.writeText($('estado').textContent+'\n'+$('eventos').textContent);aviso('Relatório copiado (sem credenciais).')}
function baixar(){const b=new Blob([$('estado').textContent+'\n'+$('eventos').textContent],{type:'text/plain;charset=utf-8'});const u=URL.createObjectURL(b);const a=document.createElement('a');a.href=u;a.download='diako-monitor.txt';a.click();setTimeout(()=>URL.revokeObjectURL(u),1000)}
setInterval(()=>{if(!$('painel').hidden){if(!$('geral').hidden)atualizar();if(!$('logs').hidden)logs()}},5000);atualizar().then(ok=>{if(ok){$('login').hidden=true;$('painel').hidden=false}});
</script></html>''';
