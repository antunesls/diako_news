import 'dart:io';

import 'package:diako_core/diako_core.dart';
import 'package:diako_news/app_scope.dart';
import 'package:diako_news/ui/home_page.dart';
import 'package:diako_news/ui/modo_culto_page.dart';
import 'package:diako_news/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'apoio/app_falso.dart';

/// Telas inteiras no tamanho do Galaxy Tab A9+ deitado (1920×1200 px, 1280×800 dp), com o app
/// de verdade sobre um servidor falso: nada pode estourar nem cortar.
void main() {
  late Directory pasta;
  ServidorFalso? atual; // o da tela aberta por último (tocar() espera as chamadas dele)
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
    atual = servidor;
    return servidor;
  }

  /// Toque que chama o servidor/Holyrics: deixa o IO de verdade (cache em arquivo) terminar. Espera
  /// as chamadas ao Holyrics pararem (3 rodadas seguidas sem nenhuma nova), não um tempo fixo: no CI
  /// a sequência (tirar a tela vazia, projetar, religar) demora mais que aqui.
  Future<void> tocar(WidgetTester tester, Finder alvo) async {
    await tester.tap(alvo);
    var quietas = 0, antes = -1;
    for (var i = 0; i < 60 && quietas < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      final agora = atual?.holyrics.length ?? 0;
      quietas = agora == antes ? quietas + 1 : 0;
      antes = agora;
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

  testWidgets('aviso ao palco durante a Palavra sai da TV do palco junto com a pregação', (tester) async {
    final servidor = await abrir(tester, const ModoCultoPage());
    await tocar(tester, find.text('Começar o culto agora'));
    await tocar(tester, find.text(TipoMomento.palavra.titulo).first);
    await tocar(tester, find.text('Faltam 5 minutos'));
    expect(servidor.corpos.lastWhere((c) => c.containsKey('show')), containsPair('text', 'Faltam 5 minutos'));

    await tocar(tester, find.text(TipoMomento.oracaoFinal.titulo).first);
    final palco = servidor.corpos.lastWhere((c) => c.containsKey('show'));
    expect(palco['show'], false, reason: 'sem leitura do texto, o aviso também tem que sair');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('mensagem ao palco sem nada no ar: slide em branco antes', (tester) async {
    // Com nada projetado o Holyrics esconde as telas, inclusive a do palco.
    final servidor = await abrir(tester, const HomePage());
    var antes = servidor.holyrics.length;
    await tocar(tester, find.text('O culto começa em 5 min'));
    expect(servidor.holyrics.sublist(antes),
        containsAllInOrder(['GetCurrentPresentation', 'ShowQuickPresentation', 'SetTextCP']));
    expect(servidor.holyrics.sublist(antes), isNot(contains('SetF9')), reason: 'F9 logo após abrir o slide falha no Holyrics');
    final i = antes + servidor.holyrics.sublist(antes).indexOf('ShowQuickPresentation');
    expect(servidor.corpos[i]['text'], ' ');
    expect(servidor.corpos.lastWhere((c) => c.containsKey('show'))['text'], 'O culto começa em 5 min');

    // Com algo no ar, só a mensagem: o telão não muda.
    servidor.noAr = {'type': 'quick_presentation', 'name': ''};
    antes = servidor.holyrics.length;
    await tocar(tester, find.text('O culto começa em 2 min'));
    final enviados = servidor.holyrics.sublist(antes);
    expect(enviados, contains('SetTextCP'));
    expect(enviados, isNot(contains('ShowQuickPresentation')));
    expect(enviados, isNot(contains('SetF9')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('papel de parede do palco é opcional e só liga F8 quando não há projeção', (tester) async {
    final servidor = await abrir(tester, const HomePage(), antes: (s) => s.confirmarSlide = true);
    final scope = AppScope.of(tester.element(find.byType(HomePage)));
    expect(scope.settings.papelDeParedePalco, isFalse);
    await tocar(tester, find.text('O culto começa em 5 min'));
    expect(servidor.holyrics, isNot(contains('SetF8')));

    await tocar(tester, find.byTooltip('Configurações'));
    expect(find.byType(SettingsPage), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Manter o papel de parede no telão ao avisar o palco'), 250,
        scrollable: find.descendant(of: find.byType(SettingsPage), matching: find.byType(Scrollable)).first);
    final opcao = find.widgetWithText(SwitchListTile, 'Manter o papel de parede no telão ao avisar o palco');
    expect(opcao, findsOneWidget);
    await tester.ensureVisible(opcao);
    await tester.tap(opcao);
    await tester.pump();
    Navigator.of(tester.element(find.byType(SettingsPage))).pop();
    await tester.pumpAndSettle();
    expect(scope.settings.papelDeParedePalco, isTrue);

    servidor.noAr = null;
    final antes = servidor.holyrics.length;
    await tester.ensureVisible(find.text('O culto começa em 2 min'));
    await tester.pump();
    await tocar(tester, find.text('O culto começa em 2 min'));
    final enviados = servidor.holyrics.sublist(antes);
    expect(enviados, containsAllInOrder(['ShowQuickPresentation', 'GetCurrentPresentation', 'SetF8', 'SetTextCP']));
    expect(servidor.corpos[antes + enviados.indexOf('SetF8')], {'enable': true});

    final depois = servidor.holyrics.length;
    await tester.ensureVisible(find.text('O culto começa em 5 min'));
    await tester.pump();
    await tocar(tester, find.text('O culto começa em 5 min'));
    expect(servidor.holyrics.sublist(depois), isNot(contains('SetF8')));
    expect(servidor.holyrics.sublist(depois), isNot(contains('ShowQuickPresentation')));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('se F8 for recusado, a mensagem ao palco ainda é enviada', (tester) async {
    final servidor = await abrir(tester, const HomePage(), antes: (s) {
      s.confirmarSlide = true;
      s.recusar.add('SetF8');
    });
    final scope = AppScope.of(tester.element(find.byType(HomePage)));
    await tester.runAsync(() => scope.settings.atualizar(papelDeParedePalco: true));
    await tocar(tester, find.text('O culto começa em 5 min'));
    expect(servidor.holyrics, containsAllInOrder(['ShowQuickPresentation', 'SetF8', 'SetTextCP']));
    expect(servidor.corpos.lastWhere((c) => c.containsKey('show'))['text'], 'O culto começa em 5 min');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('QR recusado pelo Holyrics: o telão volta para a tela vazia', (tester) async {
    final servidor = await abrir(tester, const ModoCultoPage());
    await tocar(tester, find.text('Começar o culto agora'));
    await tocar(tester, find.text(TipoMomento.oracaoFinal.titulo).first);
    expect(servidor.holyrics.last, 'GetCurrentPresentation');
    expect(servidor.corpos.lastWhere((c) => c.containsKey('enable'))['enable'], true, reason: 'oração final = tela vazia');

    servidor.recusar.add('ShowImage');
    final antes = servidor.holyrics.length;
    await tocar(tester, find.text(TipoMomento.encerramento.titulo).first);
    final enviados = servidor.holyrics.sublist(antes);
    expect(enviados, containsAllInOrder(['SetF9', 'ShowImage', 'SetF9']));
    expect(servidor.corpos.lastWhere((c) => c.containsKey('enable'))['enable'], true,
        reason: 'religou a tela vazia: o slide antigo não pode voltar ao telão');
    expect(find.textContaining('file not found'), findsOneWidget);
    expect(find.text('Tela vazia'), findsWidgets, reason: 'o tablet continua na oração final');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tela vazia depois de um QR: um slide em branco tira a imagem do telão', (tester) async {
    final servidor = await abrir(tester, const ModoCultoPage());
    await tocar(tester, find.text('Começar o culto agora'));
    await tocar(tester, find.text(TipoMomento.encerramento.titulo).first);
    expect(servidor.holyrics, contains('ShowImage'));

    // O F9 do Holyrics não esconde imagens: voltar para a oração final deixaria o QR no telão.
    servidor.noAr = {'type': 'image', 'name': 'Diako/qr-oracao.png'};
    final antes = servidor.holyrics.length;
    await tocar(tester, find.text(TipoMomento.oracaoFinal.titulo).first);
    final enviados = servidor.holyrics.sublist(antes);
    expect(enviados, containsAllInOrder(['GetCurrentPresentation', 'ShowQuickPresentation', 'SetF9']));
    expect(servidor.corpos[antes + enviados.indexOf('ShowQuickPresentation')]['text'], ' ');
    expect(servidor.corpos.lastWhere((c) => c.containsKey('enable'))['enable'], true);

    // Com texto no ar o F9 basta: nada de slide extra.
    servidor.noAr = {'type': 'quick_presentation', 'name': ''};
    await tocar(tester, find.text(TipoMomento.encerramento.titulo).first);
    final depois = servidor.holyrics.length;
    await tocar(tester, find.text(TipoMomento.oracaoFinal.titulo).first);
    expect(servidor.holyrics.sublist(depois), isNot(contains('ShowQuickPresentation')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('prévia dos QR mostra a imagem do telão; sem ela, o ícone', (tester) async {
    // PNG de 16x9 qualquer: o que importa é a prévia trocar o ícone pela imagem do servidor.
    const png = [
      137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196,
      137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 248, 15, 4, 0, 9, 251, 3, 253, 227, 85, 242, 156, 0, 0, 0, 0, 73,
      69, 78, 68, 174, 66, 96, 130,
    ];
    final imagemDoQr = find.byWidgetPredicate((w) => w is Image && w.image is MemoryImage);
    Future<void> irAoEncerramento() async {
      await tocar(tester, find.text('Começar o culto agora'));
      await tocar(tester, find.text(TipoMomento.encerramento.titulo).first);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }

    await abrir(tester, const ModoCultoPage(), antes: (s) => s.qrPng = png);
    await irAoEncerramento();
    expect(imagemDoQr, findsWidgets, reason: 'a imagem real no lugar do ícone');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());

    // Sem a imagem (servidor antigo, offline só com o agente): o ícone de sempre.
    await abrir(tester, const ModoCultoPage());
    await irAoEncerramento();
    expect(imagemDoQr, findsNothing);
    expect(find.text('QR dos pedidos de oração'), findsWidgets, reason: 'o ícone com o nome do passo');
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

    await tocar(tester, find.text('Tirar do telão'));
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

  testWidgets('ritmo da pregação: tópico, tempo previsto e se está no tempo', (tester) async {
    final palavra = Palavra(
      id: 'p2',
      titulo: 'Em memória de mim',
      autorId: 'u',
      pronta: true,
      data: diaIso(DateTime.now()),
      texto: '# A mesa (3 min)\nPrimeiro trecho.\n\n# O pão (10 min)\nSegundo trecho.',
    );
    await abrir(tester, const ModoCultoPage(), palavra: palavra);
    await tocar(tester, find.text('Começar o culto agora'));
    await tocar(tester, find.text(TipoMomento.palavra.titulo).first);
    expect(find.textContaining('Tópico 1'), findsNothing, reason: 'antes de começar a leitura');
    await tocar(tester, find.text('Começar a leitura'));
    expect(find.textContaining('Tópico 1 de 2'), findsOneWidget);
    expect(find.textContaining('de 3 min'), findsOneWidget);
    expect(find.text('no tempo'), findsOneWidget);
    await tocar(tester, find.text('Próximo trecho'));
    expect(find.textContaining('Tópico 2 de 2'), findsOneWidget);
    expect(find.text('3 min adiantado'), findsOneWidget, reason: 'o tópico 2 começou logo, 3 min antes do previsto');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('frase de destaque: um toque projeta no telão entre aspas', (tester) async {
    final palavra = Palavra(
      id: 'p3',
      titulo: 'Em memória de mim',
      autorId: 'u',
      pronta: true,
      data: diaIso(DateTime.now()),
      texto: 'Repare que a mesa foi posta antes da cruz. **A graça chegou primeiro.**',
    );
    final servidor = await abrir(tester, const ModoCultoPage(), palavra: palavra);
    await tocar(tester, find.text('Começar o culto agora'));
    await tocar(tester, find.text(TipoMomento.palavra.titulo).first);
    await tocar(tester, find.text('Começar a leitura'));
    expect(servidor.corpos.last['text'], 'Repare que a mesa foi posta antes da cruz. A graça chegou primeiro.',
        reason: 'a TV do palco recebe o texto sem as marcas');

    final antes = servidor.holyrics.length;
    await tocar(tester, find.text('A graça chegou primeiro.'));
    expect(servidor.holyrics.sublist(antes), ['SetF10', 'ShowQuickPresentation', 'GetCurrentPresentation']);
    expect(servidor.corpos[antes + 1]['text'], '“A graça chegou primeiro.”');
    expect(find.text('“A graça chegou primeiro.”'), findsOneWidget, reason: 'prévia do telão');

    await tocar(tester, find.text('Tirar do telão'));
    expect(find.text('Tela preta'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
