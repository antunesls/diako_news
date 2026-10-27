/// Mensagem privada enviada pela caixa de dúvidas, sugestões e críticas.
class Mensagem {
  const Mensagem(
      {required this.id,
      required this.tipo,
      required this.texto,
      required this.criadoEm,
      this.nome = '',
      this.contato = '',
       this.status = 'nova',
       this.observacao = '',
      this.avisoEmail = 'pendente'});

  final String id;
  final String tipo;
  final String texto;
  final String nome;
  final String contato;
  final String status;
  final String avisoEmail;
  /// Nota interna; não é enviada ao remetente nem por e-mail.
  final String observacao;
  final DateTime criadoEm;

  static const tipos = {'duvida', 'sugestao', 'critica'};
  static const statusValidos = {'nova', 'emAnalise', 'resolvida'};

  factory Mensagem.fromJson(Map<String, dynamic> j) => Mensagem(
        id: j['id'] as String,
        tipo: j['tipo'] as String,
        texto: j['texto'] as String,
        nome: j['nome'] as String? ?? '',
        contato: j['contato'] as String? ?? '',
        status: j['status'] as String? ?? 'nova',
        observacao: j['observacao'] as String? ?? '',
        avisoEmail: j['avisoEmail'] as String? ?? 'pendente',
        criadoEm: DateTime.parse(j['criadoEm'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tipo': tipo,
        'texto': texto,
        'nome': nome,
        'contato': contato,
        'status': status,
        'avisoEmail': avisoEmail,
        'observacao': observacao,
        'criadoEm': criadoEm.toIso8601String(),
      };
}
