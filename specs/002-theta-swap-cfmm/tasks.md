# Tasks: ThetaSwap Fee Concentration Insurance CFMM

**Source of truth**: `specs/model/*.tex` (power-squared Lendgine architecture)
**Design doc**: `docs/plans/2026-03-06-cfmm-component-decomposition-design.md`
**Methodology**: Type-Driven Development — invariants and types before implementation, Kontrol proofs per type
**Constraints**: SCOP (no inheritance, no `library`, no `modifier`), Diamond storage pattern

## Assumptions (other branches)

- FCI facet exposes `getDeviation(PoolKey) -> (uint256 deltaPlus)` (Q128)
- MasterHook diamond wires composite callbacks
- Diamond storage slots are disjoint

## Format: `[ID] [P?] [Issue] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Issue]**: Which GitHub issue (1-6) this task belongs to
- TDD order within each issue: Types -> Kontrol -> Implementation -> Unit tests -> Fuzz tests

---

## Issue 1: Price Representation

**Purpose**: Map FCI oracle output (Delta+) to CFMM price primitives
**Dependencies**: None
**Invariants**: FCI-09, FCI-10, FCI-11, CFMM-16

### Types

- [ ] T001 [P] [I1] Create `src/theta-swap-insurance/types/ConcentrationPriceMod.sol`: UDVT `type ConcentrationPrice is uint256` (Q128). Free functions: `fromDeltaPlus(uint256 d) -> p = d / (WAD - d)`, `toDeltaPlus(ConcentrationPrice p) -> d = p / (1 + p)`, `unwrap`, `isZero`, `gt`, `lt`
- [ ] T002 [P] [I1] Create `src/theta-swap-insurance/types/TransformedReserveMod.sol`: UDVT `type TransformedReserve is uint256` (Q128). Free functions: `fromX(uint256 x) -> u = x * x`, `toX(TransformedReserve u) -> x = sqrt(u)`, `add`, `sub`, `unwrap`
- [ ] T003 [P] [I1] Create `src/theta-swap-insurance/types/SpotPriceMod.sol`: UDVT `type SpotPrice is uint256` (Q128). Free functions: `fromReserves(TransformedReserve u, uint256 L_act, ConcentrationPrice p_l) -> p = (p_l^2 / 2) * sqrt(u / L_act)`, `unwrap`

### Kontrol Proofs

- [ ] T004 [P] [I1] Create `test/theta-swap-insurance/kontrol/ConcentrationPriceMod.k.sol`: prove `fromDeltaPlus` round-trip with `toDeltaPlus`, prove monotonicity on [0, Q128_ONE), prove `fromDeltaPlus(0) = 0`, prove no division by zero when d < Q128_ONE
- [ ] T005 [P] [I1] Create `test/theta-swap-insurance/kontrol/TransformedReserveMod.k.sol`: prove `fromX` round-trip with `toX` for x > 0, prove `fromX` monotone
- [ ] T006 [P] [I1] Create `test/theta-swap-insurance/kontrol/SpotPriceMod.k.sol`: prove `fromReserves` non-negative, prove no division by zero when L_act > 0

### Unit Tests

- [ ] T007 [I1] Write unit tests in `test/theta-swap-insurance/unit/PriceRepresentation.t.sol`: numerical verification against LaTeX reserves.tex table (p_l=0.0989, p_u=1.0, Delta*=0.09), edge cases (Delta+=0, Delta+ approaching 1), u<->x round-trip at multiple values

**Checkpoint**: All price primitives verified. Foundation for Issues 2-6.

---

## Issue 2: Trading Function

**Purpose**: Trading invariant psi(u,y) = y - (p_l^2/4)*u, swap mechanics
**Dependencies**: Issue 1
**Invariants**: CFMM-01, CFMM-03, CFMM-14, CFMM-15, CFMM-17, CFMM-18, CFMM-25

### Types

- [ ] T008 [P] [I2] Create `src/theta-swap-insurance/types/TradingFunctionMod.sol`: Free functions: `invariant(TransformedReserve u, uint256 y, ConcentrationPrice p_l) -> psi = y - (p_l^2/4)*u`, `invariantConstant(ConcentrationPrice p_u, ConcentrationPrice p_l) -> C1 = p_u^2/p_l^2`, `verifyInvariant(u, y, L, p_l, p_u) -> bool`
- [ ] T009 [P] [I2] Create `src/theta-swap-insurance/types/SwapMathMod.sol`: Free functions: `computeDeltaU(uint256 x, int256 deltaX) -> Δu = 2x*dX + dX^2`, `computeDeltaY(int256 deltaU, ConcentrationPrice p_l) -> Δy = (p_l^2/4)*Δu`, `effectivePrice(uint256 x, int256 deltaX, ConcentrationPrice p_l) -> (p_l^2/4)*(2x + dX)`

