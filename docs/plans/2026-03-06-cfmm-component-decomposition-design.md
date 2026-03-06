# CFMM Component Decomposition Design

**Date**: 2026-03-06 | **Branch**: `002-theta-swap-cfmm`
**Source of truth**: `specs/model/*.tex` (power-squared Lendgine architecture)

## Context

The LaTeX model spec defines a power-squared insurance CFMM (Lendgine/PowerMaker style) with:

- **Payoff**: `V(p) = (p_u^2 - p^2) / p_l^2` for underwriters
- **Trading function**: `psi(u, y) = y - (p_l^2 / 4) * u` where `u = x^2`
- **Price**: `p = Delta+ / (1 - Delta+)` where `Delta+ = max(0, A_T - A_T^null)`
- **Architecture**: Lendgine-style borrow/lend with JumpRate + bidirectional funding

The previous `tasks.md` described a `ln(1+p)` payoff with streaming premium deduction. This is obsolete. This document supersedes it.

## Assumptions (handled on other branches)

1. **FCI facet** exposes `getDeviation(PoolKey) -> (uint256 deltaPlus)` returning Delta+ in Q128. Also exposes `getIndex(PoolKey) -> (uint128 indexA, uint128 indexB)`. The FCI refactor (adding Theta_sum, N_pos co-primaries and computing Delta+ on the fly) happens on a separate branch.
2. **MasterHook diamond** is wired. Composite callbacks (afterSwap, afterAddLiquidity, afterRemoveLiquidity) dispatch to both FCI and Insurance facets. Handled on a separate branch.
3. **Diamond storage** slots are disjoint between FCI and Insurance facets.

## 6 Issues

### Issue 1: Price Representation

**Scope**: All types and transforms mapping FCI oracle output to CFMM-usable price primitives.

**No dependencies** on other issues. Pure math types.

**Types (UDVTs + Mod files)**:

| Type | UDVT backing | Key operations |
|------|-------------|---------------|
| `ConcentrationPrice` | `uint256` (Q128) | `fromDeltaPlus(d) -> p = d/(1-d)`, `toDeltaPlus(p) -> d = p/(1+p)` |
| `TransformedReserve` | `uint256` (Q128) | `fromX(x) -> u = x^2`, `toX(u) -> x = sqrt(u)` |
| `SpotPrice` | `uint256` (Q128) | `fromReserves(u, L_act, p_l) -> p = (p_l^2/2) * sqrt(u/L_act)` |

Tick index (`int24`) is reused from existing types. Tick `i` maps to `p_i = p_l * 1.0001^i`.

**Invariants**: FCI-09 (price non-neg), FCI-10 (price monotonicity), FCI-11 (price-deviation invertibility), CFMM-16 (u<->x bijection)

**Kontrol proofs**:
- `fromDeltaPlus` round-trip with `toDeltaPlus`
- `fromX` round-trip with `toX`
- `fromDeltaPlus(0) = 0`, `fromDeltaPlus` monotone on [0, Q128_ONE)
- No division by zero when Delta+ < 1

---

### Issue 2: Trading Function

**Scope**: The invariant `psi(u, y) = y - (p_l^2/4)*u`, swap mechanics, slippage.

**Depends on**: Issue 1 (imports `TransformedReserve`, `SpotPrice`)

**Types**:

| Type | Key operations |
|------|---------------|
| `TradingFunction` | `invariant(u, y, p_l) -> psi`, `invariantConstant(p_u, p_l) -> C1 = p_u^2/p_l^2` |
| `SwapMath` | `computeDeltaU(x, deltaX) -> 2x*dX + dX^2`, `computeDeltaY(deltaU, p_l) -> (p_l^2/4)*dU`, `effectivePrice(x, deltaX, p_l)` |

**Invariants**: CFMM-01 (convexity), CFMM-03 (swap preservation), CFMM-14 (output positive), CFMM-15 (slippage non-neg), CFMM-17 (1-homogeneity), CFMM-18 (concavity), CFMM-25 (canonical form)

**Key insight**: `psi` is LINEAR in `(u, y)`. No piecewise approximation needed. Within a tick, a swap is one multiplication plus one sqrt for x<->u conversion.

---

### Issue 3: Liquidity Management

**Scope**: Mint/burn, single-sided USDC deposit, tick crossing, tick bitmap.

**Depends on**: Issues 1 + 2

**Types**:

