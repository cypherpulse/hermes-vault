![Stacks](https://img.shields.io/badge/Stacks-000000?style=for-the-badge&logo=stacks&logoColor=white)
![Clarity%20v3](https://img.shields.io/badge/Clarity%20v3-2E3A59?style=for-the-badge)
![Clarinet](https://img.shields.io/badge/Clarinet-3.x-4B8DF8?style=for-the-badge)
![Tests](https://img.shields.io/badge/Tests-Vitest-6E57FF?style=for-the-badge)

# HermesVault

HermesVault is a Clarity smart contract that accepts STX deposits with lock periods and distributes rewards on withdrawal. It includes owner controls (pause, owner rotation, emergency drain) and on-chain events for operational visibility.

## Table of contents

1. Overview
2. Contracts
3. Architecture
4. System flow
5. Design drawing
6. Core behavior
7. Owner controls
8. Events
9. Errors
10. Testing
11. Deployment notes

## 1. Overview

Users deposit STX with a chosen lock period. The vault tracks deposits per account and calculates rewards using a reward-per-token accumulator. Rewards are funded by the owner via `add-rewards` and paid out on withdrawal. The contract enforces lock periods and supports pause/unpause for incident response.

## 2. Contracts

- `contracts/hermesvaultv3.clar` (Clarity v3)

## 3. Architecture

```mermaid
flowchart LR
	U[User] -->|deposit| V[HermesVault]
	O[Owner] -->|add-rewards| V
	V -->|withdraw| U
	O -->|pause/unpause| V
	O -->|emergency-drain| V
	V -->|events| L[Print Logs]
```

## 4. System flow

```mermaid
sequenceDiagram
	participant User
	participant Vault
	participant Owner

	User->>Vault: deposit(amount, lock)
	Vault->>Vault: settle-rewards(user)
	Vault->>Vault: update deposits + lock
	Vault-->>User: ok true

	Owner->>Vault: add-rewards(amount)
	Vault->>Vault: update reward-per-token
	Vault-->>Owner: ok true

	User->>Vault: withdraw()
	Vault->>Vault: settle-rewards(user)
	Vault->>Vault: check lock
	Vault-->>User: STX payout + event
```

## 5. Design drawing

```mermaid
graph TD
	subgraph Storage
		D[deposits: principal->uint]
		T[deposit-time: principal->uint]
		L[lock-period: principal->uint]
		R[accrued-rewards: principal->uint]
		B[reward-debt: principal->uint]
		G[global: total-deposited, reward-per-token]
	end

	subgraph Actions
		A1[deposit]
		A2[withdraw]
		A3[add-rewards]
		A4[pause/unpause]
		A5[set-owner]
		A6[emergency-drain]
	end

	A1 --> D
	A1 --> T
	A1 --> L
	A1 --> G
	A2 --> D
	A2 --> T
	A2 --> L
	A2 --> R
	A2 --> B
	A2 --> G
	A3 --> G
```

## 6. Core behavior

### Deposits

- Validates amount and lock choice.
- Transfers STX to the contract.
- Updates per-user maps and totals.
- Emits a `deposit` print event.

### Withdrawals

- Requires an active deposit and lock expiration.
- Settles rewards and applies a lock-based multiplier.
- Transfers principal + rewards from the vault.
- Resets user state.
- Emits a `withdraw` print event.

### Rewards

- Rewards are funded by the owner via `add-rewards`.
- `reward-per-token` distributes rewards proportional to deposits.
- `settle-rewards` snapshots per-user accrual on state changes.

## 7. Owner controls

- `set-owner(new-owner)` rotates control to a new principal.
- `pause()` and `unpause()` prevent deposits and withdrawals.
- `emergency-drain()` withdraws all STX to the current owner.

## 8. Events

Print events are emitted for:

- `deposit`
- `withdraw`
- `add-rewards`
- `pause` / `unpause`
- `set-owner`
- `emergency-drain`

These are useful for indexers and operational monitoring.

## 9. Errors

- `ERR_INVALID_AMOUNT` (u101)
- `ERR_NOT_OWNER` (u102)
- `ERR_NO_DEPOSIT` (u103)
- `ERR_INVALID_LOCK` (u104)
- `ERR_LOCKED` (u105)
- `ERR_PAUSED` (u106)
- `ERR_INVALID_OWNER` (u107)

## 10. Testing

```bash
npm install
npm test
```

The test suite covers deposits, withdrawals, lock enforcement, reward distribution, owner controls, and pause behavior.

## 11. Deployment notes

- Use Clarity v3 on mainnet to keep `as-contract` support.
- Ensure your deployment plan uses `clarity_version = 3`.
- Confirm the contract name matches the principal literal in `CONTRACT_PRINCIPAL`.
