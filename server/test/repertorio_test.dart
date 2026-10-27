import 'package:diako_server/repertorio.dart';
import 'package:test/test.dart';

void main() {
  test('tom escolhido substitui sugestão antiga sem apagar anotação importada', () {
    final m = RepertorioMusica.fromJson({
      'titulo': 'Canção', 'cantor': 'Banda', 'tomDiakonia': 'Em\nIntro: C', 'tomSelecionado': 'F#m',
    });
    expect(m.tomPadrao, 'F#m');
    expect(m.tomDiakonia, 'Em\nIntro: C');
    expect(RepertorioMusica.fromJson(m.toJson()).tomPadrao, 'F#m');
    expect(RepertorioMusica.fromJson({...m.toJson(), 'tomSelecionado': ''}).tomPadrao, '');
    expect(() => RepertorioMusica.fromJson({...m.toJson(), 'tomSelecionado': 'H'}), throwsFormatException);
  });

  test('importa CSV do Google Sheets com vírgulas, aspas e quebras de linha', () {
    const csv = 'Solicitado por,Link Versão,Louvor,Cantor,Compositor,Ano,Observações,Status,Tom Original,Tom Diakonia,Bpm,Resumo Biografia Cantor,Resumo Biografia Compositor\r\n'
        'Repertório,https://youtu.be/abc,"Santo, Santo",Marine Friesen,Autora,2024,"Nota ""especial""",Ok,E,"G\nComeça com D",120,"Biografia\nlonga",Outra\r\n'
        'Pedido,,Outra canção,Cantor,Autor,2020,,Pendente,F,Am,,,';
    final musicas = lerRepertorioCsv(csv);
    expect(musicas.length, 2);
    expect(musicas.first.titulo, 'Santo, Santo');
    expect(musicas.first.tomDiakonia, 'G\nComeça com D');
    expect(musicas.first.tomPadrao, 'G');
    expect(musicas.first.observacoes, 'Nota "especial"');
    expect(musicas.first.biografiaCantor, 'Biografia\nlonga');
    expect(musicas.first.ativo, isTrue);
    expect(musicas.last.ativo, isFalse);
  });

  test('compara título e cantor sem acentos e espaços extras', () {
    expect(chaveRepertorio('  SÁNTO  Santo ', ' Marine  FRIESEN '),
        chaveRepertorio('santo santo', 'marine friesen'));
  });

  test('extrai o tom musical de anotações longas da planilha', () {
    RepertorioMusica musica(String tom) => RepertorioMusica(titulo: 'Título', cantor: 'Cantor', tomDiakonia: tom);
    expect(musica('Em (Intro: C D Em..)').tomPadrao, 'Em');
    expect(musica('Jéssica: Bb (Intro Bb, Eb/Bb...)').tomPadrao, 'Bb');
    expect(musica('Masculino: A\nFeminino: B').tomPadrao, 'A');
    expect(musica('F#\nComeça com D#m').tomPadrao, 'F#');
  });

  test('rejeita cabeçalho inválido e CSV incompleto', () {
    expect(() => lerRepertorioCsv('Nome,Cantor\nTeste,Ana'), throwsFormatException);
    expect(() => lerRepertorioCsv('Louvor,Cantor\n"Teste,Ana'), throwsFormatException);
  });
}
