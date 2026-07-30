---
kind: design
name: Consolidate fixed event templates instead of generating occurrences
source: session
category: adr
---

# Consolidate fixed event templates instead of generating occurrences

_Source: coding plans from commit period 45f1c25 → 7ad4946 — records intent at planning time; the implementation may lag or differ._

**Status:** accepted

## Context
Recurring event templates were being 'exploded' into many duplicate documents in the `eventos` collection with `generated: true`, cluttering the initial panel and public site with repetitive rows (e.g., 'Culto de Oração' every Monday). Deleting a fixed event required cleaning up all generated occurrences across modules.

## Decision drivers
- data cleanliness
- UI simplicity
- single source of truth
- consistent cover image display

## Considered options
- **Read directly from `event_templates` as consolidated agenda items** — pros: One document per template, clean UI showing 'Every Monday 19:30 — Prayer Service', single deletion removes everywhere
- **Keep generating occurrence documents in `eventos`** _(rejected)_ — pros: Existing queries work unchanged; cons: Data bloat, duplicate entries, deletion requires batch cleanup, covers don't propagate consistently

## Decision
Stop generating `eventos` documents from templates. The `event_templates` collection becomes the single source of truth for fixed agendas. Flutter modules (Agenda tab, initial panel, public site) read `event_templates` directly and render each template as one consolidated entry. Deletion removes the template and any legacy generated occurrences.

## Consequences
Event templates now have a unified cover image displayed across all surfaces. The initial panel and public site show one row per recurring pattern instead of dozens of duplicates. Legacy generated documents can be cleaned up. Cloud reminder functions may need adjustment to compute next occurrence from templates.