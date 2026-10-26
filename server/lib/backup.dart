import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:diako_core/diako_core.dart';
import 'package:path/path.dart' as p;

import 'cartazes.dart';
import 'qr_oracao.dart';
import 'store.dart';

/// Formato dos arquivos de backup (manifest.json).
const versaoBackup = 2;

/// Backups em .zip: dados, histórico, cartazes e configurações públicas (sem senha nem chaves).
/// Diário no horário configurado, sob demanda pelo painel e antes de cada restauração.
class Backup {
  Backup({
    required this.pastaDados,
    String pastaDestino = '',
    String? pastaCartazes,
    String Function()? horario,
    int Function()? manter,
    Map<String, dynamic> Function()? configuracoes,
    DateTime Function()? relogio,
  })  : pastaDestino = pastaDestino.isEmpty ? p.join(pastaDados, 'backups') : pastaDestino,
        pastaCartazes = pastaCartazes ?? p.join(pastaDados, 'cartazes'),
        _horario = horario ?? (() => '03:00'),
        _manter = manter ?? (() => 30),
        _configuracoes = configuracoes ?? (() => const {}),
        _agora = relogio ?? DateTime.now;

  final String pastaDados;
  final String pastaDestino;
  final String pastaCartazes;
  final String Function() _horario;
  final int Function() _manter;
  final Map<String, dynamic> Function() _configuracoes;
  final DateTime Function() _agora;

  Timer? _timer;
  File get _estado => File(p.join(pastaDados, 'backup.json'));

  /// Sempre ativo: sem "pastaBackup" no config.json, usa data/backups.
  bool get configurado => true;
  String get horario => _horario();

  static final _nomeValido = RegExp(r'^diako-backup-\d{4}-\d{2}-\d{2}[A-Za-z0-9-]*\.zip$');

  Future<DateTime?> ultimo() async {
    if (!await _estado.exists()) return null;
    final j = jsonDecode(await _estado.readAsString()) as Map<String, dynamic>;
    return DateTime.tryParse(j['ultimo'] as String? ?? '');
  }

  /// Conteúdo do backup em memória (para baixar direto pelo painel).
  Future<Uint8List> gerarZip({DateTime? agora}) async {
    final quando = agora ?? _agora();
    final arquivo = Archive();
    for (final nome in [for (final c in Store.colecoes) '$c.json', 'historico.jsonl']) {
      final f = File(p.join(pastaDados, nome));
      if (await f.exists()) arquivo.add(ArchiveFile.bytes('data/$nome', await f.readAsBytes()));
    }
    final dirCartazes = Directory(pastaCartazes);
    if (await dirCartazes.exists()) {
      await for (final e in dirCartazes.list()) {
        final nome = p.basename(e.path);
        // O QR é refeito pelo servidor a partir do endereço público.
        if (e is File && nome != arquivoQr && nome != arquivoQrMensagens && Cartazes.nomeValido(nome)) {
          arquivo.add(ArchiveFile.bytes('cartazes/$nome', await e.readAsBytes()));
        }
      }
    }
    arquivo.add(ArchiveFile.string('configuracoes.json', const JsonEncoder.withIndent('  ').convert(_configuracoes())));
    arquivo.add(ArchiveFile.string('manifest.json',
        jsonEncode({'app': 'diako_news', 'versao': versaoBackup, 'criadoEm': quando.toIso8601String()})));
    return ZipEncoder().encodeBytes(arquivo);
  }

  /// Gera e grava o zip na pasta de backups. [sufixo] identifica backups manuais e de segurança.
  Future<File> executar({DateTime? agora, String? sufixo}) async {
    final quando = agora ?? _agora();
    final bytes = await gerarZip(agora: quando);
    await Directory(pastaDestino).create(recursive: true);
    final complemento = sufixo == null ? '' : '-${_hora(quando)}${sufixo.isEmpty ? '' : '-$sufixo'}';
    final destino = File(p.join(pastaDestino, 'diako-backup-${_data(quando)}$complemento.zip'));
    final tmp = File('${destino.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    if (await destino.exists()) await destino.delete();
    await tmp.rename(destino.path);

    await _rotacionar();
    await _estado.writeAsString(jsonEncode({'ultimo': quando.toIso8601String()}));
    return destino;
  }

  /// Backups existentes, do mais novo para o mais antigo.
  Future<List<({String nome, int tamanho, DateTime criado})>> listar() async {
    final dir = Directory(pastaDestino);
    if (!await dir.exists()) return [];
    final lista = <({String nome, int tamanho, DateTime criado})>[];
    await for (final e in dir.list()) {
      final nome = p.basename(e.path);
      if (e is! File || !_nomeValido.hasMatch(nome)) continue;
      final s = await e.stat();
      lista.add((nome: nome, tamanho: s.size, criado: s.modified));
    }
    // O nome começa com a data (e a hora, nos manuais): ordenar pelo nome é mais confiável que pela data do arquivo.
    lista.sort((a, b) => b.nome.compareTo(a.nome));
    return lista;
  }

  /// Arquivo de backup pelo nome, recusando qualquer coisa fora da pasta.
  File? arquivo(String nome) {
    if (nome != p.basename(nome) || !_nomeValido.hasMatch(nome)) return null;
    final f = File(p.join(pastaDestino, nome));
    return f.existsSync() ? f : null;
  }

  Future<bool> excluir(String nome) async {
    final f = arquivo(nome);
    if (f == null) return false;
    await f.delete();
    return true;
  }

  /// Apaga os backups mais antigos, mantendo a quantidade configurada.
  Future<void> _rotacionar() async {
    final lista = await listar();
    for (final velho in lista.skip(_manter())) {
      await File(p.join(pastaDestino, velho.nome)).delete();
    }
  }

  /// Verifica a cada minuto se chegou o horário e se o backup de hoje ainda não foi feito.
  void agendar() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) async {
      final agora = _agora();
      if (_hhmm(agora).compareTo(horario) < 0) return;
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
  static String _hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  static String _hora(DateTime d) => _hhmm(d).replaceAll(':', '') + d.second.toString().padLeft(2, '0');
}

/// O que foi restaurado.
class ResumoRestauracao {
  final colecoes = <String, int>{};
  int cartazes = 0;
  bool historico = false;
  bool configuracoes = false;
  String? backupSeguranca;

