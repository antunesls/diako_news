import 'package:diako_core/diako_core.dart';

import '../sync/repo_sincronizado.dart';

class RecadoRepo extends RepoSincronizado<Recado> {
  RecadoRepo({required super.api, required super.cache}) : super(colecao: 'recados');

  @override
  Recado fromJson(Map<String, dynamic> j) => Recado.fromJson(j);
  @override
  Map<String, dynamic> toJson(Recado item) => item.toJson();
  @override
  String idDe(Recado item) => item.id;

  /// Recebe a lista na nova ordem visual. Recados automáticos ficam de fora.
  Future<void> reordenar(List<Recado> novaOrdem) async {
    final editaveis = novaOrdem.where((r) => !r.auto).toList();
    await api.ordenarRecados([for (final r in editaveis) r.id]);
    for (var i = 0; i < editaveis.length; i++) {
      editaveis[i].ordem = i;
    }
    await aplicado();
  }
}
