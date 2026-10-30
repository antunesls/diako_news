import 'agenda.dart';
import 'motivo.dart';
import 'recado.dart';
import 'visita.dart';

/// Momentos do Modo Culto, na ordem do roteiro padrão.
enum TipoMomento {
  contagem('Antes do culto', 0),
  boasVindas('Boas-vindas', 5),
  louvor('Louvor', 30),
  recados('Recados', 10),
  ofertas('Dízimos e ofertas', 5),
  ceia('Santa Ceia', 15),
  motivos('Motivos de oração', 10),
  palavra('Palavra', 40),
  oracaoFinal('Oração final e bênção', 5),
  encerramento('Encerramento', 5);

  const TipoMomento(this.titulo, this.minutos);
  final String titulo;

  /// Tempo sugerido; 0 = sem tempo (a contagem tem a própria hora).
  final int minutos;

  static TipoMomento? porNome(Object? nome) => values.where((t) => t.name == nome).firstOrNull;
}

/// O que um passo faz no Holyrics.
enum AcaoPasso {
  /// Slide de texto (apresentação rápida). [Passo.valor] é o texto do slide.
  texto,

  /// Imagem da pasta do Holyrics. [Passo.valor] é o arquivo.
  imagem,

  /// Contagem até a hora do culto. [Passo.valor] é "HH:MM".
  contagem,

  /// Boas-vindas aos visitantes, projetadas pelo servidor. [Passo.ids] são as visitas.
  boasVindas,
  telaVazia,
  telaPreta,
  qrOracao,
  qrMensagens,
}

/// Um toque em Avançar: uma ação no telão, com o rótulo que o pastor vê.
class Passo {
  const Passo(this.acao, this.rotulo, {this.valor = '', this.ids = const []});

  final AcaoPasso acao;
  final String rotulo;
  final String valor;
  final List<String> ids;
}

class Momento {
  const Momento(this.tipo, {required this.passos, this.detalhe = '', this.linhas = const []});

  final TipoMomento tipo;
  final List<Passo> passos;

  /// Uma linha de contexto (pregador e tema, quantos visitantes…).
  final String detalhe;

  /// Informação só para o pastor (músicas, escalados); não vai ao telão.
  final List<String> linhas;
}

/// Slide fixo do momento de ofertas.
const slideOfertas = 'Dízimos e ofertas\n'
    '“Trazei todos os dízimos à casa do tesouro, para que haja mantimento na minha casa.”\n'
    'Malaquias 3.10';

/// Slide fixo da Santa Ceia.
const slideCeia = 'Santa Ceia\n“Fazei isto em memória de mim.”\n1 Coríntios 11.24';

String _negrito(String slide, bool negrito) {
  if (!negrito) return slide;
  final i = slide.indexOf('\n');
  return i < 0 ? '<b>$slide</b>' : '<b>${slide.substring(0, i)}</b>${slide.substring(i)}';
}

