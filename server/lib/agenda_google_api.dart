import 'dart:convert';
import 'dart:io';

import 'package:diako_core/diako_core.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Página de ajuda (servida pelo próprio servidor) com o passo a passo e os problemas comuns.
const ajudaAgenda = '/ajuda/agenda-google';

/// Erro da API do Google já traduzido, com a âncora da ajuda que explica como resolver.
class ErroGoogle implements Exception {
  ErroGoogle(this.mensagem, {this.ancora = 'problemas', this.status = 502});
  final String mensagem;
  final String ancora;

  /// Status HTTP a devolver ao painel/app.
  final int status;

  String get ajuda => '$ajudaAgenda#$ancora';

  @override
  String toString() => mensagem;
}

/// Chave JSON da conta de serviço do Google, guardada em data/google-conta-servico.json
/// (fora do backup e nunca enviada ao painel; só o e-mail é mostrado).
class ContaServicoGoogle {
  ContaServicoGoogle(String pastaDados) : arquivo = File(p.join(pastaDados, 'google-conta-servico.json'));

  final File arquivo;
  Map<String, dynamic>? _dados;

  Map<String, dynamic>? get dados => _dados;
  bool get configurada => _dados != null;
  String? get email => _dados?['client_email'] as String?;

  Future<void> carregar() async {
    if (!await arquivo.exists()) return;
    try {
      _dados = validar(await arquivo.readAsString());
    } on FormatException {
      _dados = null;
    }
  }

  /// Confere se o texto é a chave JSON de uma conta de serviço. Lança [FormatException].
  static Map<String, dynamic> validar(String texto) {
    final Object? j;
    try {
      j = jsonDecode(texto);
    } on FormatException {
      throw const FormatException('O arquivo não é um JSON. Envie o arquivo .json baixado em "Chaves" da conta de serviço.');
    }
    if (j is! Map || j['type'] != 'service_account') {
      throw const FormatException('Este JSON não é a chave de uma conta de serviço (o campo "type" deveria ser "service_account").');
    }
    for (final campo in ['client_email', 'private_key', 'client_id']) {
      if ((j[campo] as String? ?? '').isEmpty) throw FormatException('A chave está incompleta: falta o campo "$campo".');
    }
    if (!(j['private_key'] as String).contains('PRIVATE KEY')) {
      throw const FormatException('A chave está incompleta: "private_key" inválida.');
    }
    return Map<String, dynamic>.from(j);
  }

  Future<void> salvar(Map<String, dynamic> dados) async {
    await arquivo.parent.create(recursive: true);
    final tmp = File('${arquivo.path}.tmp');
    await tmp.writeAsString(jsonEncode(dados), flush: true);
    if (!Platform.isWindows) await Process.run('chmod', ['600', tmp.path]);
    await tmp.rename(arquivo.path);
    _dados = dados;
  }

  Future<void> remover() async {
    _dados = null;
    if (await arquivo.exists()) await arquivo.delete();
  }
}

/// Dados de um evento a criar ou alterar (horário local da igreja; fim exclusivo no dia inteiro).
class DadosEvento {
  DadosEvento({
    required this.titulo,
    required this.inicio,
    required this.fim,
    this.diaInteiro = false,
    this.local = '',
    this.descricao = '',
  });

  final String titulo;
  final DateTime inicio;
  final DateTime fim;
  final bool diaInteiro;
  final String local;
  final String descricao;

  /// Lê o corpo enviado pelo painel/app. Lança [FormatException] com a mensagem para o usuário.
  factory DadosEvento.fromJson(Map<String, dynamic> j) {
    DateTime data(String k) {
      final v = DateTime.tryParse(j[k] as String? ?? '');
      if (v == null) throw FormatException('Data inválida em "$k".');
      return v;
    }

    final d = DadosEvento(
      titulo: (j['titulo'] as String? ?? '').trim(),
      inicio: data('inicio'),
      fim: data('fim'),
      diaInteiro: j['diaInteiro'] == true,
      local: (j['local'] as String? ?? '').trim(),
      descricao: (j['descricao'] as String? ?? '').trim(),
    );
    final erro = validarEvento(
        titulo: d.titulo, inicio: d.inicio, fim: d.fim, diaInteiro: d.diaInteiro, local: d.local, descricao: d.descricao);
    if (erro != null) throw FormatException(erro);
    return d;
  }
}

