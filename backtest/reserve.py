"""Reserve simulation — pure function per @functional-python."""
from __future__ import annotations

from backtest.types import DailyPoolState, ReserveState


def simulate_reserve(
    daily_states: list[DailyPoolState],
    exits_per_day: dict[str, int],
    gamma: float,
    delta_star: float = 0.09,
) -> list[ReserveState]:
    """Simulate insurance reserve day-by-day.

    Per day:
    1. Premium in: n_exits * gamma * (pool_daily_fee / n_positions)
    2. Trigger check: if delta_plus > delta_star and balance > 0,
       D = (delta_plus - delta_star) / (1 - delta_star) * balance,
       payout = min(D, balance), balance -= payout
    """
    balance = 0.0
    result: list[ReserveState] = []

    for state in daily_states:
        n_exits = exits_per_day.get(state.day, 0)

        # Step 1: collect premiums
        if state.n_positions > 0 and n_exits > 0:
            premium = n_exits * gamma * (state.pool_daily_fee / state.n_positions)
        else:
            premium = 0.0
        balance += premium

        # Step 2: trigger check and payout
        trigger_fired = False
        payout = 0.0
        donate_amount = 0.0

        if state.delta_plus > delta_star and balance > 0:
            trigger_fired = True
            d = (state.delta_plus - delta_star) / (1.0 - delta_star) * balance
            payout = min(d, balance)
            balance -= payout

        result.append(ReserveState(
            day=state.day,
            balance=balance,
            premium_in=premium,
            payout_out=payout,
            trigger_fired=trigger_fired,
            delta_plus=state.delta_plus,
            donate_amount=donate_amount,
        ))

    return result
