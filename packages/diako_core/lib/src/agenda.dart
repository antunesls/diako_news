/// Eventos da agenda da igreja (Google Agenda via endereço iCal).
/// Datas são sempre o horário local da igreja ("relógio de parede"), sem fuso.
class Evento {
  Evento({
    required this.id,
    required this.titulo,
    required this.inicio,
    required this.fim,
    this.diaInteiro = false,
    this.local = '',
    this.descricao = '',
  });

  final String id;
  final String titulo;
  final DateTime inicio;

  /// Exclusivo: num evento de dia inteiro em 02/11, fim = 03/11 00:00.
  final DateTime fim;
  final bool diaInteiro;
  final String local;
  final String descricao;

  Map<String, dynamic> toJson() => {
        'id': id,
        'titulo': titulo,
        'inicio': inicio.toIso8601String(),
        'fim': fim.toIso8601String(),
        'diaInteiro': diaInteiro,
        'local': local,
        'descricao': descricao,
      };

  factory Evento.fromJson(Map<String, dynamic> j) => Evento(
        id: j['id'] as String,
        titulo: j['titulo'] as String? ?? '',
        inicio: DateTime.parse(j['inicio'] as String),
        fim: DateTime.parse(j['fim'] as String),
        diaInteiro: j['diaInteiro'] as bool? ?? false,
        local: j['local'] as String? ?? '',
        descricao: j['descricao'] as String? ?? '',
      );
}

// ---------- Leitura do ICS ----------

class _Prop {
  _Prop(this.nome, this.params, this.valor);
  final String nome;
  final Map<String, String> params;
  final String valor;
}

class _VEvento {
  final props = <_Prop>[];
  _Prop? um(String nome) => props.where((p) => p.nome == nome).firstOrNull;
  Iterable<_Prop> todos(String nome) => props.where((p) => p.nome == nome);
  String texto(String nome) => _desescapar(um(nome)?.valor ?? '').trim();
}

/// Lê o conteúdo de um arquivo .ics e devolve as ocorrências que se sobrepõem a [de, ate),
/// em ordem. Recorrências (RRULE) são expandidas; EXDATE, ocorrências editadas
/// (RECURRENCE-ID) e canceladas são respeitadas.
/// [offsetMinutos]: fuso da igreja, usado para horários em UTC (padrão: Brasília, -03:00).
List<Evento> lerIcs(String ics, {required DateTime de, required DateTime ate, int offsetMinutos = -180}) {
  final eventos = _separar(ics);
  final mestres = <_VEvento>[];
  final excecoes = <String, Map<DateTime, _VEvento>>{}; // uid -> RECURRENCE-ID -> evento editado
  for (final e in eventos) {
    final rid = e.um('RECURRENCE-ID');
    if (rid != null) {
      final quando = _data(rid, offsetMinutos)?.data;
      if (quando != null) (excecoes[e.texto('UID')] ??= {})[quando] = e;
    } else {
      mestres.add(e);
    }
  }

  final resultado = <Evento>[];
  final usadas = <String, Set<DateTime>>{};

  void adicionar(_VEvento e, DateTime inicio, Duration duracao, bool diaInteiro) {
    if (e.texto('STATUS').toUpperCase() == 'CANCELLED') return;
    final fim = inicio.add(duracao);
    if (!fim.isAfter(de) || !inicio.isBefore(ate)) return;
    resultado.add(Evento(
      id: '${e.texto('UID')}@${inicio.toIso8601String()}',
      titulo: e.texto('SUMMARY').isEmpty ? '(sem título)' : e.texto('SUMMARY'),
      inicio: inicio,
      fim: fim,
      diaInteiro: diaInteiro,
      local: e.texto('LOCATION'),
      descricao: _limparDescricao(e.texto('DESCRIPTION')),
    ));
  }

  ({Duration duracao, bool diaInteiro, DateTime inicio})? tempos(_VEvento e) {
    final ini = _data(e.um('DTSTART'), offsetMinutos);
    if (ini == null) return null;
    final fimProp = _data(e.um('DTEND'), offsetMinutos);
    var duracao = fimProp != null
        ? fimProp.data.difference(ini.data)
        : (_duracao(e.texto('DURATION')) ?? (ini.diaInteiro ? const Duration(days: 1) : Duration.zero));
    if (duracao.isNegative) duracao = Duration.zero;
    return (duracao: duracao, diaInteiro: ini.diaInteiro, inicio: ini.data);
  }

  for (final e in mestres) {
    if (e.texto('STATUS').toUpperCase() == 'CANCELLED') continue;
    final t = tempos(e);
    if (t == null) continue;
    final uid = e.texto('UID');
    final regra = e.um('RRULE')?.valor;
    final ocorrencias = regra == null
        ? [t.inicio]
        : _expandir(t.inicio, regra, de.subtract(t.duracao), ate, offsetMinutos);
    final excluidas = <DateTime>{
      for (final ex in e.todos('EXDATE'))
        for (final parte in ex.valor.split(','))
          if (_data(_Prop('EXDATE', ex.params, parte), offsetMinutos) case final d?) d.data,
    };
    final editadas = excecoes[uid] ?? const {};
    for (final inicio in ocorrencias) {
      if (excluidas.contains(inicio)) continue;
      final editado = editadas[inicio];
      if (editado != null) {
        final te = tempos(editado);
        if (te != null) adicionar(editado, te.inicio, te.duracao, te.diaInteiro);
        (usadas[uid] ??= {}).add(inicio);
      } else {
        adicionar(e, inicio, t.duracao, t.diaInteiro);
      }
    }
  }

  // Ocorrências editadas cuja data original ficou fora da janela, mas a nova está dentro.
  excecoes.forEach((uid, mapa) {
    mapa.forEach((original, e) {
      if (usadas[uid]?.contains(original) ?? false) return;
      final te = tempos(e);
      if (te != null && !resultado.any((r) => r.id == '${e.texto('UID')}@${te.inicio.toIso8601String()}')) {
        adicionar(e, te.inicio, te.duracao, te.diaInteiro);
      }
    });
  });

  resultado.sort((a, b) {
    final c = a.inicio.compareTo(b.inicio);
    return c != 0 ? c : a.titulo.compareTo(b.titulo);
  });
  return resultado;
}

