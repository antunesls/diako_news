import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Como o servidor chega ao Holyrics.
enum ModoHolyrics {
  /// Servidor na mesma rede do Holyrics: chama a API direto.
  local,

  /// Servidor na internet: os comandos vão pelo agente instalado no PC da igreja.
  agente,
}

/// Configuração lida de config.json (ao lado do executável).
class Config {
  Config({
    required this.pastaBase,
    this.porta = 8080,
    this.endereco = '0.0.0.0',
    required this.senhaAdmin,
    this.modoHolyrics = ModoHolyrics.local,
    this.holyricsHost = '127.0.0.1',
    this.holyricsPorta = 8091,
    this.holyricsToken = '',
    this.chaveAgente = '',
    this.chaveMural = '',
    this.confiarProxy = false,
    this.pastaImagensHolyrics = '',
    this.pastaBackup = '',
    this.horaBackup = '03:00',
    this.urlPublica = '',
  });

  /// Pasta onde ficam config.json, data/ e web/.
  final String pastaBase;
  final int porta;

  /// Interface de rede: "0.0.0.0" (toda a rede) ou "127.0.0.1" (só o proxy reverso local).
  final String endereco;
  final String senhaAdmin;
  final ModoHolyrics modoHolyrics;
  final String holyricsHost;
  final int holyricsPorta;
  final String holyricsToken;

  /// Segredo que o agente do PC da igreja usa para se conectar (modo agente).
  final String chaveAgente;

  /// Se preenchida, o mural só abre com ?chave=... na URL.
  final String chaveMural;

  /// Atrás de um proxy reverso (Caddy): usa o X-Forwarded-For como IP do visitante.
  final bool confiarProxy;

  /// Pasta de imagens da biblioteca do Holyrics. Os cartazes e o QR vão para a subpasta "Diako".
  final String pastaImagensHolyrics;
  final String pastaBackup;

  /// "HH:MM" do backup diário.
  final String horaBackup;

  /// Endereço público do site (vai no QR code), ex: https://diako.minhaigreja.com.br. Vazio = detecta o IP.
  final String urlPublica;

  String get pastaDados => p.join(pastaBase, 'data');
  String get pastaWeb => p.join(pastaBase, 'web');

  /// Onde os cartazes são gravados: na pasta de imagens do Holyrics (modo local configurado)
  /// ou em data/cartazes (modo agente, que os copia para o PC da igreja).
  String get pastaCartazes => modoHolyrics == ModoHolyrics.local && pastaImagensHolyrics.isNotEmpty
      ? p.join(pastaImagensHolyrics, subpastaHolyrics)
      : p.join(pastaDados, 'cartazes');

  /// Subpasta dentro da biblioteca de imagens do Holyrics (usada no ShowImage).
  static const subpastaHolyrics = 'Diako';

  static Future<Config> carregar(String arquivo) async {
    final f = File(arquivo);
    if (!await f.exists()) {
      throw FileSystemException('config.json não encontrado. Copie config.example.json para config.json e preencha.', arquivo);
    }
    return lerJson(await f.readAsString(), pastaBase: p.dirname(p.absolute(arquivo)));
  }

  static Config lerJson(String texto, {required String pastaBase}) {
    // O Bloco de Notas pode salvar com BOM, que o jsonDecode não aceita.
    if (texto.startsWith('﻿')) texto = texto.substring(1);
    final j = jsonDecode(texto) as Map<String, dynamic>;
    final h = (j['holyrics'] as Map?)?.cast<String, dynamic>() ?? const {};
    final modo = (h['modo'] as String? ?? 'local') == 'agente' ? ModoHolyrics.agente : ModoHolyrics.local;
    final confiarProxy = j['confiarProxy'] as bool? ?? false;
    final online = modo == ModoHolyrics.agente || confiarProxy;

    final senha = (j['senhaAdmin'] as String? ?? '').trim();
    final minimo = online ? 10 : 6;
    if (senha.length < minimo) {
      throw FormatException('Defina "senhaAdmin" no config.json com pelo menos $minimo caracteres.');
    }
    final chaveAgente = (j['chaveAgente'] as String? ?? '').trim();
    if (modo == ModoHolyrics.agente && chaveAgente.length < 24) {
      throw const FormatException('No modo agente, defina "chaveAgente" com pelo menos 24 caracteres.');
    }
    return Config(
      pastaBase: pastaBase,
      porta: (j['porta'] as num?)?.toInt() ?? 8080,
      endereco: j['endereco'] as String? ?? '0.0.0.0',
      senhaAdmin: senha,
      modoHolyrics: modo,
      holyricsHost: h['host'] as String? ?? '127.0.0.1',
      holyricsPorta: (h['porta'] as num?)?.toInt() ?? 8091,
      holyricsToken: h['token'] as String? ?? '',
      chaveAgente: chaveAgente,
      chaveMural: (j['chaveMural'] as String? ?? '').trim(),
      confiarProxy: confiarProxy,
      pastaImagensHolyrics: j['pastaImagensHolyrics'] as String? ?? '',
      pastaBackup: j['pastaBackup'] as String? ?? '',
      horaBackup: j['horaBackup'] as String? ?? '03:00',
      urlPublica: (j['urlPublica'] as String? ?? '').trim().replaceAll(RegExp(r'/+$'), ''),
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
