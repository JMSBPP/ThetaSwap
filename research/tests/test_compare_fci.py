"""Tests for compare_fci — mocked RPC responses."""
from __future__ import annotations

from compare_fci import parse_index_response, check_convergence


def test_parse_index_response():
    """Decode (uint128 indexA, uint256 thetaSum, uint256 posCount) from eth_call."""
    # All zeros
    raw = "0x" + "00" * 96
    idx, theta, pos = parse_index_response(raw)
    assert idx == 0
    assert theta == 0
    assert pos == 0


def test_check_convergence_pass():
    result = check_convergence(
        on_chain_index=1000,
        off_chain_index=1005,
        epsilon=0.01,
    )
    assert result.passed is True
    assert result.drift < 0.01


def test_check_convergence_fail():
    result = check_convergence(
        on_chain_index=1000,
        off_chain_index=1200,
        epsilon=0.01,
    )
    assert result.passed is False
    assert result.drift > 0.01
