import 'package:diako_core/diako_core.dart';

import '../sync/repo_sincronizado.dart';

class MotivoRepo extends RepoSincronizado<Motivo> {
  MotivoRepo({required super.api, required super.cache}) : super(colecao: 'motivos');

  @override
  Motivo fromJson(Map<String, dynamic> j) => Motivo.fromJson(j);
  @override
  Map<String, dynamic> toJson(Motivo item) => item.toJson();
  @override
  String idDe(Motivo item) => item.id;

  List<Motivo> _por(StatusMotivo s) => todos.where((m) => m.status == s).toList();

  /// Enviados pelo site, esperando o pastor aprovar (mais novos primeiro).
  List<Motivo> get aguardando => _por(StatusMotivo.aguardando).reversed.toList();

  /// Na lista de oração, do mais antigo para o mais novo.
  List<Motivo> get pendentes => _por(StatusMotivo.pendente);
  /// Mais recentes primeiro (pela data do atendimento).
  List<Motivo> get atendidos => _por(StatusMotivo.atendido)
    ..sort((a, b) => (b.atendidoEm ?? b.criadoEm).compareTo(a.atendidoEm ?? a.criadoEm));

  /// O que pode ir para o telão (aprovado e público).
  List<Motivo> get projetaveis => todos.where((m) => m.projetavel).toList();

  Future<void> aprovar(Motivo m) async {
    substituir(fromJson(await api.aprovarMotivo(m.id)));
    await aplicado();
  }

  Future<void> alternarAtendido(Motivo m) {
    final novo = Motivo.fromJson(m.toJson())..status = m.atendido ? StatusMotivo.pendente : StatusMotivo.atendido;
    return atualizar(novo);
  }
}
