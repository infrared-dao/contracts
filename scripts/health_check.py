#!/usr/bin/env python3
"""
Daily Infrared protocol health check.

Collects on-chain state from mainnet, compares against yesterday's snapshot
from .github/security/health-snapshot.json (persisted via actions/cache),
computes a short set of critical and informational signals, posts a
deterministic digest to Slack, and opens a GitHub issue when any CRITICAL
signal trips.

Scope is deliberately narrow. This is not a replacement for Hypernative or
the infrared-alerts monitor — it surfaces slow-moving protocol-level
health, not per-transaction anomalies.

Signals:

  CRITICAL (opens GH issue + escalation ping in Slack)
    - iBERA accounting: deposits() == pending() + confirmed()
    - Exchange rate monotonic: rate_today >= rate_yesterday
    - IR boost concentration: sum(BGT.boosted(IR, p) for p in IR validators)
      / BGT.boosts(IR) >= 1/2
    - IR unboosted BGT cap: unboosted / (boosts + queued + unboosted) <= 10%
    - iBGT collateralization: iBGT.totalSupply() <= total IR BGT holdings
    - Paused state: none of iBERA / Depositor / Withdrawor paused

  INFO (digest only, no issue)
    - 24h deltas on: iBERA deposits, iBERA totalSupply, exchange rate,
      iBGT totalSupply, BGT.boosts(IR), BGT.queuedBoost(IR),
      BGT.unboostedBalanceOf(IR), FeeReceivor BERA balance
    - Implied iBERA APR from exchange-rate delta (annualized)
    - Validator set diff (added / removed pubkeys)
    - Active validator count
    - Per-validator BGT boost stats (avg / min / max)
    - Per-validator BERA stake stats (avg / min / max)
    - Auctioned vs. IR-allocated validators (Dutch auction winners)
    - Withdrawor reserves vs. queued amount

Environment variables:
  RPC_URL_MAINNET                 required; HTTPS JSON-RPC endpoint
  SLACK_BOT_TOKEN                 required for Slack digest
  INFRARED_HEALTH_CHANNEL_ID      required; dedicated health-digest channel
  GITHUB_TOKEN, GITHUB_REPOSITORY required to open issues on CRITICAL
  INFRARED_ESCALATION_MENTION     optional; prepended when any CRITICAL trips
  GITHUB_STEP_SUMMARY             set by GH Actions
"""

import json
import logging
import os
import sys
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path

import requests
from web3 import Web3
from web3.exceptions import ContractLogicError

log = logging.getLogger("health_check")
logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")

STATE_PATH = Path(".github/security/health-snapshot.json")
HTTP_TIMEOUT = 30
SECONDS_PER_YEAR = 365 * 24 * 60 * 60
BOOST_CONCENTRATION_FLOOR = 1 / 2
UNBOOSTED_BGT_CAP = 0.10  # unboosted / total IR BGT must stay below this

# Mainnet addresses — mirror Makefile defaults
INFRARED = Web3.to_checksum_address("0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126")
IBERA = Web3.to_checksum_address("0x9b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe5")
IBGT = Web3.to_checksum_address("0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b")
BGT = Web3.to_checksum_address("0x656b95E550C07a9ffe548bd4085c72418Ceb1dba")
IBERA_DEPOSITOR = Web3.to_checksum_address("0x04CddC538ea65908106416986aDaeCeFD4CAB7D7")
IBERA_WITHDRAWOR = Web3.to_checksum_address("0x8c0E122960dc2E97dc0059c07d6901Dce72818E1")
IBERA_FEE_RECEIVOR = Web3.to_checksum_address("0xf6a4A6aCECd5311327AE3866624486b6179fEF97")
CUTTING_BOARD_AUCTION = Web3.to_checksum_address("0x50Ab64a24268b79dd10Dab18c59AFeF256E6DC84")

