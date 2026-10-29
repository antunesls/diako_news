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

  Widget abridor() => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showDialog(
                context: ctx,
                builder: (_) => const ToolsDialog(
                  contagem: SizedBox(height: 300, child: Text('Contagem no telão')),
                  palco: SizedBox(height: 300, child: Text('Mensagem para o palco')),
                ),
              ),
              child: const Text('Abrir'),
            ),
          ),
        ),
      );

  testWidgets('a janela de ferramentas abre no centro, maior que a antiga gaveta', (tester) async {
    tamanho(tester, const Size(1200, 800));
    await tester.pumpWidget(abridor());
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    final janela = tester.getRect(find.byKey(const ValueKey('janela-ferramentas')));
    expect((janela.center.dx - 600).abs(), lessThan(2), reason: 'centralizada na horizontal');
    expect((janela.center.dy - 400).abs(), lessThan(2), reason: 'centralizada na vertical');
    expect(janela.width, greaterThanOrEqualTo(700));
    expect(janela.width, lessThanOrEqualTo(900));
  });

  testWidgets('em tela baixa a janela rola sem cortar o conteúdo', (tester) async {
    tamanho(tester, const Size(800, 420));
    await tester.pumpWidget(abridor());
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Mensagem para o palco'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Mensagem para o palco')).dy, lessThan(420));
  });

  testWidgets('a janela tem título e botão de fechar', (tester) async {
    tamanho(tester, const Size(1200, 800));
    await tester.pumpWidget(abridor());
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Ferramentas do culto'), findsOneWidget);
    await tester.tap(find.byTooltip('Fechar'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });
}