### Kontrol Proofs

- [ ] T010 [P] [I2] Create `test/theta-swap-insurance/kontrol/TradingFunctionMod.k.sol`: prove 1-homogeneity `psi(k*u, k*y) = k*psi(u,y)`, prove concavity (Hessian zero), prove swap preserves invariant
- [ ] T011 [P] [I2] Create `test/theta-swap-insurance/kontrol/SwapMathMod.k.sol`: prove deltaX > 0 -> deltaY > 0 (output positive), prove effective price >= spot price (slippage non-neg)

### Unit Tests

- [ ] T012 [I2] Write unit tests in `test/theta-swap-insurance/unit/TradingFunction.t.sol`: invariant preservation through multiple swaps, numerical verification against reserves.tex table, boundary swaps (x near p_l, x near p_u)

**Checkpoint**: Swap math verified. Within-tick operations are O(1).

---

## Issue 3: Liquidity Management

**Purpose**: Mint/burn single-sided USDC, tick crossing, tick bitmap
**Dependencies**: Issues 1, 2
**Invariants**: CFMM-04, CFMM-05, CFMM-08, CFMM-09, CFMM-19, CFMM-23

### Types

- [ ] T013 [P] [I3] Create `src/theta-swap-insurance/types/MintMathMod.sol`: Free functions: `computeDeltaL(uint256 deltaY, ConcentrationPrice p_l, ConcentrationPrice p_u, ConcentrationPrice p) -> DL = dY*p_l^2/(p_u^2+p^2)`, `computeDeltaU(uint256 DL, ConcentrationPrice p, ConcentrationPrice p_l) -> Du = DL*4p^2/p_l^4`, `computeBurnReturn(uint256 DL, ConcentrationPrice p, ConcentrationPrice p_l, ConcentrationPrice p_u) -> (Du, Dy)`
- [ ] T014 [P] [I3] Create `src/theta-swap-insurance/types/TickCrossingMod.sol`: Free functions: `cross(int24 tick, int256 liquidityNet) -> newActiveLiquidity`, `flipOutsideAccumulators(tick, borrowGrowthGlobal, fundingGrowthGlobal)`
- [ ] T015 [P] [I3] Create `src/theta-swap-insurance/types/InsuranceTickBitmapMod.sol`: Free functions: `flipTick(mapping, int24 tick, int24 tickSpacing)`, `nextInitializedTickWithinOneWord(mapping, int24 tick, int24 tickSpacing, bool lte) -> (int24, bool)`, `isInitialized(mapping, int24 tick, int24 tickSpacing) -> bool`

### Kontrol Proofs

- [ ] T016 [P] [I3] Create `test/theta-swap-insurance/kontrol/MintMathMod.k.sol`: prove mint preserves invariant (CFMM-04), prove burn preserves invariant (CFMM-05), prove single-sided deposit consistency (CFMM-19)
- [ ] T017 [P] [I3] Create `test/theta-swap-insurance/kontrol/TickCrossingMod.k.sol`: prove L_act' = L_act + L_net (CFMM-08), prove L_act >= 0 after crossing (CFMM-09)

### Unit Tests

- [ ] T018 [I3] Write unit tests in `test/theta-swap-insurance/unit/LiquidityMgmt.t.sol`: mint at various prices (Case 1: p<=p_l, Case 2: p_l<p<p_u per initialization.tex), multi-tick mint/burn round-trip, tick bitmap flip and lookup, boundary reserves verification (CFMM-23)

### Implementation

- [ ] T019 [I3] Implement `addUnderwriterLiquidity()` in `src/theta-swap-insurance/ThetaSwapInsurance.sol`: validate tick range, compute DL and Du via MintMathMod, update tick state (liquidityNet, liquidityGross), flip bitmap, update activeLiquidity if range contains currentTick, snapshot borrow/funding baselines, transfer USDC, emit event
- [ ] T020 [I3] Implement `removeUnderwriterLiquidity()` in `src/theta-swap-insurance/ThetaSwapInsurance.sol`: validate position, compute net return via BurnReturn, update ticks, flip bitmap, transfer USDC, emit event

**Checkpoint**: Full concentrated liquidity management with single-sided USDC deposits.

---

## Issue 4: Borrow/Lend Engine

**Purpose**: Lendgine-style LP share borrowing, JumpRate, borrow accumulator
**Dependencies**: Issue 1
**Invariants**: INS-02, INS-03, INS-04, INS-05 (borrow side)

### Types