# Minimal ABIs — only the methods this script calls
INFRARED_ABI = [
    {"name": "infraredValidators", "type": "function", "stateMutability": "view",
     "inputs": [], "outputs": [{"type": "tuple[]", "components": [
        {"name": "pubkey", "type": "bytes"},
        {"name": "addr", "type": "address"}]}]},
    {"name": "numInfraredValidators", "type": "function", "stateMutability": "view",
     "inputs": [], "outputs": [{"type": "uint256"}]},
]
IBERA_ABI = [
    {"name": "deposits", "type": "function", "stateMutability": "view",
     "inputs": [], "outputs": [{"type": "uint256"}]},
    {"name": "pending", "type": "function", "stateMutability": "view",
     "inputs": [], "outputs": [{"type": "uint256"}]},
    {"name": "confirmed", "type": "function", "stateMutability": "view",
     "inputs": [], "outputs": [{"type": "uint256"}]},
    {"name": "totalSupply", "type": "function", "stateMutability": "view",
     "inputs": [], "outputs": [{"type": "uint256"}]},
    {"name": "stakes", "type": "function", "stateMutability": "view",
     "inputs": [{"type": "bytes"}], "outputs": [{"type": "uint256"}]},
    {"name": "paused", "type": "function", "stateMutability": "view",
     "inputs": [], "outputs": [{"type": "bool"}]},
]
PAUSABLE_ABI = [
    {"name": "paused", "type": "function", "stateMutability": "view",
     "inputs": [], "outputs": [{"type": "bool"}]},
]
WITHDRAWOR_ABI = [
    {"name": "reserves", "type": "function", "stateMutability": "view",
     "inputs": [], "outputs": [{"type": "uint256"}]},
    {"name": "getQueuedAmount", "type": "function", "stateMutability": "view",
     "inputs": [], "outputs": [{"type": "uint256"}]},
    {"name": "paused", "type": "function", "stateMutability": "view",
     "inputs": [], "outputs": [{"type": "bool"}]},
]
AUCTION_ABI = [
    {"name": "isValidatorAllocated", "type": "function", "stateMutability": "view",
     "inputs": [{"type": "bytes"}], "outputs": [{"type": "bool"}]},
]
IBGT_ABI = [
    {"name": "totalSupply", "type": "function", "stateMutability": "view",
     "inputs": [], "outputs": [{"type": "uint256"}]},
]
BGT_ABI = [
    {"name": "boosts", "type": "function", "stateMutability": "view",
     "inputs": [{"type": "address"}], "outputs": [{"type": "uint128"}]},
    {"name": "queuedBoost", "type": "function", "stateMutability": "view",
     "inputs": [{"type": "address"}], "outputs": [{"type": "uint128"}]},
    {"name": "boosted", "type": "function", "stateMutability": "view",
     "inputs": [{"type": "address"}, {"type": "bytes"}],
     "outputs": [{"type": "uint128"}]},
    {"name": "unboostedBalanceOf", "type": "function", "stateMutability": "view",
     "inputs": [{"type": "address"}], "outputs": [{"type": "uint256"}]},
]


# ---------- snapshot ----------

@dataclass
class Snapshot:
    ts: str
    ibera_deposits: int = 0
    ibera_pending: int = 0
    ibera_confirmed: int = 0
    ibera_total_supply: int = 0
    ibgt_total_supply: int = 0
    bgt_boosts_ir: int = 0
    bgt_queued_ir: int = 0
    bgt_unboosted_ir: int = 0
    validator_pubkeys: list[str] = field(default_factory=list)
    boost_to_own_set: int = 0  # sum of boosted(IR, p) across IR validators
    # Per-validator (aligned with validator_pubkeys). Empty on RPC failure.
    per_validator_boosts: list[int] = field(default_factory=list)
    per_validator_bera_stakes: list[int] = field(default_factory=list)
    # Dutch-auction winners currently controlling IR validator allocations.
    auctioned_pubkeys: list[str] = field(default_factory=list)
    # Operational state.
    fee_receivor_balance: int = 0
    withdrawor_reserves: int = 0
    withdrawor_queued: int = 0
    ibera_paused: bool = False
    depositor_paused: bool = False
    withdrawor_paused: bool = False

    @property
    def exchange_rate(self) -> float:
        # iBERA exchange rate: BERA backing per share. totalSupply == 0 means
        # no shares minted yet (fresh deploy), so the rate is undefined — we
        # surface 0.0 and let signals skip.
        if self.ibera_total_supply == 0:
            return 0.0
        return self.ibera_deposits / self.ibera_total_supply

    @property
    def total_ir_bgt(self) -> int:
        return self.bgt_boosts_ir + self.bgt_queued_ir + self.bgt_unboosted_ir

    @property
    def boost_concentration(self) -> float:
        # Ratio of IR's BGT that lands on IR-operated validators. 1.0 when
        # IR hasn't placed any boosts yet (vacuously concentrated).
        if self.bgt_boosts_ir == 0:
            return 1.0
        return self.boost_to_own_set / self.bgt_boosts_ir

    @property
    def unboosted_fraction(self) -> float:
        total = self.total_ir_bgt
        if total == 0:
            return 0.0
        return self.bgt_unboosted_ir / total


