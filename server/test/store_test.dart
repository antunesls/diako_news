import 'dart:async';
import 'dart:io';

import 'package:diako_server/store.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late Store store;
  var falhar = false;
  late List<String> avisos;

  Future<void> gravarOuFalhar(String caminho, String conteudo) async {
    if (falhar) throw const FileSystemException('disco cheio');
    await Store.gravarArquivo(caminho, conteudo);
  }

  Future<Store> reabrir() async {
    final s = Store(tmp.path);
    await s.carregar();
    return s;
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('diako_store');
    falhar = false;
    store = Store(tmp.path, gravar: gravarOuFalhar);
    await store.carregar();
    avisos = [];
    store.mudancas.listen(avisos.add);
  });
  tearDown(() async {
    await store.fechar();
    await tmp.delete(recursive: true);
  });

  test('inclui, altera, exclui, lote e substituição: memória, versão, aviso e disco', () async {
    await store.salvar('recados', {'id': 'a', 'titulo': 'A'});
    await store.salvar('recados', {'id': 'a', 'titulo': 'A2'});
    await store.salvarVarios('recados', [{'id': 'b'}, {'id': 'c'}]);
    expect(await store.excluir('recados', 'c'), isTrue);
    expect(await store.excluir('recados', 'nao-existe'), isFalse);
    expect(store.listar('recados').map((d) => d['id']), ['a', 'b']);
    expect(store.buscar('recados', 'a')!['titulo'], 'A2');
    expect(store.versoes['recados'], 4);
    await Future<void>.delayed(Duration.zero);
    expect(avisos, List.filled(4, 'recados'));

    final outro = await reabrir();
    expect(outro.listar('recados').map((d) => d['id']), ['a', 'b']);
    await outro.fechar();

    await store.substituir('recados', [{'id': 'z'}]);
    expect(store.listar('recados').single['id'], 'z');
    expect((await reabrir()).listar('recados').single['id'], 'z');
  });

  test('falha ao gravar: nada muda, sem versão nem aviso; a próxima gravação funciona', () async {
    await store.salvar('membros', {'id': 'a', 'nome': 'Ana'});
    await Future<void>.delayed(Duration.zero);
    avisos.clear();
    final versao = store.versoes['membros'];

    falhar = true;
    await expectLater(store.salvar('membros', {'id': 'a', 'nome': 'Outra'}), throwsA(isA<FileSystemException>()));
    await expectLater(store.salvar('membros', {'id': 'b'}), throwsA(isA<FileSystemException>()));
    await expectLater(store.salvarVarios('membros', [{'id': 'c'}]), throwsA(isA<FileSystemException>()));
    await expectLater(store.excluir('membros', 'a'), throwsA(isA<FileSystemException>()));
    await expectLater(store.substituir('membros', []), throwsA(isA<FileSystemException>()));
    expect(store.listar('membros'), [{'id': 'a', 'nome': 'Ana'}]);
    expect(store.buscar('membros', 'b'), isNull);
    expect(store.versoes['membros'], versao);
    await Future<void>.delayed(Duration.zero);
    expect(avisos, isEmpty);

    falhar = false;
    await store.salvar('membros', {'id': 'b', 'nome': 'Bia'});
    expect(store.listar('membros').map((d) => d['id']), ['a', 'b']);
    expect((await reabrir()).listar('membros').map((d) => d['nome']), ['Ana', 'Bia']);
  });

  test('gravações simultâneas na mesma coleção não se perdem e mantêm a ordem', () async {
    await Future.wait([
      store.salvar('visitas', {'id': '1'}),
      store.salvar('visitas', {'id': '2'}),
      store.salvarVarios('visitas', [{'id': '3'}, {'id': '1', 'novo': true}]),
      store.excluir('visitas', '2'),
    ]);
    expect(store.listar('visitas'), [{'id': '1', 'novo': true}, {'id': '3'}]);
    expect((await reabrir()).listar('visitas'), [{'id': '1', 'novo': true}, {'id': '3'}]);
  });

  test('leitura durante a gravação mostra o último estado confirmado', () async {
    final liberar = Completer<void>();
    final lento = Store(tmp.path, gravar: (caminho, conteudo) async {
      await liberar.future;
      await Store.gravarArquivo(caminho, conteudo);
    });
    await lento.carregar();
    final gravando = lento.salvar('recados', {'id': 'x'});
    await Future<void>.delayed(Duration.zero);
    expect(lento.buscar('recados', 'x'), isNull);
    liberar.complete();
    await gravando;
    expect(lento.buscar('recados', 'x'), isNotNull);
    await lento.fechar();
  });
}
