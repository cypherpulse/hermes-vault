![Stacks](https://img.shields.io/badge/Stacks-000000?style=for-the-badge&logo=stacks&logoColor=white)
![Clarity%20v4](https://img.shields.io/badge/Clarity%20v4-2E3A59?style=for-the-badge)
![Clarinet](https://img.shields.io/badge/Clarinet-3.17.0-4B8DF8?style=for-the-badge)

# Clarity v4 migration notes

This document summarizes the changes made to migrate the HermesVault contract from Clarity v1 to Clarity v4. It is structured as a before/after guide so you can quickly map legacy patterns to their Clarity v4 equivalents.

## Table of contents

- [Clarity v4 migration notes](#clarity-v4-migration-notes)
  - [Table of contents](#table-of-contents)
  - [1. Overview](#1-overview)
  - [2. Deployment plan requirements](#2-deployment-plan-requirements)
  - [3. Language changes](#3-language-changes)
    - [Removed `as-contract`](#removed-as-contract)
  - [4. Contract principal handling](#4-contract-principal-handling)
  - [5. Block height usage](#5-block-height-usage)
  - [6. Tuple literal syntax](#6-tuple-literal-syntax)
  - [7. Lint and safety checks](#7-lint-and-safety-checks)
  - [8. Final checklist](#8-final-checklist)

## 1. Overview

The original contract was written with Clarity v1 expectations. Clarity v4 removes some legacy helpers and enforces stricter syntax and linting. We updated the contract to remove unsupported features, update block height access, and align with Clarity v4 lint rules.

## 2. Deployment plan requirements

Clarity v4 requires a deployment plan targeting an epoch where Clarity v4 is supported.

Old plan (Clarity v1):

```yaml
clarity-version: 1
epoch: '2.05'
```

New plan (Clarity v4):

```yaml
clarity-version: 4
epoch: '3.0'
```

Without this change, the network compiles the contract as Clarity v1 and rejects v4-only syntax or behavior.

## 3. Language changes

### Removed `as-contract`

Clarity v4 removes `as-contract`. Any use will fail at deployment.

Old pattern:

```clarity
(as-contract (try! (stx-transfer? amount tx-sender tx-sender)))
```

New pattern:

```clarity
(try! (stx-transfer? amount CONTRACT_PRINCIPAL tx-sender))
```

## 4. Contract principal handling

Clarity v1 relied on `as-contract` to access the contract principal. In Clarity v4, use the contract principal literal instead.

Old:

```clarity
(define-constant CONTRACT_PRINCIPAL (as-contract tx-sender))
```

New:

```clarity
(define-constant CONTRACT_PRINCIPAL .hermesvaultv1)
```

This literal must match the deployed contract name.

## 5. Block height usage

Clarity v3+ removes `block-height` and replaces it with `stacks-block-height`.

Old:

```clarity
(map-set deposit-time tx-sender block-height)
(asserts! (>= (- block-height deposit-block) user-lock) ERR_LOCKED)
```

New:

```clarity
(map-set deposit-time tx-sender stacks-block-height)
(asserts! (>= (- stacks-block-height deposit-block) user-lock) ERR_LOCKED)
```

## 6. Tuple literal syntax

Clarity v4 enforces tuple keys as atoms, not strings.

Old:

```clarity
(ok {
	"withdrawn": total-to-withdraw,
	"principal": user-deposit,
	"rewards": final-reward
})
```

New:

```clarity
(ok {
	withdrawn: total-to-withdraw,
	principal: user-deposit,
	rewards: final-reward
})
```

## 7. Lint and safety checks

Clarity v4 linting is stricter. We made the following updates:

- Constants renamed to SCREAMING_SNAKE_CASE to satisfy `case_const`.
- Removed unused constants (e.g., unused error codes).
- Added an amount validation in `add-rewards` so inputs are not flagged as unchecked.

Old:

```clarity
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant VAULT-OWNER tx-sender)

(define-public (add-rewards (amount uint))
	(begin
		(asserts! (is-eq tx-sender VAULT-OWNER) ERR-NOT-OWNER)
		(try! (stx-transfer? amount tx-sender CONTRACT_PRINCIPAL))
		(var-set total-rewards (+ (var-get total-rewards) amount))
		(ok true)
	)
)
```

New:

```clarity
(define-constant ERR_INVALID_AMOUNT (err u101))
(define-constant VAULT_OWNER tx-sender)

(define-public (add-rewards (amount uint))
	(begin
		(asserts! (is-eq tx-sender VAULT_OWNER) ERR_NOT_OWNER)
		(asserts! (> amount u0) ERR_INVALID_AMOUNT)
		(try! (stx-transfer? amount tx-sender CONTRACT_PRINCIPAL))
		(var-set total-rewards (+ (var-get total-rewards) amount))
		(ok true)
	)
)
```

## 8. Final checklist

- Contract compiles under Clarity v4 with `clarinet check`.
- Deployment plan targets Clarity v4 and epoch 3.0 or later.
- No `as-contract` usage remains.
- Block height uses `stacks-block-height`.
- Tuple literals use atom keys.
- Constants follow SCREAMING_SNAKE_CASE.

If you rename the contract, update `CONTRACT_PRINCIPAL` accordingly.
