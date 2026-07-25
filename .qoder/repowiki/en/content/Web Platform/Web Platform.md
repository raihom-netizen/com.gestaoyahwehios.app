# Web Platform

<cite>
**Referenced Files in This Document**
- [flutter_app/web/index.html](file://flutter_app/web/index.html)
- [flutter_app/web/manifest.json](file://flutter_app/web/manifest.json)
- [flutter_app/web/flutter_bootstrap.js](file://flutter_app/web/flutter_bootstrap.js)
- [flutter_app/web/firebase-messaging-sw.js](file://flutter_app/web/firebase-messaging-sw.js)
- [flutter_app/lib/url_strategy_web.dart](file://flutter_app/lib/url_strategy_web.dart)
- [flutter_app/lib/url_strategy_stub.dart](file://flutter_app/lib/url_strategy_stub.dart)
- [flutter_app/lib/web_resume_repaint_web.dart](file://flutter_app/lib/web_resume_repaint_web.dart)
- [flutter_app/lib/web_resume_repaint_stub.dart](file://flutter_app/lib/web_resume_repaint_stub.dart)
- [flutter_app/public/index.html](file://flutter_app/public/index.html)
- [flutter_app/public/404.html](file://flutter_app/public/404.html)
- [flutter_app/public/reset_password.html](file://flutter_app/public/reset_password.html)
- [flutter_app/web/version.json](file://flutter_app/web/version.json)
- [flutter_app/web/assetlinks.json](file://flutter_app/web/assetlinks.json)
- [firebase.json](file://firebase.json)
- [storage_cors.json](file://storage_cors.json)
- [scripts/deploy_web_hosting_html.ps1](file://scripts/deploy_web_hosting_html.ps1)
- [scripts/deploy_web_hosting_canvaskit.ps1](file://scripts/deploy_web_hosting_canvaskit.ps1)
- [scripts/deploy_web_hosting_skwasm.ps1](file://scripts/deploy_web_hosting_skwasm.ps1)
- [scripts/build_e_deploy_web.ps1](file://scripts/build_e_deploy_web.ps1)
- [.github/workflows/deploy-web.yml](file://.github/workflows/deploy-web.yml)
</cite>

## Table of Contents
1. [Introduction](#introduction)
2. [Project Structure](#project-structure)
3. [Core Components](#core-components)
4. [Architecture Overview](#architecture-overview)
5. [Detailed Component Analysis](#detailed-component-analysis)
6. [Dependency Analysis](#dependency-analysis)
7. [Performance Considerations](#performance-considerations)
8. [Troubleshooting Guide](#troubleshooting-guide)
9. [Conclusion](#conclusion)
10. [Appendices](#appendices)

## Introduction
This document provides comprehensive web platform documentation for the web version of Gestão Yahweh Premium. It covers Progressive Web App (PWA) implementation, browser compatibility, performance optimization, hosting configuration, URL routing, service workers, offline capabilities, and web-specific features. It also includes deployment guidance for CDN configuration, browser security policies, SEO considerations, analytics integration, debugging techniques, and performance monitoring.

## Project Structure
The Flutter-based web application is built into static assets served via Firebase Hosting. The key web-related files include:
- Entry HTML and PWA manifest under flutter_app/web
- Bootstrap script to initialize Flutter on the web
- Service worker for Firebase Cloud Messaging
- URL strategy configuration for client-side routing
- Version metadata for cache busting and updates
- Public fallback pages for 404 and password reset flows
- Firebase Hosting configuration and storage CORS rules
- Deployment scripts and CI workflow for automated web builds and releases

```mermaid
graph TB
subgraph "Web Build Output"
A["index.html"]
B["flutter_bootstrap.js"]
C["version.json"]
D["assets/*"]
end
subgraph "PWA & Service Worker"
E["manifest.json"]
F["firebase-messaging-sw.js"]
end
subgraph "Hosting Config"
G["firebase.json"]
H["storage_cors.json"]
end
subgraph "Routing & Strategy"
I["url_strategy_web.dart"]
J["web_resume_repaint_web.dart"]
end
A --> B
A --> C
A --> D
A --> E
F --> |FCM messages| A
G --> |Hosting rules| A
H --> |CORS policy| D
I --> |URL routing| A
J --> |Render resume| A
```

**Diagram sources**
- [flutter_app/web/index.html](file://flutter_app/web/index.html)
- [flutter_app/web/flutter_bootstrap.js](file://flutter_app/web/flutter_bootstrap.js)
- [flutter_app/web/manifest.json](file://flutter_app/web/manifest.json)
- [flutter_app/web/firebase-messaging-sw.js](file://flutter_app/web/firebase-messaging-sw.js)
- [flutter_app/lib/url_strategy_web.dart](file://flutter_app/lib/url_strategy_web.dart)
- [flutter_app/lib/web_resume_repaint_web.dart](file://flutter_app/lib/web_resume_repaint_web.dart)
- [firebase.json](file://firebase.json)
- [storage_cors.json](file://storage_cors.json)

**Section sources**
- [flutter_app/web/index.html](file://flutter_app/web/index.html)
- [flutter_app/web/manifest.json](file://flutter_app/web/manifest.json)
- [flutter_app/web/flutter_bootstrap.js](file://flutter_app/web/flutter_bootstrap.js)
- [flutter_app/web/firebase-messaging-sw.js](file://flutter_app/web/firebase-messaging-sw.js)
- [flutter_app/lib/url_strategy_web.dart](file://flutter_app/lib/url_strategy_web.dart)
- [flutter_app/lib/web_resume_repaint_web.dart](file://flutter_app/lib/web_resume_repaint_web.dart)
- [flutter_app/public/index.html](file://flutter_app/public/index.html)
- [flutter_app/public/404.html](file://flutter_app/public/404.html)
- [flutter_app/public/reset_password.html](file://flutter_app/public/reset_password.html)
- [flutter_app/web/version.json](file://flutter_app/web/version.json)
- [flutter_app/web/assetlinks.json](file://flutter_app/web/assetlinks.json)
- [firebase.json](file://firebase.json)
- [storage_cors.json](file://storage_cors.json)

## Core Components
- Web entrypoint and bootstrap: index.html loads the Flutter engine and bootstrap script; version.json enables cache-busting and update detection.
- PWA manifest: manifest.json defines app name, icons, theme colors, display mode, and scope for installability.
- Service worker: firebase-messaging-sw.js integrates with Firebase Cloud Messaging for push notifications on the web.
- URL routing: url_strategy_web.dart configures Flutter’s URL strategy for clean URLs and deep linking on the web.
- Render resume: web_resume_repaint_web.dart optimizes repaint behavior during resume scenarios on browsers.
- Hosting and CORS: firebase.json configures hosting rewrites and SPA handling; storage_cors.json sets permissive or scoped CORS for media access.
- Public fallbacks: public/404.html and public/reset_password.html provide user-friendly error and recovery pages.

**Section sources**
- [flutter_app/web/index.html](file://flutter_app/web/index.html)
- [flutter_app/web/flutter_bootstrap.js](file://flutter_app/web/flutter_bootstrap.js)
- [flutter_app/web/manifest.json](file://flutter_app/web/manifest.json)
- [flutter_app/web/firebase-messaging-sw.js](file://flutter_app/web/firebase-messaging-sw.js)
- [flutter_app/lib/url_strategy_web.dart](file://flutter_app/lib/url_strategy_web.dart)
- [flutter_app/lib/web_resume_repaint_web.dart](file://flutter_app/lib/web_resume_repaint_web.dart)
- [flutter_app/public/404.html](file://flutter_app/public/404.html)
- [flutter_app/public/reset_password.html](file://flutter_app/public/reset_password.html)
- [flutter_app/web/version.json](file://flutter_app/web/version.json)
- [firebase.json](file://firebase.json)
- [storage_cors.json](file://storage_cors.json)

## Architecture Overview
The web architecture follows a standard Flutter web build pipeline:
- Build produces static assets (HTML, JS, WASM/CANVASKIT, fonts, images).
- Firebase Hosting serves the SPA with rewrite rules to ensure client-side routing works.
- PWA manifest enables installation and offline hints.
- Service worker handles FCM push events.
- Storage CORS allows secure media retrieval from Firebase Storage.

```mermaid
sequenceDiagram
participant Browser as "Browser"
participant Hosting as "Firebase Hosting"
participant Assets as "Static Assets"
participant Engine as "Flutter Engine"
participant App as "Gestão Yahweh App"
participant SW as "Service Worker (FCM)"
participant Storage as "Firebase Storage"
Browser->>Hosting : GET /
Hosting-->>Assets : Serve index.html + manifest.json
Browser->>Engine : Load flutter_bootstrap.js
Engine->>App : Initialize Flutter web runtime
App->>Storage : Fetch media (subject to CORS)
SW-->>Browser : Push notification event
Browser->>SW : Handle FCM message
Note over App,SW : Offline-first UI with cached assets<br/>and background sync where applicable
```

**Diagram sources**
- [flutter_app/web/index.html](file://flutter_app/web/index.html)
- [flutter_app/web/flutter_bootstrap.js](file://flutter_app/web/flutter_bootstrap.js)
- [flutter_app/web/manifest.json](file://flutter_app/web/manifest.json)
- [flutter_app/web/firebase-messaging-sw.js](file://flutter_app/web/firebase-messaging-sw.js)
- [firebase.json](file://firebase.json)
- [storage_cors.json](file://storage_cors.json)

## Detailed Component Analysis

### PWA Implementation
- Manifest configuration: Defines app identity, icons, theme color, display mode, and scope to enable installation prompts and home screen shortcuts.
- Installability: Ensure manifest meets PWA criteria and that HTTPS is enforced by hosting.
- Asset caching: Use versioned assets and cache-busting via version.json to avoid stale content.

```mermaid
flowchart TD
Start(["Install Prompt"]) --> CheckManifest["Validate manifest.json"]
CheckManifest --> Valid{"Valid and complete?"}
Valid --> |No| FixManifest["Add required fields<br/>icons, theme_color, display, scope"]
Valid --> |Yes| ShowPrompt["Show install prompt"]
ShowPrompt --> UserAction{"User accepts?"}
UserAction --> |No| End(["End"])
UserAction --> |Yes| Install["Install app"]
Install --> CacheAssets["Cache core assets"]
CacheAssets --> Ready(["Ready for offline use"])
```

**Diagram sources**
- [flutter_app/web/manifest.json](file://flutter_app/web/manifest.json)
- [flutter_app/web/version.json](file://flutter_app/web/version.json)

**Section sources**
- [flutter_app/web/manifest.json](file://flutter_app/web/manifest.json)
- [flutter_app/web/version.json](file://flutter_app/web/version.json)

### Browser Compatibility
- CanvasKit vs SkiaWasm: Choose rendering backend based on target browsers; CanvasKit offers broader GPU acceleration, while SkiaWasm may reduce payload size.
- Feature detection: Use modern APIs cautiously; provide fallbacks for older browsers.
- Security policies: Enforce HTTPS, set Content-Security-Policy headers, and configure permissions for push notifications.

**Section sources**
- [flutter_app/web/flutter_bootstrap.js](file://flutter_app/web/flutter_bootstrap.js)
- [flutter_app/web/index.html](file://flutter_app/web/index.html)

### Performance Optimization
- Asset minification and tree-shaking: Enabled by Flutter web build; ensure unused code is excluded.
- Image optimization: Use appropriate formats (WebP/AVIF), lazy loading, and responsive sizing.
- Network efficiency: Leverage CDN caching, HTTP/2, and efficient API calls.
- Rendering performance: Optimize repaint regions; use web_resume_repaint_web.dart strategies to minimize unnecessary redraws.

**Section sources**
- [flutter_app/lib/web_resume_repaint_web.dart](file://flutter_app/lib/web_resume_repaint_web.dart)
- [flutter_app/web/flutter_bootstrap.js](file://flutter_app/web/flutter_bootstrap.js)

### Hosting Configuration
- Firebase Hosting: Configure SPA rewrites to route all paths to index.html; set cache headers for static assets.
- Custom domains: Map custom domain and enforce HTTPS.
- Storage CORS: Define allowed origins, methods, and headers for media access.

```mermaid
flowchart TD
Request["Incoming Request"] --> Routing{"Path matches SPA routes?"}
Routing --> |Yes| Rewrite["Rewrite to index.html"]
Routing --> |No| Static["Serve static asset"]
Rewrite --> ServeIndex["Serve index.html"]
Static --> ServeAsset["Serve file from assets"]
ServeIndex --> InitApp["Initialize Flutter app"]
ServeAsset --> Return["Return response"]
InitApp --> Return
```

**Diagram sources**
- [firebase.json](file://firebase.json)
- [flutter_app/web/index.html](file://flutter_app/web/index.html)

**Section sources**
- [firebase.json](file://firebase.json)
- [storage_cors.json](file://storage_cors.json)

### URL Routing
- Client-side routing: url_strategy_web.dart configures Flutter’s URL strategy for clean URLs and deep links.
- Deep linking: Ensure routes map to feature screens and handle initial route on load.
- SEO: Provide meaningful titles, meta tags, and canonical URLs.

**Section sources**
- [flutter_app/lib/url_strategy_web.dart](file://flutter_app/lib/url_strategy_web.dart)
- [flutter_app/lib/url_strategy_stub.dart](file://flutter_app/lib/url_strategy_stub.dart)

### Service Workers and Offline Capabilities
- FCM service worker: firebase-messaging-sw.js handles push notifications and background messaging.
- Offline-first: Cache critical assets and data; implement graceful degradation when offline.
- Update strategy: Use version.json to detect new builds and prompt users to refresh.

```mermaid
sequenceDiagram
participant Browser as "Browser"
participant SW as "Service Worker"
participant FCM as "Firebase Cloud Messaging"
participant App as "Flutter App"
FCM-->>SW : Push event received
SW->>SW : Process notification payload
SW-->>Browser : Show notification
Browser->>App : Open app on click
App->>App : Sync latest data if needed
```

**Diagram sources**
- [flutter_app/web/firebase-messaging-sw.js](file://flutter_app/web/firebase-messaging-sw.js)
- [flutter_app/web/version.json](file://flutter_app/web/version.json)

**Section sources**
- [flutter_app/web/firebase-messaging-sw.js](file://flutter_app/web/firebase-messaging-sw.js)
- [flutter_app/web/version.json](file://flutter_app/web/version.json)

### Web-Specific Features
- AssetLinks: assetlinks.json enables Android app association for seamless cross-app experiences.
- Public fallbacks: 404.html and reset_password.html improve UX for error states and account recovery.
- Analytics: Integrate web analytics via Google Analytics or similar tools through index.html or bootstrap script.

**Section sources**
- [flutter_app/web/assetlinks.json](file://flutter_app/web/assetlinks.json)
- [flutter_app/public/404.html](file://flutter_app/public/404.html)
- [flutter_app/public/reset_password.html](file://flutter_app/public/reset_password.html)

### Deployment and CDN Configuration
- Build and deploy scripts: Scripts automate Flutter web build and Firebase Hosting deployment.
- CI/CD: GitHub Actions workflow triggers automated web deployments on changes.
- CDN best practices: Enable compression, caching, and edge delivery via Firebase Hosting.

```mermaid
sequenceDiagram
participant Dev as "Developer"
participant CI as "GitHub Actions"
participant Build as "Flutter Build"
participant Hosting as "Firebase Hosting"
participant CDN as "CDN Edge"
Dev->>CI : Push code to repository
CI->>Build : Run build_e_deploy_web.ps1
Build-->>CI : Upload artifacts
CI->>Hosting : Deploy to Firebase Hosting
Hosting->>CDN : Distribute assets globally
CDN-->>Dev : Live site updated
```

**Diagram sources**
- [scripts/build_e_deploy_web.ps1](file://scripts/build_e_deploy_web.ps1)
- [scripts/deploy_web_hosting_html.ps1](file://scripts/deploy_web_hosting_html.ps1)
- [scripts/deploy_web_hosting_canvaskit.ps1](file://scripts/deploy_web_hosting_canvaskit.ps1)
- [scripts/deploy_web_hosting_skwasm.ps1](file://scripts/deploy_web_hosting_skwasm.ps1)
- [.github/workflows/deploy-web.yml](file://.github/workflows/deploy-web.yml)

**Section sources**
- [scripts/build_e_deploy_web.ps1](file://scripts/build_e_deploy_web.ps1)
- [scripts/deploy_web_hosting_html.ps1](file://scripts/deploy_web_hosting_html.ps1)
- [scripts/deploy_web_hosting_canvaskit.ps1](file://scripts/deploy_web_hosting_canvaskit.ps1)
- [scripts/deploy_web_hosting_skwasm.ps1](file://scripts/deploy_web_hosting_skwasm.ps1)
- [.github/workflows/deploy-web.yml](file://.github/workflows/deploy-web.yml)

## Dependency Analysis
Key dependencies and relationships:
- Flutter web runtime depends on bootstrap script and version metadata.
- PWA manifest drives installability and appearance.
- Service worker integrates with FCM for push notifications.
- Hosting configuration ensures SPA routing and asset delivery.
- Storage CORS governs media access policies.

```mermaid
graph TB
Index["index.html"] --> Bootstrap["flutter_bootstrap.js"]
Index --> Manifest["manifest.json"]
Index --> Version["version.json"]
Bootstrap --> Runtime["Flutter Runtime"]
Runtime --> App["Gestão Yahweh App"]
SW["firebase-messaging-sw.js"] --> FCM["Firebase Cloud Messaging"]
Hosting["firebase.json"] --> Index
CORS["storage_cors.json"] --> Media["Media Assets"]
```

**Diagram sources**
- [flutter_app/web/index.html](file://flutter_app/web/index.html)
- [flutter_app/web/flutter_bootstrap.js](file://flutter_app/web/flutter_bootstrap.js)
- [flutter_app/web/manifest.json](file://flutter_app/web/manifest.json)
- [flutter_app/web/version.json](file://flutter_app/web/version.json)
- [flutter_app/web/firebase-messaging-sw.js](file://flutter_app/web/firebase-messaging-sw.js)
- [firebase.json](file://firebase.json)
- [storage_cors.json](file://storage_cors.json)

**Section sources**
- [flutter_app/web/index.html](file://flutter_app/web/index.html)
- [flutter_app/web/flutter_bootstrap.js](file://flutter_app/web/flutter_bootstrap.js)
- [flutter_app/web/manifest.json](file://flutter_app/web/manifest.json)
- [flutter_app/web/version.json](file://flutter_app/web/version.json)
- [flutter_app/web/firebase-messaging-sw.js](file://flutter_app/web/firebase-messaging-sw.js)
- [firebase.json](file://firebase.json)
- [storage_cors.json](file://storage_cors.json)

## Performance Considerations
- Minimize initial payload: Use SkiaWasm for smaller bundles when supported; otherwise, leverage CanvasKit with optimized assets.
- Lazy loading: Defer non-critical resources and features until needed.
- Caching strategy: Set long-term cache headers for immutable assets; use version.json for cache busting.
- Monitoring: Track Core Web Vitals (LCP, FID, CLS) and integrate performance monitoring tools.

[No sources needed since this section provides general guidance]

## Troubleshooting Guide
Common issues and resolutions:
- Routing errors: Ensure SPA rewrite rules are configured in firebase.json.
- CORS failures: Verify storage_cors.json allows correct origins and methods.
- Service worker not triggering: Confirm HTTPS and correct registration path.
- Stale assets: Clear browser cache or force reload after deployment.

**Section sources**
- [firebase.json](file://firebase.json)
- [storage_cors.json](file://storage_cors.json)
- [flutter_app/web/firebase-messaging-sw.js](file://flutter_app/web/firebase-messaging-sw.js)

## Conclusion
The web platform for Gestão Yahweh Premium leverages Flutter’s web capabilities with Firebase Hosting, PWA standards, and FCM integration. By following the outlined configurations, optimizations, and deployment practices, you can deliver a fast, reliable, and installable web experience across modern browsers.

[No sources needed since this section summarizes without analyzing specific files]

## Appendices
- SEO checklist: Add meta tags, structured data, and canonical URLs.
- Analytics integration: Embed tracking scripts in index.html or bootstrap script.
- Security policies: Implement CSP, HSTS, and secure cookie settings.

[No sources needed since this section provides general guidance]