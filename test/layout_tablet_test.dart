import 'package:diako_news/ui/control_bar.dart';
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

  Widget colunaDoPalco(double largura, String informacao) => MaterialApp(home: Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: SizedBox(
            width: largura,
            child: ProjectionControls(
              status: informacao,
              actions: [
                for (final label in ['Anterior', 'Parar', 'Próximo', 'Vazia', 'Preta', 'Contagem'])
                  SizedBox(height: 72, child: OutlinedButton(
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero), onPressed: () {}, child: Text(label))),
              ],
            ),
          ),
        ),
      ));

  testWidgets('controles do palco ficam em grade de três colunas iguais', (tester) async {
    tamanho(tester, const Size(1280, 800));
    await tester.pumpWidget(colunaDoPalco(348, 'No ar: Sequência de recados'));
    expect(tester.takeException(), isNull);
    final anterior = tester.getRect(find.widgetWithText(OutlinedButton, 'Anterior'));
    final proximo = tester.getRect(find.widgetWithText(OutlinedButton, 'Próximo'));
    final vazia = tester.getRect(find.widgetWithText(OutlinedButton, 'Vazia'));
    expect(proximo.top, anterior.top);
    expect(vazia.top, greaterThan(anterior.bottom));
    expect(vazia.left, anterior.left);
    expect(proximo.width, closeTo(anterior.width, 0.5));
    expect(tester.getRect(find.widgetWithText(OutlinedButton, 'Contagem')).right, lessThanOrEqualTo(1280));
  });

  testWidgets('informação no ar não é cortada pelos controles', (tester) async {
    tamanho(tester, const Size(800, 480));
    const informacao = 'No ar: Apresentação do culto com título comprido';
    await tester.pumpWidget(colunaDoPalco(320, informacao));
    expect(tester.takeException(), isNull);
    expect(tester.getBottomLeft(find.text(informacao)).dy, lessThan(tester.getTopLeft(find.text('Anterior')).dy));
    expect(tester.getBottomRight(find.text('Preta')).dx, lessThanOrEqualTo(800));
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
