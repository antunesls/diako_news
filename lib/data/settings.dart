import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs);

  final SharedPreferences _prefs;

  /// Endereço do servidor Diako News no PC do Holyrics (ex: http://192.168.0.10:8080).
  String get servidor => _prefs.getString('servidor') ?? '';

  /// Token de sessão recebido no login.
  String get sessao => _prefs.getString('sessao') ?? '';

  /// Nome de um tema cadastrado no Holyrics; vazio usa o tema padrão.
  String get tema => _prefs.getString('tema') ?? '';
  int get segundosPorSlide => _prefs.getInt('segundosPorSlide') ?? 10;
  bool get repetirSequencia => _prefs.getBool('repetirSequencia') ?? true;
  bool get negritoTitulo => _prefs.getBool('negritoTitulo') ?? true;
  int get motivosPorSlide => _prefs.getInt('motivosPorSlide') ?? 4;
  String get pin => _prefs.getString('pin') ?? '';

  bool get configurado => servidor.isNotEmpty && sessao.isNotEmpty;

  Future<void> atualizar({
    String? servidor,
    String? sessao,
    String? tema,
    int? segundosPorSlide,
    bool? repetirSequencia,
    bool? negritoTitulo,
    int? motivosPorSlide,
    String? pin,
  }) async {
    if (servidor != null) await _prefs.setString('servidor', servidor);
    if (sessao != null) await _prefs.setString('sessao', sessao);
    if (tema != null) await _prefs.setString('tema', tema.trim());
    if (segundosPorSlide != null) await _prefs.setInt('segundosPorSlide', segundosPorSlide);
    if (repetirSequencia != null) await _prefs.setBool('repetirSequencia', repetirSequencia);
    if (negritoTitulo != null) await _prefs.setBool('negritoTitulo', negritoTitulo);
    if (motivosPorSlide != null) await _prefs.setInt('motivosPorSlide', motivosPorSlide);
    if (pin != null) await _prefs.setString('pin', pin.trim());
    notifyListeners();
  }
}