/// Monta o roteiro do culto com o que o app já tem. Momentos sem conteúdo ficam de fora.
///
/// [visitas] são as de hoje que autorizaram ser citadas (já citadas ou não), para o
/// momento continuar no roteiro depois que o servidor dá baixa nas boas-vindas.
List<Momento> montarRoteiro({
  required String horaCulto,
  required bool ceia,
  required List<String> musicas,
  required Map<String, List<String>> louvor,
  required Map<String, List<String>> pastoral,
  required String tema,
  required List<Recado> recados,
  required List<Motivo> motivos,
  required List<Motivo> respondidas,
  required List<Visita> visitas,
  Evento? proximoEvento,
  int motivosPorSlide = 4,
  bool negritoTitulo = true,
}) {
  String nomes(Map<String, List<String>> funcoes, String funcao) => (funcoes[funcao] ?? const []).join(', ');
  List<String> escalados(Map<String, List<String>> funcoes) => [
        for (final e in funcoes.entries)
          if (e.value.isNotEmpty) '${e.key}: ${e.value.join(', ')}',
      ];

  final vistos = <String>{};
  final citaveis = [for (final v in visitas) if (v.mencionar && vistos.add(v.membroId)) v];
  final pregador = nomes(pastoral, 'Pregação');
  final textos = [
    for (final r in recados)
      r.ehImagem
          ? Passo(AcaoPasso.imagem, r.titulo.isEmpty ? 'Cartaz' : r.titulo, valor: r.imagemHolyrics!.trim())
          : Passo(AcaoPasso.texto, r.titulo, valor: montarSlide(r, negritoTitulo: negritoTitulo)),
  ];
  final oracao = montarSlidesOracao(motivos, porSlide: motivosPorSlide, negritoTitulo: negritoTitulo);
  final gratidao = montarSlidesGratidao(respondidas, negritoTitulo: negritoTitulo);

  return [
    if (RegExp(r'^\d{2}:\d{2}$').hasMatch(horaCulto))
      Momento(TipoMomento.contagem,
          detalhe: 'Contagem no telão até as $horaCulto',
          passos: [Passo(AcaoPasso.contagem, 'Contagem até $horaCulto', valor: horaCulto)]),
    if (citaveis.isNotEmpty)
      Momento(TipoMomento.boasVindas,
          detalhe: citaveis.length == 1 ? '1 visitante para citar' : '${citaveis.length} visitantes para citar',
          linhas: [for (final v in citaveis) v.nome],
          passos: [Passo(AcaoPasso.boasVindas, 'Sejam bem-vindos!', ids: [for (final v in citaveis) v.id])]),
    if (musicas.isNotEmpty || escalados(louvor).isNotEmpty)
      Momento(TipoMomento.louvor,
          detalhe: musicas.isEmpty ? 'Músicas ainda não escolhidas' : '${musicas.length} música(s)',
          linhas: [...musicas, ...escalados(louvor)],
          passos: const [Passo(AcaoPasso.telaVazia, 'Tela vazia durante o louvor')]),
    if (textos.isNotEmpty)
      Momento(TipoMomento.recados, detalhe: '${textos.length} recado(s), um por vez', passos: textos),
    Momento(TipoMomento.ofertas,
        detalhe: nomes(pastoral, 'Oração e ofertas'),
        passos: [Passo(AcaoPasso.texto, 'Dízimos e ofertas', valor: _negrito(slideOfertas, negritoTitulo))]),
    if (ceia)
      Momento(TipoMomento.ceia, detalhe: nomes(pastoral, 'Santa Ceia'), passos: [
        Passo(AcaoPasso.texto, 'Santa Ceia', valor: _negrito(slideCeia, negritoTitulo)),
        const Passo(AcaoPasso.telaVazia, 'Tela vazia'),
      ]),
    if (oracao.isNotEmpty || gratidao.isNotEmpty)
      Momento(TipoMomento.motivos,
          detalhe: [
            if (motivos.isNotEmpty) '${motivos.length} aprovado(s)',
            if (respondidas.isNotEmpty) '${respondidas.length} respondida(s)',
          ].join(' · '),
          passos: [
            for (var i = 0; i < oracao.length; i++)
              Passo(AcaoPasso.texto, oracao.length == 1 ? 'Motivos de oração' : 'Motivos ${i + 1}/${oracao.length}',
                  valor: oracao[i]),
            for (var i = 0; i < gratidao.length; i++)
              Passo(AcaoPasso.texto,
                  gratidao.length == 1 ? 'Orações respondidas' : 'Respondidas ${i + 1}/${gratidao.length}',
                  valor: gratidao[i]),
          ]),
    Momento(TipoMomento.palavra,
        detalhe: [if (pregador.isNotEmpty) pregador, if (tema.trim().isNotEmpty) '“${tema.trim()}”'].join(' · '),
        passos: const [Passo(AcaoPasso.telaPreta, 'Tela preta durante a pregação')]),
    const Momento(TipoMomento.oracaoFinal, passos: [Passo(AcaoPasso.telaVazia, 'Tela vazia')]),
    Momento(TipoMomento.encerramento, passos: [
      const Passo(AcaoPasso.qrOracao, 'QR dos pedidos de oração'),
      const Passo(AcaoPasso.qrMensagens, 'QR da caixa de mensagens'),
      if (proximoEvento != null)
        Passo(AcaoPasso.texto, 'Próximo: ${proximoEvento.titulo}',
            valor: montarSlideEvento(proximoEvento, negritoTitulo: negritoTitulo)),
    ]),
  ];
}

