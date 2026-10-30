import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'agenda_google_api.dart';
import 'auth.dart';
import 'config.dart';
import 'lgpd.dart';
import 'pagina_inicial.dart';

/// Configurações que o administrador altera pelo painel (/admin), gravadas em data/configuracoes.json.
/// Os valores do config.json valem como padrão até a primeira alteração pelo painel.
class Configuracoes {
  Configuracoes._(this._arquivo, this._valores, this._senhaInicial, {required this.urlDetectada});

  final File _arquivo;
  final Map<String, dynamic> _valores;

  /// senhaAdmin do config.json, usada enquanto a senha não for trocada pelo painel.
  final String _senhaInicial;

  /// Endereço detectado na rede (http://IP:porta), usado quando urlPublica está vazio.
  final String urlDetectada;

  static const nomeIgrejaPadrao = 'Igreja Diakonia Tulipas';

  /// Azul-marinho que o mural sempre usou.
  static const corFundoPadrao = '#0b1026';

  /// Campos que nunca saem do servidor nem vão para o backup.
  static const _segredos = {'senhaHash', 'senhaSal', 'chaveAgente', 'holyricsToken', 'agendaUrl', 'smtpSenha'};

  static Future<Configuracoes> carregar(Config config, {required String urlDetectada}) async {
    final arquivo = File(p.join(config.pastaDados, 'configuracoes.json'));
    final valores = <String, dynamic>{
      'nomeIgreja': nomeIgrejaPadrao,
      'urlPublica': config.urlPublica,
      'pedidoTitulo': 'Pedido de oração',
      'pedidoIntro': 'Conte para nós como podemos orar por você. O pastor recebe todos os pedidos.',
      'pedidoObrigado': 'Estaremos orando por você.',
      'chaveMural': config.chaveMural,
      'chaveAgente': config.chaveAgente,
      'holyricsHost': config.holyricsHost,
      'holyricsPorta': config.holyricsPorta,
      'holyricsToken': config.holyricsToken,
      'motivosPorSlide': 4,
      'segundosPorSlide': 10,
      'diasRespondidas': 30,
      'temaPadrao': '',
      'horaBackup': config.horaBackup,
      'backupsManter': 30,
      'agendaUrl': '',
      'agendaCalendarioId': '',
      'agendaMostrarDescricao': true,
      'agendaDiasMural': 7,
      'smtpHost': '',
      'smtpPorta': 587,
      'smtpSsl': false,
      'smtpUsuario': '',
      'smtpSenha': '',
      'smtpRemetente': '',
      'smtpDestinatario': '',
      'siteAtivo': true,
      'siteAgenda': false,
      'sitePix': true,
      'siteGaleria': true,
      'siteCultos': '',
      'siteEndereco': '',
      'sitePixChave': '',
      'sitePixNome': '',
      'sitePixCidade': '',
      'siteInstagram': '',
      'siteYoutube': '',
      'siteWhatsapp': '',
      'termoLgpdTexto': '', // vazio: termo padrão (termoLgpdPadrao)
      'termoLgpdVersao': 1,
      'visitanteQrAtivo': true,
      'muralBoasVindas': false, // boas-vindas também no mural principal (igreja com uma TV só)
      'textoMotivos': true, // desligado: telão, mural e resumo mostram só por quem orar e a categoria
      // Fundo das TVs: cor, imagem opcional (data/fundos-tv) e quanto escurecer a imagem (%).
      'muralFundoCor': corFundoPadrao,
      'muralFundoImagem': '',
      'muralFundoEscurecer': 55,
      'boasVindasFundoCor': corFundoPadrao,
      'boasVindasFundoImagem': '',
      'boasVindasFundoEscurecer': 55,
    };
    if (await arquivo.exists()) {
      var texto = await arquivo.readAsString();
      if (texto.startsWith('﻿')) texto = texto.substring(1);
      valores.addAll(Map<String, dynamic>.from(jsonDecode(texto) as Map));
    }
    return Configuracoes._(arquivo, valores, config.senhaAdmin, urlDetectada: urlDetectada);
  }

  String _s(String k) => _valores[k] as String? ?? '';
  int _i(String k, int padrao) => (_valores[k] as num?)?.toInt() ?? padrao;

