import 'package:diako_core/diako_core.dart';
import 'package:test/test.dart';

void main() {
  test('mensagem privada preserva dados e estados no JSON', () {
    final original = Mensagem(
        id: 'abc',
        tipo: 'duvida',
        texto: 'Como participar?',
        nome: 'Ana',
        contato: 'ana@example.org',
        criadoEm: DateTime(2026, 10, 25),
        status: 'emAnalise');
    final restaurada = Mensagem.fromJson(original.toJson());
    expect(restaurada.texto, 'Como participar?');
    expect(restaurada.status, 'emAnalise');
    expect(restaurada.contato, 'ana@example.org');
    expect(Mensagem.tipos, containsAll(['duvida', 'sugestao', 'critica']));
  });

  test('mural só mostra chamada pública e QR da caixa', () {
    final slides = montarMural(
        recados: [],
        motivos: [],
        agora: DateTime(2026, 10, 25),
        urlCartaz: (_) => null,
        urlQrMensagens: '/qr-mensagens.png');
    expect(slides.single.toJson(), containsPair('imagem', '/qr-mensagens.png'));
    expect(slides.single.toJson()['titulo'], 'Dúvidas, sugestões e críticas');
  });
}