/// Onde o culto está: o momento (pelo tipo, que não muda quando o roteiro é remontado) e o passo.
class PosicaoRoteiro {
  const PosicaoRoteiro(this.tipo, this.passo);

  final TipoMomento tipo;
  final int passo;

  @override
  bool operator ==(Object other) => other is PosicaoRoteiro && other.tipo == tipo && other.passo == passo;

  @override
  int get hashCode => Object.hash(tipo, passo);

  @override
  String toString() => '${tipo.name}/$passo';
}

/// Índice do momento da [posicao] no [roteiro]. Se o momento saiu do roteiro, o primeiro que vem
/// depois dele na ordem padrão; -1 se não há nenhum.
int indiceDoMomento(List<Momento> roteiro, TipoMomento tipo) {
  final exato = roteiro.indexWhere((m) => m.tipo == tipo);
  if (exato >= 0) return exato;
  return roteiro.indexWhere((m) => m.tipo.index > tipo.index);
}

/// A posição válida mais próxima de [posicao] depois de remontar o roteiro.
PosicaoRoteiro? localizar(List<Momento> roteiro, PosicaoRoteiro posicao) {
  final i = indiceDoMomento(roteiro, posicao.tipo);
  if (i < 0) return null;
  final m = roteiro[i];
  if (m.tipo != posicao.tipo) return PosicaoRoteiro(m.tipo, 0);
  return PosicaoRoteiro(m.tipo, posicao.passo.clamp(0, m.passos.length - 1));
}

/// O passo seguinte: o próximo do mesmo momento ou o primeiro do momento seguinte. Null no fim.
/// Se o momento atual saiu do roteiro, o seguinte é o primeiro passo do momento que veio no lugar.
PosicaoRoteiro? proximaPosicao(List<Momento> roteiro, PosicaoRoteiro atual) {
  final p = localizar(roteiro, atual);
  if (p == null) return null;
  if (p.tipo != atual.tipo) return p;
  final i = indiceDoMomento(roteiro, p.tipo);
  if (p.passo + 1 < roteiro[i].passos.length) return PosicaoRoteiro(p.tipo, p.passo + 1);
  return i + 1 < roteiro.length ? PosicaoRoteiro(roteiro[i + 1].tipo, 0) : null;
}

/// O passo anterior, voltando para o último passo do momento anterior. Null no começo.
PosicaoRoteiro? posicaoAnterior(List<Momento> roteiro, PosicaoRoteiro atual) {
  final p = localizar(roteiro, atual);
  if (p == null) return null;
  if (p.passo > 0) return PosicaoRoteiro(p.tipo, p.passo - 1);
  final i = indiceDoMomento(roteiro, p.tipo);
  if (i == 0) return null;
  final m = roteiro[i - 1];
  return PosicaoRoteiro(m.tipo, m.passos.length - 1);
}

/// Texto de um slide sem as marcações do Holyrics, para a prévia no tablet.
String textoSemMarcacao(String slide) => slide.replaceAll(RegExp(r'<[^>]+>'), '');

/// O culto está perto o bastante para sugerir o Modo Culto: de 1 h antes até 3 h depois do início.
bool cultoProximo(String data, String hora, DateTime agora) {
  final m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(hora);
  final d = DateTime.tryParse(data);
  if (m == null || d == null) return false;
  final inicio = DateTime(d.year, d.month, d.day, int.parse(m.group(1)!), int.parse(m.group(2)!));
  return !agora.isBefore(inicio.subtract(const Duration(hours: 1))) && agora.isBefore(inicio.add(const Duration(hours: 3)));
}