  String get nomeIgreja => _s('nomeIgreja').isEmpty ? nomeIgrejaPadrao : _s('nomeIgreja');
  String get urlPublica => _s('urlPublica');

  /// Endereço base do site: o público configurado ou o detectado na rede.
  String get urlBase => urlPublica.isNotEmpty ? urlPublica : urlDetectada;
  String get urlOracao => '$urlBase/oracao';
  String get urlMensagens => '$urlBase/mensagens';
  String get urlVisitante => '$urlBase/visitante';
  String get urlAutorizar => '$urlBase/autorizar';

  /// Termo de autorização (LGPD) mostrado no link, na recepção e no termo impresso.
  String get termoLgpdTexto => _s('termoLgpdTexto').isEmpty ? termoLgpdPadrao(nomeIgreja) : _s('termoLgpdTexto');
  bool get termoLgpdPersonalizado => _s('termoLgpdTexto').isNotEmpty;

  /// Sobe a cada mudança do texto: cada autorização guarda a versão que a pessoa leu.
  int get termoLgpdVersao => _i('termoLgpdVersao', 1);

  /// Cadastro de visitante pelo QR code da recepção (/visitante).
  bool get visitanteQrAtivo => _valores['visitanteQrAtivo'] as bool? ?? true;

  /// Slide de boas-vindas também no mural principal (o normal é a TV de boas-vindas própria).
  bool get muralBoasVindas => _valores['muralBoasVindas'] as bool? ?? false;

  /// Texto dos pedidos em público (telão, mural, resumo do WhatsApp). Desligado, só por quem orar
  /// e a categoria; nas orações respondidas também some o testemunho.
  bool get textoMotivos => _valores['textoMotivos'] as bool? ?? true;

  /// Fundo de uma TV; [prefixo] é "mural" ou "boasVindas" (ver FundosTv.telas).
  ({String cor, String imagem, int escurecer}) fundoTv(String prefixo) {
    final cor = _s('${prefixo}FundoCor');
    return (
      cor: RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(cor) ? cor.toLowerCase() : corFundoPadrao,
      imagem: _s('${prefixo}FundoImagem'),
      escurecer: _i('${prefixo}FundoEscurecer', 55).clamp(0, 90),
    );
  }

  /// Troca a imagem de fundo de uma TV ('' = sem imagem). Só o envio pelo /admin chama.
  Future<void> definirImagemFundo(String prefixo, String nome) async {
    _valores['${prefixo}FundoImagem'] = nome;
    await _salvar();
  }
  String get pedidoTitulo => _s('pedidoTitulo');
  String get pedidoIntro => _s('pedidoIntro');
  String get pedidoObrigado => _s('pedidoObrigado');
  String get chaveMural => _s('chaveMural');
  String get chaveAgente => _s('chaveAgente');
  String get holyricsHost => _s('holyricsHost').isEmpty ? '127.0.0.1' : _s('holyricsHost');
  int get holyricsPorta => _i('holyricsPorta', 8091);
  String get holyricsToken => _s('holyricsToken');
  int get motivosPorSlide => _i('motivosPorSlide', 4);
  int get segundosPorSlide => _i('segundosPorSlide', 10);
  int get diasRespondidas => _i('diasRespondidas', 30);
  String get temaPadrao => _s('temaPadrao');
  String get horaBackup => _s('horaBackup').isEmpty ? '03:00' : _s('horaBackup');
  int get backupsManter => _i('backupsManter', 30);

  /// Endereço secreto iCal do Google Agenda ('' = sem agenda).
  String get agendaUrl => _s('agendaUrl');
  /// ID da agenda para a API do Google (vazio: tirado do endereço iCal).
  String get agendaCalendarioId =>
      _s('agendaCalendarioId').isNotEmpty ? _s('agendaCalendarioId') : calendarioIdDoIcal(agendaUrl);
  bool get agendaMostrarDescricao => _valores['agendaMostrarDescricao'] as bool? ?? true;
  int get agendaDiasMural => _i('agendaDiasMural', 7);

  // Página inicial pública (/).
  bool get siteAtivo => _valores['siteAtivo'] as bool? ?? true;

