;; ================================================
;; STX Yield Vault
;; Users can choose lock period when depositing
;; Minimum deposit: any amount > 0
;; ================================================

(define-constant VAULT_OWNER tx-sender)

(define-constant ERR_INVALID_AMOUNT (err u101))
(define-constant ERR_NOT_OWNER      (err u102))
(define-constant ERR_NO_DEPOSIT     (err u103))
(define-constant ERR_INVALID_LOCK   (err u104))
(define-constant ERR_LOCKED         (err u105))

(define-constant CONTRACT_PRINCIPAL .hermesvaultv1)

;; Lock Periods (in blocks)
(define-constant LOCK_5DAYS    u720)     ;; ~5 days
(define-constant LOCK_15DAYS   u2160)    ;; ~15 days
(define-constant LOCK_30DAYS   u4320)    ;; ~30 days
(define-constant LOCK_90DAYS   u12960)   ;; ~90 days
(define-constant LOCK_180DAYS  u25920)   ;; ~180 days

;; Reward Multipliers
(define-constant MULTIPLIER_5DAYS    u100)   ;; 1.00x
(define-constant MULTIPLIER_15DAYS   u120)   ;; 1.20x
(define-constant MULTIPLIER_30DAYS   u140)   ;; 1.40x
(define-constant MULTIPLIER_90DAYS   u175)   ;; 1.75x
(define-constant MULTIPLIER_180DAYS  u220)   ;; 2.20x

;; Data
(define-map deposits principal uint)
(define-map deposit-time principal uint)
(define-map lock-period principal uint)

(define-data-var total-deposited uint u0)
(define-data-var total-rewards uint u0)

;; ===================== DEPOSIT =====================
(define-public (deposit (amount uint) (lock-choice uint))
  (begin
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (or (is-eq lock-choice LOCK_5DAYS)
            (is-eq lock-choice LOCK_15DAYS)
            (is-eq lock-choice LOCK_30DAYS)
            (is-eq lock-choice LOCK_90DAYS)
            (is-eq lock-choice LOCK_180DAYS))
          ERR_INVALID_LOCK)

    (try! (stx-transfer? amount tx-sender CONTRACT_PRINCIPAL))

    (map-set deposits tx-sender 
      (+ (default-to u0 (map-get? deposits tx-sender)) amount))
    
    (map-set deposit-time tx-sender stacks-block-height)
    (map-set lock-period tx-sender lock-choice)

    (var-set total-deposited (+ (var-get total-deposited) amount))
    (ok true)
  )
)

;; ===================== NORMAL WITHDRAW =====================
(define-public (withdraw)
  (let
    (
      (user-deposit (default-to u0 (map-get? deposits tx-sender)))
      (deposit-block (default-to u0 (map-get? deposit-time tx-sender)))
      (user-lock (default-to u0 (map-get? lock-period tx-sender)))
      (user-share (if (> (var-get total-deposited) u0)
                    (/ (* user-deposit u1000000) (var-get total-deposited))
                    u0))
      (base-reward (* (var-get total-rewards) user-share (/ u1000000 u1000000)))
      (multiplier (get-multiplier user-lock))
      (final-reward (/ (* base-reward multiplier) u100))
      (total-to-withdraw (+ user-deposit final-reward))
    )
    (asserts! (> user-deposit u0) ERR_NO_DEPOSIT)
    (asserts! (>= (- stacks-block-height deposit-block) user-lock) ERR_LOCKED)

    (try! (stx-transfer? total-to-withdraw CONTRACT_PRINCIPAL tx-sender))

    (map-set deposits tx-sender u0)
    (map-set deposit-time tx-sender u0)
    (map-set lock-period tx-sender u0)
    (var-set total-deposited (- (var-get total-deposited) user-deposit))

    (ok {
      withdrawn: total-to-withdraw,
      principal: user-deposit,
      rewards: final-reward
    })
  )
)

;; Helper
(define-private (get-multiplier (lock uint))
  (if (is-eq lock LOCK_180DAYS) MULTIPLIER_180DAYS
  (if (is-eq lock LOCK_90DAYS)  MULTIPLIER_90DAYS
  (if (is-eq lock LOCK_30DAYS)  MULTIPLIER_30DAYS
  (if (is-eq lock LOCK_15DAYS)  MULTIPLIER_15DAYS
      MULTIPLIER_5DAYS)))))

;; ===================== EMERGENCY WITHDRAW =====================
(define-public (emergency-withdraw)
  (let ((user-deposit (default-to u0 (map-get? deposits tx-sender))))
    (asserts! (> user-deposit u0) ERR_NO_DEPOSIT)

    (try! (stx-transfer? user-deposit CONTRACT_PRINCIPAL tx-sender))

    (map-set deposits tx-sender u0)
    (map-set deposit-time tx-sender u0)
    (map-set lock-period tx-sender u0)
    (var-set total-deposited (- (var-get total-deposited) user-deposit))

    (ok user-deposit)
  )
)

;; ===================== OWNER FUNCTIONS =====================
(define-public (add-rewards (amount uint))
  (begin
    (asserts! (is-eq tx-sender VAULT_OWNER) ERR_NOT_OWNER)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? amount tx-sender CONTRACT_PRINCIPAL))
    (var-set total-rewards (+ (var-get total-rewards) amount))
    (ok true)
  )
)

(define-public (emergency-drain)
  (begin
    (asserts! (is-eq tx-sender VAULT_OWNER) ERR_NOT_OWNER)
    (let ((balance (stx-get-balance CONTRACT_PRINCIPAL)))
      (try! (stx-transfer? balance CONTRACT_PRINCIPAL VAULT_OWNER))
      (ok balance)
    )
  )
)

;; Read-only
(define-read-only (get-user-deposit (user principal))
  (ok (default-to u0 (map-get? deposits user))))

(define-read-only (get-user-lock-period (user principal))
  (ok (default-to u0 (map-get? lock-period user))))

(define-read-only (get-total-deposited)
  (ok (var-get total-deposited)))