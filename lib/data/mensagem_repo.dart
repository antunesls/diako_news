import 'package:diako_core/diako_core.dart';

import '../sync/repo_sincronizado.dart';
import '../sync/server_api.dart';

class MensagemRepo extends RepoSincronizado<Mensagem> {
  MensagemRepo({required super.api, required super.cache})
    : super(colecao: 'mensagens');

  @override
  Mensagem fromJson(Map<String, dynamic> j) => Mensagem.fromJson(j);
  @override
  Map<String, dynamic> toJson(Mensagem item) => item.toJson();
  @override
  String idDe(Mensagem item) => item.id;

  int get novas => todos.where((m) => m.status == 'nova').length;
  List<Mensagem> get recentes =>
      todos.toList()..sort((a, b) => b.criadoEm.compareTo(a.criadoEm));

  Future<void> mudarStatus(Mensagem item, String status) async {
    if (!online)
      throw ServidorException(
        'Sem conexão. Aguarde para atualizar a mensagem.',
      );
    substituir(
      Mensagem.fromJson(
        await api.atualizar('mensagens', item.id, {'status': status}),
      ),
    );
    await aplicado();
  }
}