List<_VEvento> _separar(String ics) {
  // Desdobra linhas continuadas (RFC 5545: quebra seguida de espaço ou tab).
  final texto = ics.replaceAll('\r\n', '\n').replaceAll('\r', '\n').replaceAll(RegExp(r'\n[ \t]'), '');
  final eventos = <_VEvento>[];
  _VEvento? atual;
  var profundidade = 0; // ignora VALARM dentro do VEVENT
  for (final linha in texto.split('\n')) {
    if (linha.isEmpty) continue;
    final p = _prop(linha);
    if (p == null) continue;
    if (p.nome == 'BEGIN') {
      if (p.valor.toUpperCase() == 'VEVENT') {
        atual = _VEvento();
        profundidade = 0;
      } else if (atual != null) {
        profundidade++;
      }
      continue;
    }
    if (p.nome == 'END') {
      if (p.valor.toUpperCase() == 'VEVENT' && atual != null) {
        eventos.add(atual);
        atual = null;
      } else if (atual != null && profundidade > 0) {
        profundidade--;
      }
      continue;
    }
    if (atual != null && profundidade == 0) atual.props.add(p);
  }
  return eventos;
}

_Prop? _prop(String linha) {
  // O ":" que separa o valor é o primeiro fora de aspas.
  var aspas = false;
  var sep = -1;
  for (var i = 0; i < linha.length; i++) {
    final c = linha[i];
    if (c == '"') aspas = !aspas;
    if (c == ':' && !aspas) {
      sep = i;
      break;
    }
  }
  if (sep < 0) return null;
  final cabecalho = linha.substring(0, sep).split(';');
  final params = <String, String>{};
  for (final par in cabecalho.skip(1)) {
    final i = par.indexOf('=');
    if (i > 0) params[par.substring(0, i).toUpperCase()] = par.substring(i + 1).replaceAll('"', '');
  }
  return _Prop(cabecalho.first.toUpperCase(), params, linha.substring(sep + 1));
}

String _desescapar(String v) {
  final b = StringBuffer();
  for (var i = 0; i < v.length; i++) {
    final c = v[i];
    if (c == '\\' && i + 1 < v.length) {
      final n = v[++i];
      b.write(switch (n) { 'n' || 'N' => '\n', _ => n });
    } else {
      b.write(c);
    }
  }
  return b.toString();
}

/// O Google pode mandar a descrição com HTML simples: vira texto.
String _limparDescricao(String d) => d
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