- [ ] T021 [P] [I4] Create `src/theta-swap-insurance/types/UtilizationMod.sol`: UDVT `type Utilization is uint256` (Q128, bounded [0, Q128_ONE]). Free functions: `compute(uint256 L_borrowed, uint256 L_total) -> U_a`, `unwrap`, `isAboveKink(Utilization u, uint256 kink) -> bool`
- [ ] T022 [P] [I4] Create `src/theta-swap-insurance/types/BorrowRateMod.sol`: UDVT `type BorrowRate is uint256` (Q128). Free functions: `compute(Utilization U_a, uint256 gamma, uint256 m_low, uint256 m_high, uint256 kink) -> r = gamma + m_low*min(U,kink) + m_high*max(0, U-kink)`, `unwrap`
- [ ] T023 [P] [I4] Create `src/theta-swap-insurance/types/BorrowAccumulatorMod.sol`: Free functions: `accrue(uint256 globalGrowth, BorrowRate r, uint256 deltaT) -> newGrowth`, `perPositionFees(uint256 liquidity, uint256 globalGrowth, uint256 baseline) -> fees`

### Kontrol Proofs

- [ ] T024 [P] [I4] Create `test/theta-swap-insurance/kontrol/UtilizationMod.k.sol`: prove 0 <= U_a <= 1 (INS-02), prove no division by zero when L_total > 0
- [ ] T025 [P] [I4] Create `test/theta-swap-insurance/kontrol/BorrowRateMod.k.sol`: prove r >= gamma > 0 (INS-03), prove monotonicity in U_a (INS-04), prove continuity at kink
- [ ] T026 [P] [I4] Create `test/theta-swap-insurance/kontrol/BorrowAccumulatorMod.k.sol`: prove accumulator monotonically non-decreasing (INS-05 borrow side)

### Unit Tests

- [ ] T027 [I4] Write unit tests in `test/theta-swap-insurance/unit/BorrowLend.t.sol`: JumpRate curve at U=0, U=kink, U=1, Synthetix per-position difference pattern, accumulator accrual over multiple intervals

**Checkpoint**: Borrow rate engine verified. Underwriters always earn >= gamma.

---

## Issue 5: Funding Rate

**Purpose**: Bidirectional mark-index funding, jump premium, funding accumulator
**Dependencies**: Issue 1
**Invariants**: CFMM-26, CFMM-27, CFMM-28, INS-05 (funding side)

### Types

- [ ] T028 [P] [I5] Create `src/theta-swap-insurance/types/FundingRateMod.sol`: UDVT `type FundingRate is int256` (Q128, signed). Free functions: `compute(SpotPrice p_mark, ConcentrationPrice p_index, uint256 alpha) -> r = alpha*(p_mark - p_index)/(p_index + 1)`, `isPositive(FundingRate r) -> bool`, `abs(FundingRate r) -> uint256`
- [ ] T029 [P] [I5] Create `src/theta-swap-insurance/types/JumpPremiumMod.sol`: Free functions: `compute(ConcentrationPrice p_index_prev, ConcentrationPrice p_index_now, uint256 delta_jump, uint256 lambda) -> adjustment`, `shouldApply(uint256 dp, uint256 delta_jump) -> bool`
- [ ] T030 [P] [I5] Create `src/theta-swap-insurance/types/FundingAccumulatorMod.sol`: Free functions: `accrue(int256 globalFunding, FundingRate r_adj, uint256 deltaT) -> newGlobalFunding`, `perPositionFunding(uint256 liquidity, int256 globalFunding, int256 baseline) -> int256 funding`

### Kontrol Proofs

- [ ] T031 [P] [I5] Create `test/theta-swap-insurance/kontrol/FundingRateMod.k.sol`: prove convergence direction (p_mark > p_index -> r > 0), prove funding bounds (CFMM-27)
- [ ] T032 [P] [I5] Create `test/theta-swap-insurance/kontrol/JumpPremiumMod.k.sol`: prove jump adjustment non-negative, prove only applies above threshold
- [ ] T033 [P] [I5] Create `test/theta-swap-insurance/kontrol/FundingAccumulatorMod.k.sol`: prove accumulator is bidirectional (can decrease), prove separate from borrow accumulator

### Unit Tests

- [ ] T034 [I5] Write unit tests in `test/theta-swap-insurance/unit/FundingRate.t.sol`: funding at various mark-index divergences, jump premium activation, bidirectional accumulator behavior, edge cases (p_index=0, p_mark=p_index)

**Checkpoint**: Funding mechanism verified. Mark-index convergence direction correct.

---

## Issue 6: PLP Registration & Exit

**Purpose**: PLP borrows LP share, max-price tracking, power-squared exit payoff
**Dependencies**: Issues 1-5 (convergence point)
**Invariants**: INS-06, INS-07, INS-08, INS-10, CFMM-13

### Types

