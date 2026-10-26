import 'agenda.dart';
import 'motivo.dart';
import 'recado.dart';

/// Um slide do mural da TV da recepção.
class SlideMural {
  const SlideMural._(this.tipo,
      {this.titulo = '', this.texto = '', this.itens = const [], this.imagem, this.corArgb, this.eventos = const []});

  /// Eventos de hoje, em destaque.
  factory SlideMural.hoje(List<Map<String, String>> eventos) =>
      SlideMural._('hoje', titulo: 'Hoje', eventos: eventos, corArgb: _corAgenda);

  /// Próximos eventos da agenda.
  factory SlideMural.agenda(String titulo, List<Map<String, String>> eventos) =>
      SlideMural._('agenda', titulo: titulo, eventos: eventos, corArgb: _corAgenda);

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

  /// Para "hoje" e "agenda": {quando, titulo, local, descricao}.
  final List<Map<String, String>> eventos;

  Map<String, dynamic> toJson() => {
        'tipo': tipo,
        'titulo': titulo,
        if (texto.isNotEmpty) 'texto': texto,
        if (itens.isNotEmpty) 'itens': itens,
        if (eventos.isNotEmpty) 'eventos': eventos,
        if (imagem != null) 'imagem': imagem,
        if (corArgb != null) 'cor': '#${(corArgb! & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
      };
}

const _corOracao = 0xFFAB47BC;
const _corGratidao = 0xFF26A69A;
const _corAgenda = 0xFF5C6BC0;

/// Sequência de slides do mural. Só entra o que pode ser público:
/// eventos da agenda, recados válidos, motivos aprovados e públicos e orações respondidas públicas.
/// [urlCartaz] converte o caminho do Holyrics em endereço da imagem (null = mostra o texto).
List<SlideMural> montarMural({
  required List<Recado> recados,
  required List<Motivo> motivos,
  required DateTime agora,
  required String? Function(String caminhoHolyrics) urlCartaz,
  String? urlQr,
  String? urlQrMensagens,
  int motivosPorSlide = 5,
  List<Evento> eventos = const [],
  int diasEventos = 7,
  bool mostrarDescricao = true,
  int eventosPorSlide = 6,
}) {
  final slides = <SlideMural>[];

  // Agenda: "Hoje" (o que ainda não terminou) e os próximos dias.
  final amanha = DateTime(agora.year, agora.month, agora.day + 1);
  Map<String, String> item(Evento e, {required bool comDia}) => {
        'quando': comDia ? '${diaCurto(e.inicio)} · ${horario(e)}' : horario(e),
        'titulo': e.titulo,
        if (e.local.isNotEmpty) 'local': e.local,
        if (mostrarDescricao && e.descricao.isNotEmpty) 'descricao': _resumir(e.descricao, 180),
      };
  final hoje = [for (final e in eventos) if (e.fim.isAfter(agora) && e.inicio.isBefore(amanha)) e];
  if (hoje.isNotEmpty) {
    slides.add(SlideMural.hoje([for (final e in hoje.take(eventosPorSlide)) item(e, comDia: false)]));
  }
  final limite = DateTime(agora.year, agora.month, agora.day + diasEventos + 1);
  final proximos = [for (final e in eventos) if (!e.inicio.isBefore(amanha) && e.inicio.isBefore(limite)) e];
  for (var i = 0; i < proximos.length; i += eventosPorSlide) {
    final bloco = proximos.sublist(i, (i + eventosPorSlide).clamp(0, proximos.length));
    slides.add(SlideMural.agenda('Próximos eventos', [for (final e in bloco) item(e, comDia: true)]));
  }

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
    slides.add(SlideMural.qr('Deixe seu pedido de oração', 'Aponte a câmera do celular', urlQr));
  }
  if (urlQrMensagens != null) {
    slides.add(SlideMural.qr('Dúvidas, sugestões e críticas', 'Aponte a câmera do celular', urlQrMensagens));
  }
  return slides;
}

String _resumir(String texto, int max) {
  final t = texto.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length <= max ? t : '${t.substring(0, max - 1).trimRight()}…';
}