({DateTime data, bool diaInteiro})? _data(_Prop? p, int offsetMinutos) {
  if (p == null) return null;
  final v = p.valor.trim();
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$').firstMatch(v);
  if (m == null) return null;
  int g(int i) => int.parse(m.group(i) ?? '0');
  if (m.group(4) == null || p.params['VALUE'] == 'DATE') {
    return (data: DateTime(g(1), g(2), g(3)), diaInteiro: true);
  }
  if (m.group(7) == 'Z') {
    final local = DateTime.utc(g(1), g(2), g(3), g(4), g(5), g(6)).add(Duration(minutes: offsetMinutos));
    return (data: DateTime(local.year, local.month, local.day, local.hour, local.minute, local.second), diaInteiro: false);
  }
  // Horário local ou com TZID: tratado como o horário da igreja.
  return (data: DateTime(g(1), g(2), g(3), g(4), g(5), g(6)), diaInteiro: false);
}

Duration? _duracao(String v) {
  final m = RegExp(r'^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$').firstMatch(v.trim());
  if (m == null || v.trim().isEmpty) return null;
  int g(int i) => int.parse(m.group(i) ?? '0');
  final d = Duration(days: g(2) * 7 + g(3), hours: g(4), minutes: g(5), seconds: g(6));
  return m.group(1) == '-' ? -d : d;
}

const _dias = {'MO': 1, 'TU': 2, 'WE': 3, 'TH': 4, 'FR': 5, 'SA': 6, 'SU': 7};

/// Gera os inícios das ocorrências de [inicio] segundo a [regra] (RRULE) até [ate].
List<DateTime> _expandir(DateTime inicio, String regra, DateTime de, DateTime ate, int offsetMinutos) {
  final r = <String, String>{
    for (final par in regra.split(';'))
      if (par.contains('=')) par.substring(0, par.indexOf('=')).toUpperCase(): par.substring(par.indexOf('=') + 1),
  };
  final freq = r['FREQ'] ?? '';
  final intervalo = int.tryParse(r['INTERVAL'] ?? '') ?? 1;
  final contagem = int.tryParse(r['COUNT'] ?? '');
  final ateRegra = r['UNTIL'] == null ? null : _data(_Prop('UNTIL', const {}, r['UNTIL']!), offsetMinutos);
  // UNTIL só com data inclui o dia inteiro.
  final limite = ateRegra == null
      ? null
      : (ateRegra.diaInteiro ? ateRegra.data.add(const Duration(days: 1)) : ateRegra.data.add(const Duration(seconds: 1)));
  final porDia = [
    for (final d in (r['BYDAY'] ?? '').split(',').where((s) => s.isNotEmpty))
      if (RegExp(r'^([+-]?\d{1,2})?(MO|TU|WE|TH|FR|SA|SU)$').firstMatch(d.toUpperCase()) case final m?)
        (ordem: int.tryParse(m.group(1) ?? ''), dia: _dias[m.group(2)]!),
  ];
  final porDiaMes = (r['BYMONTHDAY'] ?? '').split(',').map(int.tryParse).whereType<int>().toList();
  final porMes = (r['BYMONTH'] ?? '').split(',').map(int.tryParse).whereType<int>().toList();

  DateTime naHora(DateTime dia) => DateTime(dia.year, dia.month, dia.day, inicio.hour, inicio.minute, inicio.second);

  List<DateTime> doMes(int ano, int mes) {
    final ultimo = DateTime(ano, mes + 1, 0).day;
    final dias = <int>{};
    if (porDia.isNotEmpty) {
      for (final b in porDia) {
        final candidatos = [for (var d = 1; d <= ultimo; d++) if (DateTime(ano, mes, d).weekday == b.dia) d];
        final o = b.ordem;
        if (o == null || o == 0) {
          dias.addAll(candidatos);
        } else if (o > 0 && o <= candidatos.length) {
          dias.add(candidatos[o - 1]);
        } else if (o < 0 && -o <= candidatos.length) {
          dias.add(candidatos[candidatos.length + o]);
        }
      }
    } else if (porDiaMes.isNotEmpty) {
      for (final d in porDiaMes) {
        final dia = d > 0 ? d : ultimo + d + 1;
        if (dia >= 1 && dia <= ultimo) dias.add(dia);
      }
    } else if (inicio.day <= ultimo) {
      dias.add(inicio.day);
    }
    return [for (final d in dias.toList()..sort()) naHora(DateTime(ano, mes, d))];
  }

  final saida = <DateTime>[];
  var total = 0;
  bool encerrou(DateTime c) => (limite != null && !c.isBefore(limite)) || (contagem != null && total >= contagem) || c.isAfter(ate);

  for (var k = 0; k < 5000; k++) {
    List<DateTime> candidatos;
    switch (freq) {
      case 'DAILY':
        candidatos = [naHora(DateTime(inicio.year, inicio.month, inicio.day + k * intervalo))];
      case 'WEEKLY':
        final segunda = DateTime(inicio.year, inicio.month, inicio.day - (inicio.weekday - 1) + k * 7 * intervalo);
        final dias = porDia.isEmpty ? [inicio.weekday] : (porDia.map((b) => b.dia).toSet().toList()..sort());
        candidatos = [for (final d in dias) naHora(DateTime(segunda.year, segunda.month, segunda.day + d - 1))];
      case 'MONTHLY':
        final m = DateTime(inicio.year, inicio.month + k * intervalo);
        candidatos = doMes(m.year, m.month);
      case 'YEARLY':
        final ano = inicio.year + k * intervalo;
        final meses = porMes.isEmpty ? [inicio.month] : porMes;
        candidatos = [
          for (final mes in meses)
            if (porDia.isEmpty && porDiaMes.isEmpty)
              if (inicio.day <= DateTime(ano, mes + 1, 0).day) naHora(DateTime(ano, mes, inicio.day)) else ...[]
            else
              ...doMes(ano, mes),
        ];
      default:
        return [inicio];
    }
    if (candidatos.isNotEmpty && candidatos.first.isAfter(ate) && candidatos.every((c) => c.isAfter(ate))) break;
    for (final c in candidatos..sort()) {
      if (c.isBefore(inicio)) continue;
      if (encerrou(c)) return saida;
      total++;
      if (!c.isBefore(de)) saida.add(c);
    }
  }
  return saida;
}