- [ ] T035 [P] [I6] Create `src/theta-swap-insurance/types/PLPPositionMod.sol`: Struct `PLPPosition` (owner, v4PositionId, borrowedLiquidity, maxPriceIndex Q128, borrowGrowthBaseline, fundingGrowthBaseline, premiumFactorQ128, registrationBlock). Free functions: `create(...)`, `updateMaxPrice(ConcentrationPrice p_index) -> updated PLPPosition`, `isActive(PLPPosition) -> bool`
- [ ] T036 [P] [I6] Create `src/theta-swap-insurance/types/ExitPayoffMod.sol`: Free functions: `computePremium(uint256 premiumFactor, uint256 lifetimeFees, uint256 accruedBorrow, int256 accruedFunding) -> premium`, `computePayout(uint256 premium, ConcentrationPrice p_max, ConcentrationPrice p_l, ConcentrationPrice p_u) -> payout = premium * [(p_max/p_l)^2 - 1]^+`, `payoutCap(uint256 premium, ConcentrationPrice p_u, ConcentrationPrice p_l) -> premium * [(p_u/p_l)^2 - 1]`

### Kontrol Proofs

- [ ] T037 [P] [I6] Create `test/theta-swap-insurance/kontrol/PLPPositionMod.k.sol`: prove p_max monotone non-decreasing (INS-06), prove p_max >= p_index at creation
- [ ] T038 [P] [I6] Create `test/theta-swap-insurance/kontrol/ExitPayoffMod.k.sol`: prove payout formula matches INS-07, prove payout <= cap (INS-08), prove payout >= 0

### Implementation

- [ ] T039 [I6] Implement `borrow()` in `src/theta-swap-insurance/ThetaSwapInsurance.sol`: validate pool initialized, validate V4 position active, validate available liquidity, create PLPPosition, update L_borrowed, update utilization, snapshot baselines, emit PLPBorrowed
- [ ] T040 [I6] Implement `exit()` (called from afterRemoveLiquidity or voluntarily) in `src/theta-swap-insurance/ThetaSwapInsurance.sol`: compute premium (base + accrued borrow + accrued funding), compute payout via ExitPayoffMod, cap payout, return LP shares, settle net (payout - premium), update L_borrowed, emit PLPExited
- [ ] T041 [I6] Implement max-price update in `_insuranceAfterSwap()`: for each active PLP, if p_index > p_max_i then p_max_i = p_index (conditional SSTORE)

### Unit Tests

- [ ] T042 [I6] Write unit tests in `test/theta-swap-insurance/unit/PLPLifecycle.t.sol`: borrow happy path + reverts, max-price tracking across multiple callbacks, exit payoff numerical verification against payoff.tex table (Delta*=0.09, p_l=0.0989), exit settlement conservation (INS-10), payout cap enforcement

### Fuzz Tests

- [ ] T043 [P] [I6] Write fuzz tests in `test/theta-swap-insurance/fuzz/ExitPayoff.fuzz.t.sol`: fuzz payout formula for all valid (premium, p_max, p_l, p_u) tuples, verify payout <= cap (INS-08), verify payout >= 0 (INS-07), 10,000+ runs

**Checkpoint**: Full PLP lifecycle verified. Power-squared payoff matches LaTeX spec.

---

## Cross-Cutting Fuzz Tests (after all issues)

- [ ] T044 [P] Write fuzz tests in `test/theta-swap-insurance/fuzz/TradingInvariant.fuzz.t.sol`: psi preserved through random swap sequences (CFMM-03), liquidity additivity at tick crossings (CFMM-08), reserve non-negativity (CFMM-02), 10,000+ runs
- [ ] T045 [P] Write fuzz tests in `test/theta-swap-insurance/fuzz/CollateralSolvency.fuzz.t.sol`: USDC reserve >= numeraire requirement (INS-01), utilization bounded (INS-02), borrow accumulator monotone (INS-05), 10,000+ runs

---

## Dependencies & Execution Order

### Issue Dependencies

- **Issue 1** (Price Rep): No dependencies. Start immediately.
- **Issue 2** (Trading Fn): Depends on Issue 1.
- **Issue 3** (Liquidity Mgmt): Depends on Issues 1, 2.
- **Issue 4** (Borrow/Lend): Depends on Issue 1. Parallel with Issues 2, 3, 5.
- **Issue 5** (Funding Rate): Depends on Issue 1. Parallel with Issues 2, 3, 4.
- **Issue 6** (PLP Lifecycle): Depends on Issues 1-5.

### Parallel Opportunities

**After Issue 1 completes**: Issues 2, 4, 5 can all start simultaneously.

**Within each issue**: Type tasks marked [P] can run in parallel. Kontrol proof tasks marked [P] can run in parallel.

### Critical Path

Issue 1 -> Issue 2 -> Issue 3 -> Issue 6

### MVP

Issue 1 + Issue 2 + Issue 3 = functioning CFMM with concentrated liquidity.
Add Issue 4 + Issue 5 + Issue 6 = full Lendgine insurance market.