/// Resultado do teste de acesso: nome da agenda e o nível de permissão da conta de serviço.
typedef AcessoAgenda = ({String nome, String permissao});

/// Agenda do Google lida e alterada pela API (Calendar v3), autenticada pela conta de serviço.
class CalendarioGoogle {
  CalendarioGoogle({
    required this.calendarioId,
    required Future<http.Client> Function() cliente,
    this.emailConta = '',
    this.fuso = 'America/Sao_Paulo',
  }) : _criarCliente = cliente;

  /// Cliente autenticado a partir da chave JSON (o [base] permite testar sem a internet).
  factory CalendarioGoogle.daConta(Map<String, dynamic> chave, String calendarioId, {http.Client? base}) =>
      CalendarioGoogle(
        calendarioId: calendarioId,
        emailConta: chave['client_email'] as String? ?? '',
        cliente: () => clientViaServiceAccount(
          ServiceAccountCredentials.fromJson(chave),
          const ['https://www.googleapis.com/auth/calendar.events'],
          baseClient: base,
        ),
      );

  final String calendarioId;
  final String emailConta;
  final String fuso;
  final Future<http.Client> Function() _criarCliente;
  Future<http.Client>? _cliente;

  static const timeout = Duration(seconds: 20);
  static const _base = 'https://www.googleapis.com/calendar/v3';

  String get _eventos => '$_base/calendars/${Uri.encodeComponent(calendarioId)}/events';

  void fechar() {
    _cliente?.then((c) => c.close()).ignore();
    _cliente = null;
  }

  /// Confere se a agenda existe e se a conta de serviço pode alterar eventos.
  Future<AcessoAgenda> testarAcesso() async {
    final j = await _pedir('GET', Uri.parse('$_eventos?maxResults=1&timeZone=$fuso'));
    final permissao = j['accessRole'] as String? ?? '';
    if (!const {'owner', 'writer', 'writerWithoutPrivateAccess'}.contains(permissao)) {
      throw ErroGoogle(
        'A conta de serviço só pode ver esta agenda. No Google Agenda, compartilhe a agenda com $emailConta '
        'com a permissão "Fazer alterações e ver detalhes do evento".',
        ancora: 'erro-permissao',
        status: 400,
      );
    }
    return (nome: j['summary'] as String? ?? calendarioId, permissao: permissao);
  }

  /// Eventos (ocorrências já expandidas) que se sobrepõem a [de, ate).
  Future<List<Evento>> listar(DateTime de, DateTime ate) async {
    final lista = <Evento>[];
    String? pagina;
    do {
      final q = {
        'singleEvents': 'true',
        'orderBy': 'startTime',
        'timeZone': fuso,
        'maxResults': '250',
        'timeMin': _instanteUtc(de),
        'timeMax': _instanteUtc(ate),
        if (pagina != null) 'pageToken': pagina,
      };
      final j = await _pedir('GET', Uri.parse(_eventos).replace(queryParameters: q));
      for (final item in (j['items'] as List? ?? const [])) {
        final e = eventoDaApi(Map<String, dynamic>.from(item as Map));
        if (e != null) lista.add(e);
      }
      pagina = j['nextPageToken'] as String?;
    } while (pagina != null);
    return lista;
  }

  Future<Evento> criar(DadosEvento d) async =>
      eventoDaApi(await _pedir('POST', Uri.parse(_eventos), corpo: _corpo(d)))!;

  Future<Evento> atualizar(String id, DadosEvento d) async {
    await _conferirEditavel(id);
    return eventoDaApi(await _pedir('PATCH', Uri.parse('$_eventos/${Uri.encodeComponent(id)}'), corpo: _corpo(d)))!;
  }

  Future<void> excluir(String id) async {
    await _conferirEditavel(id);
    await _pedir('DELETE', Uri.parse('$_eventos/${Uri.encodeComponent(id)}'));
  }

