# Roadmap: ThetaSwap Presentation

## Overview

Transform ThetaSwap's research, architecture, and implementation into a cohesive presentation package. The work flows from research synthesis (the foundation narrative) through architecture diagrams, into repository artifacts (README, demo), and culminates in complete slide content that ties everything together.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Problem & Research Narrative** - Synthesize econometric research into presentation-ready problem statement and research summary
- [ ] **Phase 2: Architecture Diagrams** - Create mermaid context and sequence diagrams showing FCI system architecture and pool listening flow
- [ ] **Phase 3: Repository Artifacts** - Update README with architecture section and document the demo test with run instructions
- [ ] **Phase 4: Slide Content Assembly** - Produce complete slide-ready content for solution, demo, roadmap, and missing-pieces sections

## Phase Details

### Phase 1: Problem & Research Narrative
**Goal**: Audience understands adverse competition as a distinct LP risk and sees the empirical evidence supporting ThetaSwap's approach
**Depends on**: Nothing (first phase)
**Requirements**: PROB-01, PROB-02, PROB-03, SLID-01, SLID-02
**Success Criteria** (what must be TRUE):
  1. A reader with no DeFi background can explain in one sentence what adverse competition risk is and why it differs from impermanent loss
  2. The research summary includes the inverted-U finding, turning point delta* ~ 0.09, and the key statistics (41 days, 600 positions, 2.65x real vs null)
  3. Problem and research content exists as standalone slide-ready markdown sections that can be dropped into any slide tool
**Plans**: TBD

Plans:
- [ ] 01-01: TBD
- [ ] 01-02: TBD

### Phase 2: Architecture Diagrams
**Goal**: System architecture is visually communicable through two mermaid diagrams that work in GitHub markdown
**Depends on**: Nothing (independent of Phase 1 content, but Phase 1 informs narrative framing)
**Requirements**: ARCH-01, ARCH-02, ARCH-03
**Success Criteria** (what must be TRUE):
  1. Context diagram shows FCI Hook, Vault, CFMM, Protocol Adapters (V3, V4), and Reactive Network with their relationships
  2. Sequence diagram traces the full pool listening flow from listenPool() through swap/mint/burn events to metric update and DeltaPlus derivation
  3. Both diagrams render correctly when viewed on GitHub (mermaid fenced code blocks in markdown)
**Plans**: TBD

Plans:
- [ ] 02-01: TBD

### Phase 3: Repository Artifacts
**Goal**: README serves as the landing page for the project and the demo is documented so anyone can run it
**Depends on**: Phase 2 (diagrams needed for README)
**Requirements**: READ-01, READ-02, DEMO-01, DEMO-02
**Success Criteria** (what must be TRUE):
  1. README.md contains an Architecture section with both mermaid diagrams embedded and rendering
  2. A developer unfamiliar with the project can find and run the demo test using only the documented forge command
  3. Running the demo test shows FCI tracking through swap, mint, and burn scenarios on V4
  4. README architecture section uses plain language with technical detail available but not required for comprehension
**Plans**: TBD

Plans:
- [ ] 03-01: TBD
- [ ] 03-02: TBD

### Phase 4: Slide Content Assembly
**Goal**: Complete presentation content exists for solution, demo, and roadmap sections -- ready to paste into any slide tool
**Depends on**: Phase 1 (narrative), Phase 2 (diagrams), Phase 3 (demo)
**Requirements**: ROAD-01, ROAD-02, ROAD-03, SLID-03, SLID-04, SLID-05
**Success Criteria** (what must be TRUE):
  1. Solution slide content references architecture diagram and explains FCI Hook, reactive adapter, and cross-protocol design
  2. Demo slide content includes step-by-step instructions for running and narrating the integration test
  3. Roadmap slide content lists missing CFMM (linearized power-squared trading function) and vault/settlement as clear next steps, not blockers
  4. All slide sections follow a consistent format and can be assembled into a single presentation document
**Plans**: TBD

Plans:
- [ ] 04-01: TBD
- [ ] 04-02: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Problem & Research Narrative | 0/2 | Not started | - |
| 2. Architecture Diagrams | 0/1 | Not started | - |
| 3. Repository Artifacts | 0/2 | Not started | - |
| 4. Slide Content Assembly | 0/2 | Not started | - |
