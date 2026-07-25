---
kind: frontend_style
name: Flutter Design System — Yahweh Clean Premium Theme
category: frontend_style
scope:
    - '**'
source_files:
    - flutter_app/lib/core/yahweh_design_system.dart
    - flutter_app/lib/ui/theme_clean_premium.dart
    - flutter_app/lib/core/design_system/app_theme.dart
    - flutter_app/lib/app_theme.dart
    - flutter_app/lib/main.dart
    - flutter_app/pubspec.yaml
---

The frontend styling of the Gestão YAHWEH Flutter app is built around a centralized design system called **YahwehDesignSystem**, consumed by a premium theme layer (**ThemeCleanPremium**) and exposed through a unified entry point (**AppTheme**). There is no CSS/SCSS/Tailwind; all visual consistency is enforced via Flutter Material 3 theming, Google Fonts typography, and shared token constants.

### What system/approach is used
- **Flutter Material 3** (`useMaterial3: true`) with `ColorScheme.fromSeed` derived from a single brand primary color.
- **Google Fonts** (Inter as default, Poppins as alternative) applied via `google_fonts` package to every text style in the theme.
- A three-layer architecture:
  1. **Tokens** — `YahwehDesignSystem` defines colors, radii, shadows, gradients, and text themes (single source of truth).
  2. **Theme builder** — `ThemeCleanPremium` constructs full `ThemeData` light/dark variants, input decoration, buttons, cards, snackbars, drawers, tabs, etc., consuming only tokens.
  3. **Public API** — `AppTheme` re-exports `ThemeCleanPremium.themeData` / `themeDataDark` plus convenience aliases (`AppColors`, `AppSpacing`, `AppRadius`, `AppComponentStyles`).
- Layout constraints are centralized in `app_theme.dart` (`AppTheme` class): 8pt spacing grid, max content width 1200px on desktop, social feed width 520px, sidebar breakpoint at 900px, card radius 20px.
- Responsive strategy uses fixed breakpoints (`breakpointMobile = 600`, `breakpointTablet = 900`, `breakpointDesktop = 1200`) and helper methods like `isMobile()`, `isNarrow()`, `pagePadding()`.

### Key files and packages
- `flutter_app/lib/core/yahweh_design_system.dart` — token definitions (colors, radii, shadows, gradients, Inter/Poppins text themes).
- `flutter_app/lib/ui/theme_clean_premium.dart` — `ThemeData` builders for light/dark, widget-specific themes (cards, inputs, buttons, snackbars, dialogs, drawers, tabs, chips, dividers).
- `flutter_app/lib/core/design_system/app_theme.dart` — public facade (`AppTheme.light`/`dark`, `AppColors`, `AppSpacing`, `AppRadius`, `AppComponentStyles`).
- `flutter_app/lib/app_theme.dart` — layout tokens (`maxContentWidthDesktop`, `space*` constants) and `SaaSContentViewport` widget that constrains content width and height per viewport.
- `flutter_app/lib/main.dart` — root `MaterialApp(theme: AppTheme.light, ...)` wiring.
- `flutter_app/pubspec.yaml` — declares `google_fonts`, `shimmer`, `skeletonizer`, `flutter_staggered_animations`, `lottie` for UI polish.

### Architecture and conventions
- **Single source of truth**: All colors, radii, and shadows come from `YahwehDesignSystem`; components must never hardcode hex values.
- **Consistent spacing**: 8pt grid (`spaceXs=6`, `spaceSm=12`, `spaceMd=18`, `spaceLg=24`, `spaceXl=32`, `spaceXxl=48`) enforced through `AppSpacing`.
- **Component styles**: Reusable `BoxDecoration` for cards, `ButtonStyle` for primary/secondary buttons, `SnackBar` factories for error/success messages — prevents duplication across modules.
- **Soft UI aesthetic**: Cards use `softCardShadow` (blur 30, offset 0,10), border `0xFFE8EEF4`, white background, generous padding, rounded corners (radiusMd=16, radiusLg=20).
- **Brand palette**: Primary blue `#0052CC` with lighter variants, gold accent `#FFFFE082`, dark navy sidebar `#0A3D91`, surface `#F4F5F7`, onSurface `#1A1A2E`.
- **Dark mode parity**: Full `themeDataDark` mirrors light theme with inverted surfaces, adjusted contrast, and matching component shapes.
- **Responsive wrappers**: `SaaSContentViewport` caps width and binds height to available viewport; `pagePadding()` adapts margins per screen size.

### Conventions and constraints
- New screens must import only `core/design_system/app_theme.dart` (legacy `ThemeCleanPremium`/`YahwehDesignSystem` imports remain valid but discouraged).
- All `ThemeData` usage goes through `AppTheme.light` / `AppTheme.dark` — direct `ThemeData` construction is not observed outside the theme file.
- Hardcoded colors/radii/paddings are avoided; tokens from `YahwehDesignSystem` and `ThemeCleanPremium` are used everywhere.
- Touch targets minimum 48px (`minTouchTarget`) enforced via button/input themes.
- Card borders consistently use `Border.all(color: Color(0xFFE8EEF4), width: 1)` with `radiusLg` (20px) for SaaS cards.
- SnackBars use floating behavior with success green background and rounded corners; error feedback uses a dedicated factory returning red background.