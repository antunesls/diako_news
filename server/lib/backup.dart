import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'store.dart';

/// Backup diário dos dados (zip) numa pasta, por exemplo dentro do Google Drive.
class Backup {
  Backup({
    required this.pastaDados,
    required this.pastaDestino,
    required this.horario,
    required this.configSemSegredos,
    this.manter = 30,
  });

  final String pastaDados;
  final String pastaDestino;

  /// "HH:MM"
  final String horario;

  /// Conteúdo do config.json sem senha e token, guardado junto para facilitar a reinstalação.
  final Map<String, dynamic> configSemSegredos;
  final int manter;

  Timer? _timer;
  File get _estado => File(p.join(pastaDados, 'backup.json'));

  bool get configurado => pastaDestino.isNotEmpty;

  Future<DateTime?> ultimo() async {
    if (!await _estado.exists()) return null;
    final j = jsonDecode(await _estado.readAsString()) as Map<String, dynamic>;
    return DateTime.tryParse(j['ultimo'] as String? ?? '');
  }

  /// Gera o zip agora. Retorna o arquivo criado.
  Future<File> executar({DateTime? agora}) async {
    if (!configurado) throw StateError('Defina "pastaBackup" no config.json.');
    final quando = agora ?? DateTime.now();
    final arquivo = Archive();
    for (final nome in [for (final c in Store.colecoes) '$c.json', 'historico.jsonl']) {
      final f = File(p.join(pastaDados, nome));
      if (await f.exists()) arquivo.add(ArchiveFile.bytes('data/$nome', await f.readAsBytes()));
    }
    arquivo.add(ArchiveFile.string(
        'config-sem-senhas.json', const JsonEncoder.withIndent('  ').convert(configSemSegredos)));

    await Directory(pastaDestino).create(recursive: true);
    final destino = File(p.join(pastaDestino, 'diako-backup-${_data(quando)}.zip'));
    final tmp = File('${destino.path}.tmp');
    await tmp.writeAsBytes(ZipEncoder().encodeBytes(arquivo));
    if (await destino.exists()) await destino.delete();
    await tmp.rename(destino.path);

    await _rotacionar();
    await _estado.writeAsString(jsonEncode({'ultimo': quando.toIso8601String()}));
    return destino;
  }

  /// Apaga os backups mais antigos, mantendo [manter] arquivos.
  Future<void> _rotacionar() async {
    final arquivos = await Directory(pastaDestino)
        .list()
        .where((e) => e is File && RegExp(r'diako-backup-\d{4}-\d{2}-\d{2}\.zip$').hasMatch(e.path))
        .cast<File>()
        .toList();
    arquivos.sort((a, b) => b.path.compareTo(a.path)); // o nome tem a data
    for (final velho in arquivos.skip(manter)) {
      await velho.delete();
    }
  }

  /// Verifica a cada minuto se chegou o horário e se o backup de hoje ainda não foi feito.
  void agendar() {
    if (!configurado) return;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) async {
      final agora = DateTime.now();
      final hhmm = '${agora.hour.toString().padLeft(2, '0')}:${agora.minute.toString().padLeft(2, '0')}';
      if (hhmm.compareTo(horario) < 0) return;
      final u = await ultimo();
      if (u != null && _data(u) == _data(agora)) return;
      try {
        final f = await executar(agora: agora);
        stdout.writeln('Backup gravado em ${f.path}');
      } catch (e) {
        stderr.writeln('Falha no backup: $e');
      }
    });
  }

  void parar() => _timer?.cancel();

  static String _data(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
