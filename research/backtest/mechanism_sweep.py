"""Mechanism sweep — epoch, decay, and sliding-window accumulation models.

Each mechanism provides a step function and delta_plus computation.
All are pure functions operating on frozen dataclasses.

Per @functional-python.
"""
from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import datetime, timedelta

from backtest.oracle_comparison import PositionExit


# ── Epoch-reset mechanism ──────────────────────────────────────────

@dataclass(frozen=True)
class EpochState:
    """Accumulator state with epoch-based reset."""
    accumulated_sum: float
    theta_sum: float
    removed_pos_count: int
    epoch_start: str
    epoch_length_days: int


def _date_diff_days(d1: str, d2: str) -> int:
    """Days between two YYYY-MM-DD strings."""
    dt1 = datetime.strptime(d1, "%Y-%m-%d")
    dt2 = datetime.strptime(d2, "%Y-%m-%d")
    return (dt2 - dt1).days


def step_epoch(state: EpochState, exit_: PositionExit) -> EpochState:
    """Accumulate exit into epoch state, resetting if epoch boundary crossed."""
    days_since_epoch = _date_diff_days(state.epoch_start, exit_.burn_date)
    x_k_sq = exit_.fee_share_x_k ** 2

    if days_since_epoch >= state.epoch_length_days:
        return EpochState(
            accumulated_sum=x_k_sq / exit_.block_lifetime,
            theta_sum=1.0 / exit_.block_lifetime,
            removed_pos_count=1,
            epoch_start=exit_.burn_date,
            epoch_length_days=state.epoch_length_days,
        )
    else:
        return EpochState(
            accumulated_sum=state.accumulated_sum + x_k_sq / exit_.block_lifetime,
            theta_sum=state.theta_sum + 1.0 / exit_.block_lifetime,
            removed_pos_count=state.removed_pos_count + 1,
            epoch_start=state.epoch_start,
            epoch_length_days=state.epoch_length_days,
        )


def epoch_delta_plus(state: EpochState) -> float:
    """Compute delta-plus from epoch state."""
    if state.removed_pos_count == 0:
        return 0.0
    n_sq = state.removed_pos_count ** 2
    return max(0.0, math.sqrt(state.accumulated_sum) - math.sqrt(state.theta_sum / n_sq))


# ── Exponential-decay mechanism ────────────────────────────────────

@dataclass(frozen=True)
class DecayState:
    """Accumulator state with exponential decay.

    effective_count decays alongside accumulated_sum and theta_sum,
    preventing the N squared denominator from growing unboundedly while
    the numerators decay.
    """
    accumulated_sum: float
    theta_sum: float
    effective_count: float  # decays with same factor as accumulators
    last_update: str
    half_life_days: float


def step_decay(state: DecayState, exit_: PositionExit) -> DecayState:
    """Decay existing state, then accumulate new exit."""
    dt = _date_diff_days(state.last_update, exit_.burn_date)
    if dt > 0:
        lam = math.log(2) / state.half_life_days
        decay = math.exp(-lam * dt)
    else:
        decay = 1.0

    x_k_sq = exit_.fee_share_x_k ** 2
    return DecayState(
        accumulated_sum=state.accumulated_sum * decay + x_k_sq / exit_.block_lifetime,
        theta_sum=state.theta_sum * decay + 1.0 / exit_.block_lifetime,
        effective_count=state.effective_count * decay + 1.0,
        last_update=exit_.burn_date,
        half_life_days=state.half_life_days,
    )


def decay_delta_plus(state: DecayState) -> float:
    """Compute delta-plus from decay state using effective N."""
    if state.effective_count < 1e-10:
        return 0.0
    n_sq = state.effective_count ** 2
    return max(0.0, math.sqrt(state.accumulated_sum) - math.sqrt(state.theta_sum / n_sq))


# ── Sliding-window mechanism ──────────────────────────────────────

@dataclass(frozen=True)
class WindowState:
    """Ring buffer of recent (fee_share_x_k, block_lifetime) entries."""
    entries: tuple[tuple[float, int], ...]
    window_size: int


def step_window(state: WindowState, exit_: PositionExit) -> WindowState:
    """Add exit to window, evicting oldest if at capacity."""
    new_entry = (exit_.fee_share_x_k, exit_.block_lifetime)
    entries = state.entries + (new_entry,)
    if len(entries) > state.window_size:
        entries = entries[1:]
    return WindowState(entries=entries, window_size=state.window_size)


def window_delta_plus(state: WindowState) -> float:
    """Compute delta-plus from window entries only."""
    if not state.entries:
        return 0.0
    n = len(state.entries)
    acc_sum = sum(x_k ** 2 / lifetime for x_k, lifetime in state.entries)
    theta_sum = sum(1.0 / lifetime for _, lifetime in state.entries)
    n_sq = n ** 2
    return max(0.0, math.sqrt(acc_sum) - math.sqrt(theta_sum / n_sq))
