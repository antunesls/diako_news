/// Perfis de acesso e o que cada um pode fazer. Esta matriz é a única fonte de verdade:
/// o servidor confere cada rota por ela e o painel/app escondem o que o perfil não permite.
library;

enum Permissao {
  /// Estar logado (logout, "eu", WebSocket).
  sessao('Entrar no painel'),
  painel('Início, Status e Histórico'),
  motivosVer('Ver pedidos de oração públicos'),
  motivosParticulares('Ver pedidos particulares e o nome de quem pediu'),
  motivosEditar('Aprovar, editar e marcar pedidos como atendidos'),
  mensagens('Caixa de mensagens'),
  recados('Recados'),
  agendaVer('Ver a agenda'),
  agendaEditar('Criar e editar eventos da agenda'),
  cartazes('Cartazes'),
  galeria('Galeria do site'),
  membros('Cadastro de membros'),
  resumo('Resumo da semana'),
  projetar('Projetar no telão'),
  admin('Administração'),
  usuarios('Usuários e perfis');

  const Permissao(this.descricao);
  final String descricao;

  static Permissao? porNome(String nome) => values.where((p) => p.name == nome).firstOrNull;
}

const _base = {Permissao.sessao, Permissao.painel, Permissao.motivosVer, Permissao.recados, Permissao.agendaVer, Permissao.cartazes};

enum Perfil {
  administrador('Administrador', 'Tudo, inclusive configurações, backup e usuários.', {
    ..._base, Permissao.motivosParticulares, Permissao.motivosEditar, Permissao.mensagens, Permissao.agendaEditar,
    Permissao.galeria, Permissao.membros, Permissao.resumo, Permissao.projetar, Permissao.admin, Permissao.usuarios,
  }),
  pastor('Pastor', 'Todo o conteúdo, inclusive pedidos particulares. Sem configurações técnicas.', {
    ..._base, Permissao.motivosParticulares, Permissao.motivosEditar, Permissao.mensagens, Permissao.agendaEditar,
    Permissao.galeria, Permissao.membros, Permissao.resumo, Permissao.projetar,
  }),
  secretaria('Secretaria', 'Recados, agenda, mensagens, aniversariantes e pedidos públicos.', {
    ..._base, Permissao.motivosEditar, Permissao.mensagens, Permissao.agendaEditar, Permissao.membros, Permissao.resumo,
  }),
  midia('Mídia', 'Cartazes, galeria do site, recados e projeção no telão.', {
    ..._base, Permissao.galeria, Permissao.projetar,
  }),
  telao('Telão (tablet)', 'Operar o telão no culto: recados, pedidos públicos e projeção.', {
    ..._base, Permissao.projetar,
  });

  const Perfil(this.nome, this.descricao, this.permissoes);
  final String nome;
  final String descricao;
  final Set<Permissao> permissoes;

  bool pode(Permissao p) => permissoes.contains(p);

  static Perfil? porNome(String nome) => values.where((p) => p.name == nome).firstOrNull;

  Map<String, dynamic> toJson() =>
      {'id': name, 'nome': nome, 'descricao': descricao, 'permissoes': [for (final p in permissoes) p.name]};
}

/// Permissão exigida por uma rota da API (caminho sem a barra inicial, ex.: "api/motivos/abc").
/// Rota não listada exige [Permissao.admin]: o padrão é negar.
Permissao permissaoDaRota(String metodo, String caminho) {
  final leitura = metodo == 'GET' || metodo == 'HEAD';
  bool comeca(String prefixo) => caminho == prefixo || caminho.startsWith('$prefixo/');

  if (caminho == 'ws' || caminho == 'api/logout' || comeca('api/eu')) return Permissao.sessao;
  if (caminho == 'api/estado' || caminho == 'api/historico') return Permissao.painel;
  if (comeca('api/motivos')) return leitura ? Permissao.motivosVer : Permissao.motivosEditar;
  if (comeca('api/mensagens')) return Permissao.mensagens;
  if (comeca('api/recados')) return Permissao.recados;
  if (comeca('api/agenda/eventos')) return Permissao.agendaEditar;
  if (caminho == 'api/agenda') return Permissao.agendaVer;
  if (comeca('api/cartazes')) return Permissao.cartazes;
  if (comeca('api/galeria')) return Permissao.galeria;
  if (comeca('api/membros')) return Permissao.membros;
  if (caminho == 'api/resumo-semanal') return Permissao.resumo;
  if (comeca('api/holyrics') || comeca('api/projetar')) return Permissao.projetar;
  if (comeca('api/admin/usuarios')) return Permissao.usuarios;
  return Permissao.admin; // api/admin/*, api/backup(s) e qualquer rota nova não listada
}