def load_snapshot() -> Snapshot | None:
    if not STATE_PATH.exists():
        return None
    try:
        raw = json.loads(STATE_PATH.read_text())
        # Drop unknown keys so snapshots written by newer schema versions still load.
        known = {f.name for f in Snapshot.__dataclass_fields__.values()}
        filtered = {k: v for k, v in raw.items() if k in known}
        return Snapshot(**filtered)
    except (OSError, json.JSONDecodeError, TypeError) as e:
        log.warning(f"snapshot: failed to read {STATE_PATH}: {e}; treating as first run")
        return None


def save_snapshot(snap: Snapshot) -> None:
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(json.dumps(asdict(snap), indent=2) + "\n")


# ---------- collection ----------

def _collect(w3: Web3) -> Snapshot:
    infrared = w3.eth.contract(address=INFRARED, abi=INFRARED_ABI)
    ibera = w3.eth.contract(address=IBERA, abi=IBERA_ABI)
    ibgt = w3.eth.contract(address=IBGT, abi=IBGT_ABI)
    bgt = w3.eth.contract(address=BGT, abi=BGT_ABI)
    depositor = w3.eth.contract(address=IBERA_DEPOSITOR, abi=PAUSABLE_ABI)
    withdrawor = w3.eth.contract(address=IBERA_WITHDRAWOR, abi=WITHDRAWOR_ABI)
    auction = w3.eth.contract(address=CUTTING_BOARD_AUCTION, abi=AUCTION_ABI)

    validators = infrared.functions.infraredValidators().call()
    pubkeys = [v[0] for v in validators]  # raw bytes
    pubkey_hex = ["0x" + p.hex() for p in pubkeys]

    # Per-validator IR boost + per-validator BERA stake + auction allocation.
    # Set is small (tens, not hundreds); sequential calls are fine, a multicall
    # helper would be overkill. Per-call try/except so one revert doesn't
    # torpedo the whole snapshot.
    per_validator_boosts: list[int] = []
    per_validator_bera_stakes: list[int] = []
    auctioned_pubkeys: list[str] = []
    for pk, pk_hex in zip(pubkeys, pubkey_hex):
        try:
            per_validator_boosts.append(bgt.functions.boosted(INFRARED, pk).call())
        except ContractLogicError as e:
            log.warning(f"bgt.boosted({pk.hex()}) reverted: {e}")
            per_validator_boosts.append(0)
        try:
            per_validator_bera_stakes.append(ibera.functions.stakes(pk).call())
        except ContractLogicError as e:
            log.warning(f"iBERA.stakes({pk.hex()}) reverted: {e}")
            per_validator_bera_stakes.append(0)
        try:
            if auction.functions.isValidatorAllocated(pk).call():
                auctioned_pubkeys.append(pk_hex)
        except ContractLogicError as e:
            log.warning(f"auction.isValidatorAllocated({pk.hex()}) reverted: {e}")

    boost_to_own_set = sum(per_validator_boosts)

    # Pause flags. If a pausable() reverts (e.g., contract isn't Pausable),
    # default to False rather than breaking the snapshot.
    def _paused(contract) -> bool:
        try:
            return bool(contract.functions.paused().call())
        except ContractLogicError as e:
            log.warning(f"paused() reverted on {contract.address}: {e}")
            return False

    return Snapshot(
        ts=datetime.now(timezone.utc).isoformat(timespec="seconds"),
        ibera_deposits=ibera.functions.deposits().call(),
        ibera_pending=ibera.functions.pending().call(),
        ibera_confirmed=ibera.functions.confirmed().call(),
        ibera_total_supply=ibera.functions.totalSupply().call(),
        ibgt_total_supply=ibgt.functions.totalSupply().call(),
        bgt_boosts_ir=bgt.functions.boosts(INFRARED).call(),
        bgt_queued_ir=bgt.functions.queuedBoost(INFRARED).call(),
        bgt_unboosted_ir=bgt.functions.unboostedBalanceOf(INFRARED).call(),
        validator_pubkeys=pubkey_hex,
        boost_to_own_set=boost_to_own_set,
        per_validator_boosts=per_validator_boosts,
        per_validator_bera_stakes=per_validator_bera_stakes,
        auctioned_pubkeys=auctioned_pubkeys,
        fee_receivor_balance=w3.eth.get_balance(IBERA_FEE_RECEIVOR),
        withdrawor_reserves=withdrawor.functions.reserves().call(),
        withdrawor_queued=withdrawor.functions.getQueuedAmount().call(),
        ibera_paused=_paused(ibera),
        depositor_paused=_paused(depositor),
        withdrawor_paused=_paused(withdrawor),
    )