  Map<String, dynamic> toJson() => {
        'colecoes': colecoes,
        'cartazes': cartazes,
        'historico': historico,
        'configuracoes': configuracoes,
        'backupSeguranca': backupSeguranca,
      };
}

/// Restaura um backup .zip: valida tudo antes, faz um backup de segurança e só então substitui.
class Restauracao {
  Restauracao({
    required this.store,
    required this.backup,
    required this.pastaDados,
    required this.pastaCartazes,
    this.aplicarConfiguracoes,
  });

  final Store store;
  final Backup backup;
  final String pastaDados;
  final String pastaCartazes;

  /// Aplica as configurações públicas do backup (quando o usuário pede).
  final Future<void> Function(Map<String, dynamic>)? aplicarConfiguracoes;

  static const tamanhoMaximo = 500 * 1024 * 1024;

  Future<ResumoRestauracao> restaurar(List<int> zip, {bool configuracoes = false}) async {
    final Archive arquivo;
    try {
      arquivo = ZipDecoder().decodeBytes(zip);
    } catch (_) {
      throw const FormatException('O arquivo não é um backup do Diako News (.zip).');
    }
    if (arquivo.files.fold<int>(0, (t, f) => t + f.size) > tamanhoMaximo) {
      throw const FormatException('Backup grande demais.');
    }

    // 1. Valida tudo antes de mexer em qualquer coisa.
    final colecoes = <String, List<Map<String, dynamic>>>{};
    for (final nome in Store.colecoes) {
      final f = arquivo.findFile('data/$nome.json');
      if (f == null) continue;
      try {
        final lista = [for (final e in jsonDecode(utf8.decode(f.content)) as List) Map<String, dynamic>.from(e as Map)];
        for (final doc in lista) {
          switch (nome) {
            case 'recados':
              Recado.fromJson(doc);
            case 'motivos':
              Motivo.fromJson(doc);
            case 'membros':
              Membro.fromJson(doc);
            case 'mensagens':
              final mensagem = Mensagem.fromJson(doc);
              if (!Mensagem.tipos.contains(mensagem.tipo) || !Mensagem.statusValidos.contains(mensagem.status)) {
                throw const FormatException('Mensagem inválida.');
              }
          }
        }
        colecoes[nome] = lista;
      } catch (_) {
        throw FormatException('Backup com dados inválidos em data/$nome.json.');
      }
    }
    if (colecoes.isEmpty) throw const FormatException('O arquivo não contém dados do Diako News.');

    final cartazes = <String, List<int>>{};
    var temPastaCartazes = false;
    for (final f in arquivo.files) {
      if (!f.isFile || !f.name.startsWith('cartazes/')) continue;
      temPastaCartazes = true;
      final nome = f.name.substring('cartazes/'.length);
        if (Cartazes.nomeValido(nome) && nome != arquivoQr && nome != arquivoQrMensagens) cartazes[nome] = f.content;
    }
    final historico = arquivo.findFile('data/historico.jsonl');
    Map<String, dynamic>? cfg;
    final cfgArquivo = arquivo.findFile('configuracoes.json');
    if (configuracoes && cfgArquivo != null) {
      try {
        cfg = Map<String, dynamic>.from(jsonDecode(utf8.decode(cfgArquivo.content)) as Map);
      } catch (_) {
        throw const FormatException('configuracoes.json inválido no backup.');
      }
    }

    // 2. Backup de segurança do estado atual.
    final resumo = ResumoRestauracao();
    resumo.backupSeguranca = p.basename((await backup.executar(sufixo: 'antes-restauracao')).path);

    // 3. Substitui.
    for (final e in colecoes.entries) {
      await store.substituir(e.key, e.value);
      resumo.colecoes[e.key] = e.value.length;
    }
    if (historico != null) {
      await File(p.join(pastaDados, 'historico.jsonl')).writeAsBytes(historico.content, flush: true);
      resumo.historico = true;
      store.avisar('historico');
    }
    // Backups antigos (sem a pasta cartazes/) mantêm os cartazes atuais.
    if (temPastaCartazes) {
      final dir = Directory(pastaCartazes);
      await dir.create(recursive: true);
      await for (final e in dir.list()) {
        final nome = p.basename(e.path);
        if (e is File && nome != arquivoQr && Cartazes.nomeValido(nome)) await e.delete();
      }
      for (final c in cartazes.entries) {
        await File(p.join(pastaCartazes, c.key)).writeAsBytes(c.value, flush: true);
      }
      resumo.cartazes = cartazes.length;
      store.avisar('cartazes');
    }
    if (cfg != null && aplicarConfiguracoes != null) {
      await aplicarConfiguracoes!(cfg);
      resumo.configuracoes = true;
    }
    return resumo;
  }
}
