import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs);

  final SharedPreferences _prefs;

  /// Endereço do servidor DiakoHub (ex: https://diako.minhaigreja.com.br ou http://192.168.0.10:8080).
  String get servidor => _prefs.getString('servidor') ?? '';

  /// Token de sessão recebido no login.
  String get sessao => _prefs.getString('sessao') ?? '';

  /// Nome de um tema cadastrado no Holyrics; vazio usa o tema padrão.
  String get tema => _prefs.getString('tema') ?? '';
  int get segundosPorSlide => _prefs.getInt('segundosPorSlide') ?? 10;
  bool get repetirSequencia => _prefs.getBool('repetirSequencia') ?? true;
  bool get negritoTitulo => _prefs.getBool('negritoTitulo') ?? true;

  /// Mensagem ao palco com nada no ar: o telão mostra o papel de parede do Holyrics (F8) em vez do
  /// fundo do tema. Desligado por padrão: sem papel de parede, o F8 mostra a logo do Holyrics.
  bool get papelDeParedePalco => _prefs.getBool('papelDeParedePalco') ?? false;
  int get motivosPorSlide => _prefs.getInt('motivosPorSlide') ?? 4;
  String get pin => _prefs.getString('pin') ?? '';

  bool get configurado => servidor.isNotEmpty && sessao.isNotEmpty;

  /// Agente do PC da igreja na rede local (ex: http://192.168.0.20:8097); vazio = só internet.
  String get agenteLocal => _prefs.getString('agenteLocal') ?? '';

  /// Frases prontas para o painel de comunicação (TV do palco), editáveis no tablet.
  static const frasesPalcoPadrao = <String>[
    'O culto começa em 5 min',
    'O culto começa em 2 min',
    'Pastor, pode se dirigir ao palco',
    'Favor encerrar a ministração',
    'Silêncio, por favor',
    'Momento de oração',
    'Atenção: microfone com problema',
  ];

  List<String> get frasesPalco => _prefs.getStringList('frasesPalco') ?? frasesPalcoPadrao;

  Future<void> atualizarFrasesPalco(List<String> frases) async {
    await _prefs.setStringList('frasesPalco', frases);
    notifyListeners();
  }

  Future<void> restaurarFrasesPalco() => atualizarFrasesPalco(frasesPalcoPadrao);

  /// Token do pareamento com o agente (vale sem internet) e o id para desfazê-lo.
  String get agenteLocalToken => _prefs.getString('agenteLocalToken') ?? '';
  String get agenteLocalId => _prefs.getString('agenteLocalId') ?? '';

  bool get agenteLocalPareado => agenteLocal.isNotEmpty && agenteLocalToken.isNotEmpty;

  /// Onde o Modo Culto parou (JSON do ModoCultoController); vazio = nenhum culto em andamento.
  String get modoCulto => _prefs.getString('modoCulto') ?? '';

  Future<void> salvarModoCulto(String estado) => _prefs.setString('modoCulto', estado);

  /// Tempo previsto da pregação no Modo Culto.
  int get minutosPregacao => _prefs.getInt('minutosPregacao') ?? 40;

  Future<void> atualizarMinutosPregacao(int minutos) async {
    await _prefs.setInt('minutosPregacao', minutos);
    notifyListeners();
  }

  Future<void> atualizar({
    String? servidor,
    String? sessao,
    String? agenteLocal,
    String? agenteLocalToken,
    String? agenteLocalId,
    String? tema,
    int? segundosPorSlide,
    bool? repetirSequencia,
    bool? negritoTitulo,
    bool? papelDeParedePalco,
    int? motivosPorSlide,
    String? pin,
  }) async {
    if (servidor != null) await _prefs.setString('servidor', servidor);
    if (sessao != null) await _prefs.setString('sessao', sessao);
    if (agenteLocal != null) await _prefs.setString('agenteLocal', agenteLocal);
    if (agenteLocalToken != null) await _prefs.setString('agenteLocalToken', agenteLocalToken);
    if (agenteLocalId != null) await _prefs.setString('agenteLocalId', agenteLocalId);
    if (tema != null) await _prefs.setString('tema', tema.trim());
    if (segundosPorSlide != null) await _prefs.setInt('segundosPorSlide', segundosPorSlide);
    if (repetirSequencia != null) await _prefs.setBool('repetirSequencia', repetirSequencia);
    if (negritoTitulo != null) await _prefs.setBool('negritoTitulo', negritoTitulo);
    if (papelDeParedePalco != null) await _prefs.setBool('papelDeParedePalco', papelDeParedePalco);
    if (motivosPorSlide != null) await _prefs.setInt('motivosPorSlide', motivosPorSlide);
    if (pin != null) await _prefs.setString('pin', pin.trim());
    notifyListeners();
  }
}
