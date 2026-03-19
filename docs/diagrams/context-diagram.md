# FCI System Context Diagram

The Fee Concentration Index system has three layers:

1. **FCI Algorithm** (`FeeConcentrationIndexV2.sol`) — warehouses the index logic. Computes fee shares, theta weights, and accumulates A_T. Protocol-agnostic.
2. **Protocol Facets** — route to protocol-specific storage slots and adapt protocol data to the algorithm's interface via helper libraries. Called via `delegatecall` from the algorithm.
3. **FCI Hook** — the client-facing interface. Exposes all metrics (A_T, DeltaPlus, ThetaSum, N) that indexers, LPs, or downstream contracts need. Clients pass `poolId` + `protocolFlag`.

Any protocol can integrate by building: (a) a facet implementing `IFCIProtocolFacet`, (b) callback helper libraries mapping their event data to V4 hook calldata equivalent. The Reactive Network enables connecting pools **on demand** — not limited to pools that instantiated with IHooks from the start. See `protocols/uniswap-v3/` for the reference implementation.

**Legend:** Solid border = live on testnet. Dashed border = planned / not yet deployed.

```mermaid
flowchart TB
    %% ── Clients ──
    IDX["Indexer / Reader"]
    PLP["Passive LP"]
    UW["Underwriter"]

    %% ── Client-facing interface ──
    HOOK["FCI Hook<br/><i>getIndex() · getDeltaPlus() · getAtNull()</i><br/>poolId + protocolFlag"]

    %% ── Core algorithm ──
    ALG["FCI Algorithm<br/><i>FeeConcentrationIndexV2.sol</i><br/>afterAdd · beforeSwap · afterSwap<br/>beforeRemove · afterRemove"]

    %% ── Protocol facets ──
    V4F["V4 Facet<br/><i>NativeUniswapV4Facet</i><br/>+ V4 storage slot"]

    subgraph V3Sub["Uniswap V3 Integration"]
        V3F["V3 Facet<br/><i>UniswapV3Facet</i><br/>+ V3 storage slot"]
        RN["Reactive Network<br/><i>UniswapV3Reactive</i><br/>+ callback helpers"]
        V3POOL["V3 Pool<br/><i>(any chain)</i>"]
    end

    PNF["Protocol N Facet<br/>(planned)<br/>+ custom storage slot"]

    %% ── Downstream (planned) ──
    VAULT["Vault<br/>(planned)"]
    CFMM["CFMM<br/>(planned)"]

    %% ── Client to hook ──
    IDX -- "queries metrics<br/>(poolId, flags)" --> HOOK
    PLP -- "queries DeltaPlus" --> HOOK

    %% ── Hook exposes algorithm ──
    HOOK -- "reads state" --> ALG

    %% ── Algorithm to facets (delegatecall) ──
    ALG -- "delegatecall<br/>(IFCIProtocolFacet)" --> V4F
    ALG -- "delegatecall<br/>(IFCIProtocolFacet)" --> V3F
    ALG -. "delegatecall<br/>(IFCIProtocolFacet)" .-> PNF

    %% ── V3 reactive bridge ──
    V3POOL -- "Swap/Mint/Burn events" --> RN
    RN -- "maps to V4 calldata<br/>(callback helpers)" --> V3F

    %% ── Downstream ──
    HOOK -. "oracle feed" .-> VAULT
    VAULT -. "price discovery" .-> CFMM
    PLP -- "deposits" --> VAULT
    UW -- "provides USDC" --> VAULT

    %% ── Styling ──
    classDef hook fill:#cce5ff,stroke:#004085,stroke-width:3px,color:#004085
    classDef algo fill:#d4edda,stroke:#28a745,stroke-width:3px,color:#155724
    classDef facet fill:#d4edda,stroke:#28a745,stroke-width:2px,color:#155724
    classDef planned fill:#fff3cd,stroke:#856404,stroke-width:2px,stroke-dasharray:5 5,color:#856404
    classDef actor fill:#e2e3e5,stroke:#383d41,stroke-width:1px,color:#383d41
    classDef reactive fill:#d1ecf1,stroke:#0c5460,stroke-width:2px,color:#0c5460
    classDef pool fill:#f8d7da,stroke:#721c24,stroke-width:1px,color:#721c24

    class HOOK hook
    class ALG algo
    class V4F,V3F facet
    class RN reactive
    class V3POOL pool
    class PNF,VAULT,CFMM planned
    class IDX,PLP,UW actor
```
