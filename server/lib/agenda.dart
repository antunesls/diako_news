import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:diako_core/diako_core.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Agenda da igreja lida do Google Agenda pelo endereço secreto no formato iCal.
/// Baixa periodicamente e guarda a última cópia boa em data/agenda.ics, para continuar
/// mostrando os eventos mesmo se a internet cair.
class AgendaGoogle {
  AgendaGoogle({
    required String pastaDados,
    required this.url,
    http.Client? cliente,
    this.aoMudar,
    DateTime Function()? relogio,
    this.intervalo = const Duration(minutes: 15),
  })  : _http = cliente ?? http.Client(),
        _agora = relogio ?? DateTime.now,
        _arquivo = File(p.join(pastaDados, 'agenda.ics')),
        _estado = File(p.join(pastaDados, 'agenda.json'));

  /// Endereço atual (lido das configurações a cada atualização).
  final String Function() url;
  final void Function()? aoMudar;
  final Duration intervalo;
  final http.Client _http;
  final DateTime Function() _agora;
  final File _arquivo;
  final File _estado;

  String? _ics;
  String? _etag;
  String? _urlDoCache;
  DateTime? ultimaAtualizacao;
  String? erro;
  Timer? _timer;
  Future<bool>? _emAndamento;

  // Memória da última leitura (o mural consulta a cada minuto).
  ({String chave, List<Evento> eventos})? _memo;

  static const timeout = Duration(seconds: 20);

  bool get configurada => url().isNotEmpty;

  Future<void> carregar() async {
    if (await _arquivo.exists()) _ics = await _arquivo.readAsString();
    if (await _estado.exists()) {
      try {
        final j = jsonDecode(await _estado.readAsString()) as Map<String, dynamic>;
        ultimaAtualizacao = DateTime.tryParse(j['atualizado'] as String? ?? '');
        _etag = j['etag'] as String?;
        _urlDoCache = j['url'] as String?;
        erro = j['erro'] as String?;
      } catch (_) {}
    }
    // A cópia guardada é de outro endereço (trocado com o servidor parado): descarta.
    if (_urlDoCache != null && _urlDoCache != url()) await _limpar();
  }

  void iniciar() {
    _timer?.cancel();
    unawaited(atualizarAgora());
    _timer = Timer.periodic(intervalo, (_) => atualizarAgora());
  }

  void parar() => _timer?.cancel();

  /// Baixa a agenda agora. Retorna true se os eventos mudaram.
  Future<bool> atualizarAgora() => _emAndamento ??= _atualizar().whenComplete(() => _emAndamento = null);

  Future<bool> _atualizar() async {
    final endereco = url();
    if (endereco != _urlDoCache && (_ics != null || _urlDoCache != null)) {
      // Endereço trocado ou removido no /admin: a agenda antiga não vale mais.
      await _limpar();
      aoMudar?.call();
    }
    if (endereco.isEmpty) return false;
    try {
      final r = await _http.get(Uri.parse(endereco), headers: {if (_etag != null) 'If-None-Match': _etag!}).timeout(timeout);
      if (r.statusCode == 304) {
        await _gravarEstado(erro: null);
        return false;
      }
      if (r.statusCode != 200) throw HttpException(_mensagemHttp(r.statusCode));
      final texto = utf8.decode(r.bodyBytes, allowMalformed: true);
      if (!texto.contains('BEGIN:VCALENDAR')) {
        throw const FormatException('O endereço não devolveu uma agenda no formato iCal.');
      }
      final mudou = texto != _ics;
      _ics = texto;
      _etag = r.headers['etag'];
      _urlDoCache = endereco;
      if (mudou) {
        _memo = null;
        final tmp = File('${_arquivo.path}.tmp');
        await tmp.writeAsString(texto, flush: true);
        await tmp.rename(_arquivo.path);
      }
      await _gravarEstado(erro: null);
      if (mudou) aoMudar?.call();
      return mudou;
    } catch (e) {
      await _gravarEstado(erro: _resumo(e));
      return false;
    }
  }

  /// Eventos (ocorrências) que se sobrepõem a [de, ate).
  List<Evento> eventos({required DateTime de, required DateTime ate}) {
    final ics = _ics;
    if (ics == null || !configurada) return const [];
    final chave = '${ics.length}|${ics.hashCode}|$de|$ate';
    final m = _memo;
    if (m != null && m.chave == chave) return m.eventos;
    final lista = lerIcs(ics, de: de, ate: ate);
    _memo = (chave: chave, eventos: lista);
    return lista;
  }

  /// Próximos eventos a partir de agora (o que ainda não terminou), por [dias].
  List<Evento> proximos({int dias = 30}) {
    final agora = _agora();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    return proximosEventos(eventos(de: hoje, ate: hoje.add(Duration(days: dias + 1))), agora, dias: dias);
  }

  Map<String, dynamic> estado() => {
        'configurada': configurada,
        'atualizado': ultimaAtualizacao?.toIso8601String(),
        'erro': erro,
        'proximos30dias': configurada ? proximos().length : 0,
      };

  /// Testa um endereço antes de salvar: devolve os próximos eventos ou lança uma mensagem amigável.
  static Future<List<Evento>> testar(String endereco, {http.Client? cliente, DateTime? agora}) async {
    final c = cliente ?? http.Client();
    final http.Response r;
    try {
      r = await c.get(Uri.parse(endereco)).timeout(timeout);
    } catch (e) {
      throw FormatException('Não foi possível acessar o endereço: ${_resumo(e)}');
    }
    if (r.statusCode != 200) throw FormatException(_mensagemHttp(r.statusCode));
    final texto = utf8.decode(r.bodyBytes, allowMalformed: true);
    if (!texto.contains('BEGIN:VCALENDAR')) {
      throw const FormatException('O endereço não devolveu uma agenda no formato iCal. Copie o "Endereço secreto no formato iCal".');
    }
    final a = agora ?? DateTime.now();
    final hoje = DateTime(a.year, a.month, a.day);
    return proximosEventos(lerIcs(texto, de: hoje, ate: hoje.add(const Duration(days: 61))), a, dias: 60);
  }

  Future<void> _limpar() async {
    _ics = null;
    _etag = null;
    _urlDoCache = null;
    _memo = null;
    ultimaAtualizacao = null;
    erro = null;
    if (await _arquivo.exists()) await _arquivo.delete();
    if (await _estado.exists()) await _estado.delete();
  }

  Future<void> _gravarEstado({required String? erro}) async {
    this.erro = erro;
    if (erro == null) ultimaAtualizacao = _agora();
    await _estado.writeAsString(jsonEncode({
      'atualizado': ultimaAtualizacao?.toIso8601String(),
      'etag': _etag,
      'url': _urlDoCache,
      'erro': erro,
    }));
  }

  static String _mensagemHttp(int status) => switch (status) {
        404 => 'Agenda não encontrada (404). Confira o endereço secreto iCal.',
        401 || 403 => 'Sem permissão ($status). Use o "Endereço secreto no formato iCal".',
        _ => 'O Google respondeu HTTP $status.',
      };

  static String _resumo(Object e) => e is FormatException ? e.message : e.toString().split('\n').first;
}