def collect_snapshot(rpc_url: str) -> Snapshot:
    w3 = Web3(Web3.HTTPProvider(rpc_url, request_kwargs={"timeout": HTTP_TIMEOUT}))
    if not w3.is_connected():
        raise RuntimeError("RPC not reachable")
    return _collect(w3)


# ---------- signals ----------

@dataclass
class Signal:
    name: str
    severity: str  # "critical" | "info"
    triggered: bool
    detail: str


def _fmt_wei(x: int) -> str:
    """Format a uint256 as ether-scaled string with 4 decimals."""
    if x == 0:
        return "0"
    return f"{x / 1e18:,.4f}"


def _fmt_delta(current: int, prior: int | None) -> str:
    """Format a uint256 as `current (Δ, pct%)`. Falls back cleanly on first run."""
    if prior is None:
        return f"{_fmt_wei(current)} (Δ n/a, first run)"
    delta = current - prior
    pct = (delta / prior * 100) if prior else 0.0
    sign = "+" if delta >= 0 else ""
    return f"{_fmt_wei(current)} ({sign}{_fmt_wei(delta)}, {sign}{pct:.2f}%)"


def _fmt_delta_float(current: float, prior: float | None, precision: int = 10) -> str:
    """Like _fmt_delta but for ratios / floats (exchange rate, concentration)."""
    if prior is None or prior == 0:
        return f"{current:.{precision}f} (no baseline)"
    delta = current - prior
    pct = delta / prior * 100
    sign = "+" if delta >= 0 else ""
    return f"{current:.{precision}f} ({sign}{delta:.{precision}f}, {sign}{pct:.2f}%)"


def _fmt_pct(fraction: float) -> str:
    return f"{fraction * 100:.2f}%"


def _fmt_stats_wei(values: list[int]) -> str:
    """Format a list of wei amounts as `total=X avg=Y min=Z max=W (n=N)`."""
    if not values:
        return "n/a (no data)"
    n = len(values)
    total = sum(values)
    avg = total // n
    return (f"total={_fmt_wei(total)} avg={_fmt_wei(avg)} "
            f"min={_fmt_wei(min(values))} max={_fmt_wei(max(values))} (n={n})")


