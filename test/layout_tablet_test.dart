import 'package:diako_news/ui/control_bar.dart';
import 'package:diako_news/ui/section_navigation.dart';
import 'package:diako_news/ui/tools_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void tamanho(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('seções rolam sem disputar espaço com o status no tablet', (tester) async {
    tamanho(tester, const Size(800, 480));
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      appBar: AppBar(
        title: const Text('DiakoNews'),
        actions: const [Chip(label: Text('Holyrics conectado')), IconButton(onPressed: null, icon: Icon(Icons.settings))],
        bottom: SectionNavigation(child: SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('Recados')),
            ButtonSegment(value: 1, label: Text('Motivos de oração')),
            ButtonSegment(value: 2, label: Text('Visitantes')),
            ButtonSegment(value: 3, label: Text('Agenda')),
            ButtonSegment(value: 4, label: Text('Escala')),
            ButtonSegment(value: 5, label: Text('Mensagens')),
          ],
          selected: const {0}, onSelectionChanged: (_) {},
        )),
      ),
    )));
    expect(tester.takeException(), isNull);
    final status = tester.getTopLeft(find.text('Holyrics conectado'));
    final secao = tester.getTopLeft(find.text('Recados'));
    expect(status.dy, lessThan(secao.dy));
    final rolagem = tester.state<ScrollableState>(find.byType(Scrollable).first);
    rolagem.position.jumpTo(rolagem.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.getTopRight(find.text('Mensagens')).dx, lessThan(800));
  });

  testWidgets('informação no ar não é cortada pelos controles inferiores', (tester) async {
    tamanho(tester, const Size(800, 480));
    const informacao = 'No ar: Apresentação do culto com título comprido';
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      bottomNavigationBar: ProjectionControls(
        status: informacao,
        actions: [for (final label in ['Anterior', 'Parar', 'Próximo', 'Vazia', 'Preta'])
          OutlinedButton(onPressed: () {}, child: Text(label))],
      ),
    )));
    expect(tester.takeException(), isNull);
    expect(tester.getBottomLeft(find.text(informacao)).dy, lessThan(tester.getTopLeft(find.text('Anterior')).dy));
    expect(tester.getBottomRight(find.text('Preta')).dx, lessThan(800));
  });

  testWidgets('janela de ferramentas rola verticalmente em tela baixa', (tester) async {
    tamanho(tester, const Size(640, 360));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox(
      height: 250,
      child: ToolsLayout(
        contagem: SizedBox(height: 260, child: Text('Contagem no telão')),
        palco: SizedBox(height: 260, child: Text('Mensagem para o palco')),
      ),
    ))));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Mensagem para o palco'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Mensagem para o palco')).dy, lessThan(360));
  });
}
