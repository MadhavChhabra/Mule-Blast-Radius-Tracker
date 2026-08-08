# BlipRadius

## What it is

BlipRadius reads a MuleSoft estate's *real* wiring — Anypoint API Manager contracts, Exchange
assets, and the actual Mule flow XML, property files and DataWeave in every registered repo — and
tells a developer, **before they merge**, which teams, APIs and fields a spec change will break.

The name is a pun on *blast radius*, which is literally what it computes.

## The mechanism, in one sentence

It diffs two API specs with explicit rules (no AI, no heuristics), resolves each changed field
against a dependency graph built by parsing real integration code, and reports who breaks — marking
clearly which of those answers are proven and which are assumptions.

## Who uses it

MuleSoft integration developers and integration architects inside large enterprises (banks,
insurers, telcos, retailers) that run tens to hundreds of Mule applications across the API-led
layers: experience → process → system → systems of record.

**The real scene.** A work laptop, a ticket-driven day, alt-tabbing between Anypoint Studio, Jira
and a terminal. Often an open-plan office under overhead light; sometimes a war room during an
incident. They are not browsing — they arrive with a specific fear ("I need to change this field")
or a specific question ("who calls this endpoint?"). Sessions are short and repeated.

## The jobs, in order of frequency

1. **"I'm about to change this API — what breaks and who do I tell?"** The primary job.
2. **"What does this endpoint call, and who calls it?"** Real per-endpoint wiring, not a diagram
   somebody drew two years ago.
3. **"Which APIs need this field change propagated?"** Field-level, both directions.
4. **"What changed here before?"** History and changelogs.

## The non-negotiable product truths

- **No AI at runtime.** Every classification is an explicit, unit-tested rule. This is a
  correctness tool; a plausible-sounding guess is worse than no answer.
- **Honesty about confidence.** A consumer discovered through an Anypoint contract is known to call
  the API but not known to read any particular field. The product must never present that
  assumption as a proven read. Confirmed and assumed are different answers and look different.
- **Minimum setup.** Point it at repos and/or an Anypoint connection, press Sync. No hand-written
  dependency manifests — those were the original pain.
- **Fail safe, not silent.** When lineage is unknown, report the consumer anyway and say the data
  is missing. Missing a real break is the worst outcome.

## Governing rule (the heart of the diff engine)

Request/response asymmetry: widening what the server **accepts** is safe; widening what it
**returns** can break strict consumers; narrowing either side is breaking.

## Surfaces

Flutter Web dashboard served by the Spring Boot server on one origin, plus a CLI and a GitHub
Action for CI gating.

1. **Home** — estate health, answer depth (coverage), governance findings, your pinned APIs.
2. **Sources** — Anypoint connection + repos, sync with live progress.
3. **Estate map** — the API-led network; hover traces the full transitive blast radius.
4. **API hub** — Change impact → Relationships → History for one API.
5. **Changelog** — global history.

## Constraints

- Flutter Web (Material widget layer), HTML renderer — must work on air-gapped enterprise networks
  with no CDN egress.
- Light **and** dark must both be first-class; developers run either.
- Dense information is the point. Large estates mean hundreds of nodes and long identifiers.
- Enterprise deployment: single self-contained container, optional shared API key.

## Brand commitments

- Product name **BlipRadius** (display), `blipradius` (command).
- Semantic colour meanings are load-bearing and may not be traded for aesthetics: breaking, safe,
  additive, and unknown/no-data must stay instantly distinguishable, including for the most common
  colour-vision deficiencies.
- Internal identifiers stay `apiguard` (Java package, config keys, jar name) — deliberate.

## Assumptions (inferred this session, not separately confirmed)

- Primary viewing context is desktop; the responsive bottom-bar layout exists for narrow windows
  rather than genuine phone use.
- No corporate design system or brand palette has been supplied to conform to.
