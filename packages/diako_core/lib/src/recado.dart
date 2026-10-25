enum Categoria {
  aviso('Aviso', 0xFF42A5F5),
  evento('Evento', 0xFF66BB6A),
  aniversario('Aniversário', 0xFFFFA726);

  const Categoria(this.label, this.corArgb);
  final String label;

  /// Cor da categoria em ARGB (ex: 0xFF42A5F5), para o app e o painel web.
  final int corArgb;

  static Categoria fromName(String? name) =>
      Categoria.values.firstWhere((c) => c.name == name, orElse: () => Categoria.aviso);
}

class Recado {
  Recado({
    required this.id,
    required this.titulo,
    this.texto = '',
    this.categoria = Categoria.aviso,
    this.imagemHolyrics,
    this.validoAte,
    this.fixo = false,
    this.ordem = 0,
    this.auto = false,
  });

  final String id;
  String titulo;
  String texto;
  Categoria categoria;

  /// Caminho na biblioteca de imagens do Holyrics (ex: "Diako/retiro.jpg").
  /// Quando preenchido, o recado é projetado como imagem em vez de texto.
  String? imagemHolyrics;

  /// Último dia em que o recado aparece na lista principal.
  DateTime? validoAte;
  bool fixo;
  int ordem;

  /// Gerado pelo servidor (ex: aniversariantes da semana); não pode ser editado.
  final bool auto;

  bool get ehImagem => imagemHolyrics != null && imagemHolyrics!.trim().isNotEmpty;

  bool expirado(DateTime agora) {
    final v = validoAte;
    if (v == null) return false;
    final fimDoDia = DateTime(v.year, v.month, v.day).add(const Duration(days: 1));
    return !agora.isBefore(fimDoDia);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'titulo': titulo,
        'texto': texto,
        'categoria': categoria.name,
        'imagemHolyrics': imagemHolyrics,
        'validoAte': validoAte?.toIso8601String(),
        'fixo': fixo,
        'ordem': ordem,
        if (auto) 'auto': true,
      };

  factory Recado.fromJson(Map<String, dynamic> j) => Recado(
        id: j['id'] as String,
        titulo: j['titulo'] as String? ?? '',
        texto: j['texto'] as String? ?? '',
        categoria: Categoria.fromName(j['categoria'] as String?),
        imagemHolyrics: j['imagemHolyrics'] as String?,
        validoAte: j['validoAte'] == null ? null : DateTime.tryParse(j['validoAte'] as String),
        fixo: j['fixo'] as bool? ?? false,
        ordem: (j['ordem'] as num?)?.toInt() ?? 0,
        auto: j['auto'] as bool? ?? false,
      );
}

/// Texto de um slide no formato de texto estilizado do Holyrics.
String montarSlide(Recado r, {bool negritoTitulo = true}) {
  final titulo = r.titulo.trim();
  final texto = r.texto.trim();
  final cabecalho = negritoTitulo && titulo.isNotEmpty ? '<b>$titulo</b>' : titulo;
  if (texto.isEmpty) return cabecalho;
  if (cabecalho.isEmpty) return texto;
  return '$cabecalho\n$texto';
}

/// Ordem de exibição: fixos primeiro, depois pela ordem definida pelo usuário.
List<Recado> ordenarParaExibicao(Iterable<Recado> recados) {
  final lista = recados.toList();
  lista.sort((a, b) {
    if (a.fixo != b.fixo) return a.fixo ? -1 : 1;
    return a.ordem.compareTo(b.ordem);
  });
  return lista;
}