// ---------- Textos ----------

const _nomesDias = ['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'];
const _nomesDiasCurtos = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];

String _dd(int n) => n.toString().padLeft(2, '0');
String _ddmm(DateTime d) => '${_dd(d.day)}/${_dd(d.month)}';

/// "19h30" ou "19h"
String horaCurta(DateTime d) => d.minute == 0 ? '${d.hour}h' : '${d.hour}h${_dd(d.minute)}';

/// "Sábado, 02/11"
String diaPorExtenso(DateTime d) {
  final n = _nomesDias[d.weekday - 1];
  return '${n[0].toUpperCase()}${n.substring(1)}, ${_ddmm(d)}';
}

/// "sáb 02/11"
String diaCurto(DateTime d) => '${_nomesDiasCurtos[d.weekday - 1]} ${_ddmm(d)}';

/// "19h30–21h", "19h30", "Dia inteiro" ou "Até sex 30/10" (vários dias)
String horario(Evento e) {
  if (e.diaInteiro) {
    final ultimoDia = e.fim.subtract(const Duration(days: 1));
    return ultimoDia.isAfter(e.inicio) ? 'Até ${diaCurto(ultimoDia)}' : 'Dia inteiro';
  }
  if (!e.fim.isAfter(e.inicio)) return horaCurta(e.inicio);
  final mesmoDia = e.fim.year == e.inicio.year && e.fim.month == e.inicio.month && e.fim.day == e.inicio.day;
  return mesmoDia ? '${horaCurta(e.inicio)}–${horaCurta(e.fim)}' : horaCurta(e.inicio);
}

/// "Sábado, 02/11 · 19h30–21h"
String quandoPorExtenso(Evento e) => '${diaPorExtenso(e.inicio)} · ${horario(e)}';

/// Slide para o Holyrics: título, quando e onde.
String montarSlideEvento(Evento e, {bool negritoTitulo = true}) => [
      negritoTitulo ? '<b>${e.titulo}</b>' : e.titulo,
      quandoPorExtenso(e),
      if (e.local.isNotEmpty) e.local,
    ].join('\n');

/// Eventos que ainda não terminaram e começam até [dias] à frente.
List<Evento> proximosEventos(List<Evento> eventos, DateTime agora, {int dias = 30}) {
  final limite = DateTime(agora.year, agora.month, agora.day + dias + 1);
  return [for (final e in eventos) if (e.fim.isAfter(agora) && e.inicio.isBefore(limite)) e];
}

/// Texto do recado criado a partir do evento.
String textoRecadoDoEvento(Evento e) => [quandoPorExtenso(e), if (e.local.isNotEmpty) e.local].join('\n');