def compute_signals(current: Snapshot, prior: Snapshot | None) -> list[Signal]:
    sigs: list[Signal] = []

    # --- CRITICAL ---

    # Accounting reconciliation.
    accounting_diff = current.ibera_deposits - (current.ibera_pending + current.ibera_confirmed)
    sigs.append(Signal(
        name="iBERA accounting",
        severity="critical",
        triggered=accounting_diff != 0,
        detail=(f"deposits={_fmt_wei(current.ibera_deposits)}, "
                f"pending+confirmed={_fmt_wei(current.ibera_pending + current.ibera_confirmed)}, "
                f"diff={accounting_diff}"),
    ))

    # Exchange-rate monotonicity. Only meaningful on a run with a prior
    # snapshot AND both sides having minted shares.
    if prior is not None and prior.exchange_rate > 0 and current.exchange_rate > 0:
        dropped = current.exchange_rate < prior.exchange_rate
        sigs.append(Signal(
            name="iBERA exchange rate monotonic",
            severity="critical",
            triggered=dropped,
            detail=f"prior={prior.exchange_rate:.10f}, current={current.exchange_rate:.10f}",
        ))

    # Boost concentration ≥ floor (see BOOST_CONCENTRATION_FLOOR).
    ratio = current.boost_concentration
    prior_ratio = prior.boost_concentration if prior is not None else None
    sigs.append(Signal(
        name="IR boost concentration",
        severity="critical",
        triggered=ratio < BOOST_CONCENTRATION_FLOOR,
        detail=(f"{_fmt_pct(ratio)} of IR's {_fmt_wei(current.bgt_boosts_ir)} BGT boost "
                f"lands on {len(current.validator_pubkeys)} IR validators "
                f"(floor: {_fmt_pct(BOOST_CONCENTRATION_FLOOR)}, "
                f"Δ={_fmt_delta_float(ratio, prior_ratio, 4)})"),
    ))

    # Unboosted-BGT cap. Unboosted BGT is idle — keepers should be queueing
    # it into boosts. Sustained high unboosted fraction means harvests are
    # piling up faster than boost activation, or queueBoost is broken.
    unboosted_frac = current.unboosted_fraction
    prior_unboosted = prior.unboosted_fraction if prior is not None else None
    sigs.append(Signal(
        name="IR unboosted BGT cap",
        severity="critical",
        triggered=unboosted_frac > UNBOOSTED_BGT_CAP,
        detail=(f"{_fmt_pct(unboosted_frac)} of {_fmt_wei(current.total_ir_bgt)} total IR BGT "
                f"is unboosted (cap: {_fmt_pct(UNBOOSTED_BGT_CAP)}, "
                f"Δ={_fmt_delta_float(unboosted_frac, prior_unboosted, 4)})"),
    ))

    # iBGT collateralization: every iBGT in circulation must be backed by
    # BGT in Infrared (whether boosted, queued, or unboosted). Undercollat
    # means someone minted iBGT without the corresponding BGT backing.
    undercollat = current.ibgt_total_supply > current.total_ir_bgt
    cover_ratio = (current.total_ir_bgt / current.ibgt_total_supply
                   if current.ibgt_total_supply else float("inf"))
    sigs.append(Signal(
        name="iBGT collateralization",
        severity="critical",
        triggered=undercollat,
        detail=(f"total IR BGT={_fmt_wei(current.total_ir_bgt)}, "
                f"iBGT supply={_fmt_wei(current.ibgt_total_supply)}, "
                f"coverage={cover_ratio:.4f}x"),
    ))

    # Pause flags. Any paused staking contract blocks user flows and should
    # page immediately — these toggles are governance-only and rare.
    pause_flags = {
        "iBERA": current.ibera_paused,
        "Depositor": current.depositor_paused,
        "Withdrawor": current.withdrawor_paused,
    }
    paused_names = [k for k, v in pause_flags.items() if v]
    sigs.append(Signal(
        name="iBERA pause state",
        severity="critical",
        triggered=bool(paused_names),
        detail=("paused: " + ", ".join(paused_names)) if paused_names
               else "iBERA, Depositor, Withdrawor all unpaused",
    ))

    # --- INFO ---

    prior_or = lambda attr: getattr(prior, attr) if prior is not None else None

    sigs.append(Signal(
        name="iBERA deposits Δ24h",
        severity="info", triggered=False,
        detail=_fmt_delta(current.ibera_deposits, prior_or("ibera_deposits")),
    ))
    sigs.append(Signal(
        name="iBERA totalSupply Δ24h",
        severity="info", triggered=False,
        detail=_fmt_delta(current.ibera_total_supply, prior_or("ibera_total_supply")),
    ))
    prior_rate = prior.exchange_rate if prior is not None and prior.exchange_rate > 0 else None
    if prior_rate is not None and current.exchange_rate > 0:
        rate_delta = current.exchange_rate - prior_rate
        # Annualize assuming ~24h between snapshots; cron pins this.
        apr = (rate_delta / prior_rate) * 365 * 100
        sigs.append(Signal(
            name="iBERA exchange rate Δ24h",
            severity="info", triggered=False,
            detail=f"{_fmt_delta_float(current.exchange_rate, prior_rate, 10)}, "
                   f"implied APR={apr:+.2f}%",
        ))
    else:
        sigs.append(Signal(
            name="iBERA exchange rate Δ24h",
            severity="info", triggered=False,
            detail=f"current={current.exchange_rate:.10f} (no baseline)",
        ))

    sigs.append(Signal(
        name="iBGT totalSupply Δ24h",
        severity="info", triggered=False,
        detail=_fmt_delta(current.ibgt_total_supply, prior_or("ibgt_total_supply")),
    ))
    sigs.append(Signal(
        name="IR BGT boosts Δ24h",
        severity="info", triggered=False,
        detail=_fmt_delta(current.bgt_boosts_ir, prior_or("bgt_boosts_ir")),
    ))
    sigs.append(Signal(
        name="IR BGT queued boost",
        severity="info", triggered=False,
        detail=_fmt_delta(current.bgt_queued_ir, prior_or("bgt_queued_ir")),
    ))
    sigs.append(Signal(
        name="IR unboosted BGT",
        severity="info", triggered=False,
        detail=_fmt_delta(current.bgt_unboosted_ir, prior_or("bgt_unboosted_ir")),
    ))
    sigs.append(Signal(
        name="Total IR BGT holdings",
        severity="info", triggered=False,
        detail=_fmt_delta(current.total_ir_bgt,
                          prior.total_ir_bgt if prior is not None else None),
    ))

    # FeeReceivor balance — EL rewards (priority fees + MEV) awaiting sweep.
    # A monotonically growing balance across multiple days means the sweep
    # keeper is wedged or compound() isn't being called.
    sigs.append(Signal(
        name="FeeReceivor BERA balance",
        severity="info", triggered=False,
        detail=_fmt_delta(current.fee_receivor_balance,
                          prior_or("fee_receivor_balance")),
    ))

    # Withdrawor reserves vs. queued amount. Shortage means withdrawal
    # claimants will be blocked until validator exits process.
    shortage = current.withdrawor_queued - current.withdrawor_reserves
    if shortage > 0:
        q_detail = (f"reserves={_fmt_wei(current.withdrawor_reserves)}, "
                    f"queued={_fmt_wei(current.withdrawor_queued)}, "
                    f"shortage={_fmt_wei(shortage)}")
    else:
        q_detail = (f"reserves={_fmt_wei(current.withdrawor_reserves)}, "
                    f"queued={_fmt_wei(current.withdrawor_queued)}, "
                    f"surplus={_fmt_wei(-shortage)}")
    sigs.append(Signal(
        name="Withdrawor reserves",
        severity="info", triggered=False,
        detail=q_detail,
    ))

    # Per-validator stake stats. Unevenness is fine (stake migrates as
    # operators rotate), but surfaces the spread so operators can spot
    # skew before it matters.
    sigs.append(Signal(
        name="Per-validator BGT boost",
        severity="info", triggered=False,
        detail=_fmt_stats_wei(current.per_validator_boosts),
    ))
    sigs.append(Signal(
        name="Per-validator BERA stake",
        severity="info", triggered=False,
        detail=_fmt_stats_wei(current.per_validator_bera_stakes),
    ))

    # Dutch-auction winners currently controlling IR validator allocations.
    # High count relative to total = more of the cutting board is set by
    # external bidders rather than IR's chosen allocations.
    auctioned = current.auctioned_pubkeys
    n_val = len(current.validator_pubkeys)
    n_auctioned = len(auctioned)
    prior_auctioned = set(prior.auctioned_pubkeys) if prior is not None else set()
    current_auctioned_set = set(auctioned)
    newly_auctioned = sorted(current_auctioned_set - prior_auctioned)
    exited_auction = sorted(prior_auctioned - current_auctioned_set)
    auction_parts = [f"{n_auctioned}/{n_val} auctioned, "
                     f"{n_val - n_auctioned} IR-allocated"]
    if newly_auctioned:
        auction_parts.append(f"+{len(newly_auctioned)}: "
                             f"{', '.join(p[:14] + '…' for p in newly_auctioned)}")
    if exited_auction:
        auction_parts.append(f"-{len(exited_auction)}: "
                             f"{', '.join(p[:14] + '…' for p in exited_auction)}")
    sigs.append(Signal(
        name="Auctioned validators",
        severity="info", triggered=False,
        detail="; ".join(auction_parts),
    ))

    # Validator set diff + count.
    if prior is not None:
        prior_set = set(prior.validator_pubkeys)
        current_set = set(current.validator_pubkeys)
        added = sorted(current_set - prior_set)
        removed = sorted(prior_set - current_set)
        if added or removed:
            parts = []
            if added:
                parts.append(f"+{len(added)}: {', '.join(p[:14] + '…' for p in added)}")
            if removed:
                parts.append(f"-{len(removed)}: {', '.join(p[:14] + '…' for p in removed)}")
            detail = "; ".join(parts)
        else:
            detail = "no change"
        sigs.append(Signal(
            name="Validator set diff", severity="info", triggered=False, detail=detail))
    sigs.append(Signal(
        name="Active validator count",
        severity="info", triggered=False,
        detail=str(len(current.validator_pubkeys)),
    ))

    return sigs


