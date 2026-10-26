import 'package:diako_core/diako_core.dart';

import '../sync/repo_sincronizado.dart';
import '../sync/server_api.dart';

/// Visitantes dos últimos 30 dias (o servidor manda só esses). No tablet interessa
/// o dia: quem chegou e quem o pastor ainda pode citar no culto.
class VisitaRepo extends RepoSincronizado<Visita> {
  VisitaRepo({required super.api, required super.cache, DateTime Function()? relogio})
      : _agora = relogio ?? DateTime.now,
        super(colecao: 'visitas');

  final DateTime Function() _agora;

  @override
  Visita fromJson(Map<String, dynamic> j) => Visita.fromJson(j);
  @override
  Map<String, dynamic> toJson(Visita item) => item.toJson();
  @override
  String idDe(Visita item) => item.id;

  /// Visitas de hoje, na ordem de chegada.
  List<Visita> get hoje {
    final dia = diaIso(_agora());
    return todos.where((v) => v.data == dia).toList()..sort((a, b) => a.criadoEm.compareTo(b.criadoEm));
  }

  /// Podem ser citadas e ainda não foram: a lista do pastor (e o número no ícone).
  List<Visita> get pendentes => pendenciasDoPastor(todos, _agora());

  /// O pastor já deu as boas-vindas (ou [desfazer] a marcação).
  Future<void> marcarMencionada(Visita v, {bool desfazer = false}) async {
    if (!online) throw ServidorException('Sem conexão. Aguarde para marcar.');
    substituir(fromJson(await api.marcarVisitaMencionada(v.id, desfazer: desfazer)));
    await aplicado();
  }

  /// "Sejam bem-vindos!" no telão. Sem [ids]: todos os pendentes de hoje.
  /// O servidor dá a baixa quando o Holyrics aceita; a lista atualiza pelo tempo real.
  Future<void> projetarBoasVindas({List<String>? ids}) async {
    final r = await api.projetarBoasVindas(ids: ids);
    if (r['status'] != 'ok') {
      throw ServidorException((r['error'] as String?) ?? 'O Holyrics não aceitou a projeção.');
    }
    await sincronizar();
  }
}