  /// Eventos que se repetem continuam sendo alterados no Google Agenda.
  Future<void> _conferirEditavel(String id) async {
    final j = await _pedir('GET', Uri.parse('$_eventos/${Uri.encodeComponent(id)}?timeZone=$fuso'));
    if (j['recurringEventId'] != null || j['recurrence'] != null) {
      throw ErroGoogle('Este evento se repete. Altere ou exclua no Google Agenda.', ancora: 'recorrentes', status: 400);
    }
  }

  Map<String, dynamic> _corpo(DadosEvento d) {
    // PATCH: os campos nulos apagam o formato anterior (ex.: trocar de dia inteiro para horário).
    Map<String, dynamic> quando(DateTime t) => d.diaInteiro
        ? {'date': _data(t), 'dateTime': null, 'timeZone': null}
        : {'dateTime': _dataHora(t), 'timeZone': fuso, 'date': null};
    return {
      'summary': d.titulo,
      'location': d.local,
      'description': d.descricao,
      'start': quando(d.inicio),
      'end': quando(d.fim),
    };
  }

  Future<Map<String, dynamic>> _pedir(String metodo, Uri uri, {Map<String, dynamic>? corpo}) async {
    final http.Response r;
    try {
      final c = await (_cliente ??= _criarCliente());
      final req = http.Request(metodo, uri);
      if (corpo != null) {
        req.headers['content-type'] = 'application/json; charset=utf-8';
        req.body = jsonEncode(corpo);
      }
      r = await http.Response.fromStream(await c.send(req).timeout(timeout));
    } on ErroGoogle {
      rethrow;
    } on ArgumentError {
      _cliente = null;
      throw _erroDaChave;
    } on Exception catch (e) {
      // Falha ao obter o token (chave excluída/errada) ou sem internet.
      _cliente = null;
      final texto = e.toString();
      if (texto.contains('invalid_grant') || texto.contains('invalid_client') || texto.contains('JWT')) throw _erroDaChave;
      throw ErroGoogle('Não foi possível falar com o Google: ${texto.split('\n').first}', ancora: 'erro-conexao');
    }
    if (r.statusCode == 204 || (metodo == 'DELETE' && r.statusCode == 200)) return const {};
    final Object? j = r.body.isEmpty ? const {} : (() {
      try {
        return jsonDecode(utf8.decode(r.bodyBytes));
      } on FormatException {
        return const {};
      }
    })();
    final mapa = j is Map ? Map<String, dynamic>.from(j) : <String, dynamic>{};
    if (r.statusCode >= 200 && r.statusCode < 300) return mapa;
    throw traduzirErro(r.statusCode, mapa, emailConta);
  }

  static ErroGoogle get _erroDaChave => ErroGoogle(
        'O Google recusou a chave da conta de serviço (ela pode ter sido excluída no Google Cloud). '
        'Gere uma chave nova e envie em Administração.',
        ancora: 'erro-chave',
        status: 400,
      );

