import 'package:diako_news/data/settings.dart';
import 'package:diako_news/ui/frases_palco.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('frases prontas do palco', () {
    test('sem preferências, valem as frases padrão', () async {
      final s = AppSettings(await SharedPreferences.getInstance());
      expect(s.frasesPalco, AppSettings.frasesPalcoPadrao);
      expect(s.frasesPalco, contains('O culto começa em 5 min'));
      expect(s.frasesPalco, contains('Atenção: microfone com problema'));
    });

    test('lista editada é gravada e lida de novo', () async {
      final s = AppSettings(await SharedPreferences.getInstance());
      await s.atualizarFrasesPalco(const ['Aviso 1', 'Aviso 2']);
      final outra = AppSettings(await SharedPreferences.getInstance());
      expect(outra.frasesPalco, ['Aviso 1', 'Aviso 2']);
      expect(s.frasesPalco, ['Aviso 1', 'Aviso 2']);
    });

    test('restaurar volta às frases padrão', () async {
      final s = AppSettings(await SharedPreferences.getInstance());
      await s.atualizarFrasesPalco(const ['Só esta']);
      await s.restaurarFrasesPalco();
      expect(AppSettings(await SharedPreferences.getInstance()).frasesPalco, AppSettings.frasesPalcoPadrao);
    });

    testWidgets('tocar numa frase envia exatamente aquele texto', (tester) async {
      String? enviado;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FrasesPalco(
            frases: const ['O culto começa em 5 min', 'Silêncio, por favor'],
            onEnviar: (f) => enviado = f,
          ),
        ),
      ));
      await tester.tap(find.text('Silêncio, por favor'));
      expect(enviado, 'Silêncio, por favor');
    });

    testWidgets('sem frases, nada é desenhado', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: FrasesPalco(frases: const [], onEnviar: (_) {})),
      ));
      expect(find.byType(ActionChip), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
