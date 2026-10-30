# Modelos de roteiro do Modo Culto (entrega 3, item 1)

Data: 2026-10-30

## Objetivo

A igreja monta no painel a ordem dos momentos do culto, os tempos e momentos livres (apresentação de crianças, batismo, testemunho), em vez do roteiro fixo da entrega 1.

## Decisões

- **Modelo:** nome, lista de momentos (os do sistema, cada um no máximo uma vez, e quantos momentos livres quiser), minutos por momento e os nomes de culto da escala em que vale. Um modelo pode ser o **padrão**, para os cultos sem modelo próprio. Sem nenhum modelo, vale o roteiro do sistema.
- **Momento livre:** título e um slide opcional (primeira linha em negrito); sem slide, tela vazia.
- **Identidade no culto:** cada momento tem uma chave (o nome do tipo, ou `livre-<id>`). A posição salva no tablet guarda a chave e a ordem no modelo; se o momento sair do roteiro, o tablet segue para o próximo na ordem. Progresso salvo pela versão anterior continua valendo (a chave é o nome do tipo).
- **Entrega ao tablet:** `GET /api/escalas/hoje` leva o modelo de cada culto (`roteiro`) e o padrão (`roteiroPadrao`); a escala já fica guardada no tablet, então o modelo também funciona sem internet.
- **Permissões:** ver com `escalasVer` (inclui o tablet do telão); criar, alterar e excluir com `escalaPastoral`. Um culto não pode estar em dois modelos; só um padrão por vez.

## Feito

- `diako_core`: `ItemRoteiro`, `ModeloRoteiro` (com validação), `modeloDoCulto`, `roteiroPadrao`, tipo `livre`, `Momento.chave/ordem/titulo/minutos`, `PosicaoRoteiro` por chave. Testes.
- Servidor: coleção `roteiros` (entra no backup), rotas `/api/roteiros`, modelo junto com a escala do dia. Testes.
- Painel: página **Roteiros** em "Cultos" (mover, remover, adicionar, minutos, momento livre). Conferida no navegador.
- App: o Modo Culto segue o modelo; títulos e minutos do modelo na trilha e no cabeçalho. Teste em tela inteira com um momento livre.
