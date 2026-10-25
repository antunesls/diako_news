import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Configuração lida de config.json (ao lado do executável).
class Config {
  Config({
    required this.pastaBase,
    this.porta = 8080,
    required this.senhaAdmin,
    this.holyricsHost = '127.0.0.1',
    this.holyricsPorta = 8091,
    this.holyricsToken = '',
    this.pastaImagensHolyrics = '',
    this.pastaBackup = '',
    this.horaBackup = '03:00',
    this.urlPublica = '',
  });

  /// Pasta onde ficam config.json, data/ e web/.
  final String pastaBase;
  final int porta;
  final String senhaAdmin;
  final String holyricsHost;
  final int holyricsPorta;
  final String holyricsToken;

  /// Pasta de imagens da biblioteca do Holyrics. Os cartazes e o QR vão para a subpasta "Diako".
  final String pastaImagensHolyrics;
  final String pastaBackup;

  /// "HH:MM" do backup diário.
  final String horaBackup;

  /// Endereço que vai no QR code (ex: http://192.168.0.10:8080). Vazio = detecta o IP.
  final String urlPublica;

  String get pastaDados => p.join(pastaBase, 'data');
  String get pastaWeb => p.join(pastaBase, 'web');

  /// Onde os cartazes são gravados. Sem pasta do Holyrics configurada, ficam em data/cartazes.
  String get pastaCartazes =>
      pastaImagensHolyrics.isEmpty ? p.join(pastaDados, 'cartazes') : p.join(pastaImagensHolyrics, subpastaHolyrics);

  /// Subpasta dentro da biblioteca de imagens do Holyrics (usada no ShowImage).
  static const subpastaHolyrics = 'Diako';

  static Future<Config> carregar(String arquivo) async {
    final f = File(arquivo);
    if (!await f.exists()) {
      throw FileSystemException('config.json não encontrado. Copie config.example.json para config.json e preencha.', arquivo);
    }
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    final h = (j['holyrics'] as Map?)?.cast<String, dynamic>() ?? const {};
    final senha = (j['senhaAdmin'] as String? ?? '').trim();
    if (senha.length < 6) {
      throw const FormatException('Defina "senhaAdmin" no config.json com pelo menos 6 caracteres.');
    }
    return Config(
      pastaBase: p.dirname(p.absolute(arquivo)),
      porta: (j['porta'] as num?)?.toInt() ?? 8080,
      senhaAdmin: senha,
      holyricsHost: h['host'] as String? ?? '127.0.0.1',
      holyricsPorta: (h['porta'] as num?)?.toInt() ?? 8091,
      holyricsToken: h['token'] as String? ?? '',
      pastaImagensHolyrics: j['pastaImagensHolyrics'] as String? ?? '',
      pastaBackup: j['pastaBackup'] as String? ?? '',
      horaBackup: j['horaBackup'] as String? ?? '03:00',
      urlPublica: j['urlPublica'] as String? ?? '',
    );
  }
}

/// IPv4 da rede local (prefere 192.168.x, 10.x e 172.16-31.x).
Future<String?> ipLocal() async {
  final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
  final ips = [for (final i in interfaces) for (final a in i.addresses) if (!a.isLoopback) a.address];
  bool privado(String ip) =>
      ip.startsWith('192.168.') || ip.startsWith('10.') || RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip);
  return ips.where(privado).firstOrNull ?? ips.firstOrNull;
}