| Type | Key operations |
|------|---------------|
| `MintMath` | `computeDeltaL(deltaY, p_l, p_u, p) -> DL = dY*p_l^2/(p_u^2+p^2)`, `computeDeltaU(DL, p, p_l) -> Du = DL*4p^2/p_l^4` |
| `TickCrossing` | `cross(tick) -> L_act += L_net`, `flipOutsideAccumulators()` |
| `InsuranceTickBitmap` | `flipTick`, `nextInitializedTick`, `isInitialized` |

**Invariants**: CFMM-04 (mint), CFMM-05 (burn), CFMM-08 (tick crossing), CFMM-09 (liquidity non-neg), CFMM-19 (single-sided deposit), CFMM-23 (boundary reserves)

---

### Issue 4: Borrow/Lend Engine

**Scope**: Lendgine-style LP share borrowing, JumpRate utilization curve, borrow accumulator.

**Depends on**: Issue 1 only

**Types**:

| Type | Key operations |
|------|---------------|
| `Utilization` | `compute(L_borrowed, L_total) -> U_a`, bounded [0,1] |
| `BorrowRate` | `compute(U_a, gamma, m_low, m_high, kink) -> r_borrow` (JumpRate piecewise-linear) |
| `BorrowAccumulator` | `accrue(r_borrow, Dt) -> g += r*Dt`, Synthetix per-position difference |

**Invariants**: INS-02 (utilization bound), INS-03 (borrow rate positivity), INS-04 (borrow rate monotonicity), INS-05 (separate accumulators -- borrow side)

---

### Issue 5: Funding Rate

**Scope**: Bidirectional mark-index funding, jump premium, funding accumulator.

**Depends on**: Issue 1 only

**Types**:

| Type | Key operations |
|------|---------------|
| `FundingRate` | `compute(p_mark, p_index, alpha) -> r = alpha*(p_mark - p_index)/(p_index + 1)` |
| `JumpPremium` | `compute(Dp_index, delta_jump, lambda) -> lambda*|Dp_index|` if above threshold |
| `FundingAccumulator` | `accrue(r_adj, Dt) -> g += r*Dt` (bidirectional, signed) |

**Invariants**: CFMM-26 (convergence), CFMM-27 (funding bounds), CFMM-28 (jump safety), INS-05 (separate accumulators -- funding side)

---

### Issue 6: PLP Registration & Exit

**Scope**: PLP borrows LP share, max-price tracking, power-squared exit payoff, settlement.

**Depends on**: Issues 1-5 (convergence point)

**Types**:

| Type | Key operations |
|------|---------------|
| `PLPPosition` | `create(borrowAmount, p_index_now)`, `updateMaxPrice(p_index)`, `computePayout(...)` |
| `ExitPayoff` | `compute(premium, p_max, p_l, p_u) -> premium * [(p_max/p_l)^2 - 1]^+`, capped at `(p_u/p_l)^2 - 1` |

**Invariants**: INS-06 (max-price tracking), INS-07 (payout formula), INS-08 (payout cap), INS-10 (exit settlement), CFMM-13 (LP value bounded)

## Dependency Graph

```
Issue 1 (Price Rep)  [no deps]
    |
    +--- Issue 2 (Trading Fn)  [deps: 1]
    |        |
    |        +--- Issue 3 (Liquidity Mgmt)  [deps: 1, 2]
    |
    +--- Issue 4 (Borrow/Lend)  [deps: 1]
    |
    +--- Issue 5 (Funding Rate)  [deps: 1]
    |
    +--------+--------+--- Issue 6 (PLP Lifecycle)  [deps: 1-5]
```

**Critical path**: 1 -> 2 -> 3 -> 6
**Parallel after Issue 1**: Issues 2, 4, 5 can start simultaneously.
**Issue 6** waits for all five predecessors.

## Invariant Coverage

| Group | Count | Covered by Issues |
|-------|-------|------------------|
| CFMM-01 to CFMM-19 | 19 | Issues 1, 2, 3 |
| CFMM-20 to CFMM-25 | 6 | Issues 2, 3 |
| CFMM-26 to CFMM-28 | 3 | Issue 5 |
| FCI-09 to FCI-11 | 3 | Issue 1 |
| INS-01 to INS-10 | 10 | Issues 3, 4, 5, 6 |
| **Total** | **41** | |

Note: FCI-01 through FCI-08 and FCI-12 through FCI-13 are covered by the FCI Refactor branch (out of scope here).

## TDD Order Per Issue

Each issue follows type-driven development:
1. Types (UDVTs + Mod files)
2. Kontrol proofs for type safety
3. Implementation (external functions using types)
4. Unit tests
5. Fuzz tests for invariant coverage

## Stale Artifacts

`specs/002-theta-swap-cfmm/tasks.md` references the obsolete `ln(1+p)` architecture. It must be rewritten to align with this decomposition.
