---
kind: business_term
name: Business Glossary
category: business_term
scope:
    - '**'
---

### Igreja
- Definition：Church or congregation - the primary tenant entity in the multi-tenant architecture. Each church has its own isolated data space under `igrejas/{churchId}/` in both Firestore and Storage.
- Aliases：igreja、church、tenant

### Painel Master
- Definition：Master panel - administrative interface for managing multiple churches and global settings. Used by super-administrators to oversee the entire system.
- Aliases：master panel、painel master、admin

### Avisos
- Definition：Notices or announcements - community announcements posted by church administrators, stored in `igrejas/{churchId}/avisos/` with associated media in Storage.
- Aliases：aviso、notice、announcement

### Eventos
- Definition：Events - scheduled church activities and events with media attachments (images, videos), stored in `igrejas/{churchId}/eventos/`.
- Aliases：evento、event

### Patrimônio
- Definition：Assets or property management - tracking church assets, equipment, and property with photo documentation in `igrejas/{churchId}/patrimonio/`.
- Aliases：património、asset、property

### Financeiro
- Definition：Financial module - church financial management including transactions, accounts, and receipt storage in `igrejas/{churchId}/finance/` and `financeiro/YYYY_MM/`.
- Aliases：finanças、financial、finance

### Membros
- Definition：Members - church member management including profiles, photos, and personal information stored in `igrejas/{churchId}/membros/`.
- Aliases：membro、member

### Departamentos
- Definition：Departments - organizational units within a church that can be converted to Telegram groups for communication.
- Aliases：departamento、department

### Chat Yahweh
- Definition：The integrated chat system supporting both Firestore-based messaging and optional Telegram TDLib backend for enhanced messaging capabilities.
- Aliases：chat、messaging、yahweh chat

### Site Público
- Definition：Public website accessible at `/igreja/<slug>` for non-authenticated visitors to view church information, events, and notices.
- Aliases：site público、public site、website

### Upload Turbo
- Definition：High-speed upload optimization using parallel processing, compression, and background queuing for images and videos across all modules.
- Aliases：upload turbo、fast upload、turbo upload

### Strict Publish
- Definition：Publishing workflow ensuring data consistency with validation, preparation, single-write operations, and automatic recovery on failure.
- Aliases：strict publish、publish strict