  /// Mostrar a agenda na página inicial (desligado: os eventos só aparecem com senha ou chave do mural).
  bool get siteAgenda => _valores['siteAgenda'] as bool? ?? false;

  /// Mostrar o PIX na página inicial (desligar mantém chave, nome e cidade salvos).
  bool get sitePix => _valores['sitePix'] as bool? ?? true;

  /// Mostrar o carrossel de fotos (galeria do site) na página inicial.
  bool get siteGaleria => _valores['siteGaleria'] as bool? ?? true;

  /// PIX ligado e completo (o QR exige chave, nome e cidade).
  bool get pixNoSite => sitePix && sitePixChave.isNotEmpty && sitePixNome.isNotEmpty && sitePixCidade.isNotEmpty;

  /// Uma linha por culto, ex.: "Domingo — 19h".
  String get siteCultos => _s('siteCultos');
  String get siteEndereco => _s('siteEndereco');
  String get sitePixChave => _s('sitePixChave');
  String get sitePixNome => _s('sitePixNome');
  String get sitePixCidade => _s('sitePixCidade');
  String get siteInstagram => _s('siteInstagram');
  String get siteYoutube => _s('siteYoutube');

  /// Só os dígitos (com DDI ou não).
  String get siteWhatsapp => _s('siteWhatsapp');

  String get smtpHost => _s('smtpHost');
  int get smtpPorta => _i('smtpPorta', 587);
  bool get smtpSsl => _valores['smtpSsl'] as bool? ?? false;
  String get smtpUsuario => _s('smtpUsuario');
  String get smtpSenha => _s('smtpSenha');
  String get smtpRemetente => _s('smtpRemetente');
  String get smtpDestinatario => _s('smtpDestinatario');
  bool get smtpConfigurado => smtpHost.isNotEmpty && smtpRemetente.isNotEmpty && smtpDestinatario.isNotEmpty &&
      (smtpUsuario.isEmpty || smtpSenha.isNotEmpty);

  /// Configurações sem segredos (para o painel e para o backup).
  Map<String, dynamic> publicas() => {
        for (final e in _valores.entries)
          if (!_segredos.contains(e.key)) e.key: e.value,
        'holyricsTokenDefinido': holyricsToken.isNotEmpty,
        'agendaConfigurada': agendaUrl.isNotEmpty,
        'smtpSenhaDefinida': smtpSenha.isNotEmpty,
        'smtpConfigurado': smtpConfigurado,
      };

