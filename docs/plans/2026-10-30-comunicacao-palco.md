# Comunicação com o palco: frases prontas e TV só com texto

Data: 2026-10-30

## Objetivo

Melhorar o envio de mensagens ao painel de comunicação do Holyrics (TV do palco):

1. O app do tablet oferece **frases prontas** para enviar com um toque, além do texto livre que já existe.
2. A **TV de comunicação mostra apenas o texto**: fundo transparente, fonte branca em negrito, alinhada ao centro, com sombra leve — sem tema, imagem ou moldura.

## Decisões

- As frases ficam **no tablet** (`AppSettings`/SharedPreferences), editáveis em Configurações › Mensagens do palco. Não dependem de internet e não exigem mudança no servidor.
- Frases padrão iniciais:
  - O culto começa em 5 min
  - O culto começa em 2 min
  - Pastor, pode se dirigir ao palco
  - Favor encerrar a ministração
  - Silêncio, por favor
  - Momento de oração
  - Atenção: microfone com problema
- Tocar numa frase **envia na hora** (sem passo extra); o campo de texto livre e o botão **Ocultar** continuam.
- O visual "só texto" é garantido enviando `custom_theme` no `SetTextCP`:

```json
{
  "text": "…",
  "show": true,
  "display_ahead": true,
  "custom_theme": {
    "background": { "type": "transparent", "id": "transparent" },
    "font": { "bold": true, "size": 14, "color": "FFFFFF" },
    "align": { "horizontal": "center", "vertical": "middle" },
    "effect": { "shadow_color": "000000", "shadow_x_weight": 20, "shadow_y_weight": 20 }
  }
}
```

- Holyrics anterior à v2.21 ignora `custom_theme` e mantém o visual atual; nada quebra. O tema padrão do Holyrics não é alterado.

## Onde mexe

| Arquivo | Mudança |
|---|---|
| `lib/data/settings.dart` | Lista `frasesPalco`, padrões e gravação |
| `lib/ui/frases_palco.dart` | Widget dos botões de frase (testável sem AppScope) |
| `lib/ui/tools_sheet.dart` | Mostra as frases acima do campo de texto |
| `lib/ui/settings_page.dart` | Seção "Mensagens do palco": adicionar, editar, remover, restaurar padrões |
| `lib/holyrics/holyrics_client.dart` | `mensagemPalco` envia `custom_theme` transparente |

## Fora de escopo

- Sincronizar as frases entre tablets ou pelo servidor.
- Alterar as configurações globais do painel no Holyrics (`SetCPSettings`).
- Reordenar frases por arrastar.

## Verificação

- Testes (escritos antes da implementação):
  - corpo enviado ao Holyrics com `custom_theme` transparente e texto;
  - frases padrão e persistência em `AppSettings`;
  - widget das frases envia o texto tocado;
  - restauração dos padrões.
- `flutter test` e `flutter analyze` completos.