  /// Converte a resposta de erro do Google numa mensagem em português.
  static ErroGoogle traduzirErro(int status, Map<String, dynamic> corpo, String emailConta) {
    final erro = corpo['error'] is Map ? Map<String, dynamic>.from(corpo['error'] as Map) : const <String, dynamic>{};
    final mensagem = erro['message'] as String? ?? '';
    final motivos = [
      for (final e in (erro['errors'] as List? ?? const [])) if (e is Map) e['reason'],
      for (final d in (erro['details'] as List? ?? const [])) if (d is Map) d['reason'],
    ];
    final quem = emailConta.isEmpty ? 'a conta de serviço' : emailConta;
    if (motivos.contains('accessNotConfigured') || motivos.contains('SERVICE_DISABLED') ||
        mensagem.contains('has not been used') || mensagem.contains('is disabled')) {
      return ErroGoogle('A Google Calendar API não está ativada no projeto do Google Cloud. Ative a API e tente de novo.',
          ancora: 'erro-api', status: 400);
    }
    if (status == 404) {
      return ErroGoogle('Agenda ou evento não encontrado. Confira o ID da agenda e se ela foi compartilhada com $quem.',
          ancora: 'erro-404', status: 404);
    }
    if (status == 403 || status == 401) {
      if (motivos.contains('rateLimitExceeded') || motivos.contains('userRateLimitExceeded')) {
        return ErroGoogle('O Google pediu para esperar um pouco (limite de uso). Tente de novo em alguns minutos.',
            ancora: 'problemas', status: 429);
      }
      return ErroGoogle(
        'Sem permissão para alterar a agenda. Compartilhe a agenda com $quem com a permissão '
        '"Fazer alterações e ver detalhes do evento".',
        ancora: 'erro-permissao',
        status: 403,
      );
    }
    if (status == 400) {
      return ErroGoogle('O Google recusou os dados do evento${mensagem.isEmpty ? '' : ': $mensagem'}', ancora: 'problemas', status: 400);
    }
    if (status == 429) {
      return ErroGoogle('O Google pediu para esperar um pouco (limite de uso). Tente de novo em alguns minutos.',
          ancora: 'problemas', status: 429);
    }
    return ErroGoogle('O Google respondeu HTTP $status${mensagem.isEmpty ? '' : ': $mensagem'}', ancora: 'problemas');
  }

  /// Converte um evento da API. Retorna null para cancelados ou sem data.
  static Evento? eventoDaApi(Map<String, dynamic> j) {
    if (j['status'] == 'cancelled') return null;
    final ini = j['start'] is Map ? Map<String, dynamic>.from(j['start'] as Map) : null;
    final fim = j['end'] is Map ? Map<String, dynamic>.from(j['end'] as Map) : null;
    if (ini == null) return null;
    final diaInteiro = ini['date'] != null;
    final inicio = _lerQuando(ini);
    if (inicio == null) return null;
    final termino = (fim == null ? null : _lerQuando(fim)) ??
        (diaInteiro ? DateTime(inicio.year, inicio.month, inicio.day + 1) : inicio);
    return Evento(
      id: j['id'] as String,
      titulo: (j['summary'] as String? ?? '').trim(),
      inicio: inicio,
      fim: termino,
      diaInteiro: diaInteiro,
      local: (j['location'] as String? ?? '').trim(),
      descricao: _textoDaDescricao(j['description'] as String? ?? ''),
      editavel: j['recurringEventId'] == null && j['recurrence'] == null,
    );
  }

  /// "2026-11-07T19:30:00-03:00" vira 07/11 19:30 (relógio de parede, como no resto da agenda).
  static DateTime? _lerQuando(Map<String, dynamic> q) {
    final data = q['date'] as String?;
    if (data != null) return DateTime.tryParse(data);
    final dh = q['dateTime'] as String?;
    if (dh == null || dh.length < 19) return null;
    return DateTime.tryParse(dh.substring(0, 19));
  }

  /// O Google Agenda guarda a descrição com HTML simples quando editada no navegador.
  static String _textoDaDescricao(String s) => s
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>\s*', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .trim();

  static String _dd(int n) => n.toString().padLeft(2, '0');
  static String _data(DateTime d) => '${d.year}-${_dd(d.month)}-${_dd(d.day)}';
  static String _dataHora(DateTime d) => '${_data(d)}T${_dd(d.hour)}:${_dd(d.minute)}:00';

  /// Limite da consulta: a data de parede com o deslocamento de Brasília (-03:00) basta para a janela.
  static String _instanteUtc(DateTime d) => '${_dataHora(d)}-03:00';
}

/// ID da agenda a partir do "endereço secreto iCal"
/// (https://calendar.google.com/calendar/ical/<id>/private-…/basic.ics). '' se não der para saber.
String calendarioIdDoIcal(String url) {
  final u = Uri.tryParse(url);
  if (u == null || !u.host.endsWith('google.com')) return '';
  final i = u.pathSegments.indexOf('ical');
  if (i < 0 || i + 1 >= u.pathSegments.length) return '';
  return u.pathSegments[i + 1];
}
