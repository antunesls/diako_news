import 'dart:io';

import 'package:diako_news/ui/evento_form.dart';
import 'package:diako_news/ui/home_page.dart';
import 'package:diako_news/ui/modo_culto_page.dart';
import 'package:diako_news/ui/recado_form.dart';
import 'package:diako_news/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/app_falso.dart';

/// O Galaxy Tab A9+ da igreja como ele está: Android 16 desenha o app por baixo das barras do
/// sistema (status 40 px, navegação 64 px), densidade 213 e fonte 1.1. Nada pode ficar atrás da
/// barra de navegação, nem rolando até o fim.
void main() {
  const dpr = 213 / 160;
  const barraNavegacao = 64 / dpr;
  late Directory pasta;
  setUp(() async => pasta = await Directory.systemTemp.createTemp('diako_barras'));
  tearDown(() async {
    try {
      await pasta.delete(recursive: true);
    } on FileSystemException {
      // No Windows o cache em arquivo às vezes ainda está aberto; é pasta temporária.
    }
  });

  Future<double> abrir(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1920, 1200);
    tester.view.devicePixelRatio = dpr;
    tester.view.padding = const FakeViewPadding(top: 40, bottom: 64);
    tester.view.viewPadding = const FakeViewPadding(top: 40, bottom: 64);
    tester.platformDispatcher.textScaleFactorTestValue = 1.1;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    final app = await tester.runAsync(() => montarApp(ServidorFalso(DateTime.now()), pasta, home));
    await tester.pumpWidget(app!);
    await tester.pump();
    return 1200 / dpr - barraNavegacao;
  }

  /// Rola tudo até o fim e confere que nenhuma área de rolagem invade a barra de navegação.
  Future<void> conferirRolagens(WidgetTester tester, double limite) async {
    final rolagens = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
    for (final r in rolagens.evaluate().toList()) {
      final alvo = find.byWidget(r.widget);
      if (tester.getRect(alvo).height < 50) continue;
      // A lista é montada aos poucos: pula para o fim até o tamanho parar de crescer.
      final posicao = tester.state<ScrollableState>(alvo).position;
      var tentativas = 0;
      do {
        posicao.jumpTo(posicao.maxScrollExtent);
        await tester.pump();
      } while (posicao.pixels < posicao.maxScrollExtent && ++tentativas < 10);
      expect(tester.getRect(alvo).bottom, lessThanOrEqualTo(limite + 0.5), reason: 'rolagem atrás da barra');
    }
  }

  testWidgets('Configurações: a última linha fica acima da barra de navegação', (tester) async {
    final limite = await abrir(tester, const SettingsPage());
    expect(tester.takeException(), isNull);
    await conferirRolagens(tester, limite);
    final ultima = find.textContaining('backup dos recados');
    expect(ultima, findsOneWidget);
    expect(tester.getRect(ultima).bottom, lessThanOrEqualTo(limite));
    await tester.pumpWidget(const SizedBox());
  });

  for (final (nome, tela) in [
    ('Novo recado', const RecadoForm()),
    ('Novo evento', const EventoForm()),
    ('tela de organizar', const HomePage()),
  ]) {
    testWidgets('$nome: nada atrás da barra de navegação', (tester) async {
      final limite = await abrir(tester, tela);
      expect(tester.takeException(), isNull);
      await conferirRolagens(tester, limite);
      expect(tester.getRect(find.byType(Scaffold).first).bottom, lessThanOrEqualTo(limite + 0.5));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('Modo Culto: nada atrás da barra de navegação', (tester) async {
    final limite = await abrir(tester, const ModoCultoPage());
    await tester.tap(find.text('Começar o culto agora'));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
    await conferirRolagens(tester, limite);
    expect(tester.getRect(find.byType(Scaffold).first).bottom, lessThanOrEqualTo(limite + 0.5));
    await tester.pumpWidget(const SizedBox());
  });
}
