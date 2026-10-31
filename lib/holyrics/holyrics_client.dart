import '../sync/server_api.dart';
import 'agente_local.dart';

/// Erro com mensagem pronta para mostrar ao usuário.
class HolyricsException extends ErroAmigavel {
  HolyricsException(this.message);
  @override
  final String message;
}

/// O que está sendo projetado agora (resposta de GetCurrentPresentation).
class Apresentacao {
  Apresentacao({required this.tipo, required this.nome, this.slide, this.totalSlides, this.tipoSlide});

  final String tipo;
  final String nome;
  final int? slide;
  final int? totalSlides;
  final String? tipoSlide;

  bool get rapida => tipo == 'quick_presentation';

  factory Apresentacao.fromJson(Map<String, dynamic> j) => Apresentacao(
        tipo: j['type'] as String? ?? '',
        nome: j['name'] as String? ?? '',
        slide: j['slide_number'] as int?,
        totalSlides: j['total_slides'] as int?,
        tipoSlide: j['slide_type'] as String?,
      );
}

/// Comandos para o Holyrics. Com o tablet pareado, vão primeiro direto ao agente do PC da igreja
/// pela rede local; senão (ou se ele não responder), passam pelo servidor DiakoHub, que guarda
/// o token e repassa para a API Server do Holyrics.
/// Docs: https://github.com/holyrics/API-Server
class HolyricsClient {
  HolyricsClient(this._api, {this.local});

  final ServerApi _api;
  final AgenteLocal? local;

  Future<dynamic> call(String action, [Map<String, dynamic> body = const {}]) async {
    final relogio = Stopwatch()..start();
    final viaLocal = await local?.holyrics(action, body);
    final Map<String, dynamic> json;
    if (viaLocal != null) {
      json = viaLocal;
      local!.registrar('rede local', relogio.elapsedMilliseconds);
    } else {
      json = await _api.holyrics(action, body);
      if (local?.configurado ?? false) local!.registrar('internet', relogio.elapsedMilliseconds);
    }
    if (json['status'] != 'ok') {
      final erro = json['error'];
      throw HolyricsException(
          erro == 'invalid token' ? 'Token do Holyrics inválido (config.json do servidor).' : 'Holyrics: ${erro ?? 'erro desconhecido'}');
    }
    return json['data'];
  }

  Map<String, dynamic> _tema(String? tema) =>
      tema == null || tema.isEmpty ? {} : {'theme': {'name': tema}};

  Future<void> testar() => call('GetCPInfo');

  Future<Apresentacao?> apresentacaoAtual() async {
    final data = await call('GetCurrentPresentation');
    return data is Map ? Apresentacao.fromJson(Map<String, dynamic>.from(data)) : null;
  }

  Future<void> projetarTexto(String texto, {String? tema}) =>
      call('ShowQuickPresentation', {'text': texto, ..._tema(tema)});

  /// Um slide por item, passando sozinho (requer Holyrics v2.23+).
  Future<void> projetarSequencia(List<String> slides, {String? tema, required int segundos, required bool repetir}) =>
      call('ShowQuickPresentation', {
        'slides': [for (final s in slides) {'text': s, 'duration': segundos}],
        'automatic': {'seconds': segundos, 'repeat': repetir},
        ..._tema(tema),
      });

  Future<void> mostrarImagem(String arquivo) => call('ShowImage', {'file': arquivo});

  Future<void> proximo({bool rapida = false}) => call(rapida ? 'ActionNextQuickPresentation' : 'ActionNext');
  Future<void> anterior({bool rapida = false}) =>
      call(rapida ? 'ActionPreviousQuickPresentation' : 'ActionPrevious');

  Future<void> encerrar() => call('CloseCurrentPresentation');

  /// Tela vazia (F9). O F9 do Holyrics só esconde texto: com uma imagem no ar (QR, cartaz) ela
  /// continuaria no telão. Nesse caso entra antes um slide em branco, no [tema] dos recados.
  Future<void> telaVazia(bool ativar, {String? tema}) async {
    if (ativar && (await apresentacaoAtual())?.tipo == 'image') await projetarTexto(' ', tema: tema);
    await call('SetF9', {'enable': ativar});
  }
  Future<void> telaPreta(bool ativar) => call('SetF10', {'enable': ativar});

  Future<void> mensagemPalco(String texto, {bool mostrar = true}) =>
      call('SetTextCP', {
        'text': texto,
        'show': mostrar,
        'display_ahead': mostrar,
        // Sem tema: só o texto, sobre o que já está na TV do palco.
        'custom_theme': {
          'background': {'type': 'transparent', 'id': 'transparent'},
          'font': {'bold': true, 'size': 14, 'color': 'FFFFFF'},
          'align': {'horizontal': 'center', 'vertical': 'middle'},
          'effect': {'shadow_color': '000000', 'shadow_x_weight': 20, 'shadow_y_weight': 20},
        },
      });

  /// Trecho da Palavra na TV do palco, para o pastor ler: alinhado à esquerda, no alto, sem negrito.
  Future<void> leituraPalco(String texto) =>
      call('SetTextCP', {
        'text': texto,
        'show': true,
        'display_ahead': true,
        'custom_theme': {
          'background': {'type': 'transparent', 'id': 'transparent'},
          'font': {'bold': false, 'color': 'FFFFFF'},
          'align': {'horizontal': 'left', 'vertical': 'top'},
        },
      });

  /// Versículos no telão, na versão padrão do Holyrics. [ids] no formato LLCCCVVV (livro, capítulo,
  /// versículo), que não depende do idioma das abreviações.
  // Ainda não testado na igreja (roteiro de teste em docs/modo-culto.html): se a versão do Holyrics
  // não aceitar ids, é aqui que se troca por references.
  Future<void> mostrarVersiculo(List<String> ids) => call('ShowVerse', {'ids': ids});

  Future<void> contagemPalco(int minutos) =>
      call('StartCountdownCP', {'minutes': minutos, 'seconds': 0, 'yellow_starts_at': 60, 'stop_at_zero': true});
  Future<void> pararContagemPalco() => call('StopCountdownCP');

  /// [tempo] em "MM:SS" (duração) ou "HH:MM" quando [horaExata].
  Future<void> contagemTela(String tempo, {bool horaExata = false, String textoAntes = '', String? tema}) =>
      call('ShowCountdown', {
        'time': tempo,
        'exact_time': horaExata,
        'text_before': textoAntes,
        'zero_fill': true,
        ..._tema(tema),
      });

  /// Nomes dos temas cadastrados (Holyrics v2.27+).
  Future<List<String>> temas() async {
    final data = await call('GetThemes');
    if (data is! List) return [];
    return [for (final t in data) if (t is Map && t['name'] is String) t['name'] as String];
  }
}
