<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo/thetaswap-hero-dark.svg" />
    <source media="(prefers-color-scheme: light)" srcset="assets/logo/thetaswap-hero-mono.svg" />
    <img src="assets/logo/thetaswap-hero-dark.svg" width="200" alt="thetaswap" />
  </picture>
</p>

<h2 align="center">thetaswap</h2>

<p align="center">
  Fee concentration insurance for Uniswap V4 passive LPs
</p>

<p align="center">
  <a href="#architecture">Architecture</a> · <a href="#quick-start--demo">Demo</a> · <a href="#repository-structure">Directory</a>
</p>

---

## Overview

When multiple liquidity providers supply capital to a DEX pool, each should earn a fee share proportional to their contributed liquidity. In practice, a small number of sophisticated actors -- JIT providers and MEV-aware strategies -- concentrate fee revenue away from passive participants, diluting their effective fee rate without generating proportional volume. This is **adverse competition**, a risk dimension orthogonal to both impermanent loss and loss-versus-rebalancing (LVR). ThetaSwap builds the first on-chain adverse competition oracle: the Fee Concentration Index (FCI) Hook tracks fee share distribution across protocols (Uniswap V3 via Reactive Network, V4 natively) and derives a `DeltaPlus` value that prices the insurance-relevant deviation from the competitive equilibrium baseline. See [research/README.md](research/README.md) for the full empirical evidence.

## Architecture

FCI Hook is a protocol-agnostic orchestrator that dispatches behavioral calls via `delegatecall` to registered protocol facets.

### System Context

Solid border = live on testnet. Dashed border = planned.

```mermaid
flowchart TB
    PLP["PLP (Passive LP)"]
    UW["Underwriter"]
    TR["Trader"]
    FCI["FCI Hook<br/>(Orchestrator)<br/><i>FeeConcentrationIndexV2.sol</i>"]
    V4["Uniswap V4 Adapter<br/><i>NativeUniswapV4Facet</i>"]

    subgraph V3Sub["Uniswap V3 Adapter"]
        V3Facet["UniswapV3Facet"]
        RN["Reactive Network<br/><i>UniswapV3Reactive +<br/>UniswapV3Callback</i>"]
    end

    PN["Protocol N<br/>(planned)"]
    VAULT["Token Vault<br/>(planned)<br/><i>CollateralCustodianFacet</i>"]
    CFMM["CFMM<br/>(planned)<br/><i>Price Discovery</i>"]

    FCI -- "tracks metrics<br/>(afterSwap() delegatecall)" --> V4
    FCI -- "bridges events<br/>(unlockCallbackReactive())" --> V3Sub
    FCI -. "implements IFCIProtocolFacet" .-> PN
    FCI -- "provides DeltaPlus oracle<br/>(getDeltaPlus())" --> VAULT
    RN -- "V3 Swap log --> ReactVM --> Callback" --> V3Facet
    VAULT -. "price discovery" .-> CFMM
    PLP -- "deposits collateral" --> VAULT
    UW -- "provides USDC" --> VAULT
    TR -- "trades LONG/SHORT" --> CFMM
    classDef live fill:#d4edda,stroke:#28a745,stroke-width:2px,color:#155724
    classDef orchestrator fill:#cce5ff,stroke:#004085,stroke-width:3px,color:#004085
    classDef planned fill:#fff3cd,stroke:#856404,stroke-width:2px,stroke-dasharray:5 5,color:#856404
    classDef actor fill:#e2e3e5,stroke:#383d41,stroke-width:1px,color:#383d41
    classDef reactive fill:#d1ecf1,stroke:#0c5460,stroke-width:2px,color:#0c5460

    class FCI orchestrator
    class V4 live
    class V3Facet live
    class RN reactive
    class PN planned
    class VAULT planned
    class CFMM planned
    class PLP,UW,TR actor
```

### Pool Listening Flow

Mint and burn follow the same delegatecall dispatch pattern.

