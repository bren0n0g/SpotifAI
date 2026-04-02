# Spotifai Blueprint

## 1. Overview
O **Spotifai** foi construído a seguir rigorosamente a *Constituição do Agente* baseada no ecossistema Apple/iOS (Premium Apple-Style UI Kit). A arquitetura é modular, consumindo obrigatoriamente lógicas visuais e tokens do pacote local `premium_ui_kit`.

## 2. Project Architecture and Design Baseline (Current Version)
- **Core:** Flutter 3.11+, integrando `provider` para Theming.
- **UI Kit:** Efeitos Translúcidos (*Glassmorphism*), sombras discretas e `BorderRadius` entre 16 e 24, abandonando Material UI Widgets básicos em favor do `premium_ui_kit` e ícones `cupertino_icons`.
- **Theme:** Transição orgânica entre Tema Escuro e Claro através do `ThemeToggleBtn` com `ChangeNotifierProvider` sem o uso de cores chumbadas (*hardcoded*).

## 3. Current Requested Change: Home Page
**Planejamento & Execução:**
1. Injetar suporte a pasta `assets/images` no `pubspec.yaml` e adicionar dependência relativa: `premium_ui_kit: path: ../premium_ui_kit` junto com o `provider`.
2. Incluir um Logo Spotify P&B (`logo_bw.png`) no topo da tela.
3. Criar uma `HomePage` (via `lib/presentation/home/home_page.dart`):
   - Scaffold transparente baseando-se no tema.
   - Ícone de menu no topo esquerdo (`CupertinoIcons.bars`) conectando a um **Drawer** (Menu Lateral Premium).
   - `ThemeToggleBtn` no topo direito para alternar Dark Mode.
   - Título Centralizado: **SPOTIFAI**.
   - Caixa de Busca Estilizada: **`AppleTranslucentSearchBar`**.
4. Modificar o arquivo `main.dart` para envolver o `MaterialApp` com o themer do provider e usar o `AppTheme`.