# ---------- digest rendering ----------

def render_digest(current: Snapshot, prior: Snapshot | None, signals: list[Signal]) -> str:
    lines = ["*Infrared daily health check — mainnet*"]
    lines.append(f"`{current.ts}`")
    if prior is not None:
        lines.append(f"_Comparing against snapshot from {prior.ts}._")
    else:
        lines.append("_First run — no baseline yet. Delta signals will appear tomorrow._")

    criticals = [s for s in signals if s.severity == "critical"]
    lines.append("")
    lines.append("*Critical checks*")
    for s in criticals:
        icon = ":red_circle:" if s.triggered else ":large_green_circle:"
        lines.append(f"{icon} `{s.name}` — {s.detail}")

    infos = [s for s in signals if s.severity == "info"]
    lines.append("")
    lines.append("*Info (24h deltas)*")
    for s in infos:
        lines.append(f"• `{s.name}`: {s.detail}")
    return "\n".join(lines)


# ---------- headline ----------

def render_headline(current: Snapshot, prior: Snapshot | None, signals: list[Signal]) -> str:
    """One-line deterministic summary for the top of the Slack digest."""
    criticals = [s for s in signals if s.severity == "critical"]
    tripped = [s for s in criticals if s.triggered]

    if tripped:
        detail = "; ".join(f"`{s.name}` — {s.detail}" for s in tripped)
        return f":red_circle: {len(tripped)}/{len(criticals)} critical tripped: {detail}"

    parts = [f":large_green_circle: All {len(criticals)} critical checks green."]

    if prior is not None and prior.ibera_total_supply > 0:
        supply_pct = (current.ibera_total_supply - prior.ibera_total_supply) / prior.ibera_total_supply * 100
        parts.append(f"iBERA supply {supply_pct:+.2f}%")
        if prior.exchange_rate > 0 and current.exchange_rate > 0:
            rate_pct = (current.exchange_rate - prior.exchange_rate) / prior.exchange_rate * 100
            apr = rate_pct * 365
            parts.append(f"rate {rate_pct:+.4f}% (APR {apr:+.2f}%)")
        parts.append(f"unboosted {_fmt_pct(current.unboosted_fraction)}")
    else:
        # First-run fallback — surface the key steady-state readings so the
        # first digest is useful even without deltas.
        parts.append(f"{len(current.validator_pubkeys)} validators "
                     f"({len(current.auctioned_pubkeys)} auctioned)")
        parts.append(f"boost concentration {_fmt_pct(current.boost_concentration)}")
        parts.append(f"unboosted {_fmt_pct(current.unboosted_fraction)}")

    return " ".join(parts[:1]) + " " + ", ".join(parts[1:]) + "."


