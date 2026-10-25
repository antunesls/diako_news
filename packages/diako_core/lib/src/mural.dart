import 'motivo.dart';
import 'recado.dart';

/// Um slide do mural da TV da recepção.
class SlideMural {
  const SlideMural._(this.tipo, {this.titulo = '', this.texto = '', this.itens = const [], this.imagem, this.corArgb});

  /// Recado em texto.
  factory SlideMural.texto(String titulo, String texto, {int? corArgb}) =>
      SlideMural._('texto', titulo: titulo, texto: texto, corArgb: corArgb);

  /// Cartaz em tela cheia.
  factory SlideMural.imagem(String titulo, String url) => SlideMural._('imagem', titulo: titulo, imagem: url);

  /// Lista com título (motivos, orações respondidas).
  factory SlideMural.lista(String titulo, List<String> itens, {int? corArgb}) =>
      SlideMural._('lista', titulo: titulo, itens: itens, corArgb: corArgb);

  /// QR code com chamada.
  factory SlideMural.qr(String titulo, String texto, String url) =>
      SlideMural._('qr', titulo: titulo, texto: texto, imagem: url);

  final String tipo;
  final String titulo;
  final String texto;
  final List<String> itens;
  final String? imagem;
  final int? corArgb;

  Map<String, dynamic> toJson() => {
        'tipo': tipo,
        'titulo': titulo,
        if (texto.isNotEmpty) 'texto': texto,
        if (itens.isNotEmpty) 'itens': itens,
        if (imagem != null) 'imagem': imagem,
        if (corArgb != null) 'cor': '#${(corArgb! & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
      };
}

const _corOracao = 0xFFAB47BC;
const _corGratidao = 0xFF26A69A;

/// Sequência de slides do mural. Só entra o que pode ser público:
/// recados válidos, motivos aprovados e públicos e orações respondidas públicas.
/// [urlCartaz] converte o caminho do Holyrics em endereço da imagem (null = mostra o texto).
List<SlideMural> montarMural({
  required List<Recado> recados,
  required List<Motivo> motivos,
  required DateTime agora,
  required String? Function(String caminhoHolyrics) urlCartaz,
  String? urlQr,
  int motivosPorSlide = 5,
}) {
  final slides = <SlideMural>[];
  for (final r in ordenarParaExibicao(recados.where((r) => !r.expirado(agora)))) {
    final url = r.ehImagem ? urlCartaz(r.imagemHolyrics!.trim()) : null;
    slides.add(url != null ? SlideMural.imagem(r.titulo, url) : SlideMural.texto(r.titulo, r.texto.trim(), corArgb: r.categoria.corArgb));
  }

  List<List<String>> blocos(List<String> linhas, int n) =>
      [for (var i = 0; i < linhas.length; i += n) linhas.sublist(i, (i + n).clamp(0, linhas.length))];

  final pedidos = [for (final m in motivos.where((m) => m.projetavel)) m.linha];
  for (final b in blocos(pedidos, motivosPorSlide)) {
    slides.add(SlideMural.lista('Motivos de oração', b, corArgb: _corOracao));
  }

  final respondidas = [
    for (final m in oracoesRespondidas(motivos, agora))
      m.testemunho.trim().isEmpty ? m.linha : '${m.linha}\n${m.testemunho.trim()}',
  ];
  for (final b in blocos(respondidas, 3)) {
    slides.add(SlideMural.lista('Orações respondidas', b, corArgb: _corGratidao));
  }

  if (urlQr != null) {
    slides.add(SlideMural.qr('Deixe seu pedido de oração', 'Aponte a câmera do celular (Wi-Fi da igreja)', urlQr));
  }
  return slides;
}
