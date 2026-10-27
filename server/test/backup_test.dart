import 'dart:io';

import 'package:diako_server/backup.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('alertas do backup', () {
    final agora = DateTime(2026, 10, 27, 10);
    final ontem = DateTime(2026, 10, 26, 3);

    test('tudo em dia: nenhum alerta', () {
      expect(alertasBackup(ultimo: ontem, falha: null, agora: agora), isEmpty);
      expect(alertasBackup(ultimo: ontem, falha: null, copiaPc: ontem, modoAgente: true, agora: agora), isEmpty);
      // Instalação nova: ainda não houve backup nem falha.
      expect(alertasBackup(ultimo: null, falha: null, modoAgente: true, agora: agora), isEmpty);
    });

    test('falha depois do último sucesso', () {
      final a = alertasBackup(ultimo: ontem, falha: DateTime(2026, 10, 27, 3), agora: agora);
      expect(a.single, contains('falhou em 27/10 às 03:00'));
      // Uma falha antiga, já seguida de um backup bom, não conta.
      expect(alertasBackup(ultimo: ontem, falha: DateTime(2026, 10, 25, 3), agora: agora), isEmpty);
    });

    test('backup atrasado', () {
      expect(alertasBackup(ultimo: DateTime(2026, 10, 24, 3), falha: null, agora: agora).single, contains('há 3 dias'));
    });

    test('modo agente: sem cópia no PC ou cópia atrasada', () {
      final semCopia = alertasBackup(ultimo: DateTime(2026, 10, 26, 3), falha: null, modoAgente: true, agora: agora);
      expect(semCopia.single, contains('Ainda não há cópia'));
      // Backup de hoje: o agente ainda tem tempo de copiar.
      expect(alertasBackup(ultimo: DateTime(2026, 10, 27, 3), falha: null, modoAgente: true, agora: agora), isEmpty);
      final atrasada =
          alertasBackup(ultimo: ontem, falha: null, copiaPc: DateTime(2026, 10, 23, 4), modoAgente: true, agora: agora);
      expect(atrasada.single, contains('23/10'));
      // Sem senha do backup a cópia fica desligada: o alerta diz como ligar.
      expect(alertasBackup(ultimo: ontem, falha: null, modoAgente: true, copiaPcLigada: false, agora: agora).single,
          contains('Defina a senha do backup'));
      expect(alertasBackup(ultimo: ontem, falha: null, copiaPcLigada: false, agora: agora), isEmpty);
      // No modo local não há cópia no PC para cobrar.
      expect(alertasBackup(ultimo: DateTime(2026, 10, 26, 3), falha: null, agora: agora), isEmpty);
    });
  });

  group('backup automático', () {
    late Directory tmp;
    late DateTime agora;
    late Backup backup;
    late List<DateTime> avisos;
    late String destino;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('diako_backup');
      final dados = p.join(tmp.path, 'data');
      await Directory(dados).create();
      // Um arquivo no lugar da pasta de destino faz a gravação falhar.
      destino = p.join(tmp.path, 'destino');
      await File(destino).writeAsString('não é pasta');
      agora = DateTime(2026, 10, 27, 3, 0);
      avisos = [];
      backup = Backup(pastaDados: dados, pastaDestino: destino, relogio: () => agora)
        ..aoFalhar = (quando) async => avisos.add(quando);
    });
    tearDown(() => tmp.delete(recursive: true));

    test('falha: registra, avisa uma vez por dia e espera 60 min para tentar de novo', () async {
      await backup.verificar();
      expect((await backup.estado()).falha, agora);
      expect(avisos, [agora]);

      agora = DateTime(2026, 10, 27, 3, 30);
      await backup.verificar(); // ainda não passou o intervalo
      expect((await backup.estado()).falha, DateTime(2026, 10, 27, 3, 0));

      agora = DateTime(2026, 10, 27, 4, 1);
      await backup.verificar(); // tenta de novo e falha, mas não avisa outra vez hoje
      expect((await backup.estado()).falha, agora);
      expect(avisos, hasLength(1));
      final estado = await backup.estado();
      expect(alertasBackup(ultimo: estado.ultimo, falha: estado.falha, agora: agora), hasLength(1));

      // Corrigido o destino, a próxima tentativa grava e o alerta some.
      await File(destino).delete();
      agora = DateTime(2026, 10, 27, 5, 2);
      final gravados = <String>[];
      backup.aoGravar = (f) => gravados.add(p.basename(f.path));
      await backup.verificar();
      final depois = await backup.estado();
      expect(depois.ultimo, agora);
      expect(gravados, ['diako-backup-2026-10-27.zip']);
      expect(alertasBackup(ultimo: depois.ultimo, falha: depois.falha, agora: agora), isEmpty);

      // Já fez o de hoje: não grava de novo.
      agora = DateTime(2026, 10, 27, 23, 0);
      await backup.verificar();
      expect(gravados, hasLength(1));
    });

    test('antes do horário não faz nada', () async {
      agora = DateTime(2026, 10, 27, 2, 59);
      await backup.verificar();
      expect((await backup.estado()).falha, isNull);
      expect(avisos, isEmpty);
    });

    test('cópia no PC da igreja fica registrada sem apagar o resto do estado', () async {
      await File(destino).delete();
      await backup.executar();
      agora = DateTime(2026, 10, 27, 3, 10);
      await backup.registrarCopiaPc('diako-backup-2026-10-27.zip');
      await backup.registrarCopiaPc('../fora.zip'); // nome inválido é ignorado
      final e = await backup.estado();
      expect(e.ultimo, DateTime(2026, 10, 27, 3, 0));
      expect(e.copiaPcEm, agora);
      expect(e.copiaPcNome, 'diako-backup-2026-10-27.zip');
    });
  });
}
