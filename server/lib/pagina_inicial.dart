import 'dart:typed_data';

import 'package:diako_core/diako_core.dart';
import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';

// Página inicial pública (/): PIX, horários dos cultos, links e convite de calendário.

/// "Copia e cola" do PIX estático (BR Code do Banco Central), sem valor definido.
/// [nome] e [cidade] vão sem acento e em maiúsculas (limites de 25 e 15 caracteres do padrão).
String payloadPix({required String chave, required String nome, required String cidade}) {
  String campo(String id, String valor) => '$id${valor.length.toString().padLeft(2, '0')}$valor';
  final conta = campo('00', 'br.gov.bcb.pix') + campo('01', chave.trim());
  final semCrc = campo('00', '01') +
      campo('26', conta) +
      campo('52', '0000') +
      campo('53', '986') +
      campo('58', 'BR') +
      campo('59', _textoPix(nome, 25)) +
      campo('60', _textoPix(cidade, 15)) +
      campo('62', campo('05', '***')) +
      '6304';
  return semCrc + crc16Pix(semCrc);
}

/// Chave como o Pix exige: CNPJ, CPF e telefone só com dígitos (o telefone com +).
/// E-mail e chave aleatória ficam como foram digitados.
String normalizarChavePix(String chave) {
  final t = chave.trim();
  if (t.contains('@') || !RegExp(r'^[+\d][\d\s.()/-]*$').hasMatch(t)) return t;
  final digitos = t.replaceAll(RegExp(r'\D'), '');
  return t.startsWith('+') ? '+$digitos' : digitos;
}

/// Chave para mostrar na página: CNPJ como 12.345.678/0001-99 e CPF como 123.456.789-09.
String formatarChavePix(String chave) {
  final m14 = RegExp(r'^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$').firstMatch(chave);
  if (m14 != null) return '${m14[1]}.${m14[2]}.${m14[3]}/${m14[4]}-${m14[5]}';
  final m11 = RegExp(r'^(\d{3})(\d{3})(\d{3})(\d{2})$').firstMatch(chave);
  if (m11 != null) return '${m11[1]}.${m11[2]}.${m11[3]}-${m11[4]}';
  return chave;
}

/// CRC16-CCITT (polinômio 0x1021, valor inicial 0xFFFF), em 4 dígitos hexadecimais maiúsculos.
String crc16Pix(String texto) {
  var crc = 0xFFFF;
  for (final b in texto.codeUnits) {
    crc ^= b << 8;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) : (crc << 1);
      crc &= 0xFFFF;
    }
  }
  return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
}

String _textoPix(String s, int max) {
  const de = 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑáàâãäéèêëíìîïóòôõöúùûüçñ';
  const para = 'AAAAAEEEEIIIIOOOOOUUUUCNaaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final c in s.trim().split('')) {
    final i = de.indexOf(c);
    final t = i >= 0 ? para[i] : c;
    if (RegExp(r'[A-Za-z0-9 ]').hasMatch(t)) b.write(t);
  }
  final r = b.toString().toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  return r.length > max ? r.substring(0, max) : r;
}

/// PNG quadrado (fundo branco) com o QR do PIX.
Uint8List gerarPngQrQuadrado(String conteudo, {int tamanho = 600}) {
  final qr = QrImage(QrCode(payload: QrPayload.fromString(conteudo), errorCorrectLevel: QrErrorCorrectLevel.medium));
  const margem = 4;
  final total = qr.moduleCount + margem * 2;
  final escala = (tamanho / total).floor();
  final lado = total * escala;
  final imagem = img.Image(width: lado, height: lado);
  img.fill(imagem, color: img.ColorRgb8(255, 255, 255));
  final preto = img.ColorRgb8(0, 0, 0);
  for (var linha = 0; linha < qr.moduleCount; linha++) {
    for (var coluna = 0; coluna < qr.moduleCount; coluna++) {
      if (!qr.isDark(linha, coluna)) continue;
      final x = (coluna + margem) * escala, y = (linha + margem) * escala;
      img.fillRect(imagem, x1: x, y1: y, x2: x + escala - 1, y2: y + escala - 1, color: preto);
    }
  }
  return img.encodePng(imagem);
}

/// "Domingo — 19h" (uma linha por culto; separador —, – , | ou " - ") vira {dia, hora}.
/// Sem separador, a linha inteira vai em "dia".
List<Map<String, String>> lerCultos(String texto) => [
      for (final linha in texto.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty))
        () {
          final m = RegExp(r'^(.*?)\s*(?:—|–|\||\s-\s)\s*(.+)$').firstMatch(linha);
          return m == null ? {'dia': linha, 'hora': ''} : {'dia': m.group(1)!.trim(), 'hora': m.group(2)!.trim()};
        }(),
    ];

/// Abre o endereço no Google Maps (no celular, abre o app de mapas).
String linkMapa(String endereco) =>
    'https://www.google.com/maps/search/?api=1&query=${Uri.encodeQueryComponent(endereco)}';

/// Link de conversa no WhatsApp (números brasileiros sem DDI ganham o 55).
String linkWhatsapp(String digitos) => 'https://wa.me/${digitos.length <= 11 ? '55$digitos' : digitos}';

/// Convite de calendário (.ics) de um evento, para o botão "+ Agenda" do site.
/// Horário de Brasília convertido para UTC (o Brasil não tem horário de verão desde 2019).
String icsDoEvento(Evento e, {required String igreja, required DateTime agora}) {
  String dd(int n) => n.toString().padLeft(2, '0');
  String data(DateTime d) => '${d.year}${dd(d.month)}${dd(d.day)}';
  String utc(DateTime d) {
    final u = DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second).add(const Duration(hours: 3));
    return '${data(u)}T${dd(u.hour)}${dd(u.minute)}${dd(u.second)}Z';
  }

  String esc(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll(';', r'\;').replaceAll(',', r'\,').replaceAll(RegExp(r'\r?\n'), r'\n');
  final linhas = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//DiakoNews//Agenda//PT',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    'UID:${e.id.replaceAll(RegExp(r'[^A-Za-z0-9._@-]'), '_')}@diakonews',
    'DTSTAMP:${utc(agora)}',
    if (e.diaInteiro) ...['DTSTART;VALUE=DATE:${data(e.inicio)}', 'DTEND;VALUE=DATE:${data(e.fim)}']
    else ...['DTSTART:${utc(e.inicio)}', 'DTEND:${utc(e.fim.isAfter(e.inicio) ? e.fim : e.inicio.add(const Duration(hours: 1)))}'],
    'SUMMARY:${esc(e.titulo)}',
    if (e.local.isNotEmpty) 'LOCATION:${esc(e.local)}',
    'DESCRIPTION:${esc([e.descricao, igreja].where((t) => t.isNotEmpty).join('\n\n'))}',
    'END:VEVENT',
    'END:VCALENDAR',
  ];
  return '${linhas.join('\r\n')}\r\n';
}
