import 'dart:convert';

import 'package:diako_core/diako_core.dart';
import 'package:diako_news/data/modo_culto.dart';
import 'package:diako_news/ui/modo_culto_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const momento = Momento(TipoMomento.boasVindas, passos: [], linhas: ['Família Oliveira', 'Renata Campos']);
  const passos = [
    Passo(AcaoPasso.texto, 'Retiro', valor: '<b>Retiro de Jovens 2026</b>\nDe 14 a 16/11 no Sítio Boa Esperança.'),
    Passo(AcaoPasso.imagem, 'Cartaz', valor: 'DiakoNews/bazar.jpg'),
    Passo(AcaoPasso.contagem, 'Contagem', valor: '19:00'),
    Passo(AcaoPasso.boasVindas, 'Sejam bem-vindos!'),
    Passo(AcaoPasso.telaVazia, 'Tela vazia'),
    Passo(AcaoPasso.telaPreta, 'Tela preta'),
    Passo(AcaoPasso.qrOracao, 'QR dos pedidos de oração'),
    Passo(AcaoPasso.qrMensagens, 'QR da caixa de mensagens'),
  ];

  for (final largura in [140.0, 360.0]) {
    testWidgets('prévia de todos os tipos de passo cabe em $largura de largura', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(children: [
              for (final p in passos) SizedBox(width: largura, child: SlideDoPasso(passo: p, momento: momento)),
            ]),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('Retiro de Jovens 2026'), findsOneWidget, reason: 'título sem as marcações do Holyrics');
      expect(find.text('Sejam bem-vindos!'), findsOneWidget);
    });
  }

  test('Avançar não repete o nome do momento quando o slide tem o mesmo nome', () {
    expect(rotuloDoProximo('Dízimos e ofertas', 'Dízimos e ofertas', mudaDeMomento: true), 'Dízimos e ofertas');
    expect(rotuloDoProximo('Encerramento', 'QR dos pedidos de oração', mudaDeMomento: true),
        'Encerramento · QR dos pedidos de oração');
    expect(rotuloDoProximo('Encerramento', 'QR da caixa de mensagens', mudaDeMomento: false), 'QR da caixa de mensagens');
    expect(rotuloDoProximo('Palavra', '', mudaDeMomento: true), 'Palavra');
  });

  test('culto em andamento só no mesmo dia e depois de começar', () {
    final hoje = DateTime(2026, 11, 2, 19, 30);
    String salvo(String dia, bool iniciado) => jsonEncode({'dia': dia, 'iniciado': iniciado});
    expect(ModoCultoController.emAndamento(salvo('2026-11-02', true), hoje), isTrue);
    expect(ModoCultoController.emAndamento(salvo('2026-11-02', false), hoje), isFalse);
    expect(ModoCultoController.emAndamento(salvo('2026-11-01', true), hoje), isFalse);
    expect(ModoCultoController.emAndamento('', hoje), isFalse);
  });
}
