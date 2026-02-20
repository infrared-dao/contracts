# Vendors

Third-party contract modifications used by the Infrared protocol. These files are vendored (copied locally) rather than imported from package dependencies to allow targeted modifications that upstream packages do not support.

## Contracts

### `ERC20PresetMinterPauser.sol`

A role-based ERC-20 preset extending OpenZeppelin's standard implementation with four access control roles:

| Role | Permission |
|------|-----------|
| `DEFAULT_ADMIN_ROLE` | Grants/revokes all other roles |
| `MINTER_ROLE` | Call `mint()` |
| `PAUSER_ROLE` | Call `pause()` / `unpause()` |
| `BURNER_ROLE` | Call `burn()` (skipped if zero address) |

**Constructor:** `constructor(admin, minter, pauser, burner)` — all roles set at deploy time.

Used as the base token contract for IR and similar protocol tokens.

---

### `CustomPausable.sol`

A modified version of OpenZeppelin's `Pausable` (v5.1.0) that changes the pause semantics: **transfers are always allowed**, but minting and burning are blocked when paused.

**Modification from upstream:**

Standard OpenZeppelin `Pausable` blocks all `_update()` calls (including transfers) when paused. `CustomPausable` overrides `_update()` to only enforce the pause check when `from == address(0)` (mint) or `to == address(0)` (burn), leaving peer-to-peer transfers unrestricted.

This is intentional: pausing IR token issuance during an emergency should not prevent users from moving tokens they already hold.

## Why Vendor?

- `ERC20PresetMinterPauser` — the upstream OpenZeppelin preset does not include a separate `BURNER_ROLE`; the local copy adds it
- `CustomPausable` — the upstream `Pausable` blocks all transfers; the local copy restricts only mint/burn, which is a behavioral change that cannot be achieved by subclassing alone
