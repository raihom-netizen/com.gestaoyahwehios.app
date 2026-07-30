---
kind: frontend_style
name: Flutter Design System — Clean Premium Theme & YahwehDesignSystem
category: frontend_style
scope:
    - '**'
source_files:
    - flutter_app/lib/core/yahweh_design_system.dart
    - flutter_app/lib/ui/theme_clean_premium.dart
    - flutter_app/lib/core/design_system/app_theme.dart
    - flutter_app/lib/app_theme.dart
    - flutter_app/pubspec.yaml
---

The app uses a centralized Flutter design system built on Material 3 with a custom "Clean Premium" visual identity. The styling is organized in three layers:

**1. Single source of truth — `YahwehDesignSystem` (`lib/core/yahweh_design_system.dart`)**
- Defines all brand tokens: colors (brandPrimary `#0052CC`, brandGold, surface, error, success), radii (10/16/20/24/28), shadows (soft UI card shadow), and gradients (panelBodyGradient, publicPageGradient).
- Provides two text themes via Google Fonts: Inter (default for panels) and Poppins (for branding/headings). PDFs use Noto Sans.
- Dark mode tokens are defined alongside light ones (surfaceDark, onSurfaceDark, etc.).

**2. Theme factory — `ThemeCleanPremium` (`lib/ui/theme_clean_premium.dart`)**
- Consumes `YahwehDesignSystem` tokens to build complete `ThemeData` instances for light/dark modes.
- Configures Material 3: ColorScheme.fromSeed(seedColor: primary), AppBarTheme (gradient background, white foreground), CardTheme (flat with subtle border + soft shadow), InputDecorationTheme (filled inputs, rounded borders), button themes (elevated/filled/outlined/text).
- Exposes spacing constants (spaceXs=6 through spaceXxl=48) and radius constants.
- Provides haptic feedback helper and successSnackBar utility.

**3. Unified entry point — `AppTheme` (`lib/core/design_system/app_theme.dart`)**
- Re-exports `ThemeCleanPremium.themeData` and `themeDataDark` as `AppTheme.light` / `AppTheme.dark`.
- Groups related tokens into `AppColors`, `AppSpacing`, `AppRadius` static classes for convenient access.
- Provides `AppComponentStyles` with reusable widget styles: card BoxDecoration, appBarGradient, primaryFilled/secondaryOutlined ButtonStyle, dialogShape, errorSnack/successSnack helpers.

**4. Layout constraints — `AppTheme` (`lib/app_theme.dart`)**
- Desktop content width cap: `maxContentWidthDesktop = 1200px`.
- Social feed width cap: `maxSocialFeedWeb = 520px`.
- 8pt spacing grid: space8, space16, space24, space32.
- Sidebar breakpoint: `desktopSidebarBreakpoint = 900px`.
- SaaS card radius: `cardRadiusSaaS = 20`.
- `SaaSContentViewport` widget centralizes content with max-width constraints and viewport-height binding.

**Typography:**
- Primary font: Inter (via `google_fonts` package).
- Secondary font: Poppins for headings/branding.
- PDF fonts: Noto Sans (regular, bold, italic, boldItalic).
- Custom fonts embedded in assets: Roboto, GreatVibes, UnifrakturMaguntia, CinzelDecorative, PinyonScript, LibreBaskerville.

**Responsive strategy:**
- Mobile-first with breakpoints at 900px (sidebar vs drawer).
- Web-specific content width caps prevent stretched layouts on large screens.
- Platform-specific system chrome configuration (edge-to-edge on Android, transparent status bar).

**No CSS/SCSS/Tailwind** — styling is entirely Dart/Flutter with Material 3 theming.