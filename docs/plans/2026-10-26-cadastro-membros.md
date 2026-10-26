# Cadastro de Membros Implementation Plan

**Objetivo:** transformar a lista de aniversariantes (nome + dia/mês) num cadastro completo de pessoas da igreja, usado pela secretaria no painel web, mantendo o app do tablet, o mural e o recado automático de aniversariantes funcionando sem mudança.

**Arquitetura:** o modelo `Membro` do `diako_core` cresce com campos opcionais e um enum `StatusMembro` (visitante, congregado, membro, inativo, transferido) — o JSON antigo continua válido (status derivado do `ativo` de então). Coleção `membros` e permissão de mesmo nome ficam como estão (admin, pastor e secretaria). Fotos processadas como na galeria (EXIF removido), porém em `data/fotos-membros/` e servidas **atrás de login**; o backup passa a levar a pasta. Vínculos familiares: `conjugeId` recíproco mantido pelo servidor e `paisIds` no filho (filhos derivados por consulta). Exportação CSV gerada pelo servidor com BOM; PDF via impressão do navegador.

**Stack:** Dart/Shelf, diako_core, HTML/JS do painel, `package:test`.

## Mapa de contexto

| Área | Arquivos de alteração | Referência/teste |
|---|---|---|
| Modelo | `packages/diako_core/lib/src/membro.dart` | `packages/diako_core/test/core_test.dart` |
| API | `server/lib/app.dart` (rotas `/api/membros…`), `server/lib/permissoes.dart` (descrição) | `server/test/membros_test.dart`, `server/test/admin_test.dart`, `server/test/usuarios_test.dart` |
| Fotos | `server/lib/fotos_membros.dart` (novo), `server/lib/galeria.dart` (`processarFoto` com larguras), `server/lib/backup.dart` | `server/test/membros_test.dart` |
| Painel | `server/web/painel.html`, `server/web/painel.js`, `server/web/comum.js` (`urlAutenticada`) | `node --check` |
| Docs | `README.md`, `server/LEIA-ME.md` | — |

**Decisões:** só no painel web (decisão do usuário); campos de contato, eclesiásticos, família, documentos e emergência; foto com upload; busca/filtros, exportar CSV, importar CSV ampliado (cabeçalho aceito), estatísticas; PDF por impressão; vínculos entre membros (sem cadastro de família separado).

## Tarefas

1. **Modelo ampliado.** Enum `StatusMembro` (+ aceitar forma feminina no `porNome`), `Membro` com campos opcionais, `ativo` derivado, histórico de mudanças de status, validação de CPF (dígito verificador) e datas `dd/mm/aaaa` → `aaaa-mm-dd`. `lerCsvMembros` aceita cabeçalho (`Nome;Aniversário;Telefone;…`) e o formato antigo; retorna erros com motivo.
2. **API.** CRUD estendido com validações (CPF, e-mail, status, datas, vínculos existem e não apontam para a própria pessoa), histórico de status e limpeza de vínculos na exclusão; `POST/DELETE/GET /api/membros/<id>/foto` (e `/foto-miniatura`); `GET /api/membros/exportar` com filtros por query; importação com avisos (CPF inválido entra sem o campo, sem perder a pessoa).
3. **Fotos.** `FotosMembros` (data/fotos-membros, 1280 px, miniatura 320 px, EXIF removido); backup inclui a pasta e a restauração devolve os arquivos.
4. **Painel.** Aba *Membros* com indicadores, busca, filtros (status, ministério, aniversariantes do mês), cards com miniatura (blob autenticado), ficha completa com links de família, dialog de edição com todas as seções e upload de foto, importação com modelo e relatório, exportar CSV e impressão (`@media print`).
5. **Documentação e verificação.** LEIA-ME do servidor, README, bump de `?v=` dos assets; `dart test` no servidor e no `diako_core`, `dart analyze`, `node --check` nos JS.
