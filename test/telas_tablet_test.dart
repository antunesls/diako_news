import 'dart:io';

import 'package:diako_core/diako_core.dart';
import 'package:diako_news/ui/home_page.dart';
import 'package:diako_news/ui/modo_culto_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/app_falso.dart';

/// Telas inteiras no tamanho do Galaxy Tab A9+ deitado (1920×1200 px, 1280×800 dp), com o app
/// de verdade sobre um servidor falso: nada pode estourar nem cortar.
void main() {
  late Directory pasta;
  setUp(() async => pasta = await Directory.systemTemp.createTemp('diako_telas'));
  tearDown(() => pasta.delete(recursive: true));

  Future<ServidorFalso> abrir(WidgetTester tester, Widget home, {Palavra? palavra, void Function(ServidorFalso)? antes}) async {
    tester.view.physicalSize = const Size(1920, 1200);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.reset);
    final servidor = ServidorFalso(DateTime.now())..palavra = palavra;
    antes?.call(servidor);
    final app = await tester.runAsync(() => montarApp(servidor, pasta, home));
    await tester.pumpWidget(app!);
    await tester.pump();
    return servidor;
  }

  /// Toque que chama o servidor/Holyrics: deixa o IO de verdade (cache em arquivo) terminar.
  Future<void> tocar(WidgetTester tester, Finder alvo) async {
    await tester.tap(alvo);
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
  }

  testWidgets('tela de organizar: trilho, coluna do palco e aviso do culto', (tester) async {
    await abrir(tester, const HomePage());
    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.textContaining('Entrar no Modo Culto'), findsOneWidget);
    expect(find.text('Próximo'), findsOneWidget);
    expect(find.text('PRÉ-VISUALIZAÇÃO'), findsOneWidget);
  });

  testWidgets('Modo Culto: conferência, todos os momentos e o Avançar', (tester) async {
    final servidor = await abrir(tester, const ModoCultoPage());
    expect(tester.takeException(), isNull);
    expect(find.text('Iniciar contagem'), findsOneWidget);
    expect(find.text('1 pedido(s) aguardando aprovação'), findsOneWidget);

    await tocar(tester, find.text('Começar o culto agora'));
    expect(tester.takeException(), isNull);
    expect(find.text('MODO CULTO'), findsOneWidget);
    expect(find.text('CHEGOU AGORA'), findsOneWidget);

    // Cada momento do roteiro, tocando na trilha da esquerda.
    for (final tipo in [
      TipoMomento.contagem,
      TipoMomento.boasVindas,
      TipoMomento.louvor,
      TipoMomento.recados,
      TipoMomento.ofertas,
      TipoMomento.ceia,
      TipoMomento.motivos,
      TipoMomento.palavra,
      TipoMomento.oracaoFinal,
      TipoMomento.encerramento,
    ]) {
      await tocar(tester, find.text(tipo.titulo).first);
      expect(tester.takeException(), isNull, reason: tipo.titulo);
    }
    // Encerramento: QR de pedidos no telão, QR de mensagens a seguir.
    expect(find.textContaining('QR da caixa de mensagens'), findsWidgets);
    expect(servidor.holyrics, contains('ShowImage'));

    // Volta aos recados e avança um a um.
    await tocar(tester, find.text(TipoMomento.recados.titulo).first);
    final antes = servidor.holyrics.length;
    await tocar(tester, find.text('Avançar'));
    expect(tester.takeException(), isNull);
    expect(servidor.holyrics.sublist(antes), contains('ShowQuickPresentation'));

    // Palavra: cronômetro e avisos ao palco.
    await tocar(tester, find.text(TipoMomento.palavra.titulo).first);
    expect(find.textContaining('restam da pregação'), findsOneWidget);
    expect(find.text('Faltam 5 minutos'), findsOneWidget);
    expect(servidor.holyrics, contains('SetF10'), reason: 'tela preta durante a pregação');

    // Louvor: músicas e escalados.
    await tocar(tester, find.text(TipoMomento.louvor.titulo).first);
    expect(find.text('Bondade de Deus'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Palavra com texto: trechos na TV do palco e versículos no telão', (tester) async {
    final palavra = Palavra(
      id: 'p1',
      titulo: 'Em memória de mim',
      autorId: 'u',
      pronta: true,
      data: diaIso(DateTime.now()),
      texto: '# A mesa preparada\nJesus não improvisou aquela noite.\n\nPaulo repete aos coríntios: 1Co 11.23-24.\n\n'
          '# O pão partido\nComo diz Romanos 5.8, a graça chegou primeiro.',
      decisoes: {
        '1Co 11.23-24': const DecisaoReferencia(StatusReferencia.confirmada),
        'Romanos 5.8': const DecisaoReferencia(StatusReferencia.confirmada),
      },
    );
    final servidor = await abrir(tester, const ModoCultoPage(), palavra: palavra);
    await tocar(tester, find.text('Começar o culto agora'));
    await tocar(tester, find.text(TipoMomento.palavra.titulo).first);
    expect(tester.takeException(), isNull);
    expect(find.text('Começar a leitura'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'O pão partido'), findsOneWidget);

    await tocar(tester, find.text('Começar a leitura'));
    expect(servidor.holyrics.last, 'SetTextCP');
    expect(servidor.corpos.last['text'], 'Jesus não improvisou aquela noite.');
    expect(find.text('NA TV DO PALCO'), findsOneWidget);

    await tocar(tester, find.text('Próximo trecho'));
    expect(servidor.corpos.last['text'], 'Paulo repete aos coríntios: 1Co 11.23-24.');

    // O versículo citado: tira a tela preta da pregação e abre no telão.
    final antes = servidor.holyrics.length;
    await tocar(tester, find.text('1Co 11.23-24'));
    expect(servidor.holyrics.sublist(antes), ['SetF10', 'ShowVerse', 'GetCurrentPresentation']);
    expect(servidor.corpos[antes]['enable'], false);
    expect(servidor.corpos[antes + 1]['ids'], ['46011023', '46011024']);
    expect(find.text('1 Coríntios 11.23-24'), findsOneWidget);

    await tocar(tester, find.text('Tirar versículo'));
    expect(servidor.holyrics, contains('SetF10'));
    expect(find.text('Tela preta'), findsOneWidget);

    // Sair da Palavra limpa a TV do palco.
    await tocar(tester, find.textContaining('Próximo momento'));
    expect(servidor.corpos.lastWhere((c) => c.containsKey('show'))['show'], false);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('modelo do painel: ordem própria e momento livre com slide', (tester) async {
    final servidor = await abrir(tester, const ModoCultoPage(), antes: (s) => s.culto['roteiro'] = [
          {'chave': 'louvor', 'tipo': 'louvor', 'minutos': 25},
          {'chave': 'livre-criancas', 'tipo': 'livre', 'titulo': 'Apresentação de crianças', 'texto': 'Apresentação de crianças'},
          {'chave': 'palavra', 'tipo': 'palavra'},
        ]);
    await tocar(tester, find.text('Começar o culto agora'));
    expect(tester.takeException(), isNull);
    expect(find.text('Recados'), findsNothing, reason: 'fora do modelo');
    expect(find.text('25 min'), findsNothing);
    expect(find.textContaining('/ 25 min'), findsOneWidget, reason: 'minutos do modelo no louvor');

    await tocar(tester, find.text('Avançar'));
    expect(find.text('Apresentação de crianças'), findsWidgets);
    expect(servidor.holyrics.last, 'GetCurrentPresentation');
    expect(servidor.holyrics, contains('ShowQuickPresentation'));
    expect(servidor.corpos.lastWhere((c) => c.containsKey('text'))['text'], '<b>Apresentação de crianças</b>');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