# ---------- slack ----------

def post_to_slack(channel: str, text: str) -> bool:
    token = os.environ.get("SLACK_BOT_TOKEN")
    if not token or not channel:
        log.warning("slack: missing token or channel; skipping post")
        return False
    try:
        r = requests.post(
            "https://slack.com/api/chat.postMessage",
            headers={"Authorization": f"Bearer {token}",
                     "Content-Type": "application/json; charset=utf-8"},
            json={"channel": channel, "text": text, "mrkdwn": True},
            timeout=HTTP_TIMEOUT,
        )
        r.raise_for_status()
        payload = r.json()
        if not payload.get("ok"):
            log.warning(f"slack: post failed: {payload.get('error')}")
            return False
        return True
    except Exception as e:
        log.warning(f"slack: post failed: {e}")
        return False


# ---------- github issue ----------

def open_issue(title: str, body: str) -> str | None:
    token = os.environ.get("GITHUB_TOKEN")
    repo = os.environ.get("GITHUB_REPOSITORY")
    if not token or not repo:
        log.warning("github: missing token or repo; skipping issue")
        return None
    try:
        r = requests.post(
            f"https://api.github.com/repos/{repo}/issues",
            headers={"Authorization": f"Bearer {token}",
                     "Accept": "application/vnd.github+json"},
            json={"title": title, "body": body, "labels": ["health-check", "critical"]},
            timeout=HTTP_TIMEOUT,
        )
        r.raise_for_status()
        return r.json().get("html_url")
    except Exception as e:
        log.warning(f"github: issue creation failed: {e}")
        return None