  /// Aplica alterações vindas do painel, validando cada campo. Lança [FormatException].
  Future<void> atualizar(Map<String, dynamic> mudancas) async {
    final novos = <String, dynamic>{};
    String texto(String k, int max, {bool vazio = true}) {
      final v = (mudancas[k] as String? ?? '').trim();
      if (!vazio && v.isEmpty) throw FormatException('Preencha "$k".');
      if (v.length > max) throw FormatException('"$k" muito longo.');
      return v;
    }

    int inteiro(String k, int min, int max) {
      final v = mudancas[k];
      final n = v is num ? v.toInt() : int.tryParse('$v');
      if (n == null || n < min || n > max) throw FormatException('"$k" deve ser entre $min e $max.');
      return n;
    }

    for (final k in mudancas.keys) {
      switch (k) {
        case 'nomeIgreja':
          novos[k] = texto(k, 80, vazio: false);
        case 'urlPublica':
          final v = texto(k, 200).replaceAll(RegExp(r'/+$'), '');
          if (v.isNotEmpty && !RegExp(r'^https?://[^\s/]+$').hasMatch(v)) {
            throw const FormatException('Endereço público inválido. Use algo como https://diako.minhaigreja.com.br');
          }
          novos[k] = v;
        case 'pedidoTitulo':
          novos[k] = texto(k, 80, vazio: false);
        case 'pedidoIntro' || 'pedidoObrigado':
          novos[k] = texto(k, 300);
        case 'temaPadrao':
          novos[k] = texto(k, 80);
        case 'holyricsHost':
          novos[k] = texto(k, 100, vazio: false);
        case 'holyricsPorta':
          novos[k] = inteiro(k, 1, 65535);
        case 'holyricsToken':
          // Vazio mantém o token atual (o painel nunca recebe o valor).
          final v = texto(k, 200);
          if (v.isNotEmpty) novos[k] = v;
        case 'motivosPorSlide':
          novos[k] = inteiro(k, 1, 8);
        case 'segundosPorSlide':
          novos[k] = inteiro(k, 3, 120);
        case 'diasRespondidas':
          novos[k] = inteiro(k, 1, 365);
        case 'backupsManter':
          novos[k] = inteiro(k, 1, 365);
        case 'horaBackup':
          final v = texto(k, 5, vazio: false);
          if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(v)) throw const FormatException('Horário inválido (use HH:MM).');
          novos[k] = v;
        case 'agendaUrl':
          final v = texto(k, 1000);
          if (v.isNotEmpty && !enderecoAgendaValido(v)) {
            throw const FormatException('Endereço da agenda inválido. Cole o "Endereço secreto no formato iCal" do Google Agenda.');
          }
          novos[k] = v;
        case 'agendaCalendarioId':
          final v = texto(k, 300);
          if (v.contains(RegExp(r'[\s/]'))) {
            throw const FormatException('ID da agenda inválido. Copie o "ID da agenda" em Integrar agenda.');
          }
          novos[k] = v;
        case 'agendaMostrarDescricao':
          if (mudancas[k] is! bool) throw const FormatException('"agendaMostrarDescricao" deve ser verdadeiro ou falso.');
          novos[k] = mudancas[k];
        case 'agendaDiasMural':
          novos[k] = inteiro(k, 1, 30);
        case 'siteAtivo' || 'siteAgenda' || 'sitePix' || 'siteGaleria':
          if (mudancas[k] is! bool) throw FormatException('"$k" deve ser verdadeiro ou falso.');
          novos[k] = mudancas[k];
        case 'siteCultos':
          novos[k] = texto(k, 500);
        case 'siteEndereco':
          novos[k] = texto(k, 200);
        case 'sitePixChave':
          // CNPJ/CPF digitado com pontos e barra vira só números, como o Pix exige.
          novos[k] = normalizarChavePix(texto(k, 77));
        case 'sitePixNome':
          // O nome completo aparece na página; no QR (BR Code) vão só as 25 primeiras letras (ver payloadPix).
          novos[k] = texto(k, 100);
        case 'sitePixCidade':
          novos[k] = texto(k, 15);
        case 'siteInstagram' || 'siteYoutube':
          final v = texto(k, 200);
          if (v.isNotEmpty && !RegExp(r'^https://\S+$').hasMatch(v)) {
            throw FormatException('Use o link completo, começando com https://, em "$k".');
          }
          novos[k] = v;
        case 'siteWhatsapp':
          final v = texto(k, 30).replaceAll(RegExp(r'\D'), '');
          if (v.isNotEmpty && (v.length < 10 || v.length > 15)) {
            throw const FormatException('WhatsApp inválido. Use DDD e número, ex.: 11 91234-5678.');
          }
          novos[k] = v;
        case 'smtpHost' || 'smtpUsuario':
          novos[k] = texto(k, 200);
        case 'smtpPorta':
          novos[k] = inteiro(k, 1, 65535);
        case 'smtpSsl':
          if (mudancas[k] is! bool) throw const FormatException('"smtpSsl" deve ser verdadeiro ou falso.');
          novos[k] = mudancas[k];
        case 'smtpRemetente' || 'smtpDestinatario':
          final v = texto(k, 200);
          if (v.isNotEmpty && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v)) {
            throw FormatException('E-mail inválido em "$k".');
          }
          novos[k] = v;
        case 'termoLgpdTexto':
          // Vazio volta ao termo padrão. Texto diferente vira versão nova: as autorizações
          // já dadas continuam apontando para a versão que cada pessoa leu.
          final v = texto(k, 8000);
          final atual = _s('termoLgpdTexto');
          if (v != atual && v != (atual.isEmpty ? termoLgpdPadrao(nomeIgreja) : atual)) {
            novos['termoLgpdVersao'] = termoLgpdVersao + 1;
          }
          novos[k] = v == termoLgpdPadrao(nomeIgreja) ? '' : v;
        case 'muralFundoCor' || 'boasVindasFundoCor':
          final v = texto(k, 7, vazio: false).toLowerCase();
          if (!RegExp(r'^#[0-9a-f]{6}$').hasMatch(v)) throw FormatException('Cor inválida em "$k" (use #rrggbb).');
          novos[k] = v;
        case 'muralFundoEscurecer' || 'boasVindasFundoEscurecer':
          novos[k] = inteiro(k, 0, 90);
        case 'visitanteQrAtivo' || 'muralBoasVindas' || 'textoMotivos':
          if (mudancas[k] is! bool) throw FormatException('"$k" deve ser verdadeiro ou falso.');
          novos[k] = mudancas[k];
        case 'smtpSenha':
          final v = texto(k, 300);
          if (v.isNotEmpty) novos[k] = v;
        default:
          throw FormatException('Campo desconhecido: $k');
      }
    }
    _valores.addAll(novos);
    await _salvar();
  }

  /// Restaura configurações públicas de um backup (ignora segredos e campos desconhecidos).
  Future<void> restaurarPublicas(Map<String, dynamic> dados) async {
    final permitidos = {
      'nomeIgreja', 'urlPublica', 'pedidoTitulo', 'pedidoIntro', 'pedidoObrigado', 'chaveMural',
      'holyricsHost', 'holyricsPorta', 'motivosPorSlide', 'segundosPorSlide', 'diasRespondidas',
      'temaPadrao', 'horaBackup', 'backupsManter', 'agendaMostrarDescricao', 'agendaDiasMural', 'agendaCalendarioId',
      'smtpHost', 'smtpPorta', 'smtpSsl', 'smtpUsuario', 'smtpRemetente', 'smtpDestinatario',
      'siteAtivo', 'siteAgenda', 'sitePix', 'siteGaleria', 'siteCultos', 'siteEndereco', 'sitePixChave', 'sitePixNome', 'sitePixCidade',
      'siteInstagram', 'siteYoutube', 'siteWhatsapp', 'termoLgpdTexto', 'termoLgpdVersao', 'visitanteQrAtivo', 'muralBoasVindas',
      'textoMotivos', 'muralFundoCor', 'muralFundoImagem', 'muralFundoEscurecer',
      'boasVindasFundoCor', 'boasVindasFundoImagem', 'boasVindasFundoEscurecer',
    };
    for (final e in dados.entries) {
      if (permitidos.contains(e.key)) _valores[e.key] = e.value;
    }
    await _salvar();
  }

  /// Nova chave do mural ('' desativa a proteção).
  Future<String> novaChaveMural({bool desativar = false}) async {
    _valores['chaveMural'] = desativar ? '' : gerarSegredo(15);
    await _salvar();
    return chaveMural;
  }

  /// Nova chave do agente (o agente.json do PC da igreja precisa ser atualizado).
  Future<String> novaChaveAgente() async {
    _valores['chaveAgente'] = gerarSegredo(30);
    await _salvar();
    return chaveAgente;
  }

  // ---------- Senha ----------

  bool conferirSenha(String senha) {
    final hash = _s('senhaHash'), sal = _s('senhaSal');
    if (hash.isEmpty || sal.isEmpty) return iguaisSeguro(senha, _senhaInicial);
    return conferirHashSenha(senha, hash: hash, sal: sal);
  }

  Future<void> trocarSenha(String nova, {required int minimo}) async {
    if (nova.trim().length < minimo) throw FormatException('A senha precisa ter pelo menos $minimo caracteres.');
    final h = gerarHashSenha(nova.trim());
    _valores['senhaSal'] = h.sal;
    _valores['senhaHash'] = h.hash;
    await _salvar();
  }

  Future<void> _salvar() async {
    await _arquivo.parent.create(recursive: true);
    final tmp = File('${_arquivo.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(_valores), flush: true);
    await tmp.rename(_arquivo.path);
  }
}

/// Aceita https (Google Agenda ou qualquer .ics) e http só em localhost (testes).
bool enderecoAgendaValido(String v) {
  final u = Uri.tryParse(v);
  if (u == null || u.host.isEmpty) return false;
  if (u.scheme == 'https') return true;
  return u.scheme == 'http' && (u.host == 'localhost' || u.host == '127.0.0.1');
}