```mermaid
sequenceDiagram
    participant Caller as Caller (Pool Deployer)
    participant FCI as FCI V2 (Orchestrator)
    participant Facet as Protocol Facet (V4/V3)
    participant Reader as External Reader

    %% -- Part 1: Pool Registration --
    rect rgb(204, 229, 255)
        Note over Caller,FCI: Pool Registration (one-time setup)
        Caller->>FCI: registerProtocolFacet(flags, facet)
        activate FCI
        FCI->>FCI: store facet address in registry
        deactivate FCI

        Caller->>FCI: listenPool(poolId, protocolFlags, hookData)
        activate FCI
        Note over FCI: Pool is now tracked.<br/>Maps poolId to protocolFlags.<br/>Initializes A_T = 0, N = 0.
        FCI->>Facet: delegatecall listen(hookData, poolId)
        activate Facet
        Facet-->>FCI: pool initialized in protocol storage
        deactivate Facet
        deactivate FCI
    end

    %% -- Part 2: Swap Flow (representative) --
    rect rgb(212, 237, 218)
        Note over FCI,Facet: Per-swap metric computation (repeats every swap)

        Note over FCI: PoolManager calls beforeSwap()<br/>or UniswapV3Callback triggers it

        activate FCI
        FCI->>FCI: extract protocolFlags from hookData[0:2]

        Note over FCI: beforeSwap: store tickBefore via tstoreTick()
        FCI->>Facet: delegatecall currentTick(hookData, poolId)
        activate Facet
        Facet-->>FCI: tickBefore
        deactivate Facet

        FCI->>Facet: delegatecall tstoreTick(hookData, tickBefore)
        activate Facet
        Facet-->>FCI: tick stored in transient storage
        deactivate Facet

        Note over FCI: afterSwap callback fires

        FCI->>Facet: delegatecall tloadTick(hookData)
        activate Facet
        Note right of Facet: load tick before swap (tloadTick())
        Facet-->>FCI: tickBefore
        deactivate Facet

        FCI->>Facet: delegatecall currentTick(hookData, poolId)
        activate Facet
        Note right of Facet: read tick after swap (currentTick())
        Facet-->>FCI: tickAfter
        deactivate Facet

        FCI->>FCI: compute tick overlap interval<br/>sortTicks(tickBefore, tickAfter)

        FCI->>Facet: delegatecall incrementOverlappingRanges(<br/>hookData, poolId, tickMin, tickMax)
        activate Facet
        Note right of Facet: increment swapCount for<br/>all ranges spanning [tickMin, tickMax]
        Facet-->>FCI: ranges updated
        deactivate Facet

        Note over FCI: On position removal (afterRemoveLiquidity):<br/>FCI computes xk (FeeShareRatio),<br/>updates A_T accumulator,<br/>emits FCITermAccumulated event

        FCI->>Facet: delegatecall addStateTerm(<br/>hookData, poolId, blockLifetime, xSquaredQ128)
        activate Facet
        Note right of Facet: accumulate FCI state term
        Facet-->>FCI: A_T, ThetaSum updated
        deactivate Facet
        deactivate FCI
    end

    %% -- Part 3: External Query --
    rect rgb(255, 243, 205)
        Note over Reader,FCI: External read (any time after accumulation)

        Reader->>FCI: getDeltaPlus(poolKey, flags)
        activate FCI
        FCI-->>Reader: DeltaPlus value (uint128)
        deactivate FCI

        Note over Reader: DeltaPlus = max(0, 1 - A_T)<br/>Used for insurance pricing<br/>and vault oracle payoff
    end

    Note over Caller,Reader: Mint/burn follow the same delegatecall pattern<br/>with position-level fee growth accounting
```

## Quick Start / Demo

```bash
forge test --match-path "test/fee-concentration-index-v2/protocols/uniswapV4/NativeV4FeeConcentrationIndex.integration.t.sol" -vv
```

What the integration test demonstrates:

- **Swap scenario:** each swap updates the A_T accumulator by computing fee share ratios across overlapping positions
- **Mint scenario:** adding liquidity increments position count N and registers the position for FCI tracking
- **Burn scenario:** removing liquidity triggers fee share computation (xk), accumulates the FCI state term, and derives DeltaPlus
- **DeltaPlus query:** external readers call `getDeltaPlus()` to get the insurance-relevant oracle value (`max(0, 1 - A_T)`)
- **Cross-protocol:** the same orchestrator logic works for both V4 native hooks and V3 via Reactive Network callbacks

## Repository Structure

| Directory | Description |
|-----------|-------------|
| `src/` | Solidity contracts: FCI V2 orchestrator, protocol facets (V4 native, V3 reactive), vault, libraries |
| `test/` | Forge test suites: unit, fuzz, fork, and integration tests |
| `research/` | Econometric analysis, backtest engine, mathematical model, data fixtures ([detailed README](research/README.md)) |
| `docs/` | Architecture diagrams (mermaid), implementation plans |
| `specs/` | Contract specifications (per-feature) |