def append_step_summary(text: str) -> None:
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not path:
        return
    try:
        with open(path, "a") as f:
            f.write(text + "\n")
    except OSError as e:
        log.warning(f"step summary: write failed: {e}")


# ---------- main ----------

def main() -> int:
    rpc_url = os.environ.get("RPC_URL_MAINNET")
    if not rpc_url:
        log.error("RPC_URL_MAINNET is required")
        return 2

    channel = os.environ.get("INFRARED_HEALTH_CHANNEL_ID", "")

    log.info("collecting current snapshot")
    current = collect_snapshot(rpc_url)
    prior = load_snapshot()
    signals = compute_signals(current, prior)

    tripped = [s for s in signals if s.triggered]
    headline = render_headline(current, prior, signals)
    digest = render_digest(current, prior, signals)
    slack_text = headline + "\n\n" + digest

    # Always print to stdout so `make health-check-daily` (no Slack/GH
    # tokens) is genuinely useful standalone.
    print(slack_text)

    if tripped:
        mention = os.environ.get("INFRARED_ESCALATION_MENTION", "").strip()
        if mention:
            slack_text = f"{mention} " + slack_text

    posted = post_to_slack(channel, slack_text)
    log.info(f"slack post: {'ok' if posted else 'skipped/failed'}")

    issue_url = None
    if tripped:
        body_lines = [
            "Automated health check tripped one or more CRITICAL signals.",
            "",
            "## Tripped signals",
            "",
        ]
        for s in tripped:
            body_lines.append(f"- **{s.name}** — {s.detail}")
        body_lines += ["", "## Full digest", "", digest]
        issue_title = f"health-check: {len(tripped)} critical signal(s) — {current.ts[:10]}"
        issue_url = open_issue(issue_title, "\n".join(body_lines))
        if issue_url:
            log.info(f"issue opened: {issue_url}")

    summary = ["# Infrared health check", "", digest]
    if issue_url:
        summary += ["", f"Issue: {issue_url}"]
    append_step_summary("\n".join(summary))

    save_snapshot(current)
    log.info(f"snapshot saved: {STATE_PATH}")

    # Never fail the workflow on tripped signals — digest + issue + step
    # summary already surface them. A non-zero exit would only mask the
    # signal behind a red X.
    return 0


if __name__ == "__main__":
    sys.exit(main())
