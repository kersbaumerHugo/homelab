# Operations Documentation

This directory documents the current operational posture of the homelab.

These documents describe what is true now, what risks are accepted and what
the platform should improve next.

## Documents

### [Current Platform State](current-state.md)

The canonical snapshot of the current implementation.

Use this document to answer:

- what is currently operational;
- what has been tested;
- what limitations exist now.

### [Reliability Posture](reliability.md)

Documents:

- reliability principles;
- recovery controls;
- tested failure scenarios;
- single points of failure;
- RPO/RTO targets;
- current maturity.

### [Security Posture](security.md)

Documents:

- trust boundaries;
- repository security;
- administrative access;
- current controls;
- known security gaps;
- future security direction.

### [Known Risks](known-risks.md)

The current risk register.

Risks should not be removed because they are inconvenient.

A risk should be closed only when its mitigation is implemented, documented
and tested where practical.

### [Roadmap](roadmap.md)

Defines the planned sequence of platform evolution.

The roadmap is intentionally infrastructure-first.

## Update rule

Update operations documentation when:

- a risk changes;
- a milestone is completed;
- recovery capability changes;
- an operational objective changes;
- a new single point of failure appears;
- a former limitation is removed.
