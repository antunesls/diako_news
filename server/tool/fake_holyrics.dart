import 'dart:convert';
import 'dart:io';

/// Holyrics simulado para testes sem o programa real.
/// Uso: dart run tool/fake_holyrics.dart [porta] [token]
/// Mostra no console cada ação recebida e responde como a API Server do Holyrics.
Future<void> main(List<String> args) async {
  final porta = args.isNotEmpty ? int.parse(args[0]) : 8091;
  final token = args.length > 1 ? args[1] : 'teste';
  Map<String, dynamic>? atual;

  final servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, porta);
  stdout.writeln('Holyrics simulado em http://127.0.0.1:$porta (token "$token")');

  await for (final req in servidor) {
    final corpo = await utf8.decodeStream(req);
    final acao = req.uri.pathSegments.length == 2 && req.uri.pathSegments[0] == 'api' ? req.uri.pathSegments[1] : '';
    Object? dados;
    var resposta = <String, dynamic>{'status': 'ok'};

    if (req.uri.queryParameters['token'] != token) {
      resposta = {'status': 'error', 'error': 'invalid token'};
    } else {
      stdout.writeln('[${DateTime.now().toIso8601String().substring(11, 19)}] $acao $corpo');
      final j = corpo.isEmpty ? <String, dynamic>{} : jsonDecode(corpo) as Map<String, dynamic>;
      switch (acao) {
        case 'ShowQuickPresentation':
          final slides = (j['slides'] as List?)?.length ?? 1;
          atual = {'id': 'teste-local', 'type': 'quick_presentation', 'name': 'Apresentação rápida', 'slide_number': 1, 'total_slides': slides};
        case 'ShowImage':
          atual = {'type': 'image', 'name': j['file'], 'slide_number': 1, 'total_slides': 1};
        case 'ActionNext' || 'ActionNextQuickPresentation':
          if (atual case {'slide_number': final int n, 'total_slides': final int t}) atual['slide_number'] = n % t + 1;
        case 'ActionPrevious' || 'ActionPreviousQuickPresentation':
          if (atual case {'slide_number': final int n, 'total_slides': final int t}) atual['slide_number'] = (n + t - 2) % t + 1;
        case 'CloseCurrentPresentation':
          atual = null;
        case 'GetCurrentPresentation':
          dados = atual;
        case 'GetThemes':
          dados = [
            {'id': '1', 'name': 'Padrão'},
            {'id': '2', 'name': 'Avisos'},
          ];
        case 'GetThumbnail':
          dados = [for (final id in (j['ids'] as List? ?? [])) {'type': 'theme', 'id': id, 'image': 'iVBORw0KGgo='}];
      }
      if (dados != null || acao == 'GetCurrentPresentation') resposta['data'] = dados;
    }
    req.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(resposta));
    await req.response.close();
  }
}
