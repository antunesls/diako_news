import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:diako_server/app.dart';
import 'package:diako_server/auth.dart';
import 'package:diako_server/backup.dart';
import 'package:diako_server/cartazes.dart';
import 'package:diako_server/config.dart';
import 'package:diako_server/configuracoes.dart';
import 'package:diako_server/historico.dart';
import 'package:diako_server/holyrics.dart';
import 'package:diako_server/store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

Uint8List foto(int largura, int altura) => img.encodeJpg(img.Image(width: largura, height: altura));

void main() {
  group('servidor', () {
    late Directory tmp;
    late Store store;
    late Handler handler;
    late String token;
    late String pastaDados;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('diako_membros');
      final config = Config.lerJson('{"senhaAdmin":"senha-teste"}', pastaBase: tmp.path);
      pastaDados = config.pastaDados;
      store = Store(config.pastaDados);
      await store.carregar();
      final cfg = await Configuracoes.carregar(config, urlDetectada: 'http://192.168.0.10:8080');
      final auth = Auth(conferirSenha: cfg.conferirSenha, pastaDados: config.pastaDados);
      final backup = Backup(pastaDados: config.pastaDados, configuracoes: cfg.publicas);
      final web = Directory(p.join(tmp.path, 'web'))..createSync();
      handler = Servidor(
        store: store,
        auth: auth,
        holyrics:
            HolyricsDireto(host: 'h', porta: 1, token: 't', cliente: MockClient((_) async => http.Response('{}', 200))),
        cartazes: Cartazes(config.pastaCartazes),
        backup: backup,
        pastaWeb: web.path,
        urlOracao: cfg.urlOracao,
        cartazesNoHolyrics: false,
        historico: Historico(config.pastaDados),
        cfg: cfg,
        restauracao: Restauracao(
            store: store, backup: backup, pastaDados: config.pastaDados, pastaCartazes: config.pastaCartazes),
      ).handler;
      final r =
          await handler(Request('POST', Uri.parse('http://x/api/login'), body: jsonEncode({'senha': 'senha-teste'})));
      token = (jsonDecode(await r.readAsString()) as Map)['token'] as String;
    });
    tearDown(() async {
      await store.fechar();
      await tmp.delete(recursive: true);
    });

    Future<(int, dynamic)> chamar(String metodo, String caminho,
        {Object? json, List<int>? bytes, bool login = true}) async {
      final r = await handler(Request(metodo, Uri.parse('http://x$caminho'),
          headers: {
            if (login) 'authorization': 'Bearer $token',
            if (json != null) 'content-type': 'application/json'
          },
          body: bytes ?? (json == null ? null : jsonEncode(json))));
      final corpo = await r.read().expand((b) => b).toList();
      final texto = utf8.decode(corpo, allowMalformed: true);
      return (r.statusCode, texto.startsWith('{') || texto.startsWith('[') ? jsonDecode(texto) : corpo);
    }

    Future<Map<String, dynamic>> criar(Map<String, dynamic> dados) async =>
        (await chamar('POST', '/api/membros', json: dados)).$2 as Map<String, dynamic>;

    test('membro antigo (só nome/dia/mês/ativo) volta com status derivado', () async {
      await store.salvar('membros', {'id': 'antigo', 'nome': 'Membro Antigo', 'dia': 20, 'mes': 12, 'ativo': false});
      final lista = (await chamar('GET', '/api/membros')).$2 as List;
      final m = lista.single;
      expect(m['status'], 'inativo');
      expect(m['ativo'], isFalse);
      expect(m['dia'], 20);
      expect(m['mes'], 12);
      // Editar pelo painel grava o formato novo, sem perder o cadastro antigo.
      final (st, salvo) = await chamar('PUT', '/api/membros/antigo', json: {'nome': 'Membro Antigo', 'status': 'membro'});
      expect(st, 200);
      expect(salvo['status'], 'membro');
      expect(salvo['ativo'], isTrue);
      expect((salvo['historicoStatus'] as List).map((h) => h['status']), ['membro']);
    });

    test('cadastro completo mantém os campos do app e o histórico de status', () async {
      final m = await criar({
        'nome': 'Ana Souza',
        'dia': 5,
        'mes': 3,
        'ano': 1990,
        'sexo': 'F',
        'estadoCivil': 'Casada',
        'cpf': '111.444.777-35',
        'telefone': '(11) 98888-7777',
        'email': 'ana@exemplo.com',
        'cep': '01234-000',
        'rua': 'Rua das Flores',
        'numero': '120',
        'cidade': 'São Paulo',
        'estado': 'SP',
        'status': 'congregado',
        'dataBatismo': '14/06/2015',
        'ministerios': ['Louvor', 'Infantil'],
        'funcao': 'Líder',
        'emergenciaNome': 'Bruno',
        'emergenciaTelefone': '(11) 97777-6666',
        'emergenciaVinculo': 'esposo',
        'observacoes': 'Chegou pela família',
      });
      // Campos do formato antigo (app e aniversariantes continuam funcionando).
      expect([m['dia'], m['mes'], m['ativo']], [5, 3, true]);
      expect(m['status'], 'congregado');
      // Normalizações: CPF e CEP só dígitos, data dd/mm/aaaa vira ISO.
      expect(m['cpf'], '11144477735');
      expect(m['cep'], '01234000');
      expect(m['dataBatismo'], '2015-06-14');
      expect(m['historicoStatus'].single['status'], 'congregado');

      // Mudou de status: entra no histórico e sai dos aniversariantes.
      final inativa = (await chamar('PUT', '/api/membros/${m['id']}', json: {'status': 'inativo'})).$2;
      expect(inativa['ativo'], isFalse);
      expect((inativa['historicoStatus'] as List).map((h) => h['status']), ['congregado', 'inativo']);

      // Sem o campo status no corpo, mantém o atual.
      final igual = (await chamar('PUT', '/api/membros/${m['id']}', json: {'nome': 'Ana Souza Lima'})).$2;
      expect(igual['status'], 'inativo');
      expect((igual['historicoStatus'] as List).length, 2);
      expect(igual['nome'], 'Ana Souza Lima');
    });

    test('valida CPF, e-mail, status, datas e vínculos', () async {
      const base = {'nome': 'Ana', 'dia': 5, 'mes': 3};
      expect((await chamar('POST', '/api/membros', json: {...base, 'cpf': '11144477736'})).$1, 400);
      expect((await chamar('POST', '/api/membros', json: {...base, 'email': 'ana@'})).$1, 400);
      expect((await chamar('POST', '/api/membros', json: {...base, 'status': 'santo'})).$1, 400);
      expect((await chamar('POST', '/api/membros', json: {...base, 'dataBatismo': 'ontem'})).$1, 400);
      expect((await chamar('POST', '/api/membros', json: {...base, 'dataBatismo': '31/02/2015'})).$1, 400);
      expect((await chamar('POST', '/api/membros', json: {...base, 'ano': 1850})).$1, 400);
      expect((await chamar('POST', '/api/membros', json: {...base, 'conjugeId': 'nao-existe'})).$1, 400);

      final a = await criar(base);
      expect((await chamar('PUT', '/api/membros/${a['id']}', json: {'conjugeId': a['id']})).$1, 400);
      expect((await chamar('PUT', '/api/membros/${a['id']}', json: {'paisIds': [a['id']]})).$1, 400);

      // Foto e histórico só mudam pelo servidor, nunca pelo corpo do PUT.
      final editado = (await chamar('PUT', '/api/membros/${a['id']}',
              json: {'foto': '0123456789abcdef0123.jpg', 'historicoStatus': [], 'criadoEm': '2000-01-01T00:00:00.000'}))
          .$2 as Map<String, dynamic>;
      expect(editado.containsKey('foto'), isFalse);
      expect(editado['historicoStatus'] as List, hasLength(1));
      expect(editado['criadoEm'], isNot(startsWith('2000')));
    });

    test('vínculos de cônjuge são recíprocos e a exclusão limpa tudo', () async {
      final ana = await criar({'nome': 'Ana', 'dia': 5, 'mes': 3});
      final bruno = await criar({'nome': 'Bruno', 'dia': 10, 'mes': 4});
      final carla = await criar({'nome': 'Carla', 'dia': 15, 'mes': 5});

      // Ana casa com Bruno: Bruno ganha o vínculo de volta.
      await chamar('PUT', '/api/membros/${ana['id']}', json: {'conjugeId': bruno['id']});
      final bruno1 = (await chamar('GET', '/api/membros')).$2 as List;
      expect(bruno1.firstWhere((m) => m['id'] == bruno['id'])['conjugeId'], ana['id']);

      // Bruno troca de cônjuge: Ana fica livre, Carla aponta para Bruno.
      await chamar('PUT', '/api/membros/${bruno['id']}', json: {'conjugeId': carla['id']});
      final lista = (await chamar('GET', '/api/membros')).$2 as List;
      expect(lista.firstWhere((m) => m['id'] == ana['id']).containsKey('conjugeId'), isFalse);
      expect(lista.firstWhere((m) => m['id'] == carla['id'])['conjugeId'], bruno['id']);

      // Filha com pais cadastrados; excluir o pai limpa o vínculo nela e no cônjuge.
      final filha = await criar({'nome': 'Bia', 'dia': 1, 'mes': 1, 'paisIds': [bruno['id']]});
      await chamar('DELETE', '/api/membros/${bruno['id']}');
      final depois = (await chamar('GET', '/api/membros')).$2 as List;
      final bia = depois.firstWhere((m) => m['id'] == filha['id']);
      expect(bia.containsKey('paisIds'), isFalse);
      expect(depois.firstWhere((m) => m['id'] == carla['id']).containsKey('conjugeId'), isFalse);
    });

    test('foto: envio atrás de login, troca apaga a anterior, exclusão limpa', () async {
      final m = await criar({'nome': 'Ana', 'dia': 5, 'mes': 3});
      final id = m['id'] as String;
      expect((await chamar('POST', '/api/membros/$id/foto', bytes: utf8.encode('x'))).$1, 400);

      final (st1, comFoto) = await chamar('POST', '/api/membros/$id/foto', bytes: foto(800, 600));
      expect(st1, 201);
      final arquivo1 = comFoto['foto'] as String;
      expect(arquivo1.endsWith('.jpg'), isTrue);

      // A foto nunca é pública.
      expect((await chamar('GET', '/api/membros/$id/foto', login: false)).$1, 401);
      final (stFoto, bytes) = await chamar('GET', '/api/membros/$id/foto');
      expect(stFoto, 200);
      expect(img.decodeJpg(Uint8List.fromList(bytes as List<int>))!.width, lessThanOrEqualTo(1280));
      final (stMini, mini) = await chamar('GET', '/api/membros/$id/foto-miniatura');
      expect(stMini, 200);
      expect(img.decodeJpg(Uint8List.fromList(mini as List<int>))!.width, lessThanOrEqualTo(320));

      // Troca: arquivo antigo sai do disco.
      final (_, comFoto2) = await chamar('POST', '/api/membros/$id/foto', bytes: foto(900, 900));
      final arquivo2 = comFoto2['foto'] as String;
      expect(arquivo2, isNot(arquivo1));
      expect(File(p.join(pastaDados, 'fotos-membros', arquivo1)).existsSync(), isFalse);
      expect(File(p.join(pastaDados, 'fotos-membros', arquivo2)).existsSync(), isTrue);

      // Remover a foto e, depois, excluir o membro: pasta fica vazia.
      await chamar('DELETE', '/api/membros/$id/foto');
      final semFoto = (await chamar('GET', '/api/membros')).$2 as List;
      expect(semFoto.single.containsKey('foto'), isFalse);
      expect((await chamar('GET', '/api/membros/$id/foto')).$1, 404);
      await chamar('DELETE', '/api/membros/$id');
      expect(File(p.join(pastaDados, 'fotos-membros', arquivo2)).existsSync(), isFalse);
    });

    test('exportar CSV com BOM e filtros', () async {
      final mes = DateTime.now().month;
      final outroMes = mes == 12 ? 1 : mes + 1;
      await criar({'nome': 'Ana Souza', 'dia': 5, 'mes': mes, 'status': 'membro', 'telefone': '11988887777'});
      await criar({'nome': 'Bruno', 'dia': 10, 'mes': outroMes, 'status': 'visitante'});
      await criar({'nome': 'Zeca', 'dia': 2, 'mes': outroMes, 'status': 'inativo'});

      final (_, bytes) = await chamar('GET', '/api/membros/exportar?status=membro');
      final brutos = bytes as List<int>;
      expect(brutos.take(3), [0xEF, 0xBB, 0xBF]); // BOM para o Excel
      final texto = utf8.decode(brutos);
      expect(texto, contains('Nome;Aniversário;Idade;Status'));
      expect(texto, contains('Ana Souza;05/${mes.toString().padLeft(2, '0')}'));
      expect(texto, isNot(contains('Bruno')));

      // "Ativos" inclui membro e visitante, sem o inativo.
      final (_, ativosBytes) = await chamar('GET', '/api/membros/exportar?status=ativos');
      final ativos = utf8.decode(ativosBytes as List<int>);
      expect(ativos, contains('Ana Souza'));
      expect(ativos, contains('Bruno'));
      expect(ativos, isNot(contains('Zeca')));

      // Só os aniversariantes do mês.
      final (_, mesBytes) = await chamar('GET', '/api/membros/exportar?aniversariantes=mes');
      final doMes = utf8.decode(mesBytes as List<int>);
      expect(doMes, contains('Ana Souza'));
      expect(doMes, isNot(contains('Bruno')));

      // Busca (sem acento, como na tela) e quem falta autorizar (LGPD).
      await criar({'nome': 'José Araújo', 'dia': 3, 'mes': outroMes, 'consentimentoEm': '01/02/2024'});
      final (_, buscaBytes) = await chamar('GET', '/api/membros/exportar?busca=jose%20araujo');
      final achados = utf8.decode(buscaBytes as List<int>);
      expect(achados, contains('José Araújo'));
      expect(achados, contains('01/02/2024'));
      expect(achados, isNot(contains('Ana Souza')));
      final (_, semBytes) = await chamar('GET', '/api/membros/exportar?semConsentimento=1');
      final sem = utf8.decode(semBytes as List<int>);
      expect(sem, contains('Ana Souza'));
      expect(sem, isNot(contains('José Araújo')));
      final (_, novasBytes) = await chamar('GET', '/api/membros/exportar?novasDias=90');
      expect(utf8.decode(novasBytes as List<int>), contains('Zeca'));
    });

    test('escolher como cônjuge alguém já casado desfaz o vínculo antigo', () async {
      final ana = await criar({'nome': 'Ana', 'dia': 5, 'mes': 3});
      final bruno = await criar({'nome': 'Bruno', 'dia': 10, 'mes': 4, 'conjugeId': ana['id']});
      final carlos = await criar({'nome': 'Carlos', 'dia': 15, 'mes': 5});

      // Carlos passa a ser cônjuge de Ana: Bruno não pode continuar apontando para ela.
      await chamar('PUT', '/api/membros/${carlos['id']}', json: {'conjugeId': ana['id']});
      final lista = (await chamar('GET', '/api/membros')).$2 as List;
      Map porId(Object? id) => lista.firstWhere((m) => m['id'] == id) as Map;
      expect(porId(ana['id'])['conjugeId'], carlos['id']);
      expect(porId(carlos['id'])['conjugeId'], ana['id']);
      expect(porId(bruno['id']).containsKey('conjugeId'), isFalse);
    });

    test('visitante rápido guarda como conheceu e a autorização (LGPD)', () async {
      final v = await criar({
        'nome': 'Rita', 'dia': 7, 'mes': 8, 'status': 'visitante',
        'comoConheceu': 'Convite de amigo', 'consentimentoEm': '2026-10-26',
      });
      expect(v['comoConheceu'], 'Convite de amigo');
      expect(v['consentimentoEm'], '2026-10-26');
      expect((await chamar('POST', '/api/membros', json: {'nome': 'X', 'dia': 1, 'mes': 1, 'consentimentoEm': '31/02/2026'})).$1, 400);
    });

    group('LGPD', () {
      Future<String> gerarLink(String id) async {
        final (status, r) = await chamar('POST', '/api/membros/$id/lgpd/link');
        expect(status, 201);
        final url = r['url'] as String;
        expect(url, startsWith('http://192.168.0.10:8080/autorizar#'));
        return url.split('#').last;
      }

      Future<Map> membro(Object? id) async =>
          ((await chamar('GET', '/api/membros')).$2 as List).firstWhere((m) => m['id'] == id) as Map;

      test('link: a pessoa vê os dados mascarados, autoriza uma vez e fica a prova', () async {
        final ana = await criar({
          'nome': 'Ana Souza', 'dia': 5, 'mes': 3, 'ano': 1990, 'telefone': '(11) 98888-7777',
          'email': 'ana@exemplo.com', 'cpf': '11144477735',
        });
        final token = await gerarLink(ana['id'] as String);
        // O painel não recebe o hash do link, só até quando ele vale.
        final noPainel = await membro(ana['id']);
        expect(noPainel.containsKey('conviteLgpd'), isFalse);
        expect(noPainel['linkLgpdValidoAte'], isNotNull);

        final (s1, info) = await chamar('POST', '/api/public/autorizacao', json: {'token': token}, login: false);
        expect(s1, 200);
        expect(info['nome'], 'Ana Souza');
        expect(info['menor'], isFalse);
        expect(info['termo']['versao'], 1);
        final dados = {for (final d in info['dados'] as List) d['rotulo']: d['valor']};
        expect(dados['Telefone'], 'terminado em 7777');
        expect(dados['E-mail'], 'a•••@exemplo.com');
        expect(dados['CPF'], 'cadastrado'); // nunca os números
        expect(jsonEncode(info), isNot(contains('11144477735')));

        expect((await chamar('POST', '/api/public/autorizacao/aceitar', json: {'token': token}, login: false)).$1, 400);
        final (s2, _) =
            await chamar('POST', '/api/public/autorizacao/aceitar', json: {'token': token, 'autorizo': true}, login: false);
        expect(s2, 200);
        final depois = await membro(ana['id']);
        expect(depois['consentimentoVia'], 'link');
        expect(depois['consentimentoEm'], isNotNull);
        expect(depois['consentimentoRegistro']['versaoTermo'], 1);
        expect(depois['consentimentoRegistro']['em'], isNotNull);
        expect(depois.containsKey('linkLgpdValidoAte'), isFalse);

        // Uso único; e a secretaria não consegue "editar" uma autorização dada pela pessoa.
        expect((await chamar('POST', '/api/public/autorizacao', json: {'token': token}, login: false)).$1, 410);
        expect((await chamar('PUT', '/api/membros/${ana['id']}', json: {'consentimentoEm': null})).$1, 400);
        // Outras edições continuam funcionando sem mexer na prova.
        expect((await chamar('PUT', '/api/membros/${ana['id']}', json: {'funcao': 'Líder'})).$1, 200);
        expect((await membro(ana['id']))['consentimentoVia'], 'link');
      });

      test('link: menor precisa do responsável; link vencido ou trocado não vale', () async {
        final bia = await criar({'nome': 'Bia', 'dia': 1, 'mes': 1, 'ano': DateTime.now().year - 10});
        final antigo = await gerarLink(bia['id'] as String);
        final token = await gerarLink(bia['id'] as String); // o novo invalida o antigo
        expect((await chamar('POST', '/api/public/autorizacao', json: {'token': antigo}, login: false)).$1, 410);
        expect((await chamar('POST', '/api/public/autorizacao', json: {'token': token}, login: false)).$2['menor'], isTrue);
        expect((await chamar('POST', '/api/public/autorizacao/aceitar',
                json: {'token': token, 'autorizo': true}, login: false)).$1, 400);
        expect((await chamar('POST', '/api/public/autorizacao/aceitar',
                json: {'token': token, 'autorizo': true, 'responsavel': 'Carla Mãe'}, login: false)).$1, 200);
        expect((await membro(bia['id']))['consentimentoRegistro']['responsavel'], 'Carla Mãe');

        // Vencido: 410.
        final caio = await criar({'nome': 'Caio', 'dia': 2, 'mes': 2});
        final t2 = await gerarLink(caio['id'] as String);
        final doc = store.buscar('membros', caio['id'] as String)!;
        await store.salvar('membros', {
          ...doc,
          'conviteLgpd': {...doc['conviteLgpd'] as Map, 'expiraEm': DateTime.now().subtract(const Duration(days: 1)).toIso8601String()},
        });
        expect((await chamar('POST', '/api/public/autorizacao', json: {'token': t2}, login: false)).$1, 410);
        expect((await chamar('POST', '/api/public/autorizacao', json: {'token': 'x' * 43}, login: false)).$1, 410);
      });

      test('termo assinado: anexa, serve só com login, revogar apaga o arquivo', () async {
        final ana = await criar({'nome': 'Ana', 'dia': 5, 'mes': 3});
        final id = ana['id'] as String;
        expect((await chamar('POST', '/api/membros/$id/lgpd/termo', bytes: utf8.encode('não é termo'))).$1, 400);
        final pdf = utf8.encode('%PDF-1.4\n%termo de teste\n');
        final (s, r) = await chamar('POST', '/api/membros/$id/lgpd/termo?data=2026-10-20&responsavel=', bytes: pdf);
        expect(s, 201);
        expect(r['consentimentoVia'], 'termo');
        expect(r['consentimentoEm'], '2026-10-20');
        expect(r['consentimentoRegistro']['dataAssinatura'], '2026-10-20');
        final arquivo = r['termoAssinado'] as String;
        expect(File(p.join(pastaDados, 'termos-lgpd', arquivo)).existsSync(), isTrue);

        final (sv, conteudo) = await chamar('GET', '/api/membros/$id/lgpd/termo');
        expect(sv, 200);
        expect(utf8.decode(conteudo as List<int>), startsWith('%PDF-'));
        expect((await chamar('GET', '/api/membros/$id/lgpd/termo', login: false)).$1, 401);

        // Foto do papel também vale (vira JPG sem EXIF).
        final (sf, rf) = await chamar('POST', '/api/membros/$id/lgpd/termo', bytes: foto(800, 1100));
        expect(sf, 201);
        expect(rf['termoAssinado'], endsWith('.jpg'));
        expect(File(p.join(pastaDados, 'termos-lgpd', arquivo)).existsSync(), isFalse); // o anterior saiu

        final (sr, rr) = await chamar('POST', '/api/membros/$id/lgpd/revogar');
        expect(sr, 200);
        expect(rr.containsKey('consentimentoEm'), isFalse);
        expect(rr.containsKey('termoAssinado'), isFalse);
        expect(rr['consentimentoRevogado']['via'], 'termo');
        expect(Directory(p.join(pastaDados, 'termos-lgpd')).listSync(), isEmpty);
        expect((await chamar('POST', '/api/membros/$id/lgpd/revogar')).$1, 400);
      });

      test('manual: data digitada registra quem foi; não aceita data futura', () async {
        final ana = await criar({'nome': 'Ana', 'dia': 5, 'mes': 3, 'consentimentoEm': '2026-01-10'});
        expect(ana['consentimentoVia'], 'manual');
        expect(ana['consentimentoRegistro']['versaoTermo'], 1);
        final futuro = DateTime.now().add(const Duration(days: 30));
        final dataFutura = '${futuro.year}-${futuro.month.toString().padLeft(2, '0')}-${futuro.day.toString().padLeft(2, '0')}';
        expect((await chamar('PUT', '/api/membros/${ana['id']}', json: {'consentimentoEm': dataFutura})).$1, 400);
        final (_, limpo) = await chamar('PUT', '/api/membros/${ana['id']}', json: {'consentimentoEm': null});
        expect(limpo.containsKey('consentimentoVia'), isFalse);
        // Campos de prova não entram pelo corpo.
        final (_, forjado) = await chamar('PUT', '/api/membros/${ana['id']}',
            json: {'consentimentoVia': 'link', 'consentimentoRegistro': {'em': 'x'}, 'termoAssinado': '0123456789abcdef0123.pdf'});
        expect(forjado.containsKey('consentimentoVia'), isFalse);
        expect(forjado.containsKey('termoAssinado'), isFalse);
      });

      test('recepção (QR): a pessoa se cadastra e autoriza; pode ser desligado no /admin', () async {
        final (si, info) = await chamar('GET', '/api/public/visitante', login: false);
        expect(si, 200);
        expect(info['termo']['texto'], contains('Lei Geral de Proteção de Dados'));
        const base = {'nome': 'Rita Alves', 'aniversario': '07/08', 'telefone': '(11) 91234-5678', 'comoConheceu': 'Amigos', 'mencionar': true};
        expect((await chamar('POST', '/api/public/visitante', json: base, login: false)).$1, 400); // sem autorizar
        final (s, _) = await chamar('POST', '/api/public/visitante', json: {...base, 'autorizo': true}, login: false);
        expect(s, 201);
        final rita = ((await chamar('GET', '/api/membros')).$2 as List).firstWhere((m) => m['nome'] == 'Rita Alves') as Map;
        expect(rita['status'], 'visitante');
        expect(rita['whatsapp'], '(11) 91234-5678');
        expect(rita['consentimentoVia'], 'recepcao');
        expect(rita['comoConheceu'], 'Amigos');

        final menor = {'nome': 'Léo', 'aniversario': '01/01/${DateTime.now().year - 12}', 'autorizo': true, 'mencionar': false};
        expect((await chamar('POST', '/api/public/visitante', json: menor, login: false)).$1, 400);
        expect((await chamar('POST', '/api/public/visitante', json: {...menor, 'responsavel': 'Pai do Léo'}, login: false)).$1, 201);

        expect((await chamar('GET', '/qr-visitante.png', login: false)).$1, 200);
        expect((await chamar('PUT', '/api/admin/configuracoes', json: {'visitanteQrAtivo': false})).$1, 200);
        expect((await chamar('POST', '/api/public/visitante', json: {...base, 'autorizo': true}, login: false)).$1, 403);
        expect((await chamar('GET', '/qr-visitante.png', login: false)).$1, 404);
      });

      test('mudar o texto do termo cria uma versão nova', () async {
        final (_, antes) = await chamar('GET', '/api/membros/termo-lgpd');
        expect(antes['versao'], 1);
        await chamar('PUT', '/api/admin/configuracoes', json: {'termoLgpdTexto': antes['texto']}); // igual: não muda
        expect((await chamar('GET', '/api/membros/termo-lgpd')).$2['versao'], 1);
        await chamar('PUT', '/api/admin/configuracoes', json: {'termoLgpdTexto': 'Autorizo o uso dos meus dados.'});
        final (_, depois) = await chamar('GET', '/api/membros/termo-lgpd');
        expect(depois['versao'], 2);
        expect(depois['texto'], 'Autorizo o uso dos meus dados.');
        final ana = await criar({'nome': 'Ana', 'dia': 5, 'mes': 3, 'consentimentoEm': '2026-01-10'});
        expect(ana['consentimentoRegistro']['versaoTermo'], 2);
      });
    });

    test('importar: formato antigo, CSV com cabeçalho e avisos de CPF', () async {
      // Formato antigo continua valendo.
      final (_, r1) =
          await chamar('POST', '/api/membros/importar', bytes: utf8.encode('Ana Souza;05/03\nBruno Lima;10/04\n'));
      expect(r1['importados'], 2);
      expect(r1['linhasComErro'], isEmpty);

      // Mesmas pessoas: não duplica.
      final (_, r2) =
          await chamar('POST', '/api/membros/importar', bytes: utf8.encode('Ana Souza;05/03\n'));
      expect(r2['importados'], 0);

      // CSV completo com cabeçalho.
      const csv = 'Nome;Aniversário;Telefone;E-mail;Status;Ministérios;Data de batismo\n'
          'Carla Lima;15/05/1992;(11) 96666-5555;carla@exemplo.com;congregada;Louvor;14/06/2015\n'
          'Erro;32/13;;;;;;;;\n';
      final (st, r3) = await chamar('POST', '/api/membros/importar', bytes: utf8.encode(csv));
      expect(st, 200);
      expect(r3['importados'], 1);
      expect(r3['linhasComErro'], [3]);
      final lista = (await chamar('GET', '/api/membros')).$2 as List;
      final carla = lista.firstWhere((m) => m['nome'] == 'Carla Lima');
      expect(carla['ano'], 1992);
      expect(carla['status'], 'congregado');
      expect(carla['ministerios'], ['Louvor']);
      expect(carla['dataBatismo'], '2015-06-14');

      // CPF digitado errado: a pessoa entra, o campo não (fica como aviso).
      final (_, r4) = await chamar('POST', '/api/membros/importar',
          bytes: utf8.encode('Nome;Aniversário;CPF\nDuda;20/06;11144477736\n'));
      expect(r4['importados'], 1);
      expect(r4['detalhes'].single, contains('CPF'));
      final duda = ((await chamar('GET', '/api/membros')).$2 as List).firstWhere((m) => m['nome'] == 'Duda');
      expect(duda.containsKey('cpf'), isFalse);
    });

    test('backup leva e restaura os membros com as fotos', () async {
      final m = await criar({'nome': 'Ana', 'dia': 5, 'mes': 3, 'status': 'congregado'});
      await chamar('POST', '/api/membros/${m['id']}/foto', bytes: foto(800, 600));
      await chamar('POST', '/api/membros/${m['id']}/lgpd/termo', bytes: utf8.encode('%PDF-1.4 termo'));
      final (_, zipBytes) = await chamar('GET', '/api/backups/agora/download');
      final zip = ZipDecoder().decodeBytes(zipBytes as List<int>);
      expect(zip.findFile('data/membros.json'), isNotNull);
      final arquivos = [for (final f in zip.files) f.name];
      expect(arquivos.where((n) => n.startsWith('fotos-membros/')).length, 2); // foto + miniatura
      expect(arquivos.where((n) => n.startsWith('termos-lgpd/')).length, 1);

      await chamar('DELETE', '/api/membros/${m['id']}');
      expect(((await chamar('GET', '/api/membros')).$2 as List), isEmpty);
      final (st, r) = await chamar('POST', '/api/backups/restaurar', bytes: zipBytes);
      expect(st, 200, reason: '$r');
      final lista = (await chamar('GET', '/api/membros')).$2 as List;
      expect(lista.single['nome'], 'Ana');
      expect(lista.single['status'], 'congregado');
      expect((await chamar('GET', '/api/membros/${m['id']}/foto')).$1, 200);
      expect((await chamar('GET', '/api/membros/${m['id']}/lgpd/termo')).$1, 200); // o termo voltou junto
      expect(r['termosLgpd'], 1);
    });
  });
}
