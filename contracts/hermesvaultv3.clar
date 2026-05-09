;; ================================================
;; STX Yield Vault
;; Users can choose lock period when depositing
;; Minimum deposit: any amount > 0
;; ================================================

(define-constant ERR_INVALID_AMOUNT (err u101))
(define-constant ERR_NOT_OWNER      (err u102))
(define-constant ERR_NO_DEPOSIT     (err u103))
(define-constant ERR_INVALID_LOCK   (err u104))
(define-constant ERR_LOCKED         (err u105))
(define-constant ERR_PAUSED         (err u106))
(define-constant ERR_INVALID_OWNER  (err u107))

(define-constant CONTRACT_PRINCIPAL .hermesvaultv000)
(define-constant REWARD_PRECISION u1000000)

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
(define-map reward-debt principal uint)
(define-map accrued-rewards principal uint)

(define-data-var total-deposited uint u0)
(define-data-var total-rewards uint u0)
(define-data-var reward-per-token uint u0)
(define-data-var unallocated-rewards uint u0)
(define-data-var paused bool false)
(define-data-var vault-owner principal tx-sender)

(define-private (assert-not-paused)
  (begin
    (asserts! (not (var-get paused)) ERR_PAUSED)
    (ok true)))

(define-private (assert-owner)
  (begin
    (asserts! (is-eq tx-sender (var-get vault-owner)) ERR_NOT_OWNER)
    (ok true)))

(define-private (distribute-rewards (amount uint))
  (if (> (var-get total-deposited) u0)
      (begin
        (var-set reward-per-token
          (+ (var-get reward-per-token)
             (/ (* amount REWARD_PRECISION) (var-get total-deposited))))
        true)
      (begin
        (var-set unallocated-rewards (+ (var-get unallocated-rewards) amount))
        true)))

(define-private (settle-rewards (user principal))
  (let
    (
      (balance (default-to u0 (map-get? deposits user)))
      (rpt (var-get reward-per-token))
      (debt (default-to u0 (map-get? reward-debt user)))
      (accrued (default-to u0 (map-get? accrued-rewards user)))
      (gross (/ (* balance rpt) REWARD_PRECISION))
      (pending (if (> gross debt) (- gross debt) u0))
    )
    (map-set accrued-rewards user (+ accrued pending))
    (map-set reward-debt user gross)
    pending))

;; ===================== DEPOSIT =====================
(define-public (deposit (amount uint) (lock-choice uint))
  (begin
    (try! (assert-not-paused))
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (or (is-eq lock-choice LOCK_5DAYS)
            (is-eq lock-choice LOCK_15DAYS)
            (is-eq lock-choice LOCK_30DAYS)
            (is-eq lock-choice LOCK_90DAYS)
            (is-eq lock-choice LOCK_180DAYS))
          ERR_INVALID_LOCK)

    (try! (stx-transfer? amount tx-sender CONTRACT_PRINCIPAL))

    (let ((previous-total (var-get total-deposited)))
      (settle-rewards tx-sender)

      (map-set deposits tx-sender 
        (+ (default-to u0 (map-get? deposits tx-sender)) amount))
      
      (map-set deposit-time tx-sender stacks-block-height)
      (map-set lock-period tx-sender lock-choice)

      (var-set total-deposited (+ (var-get total-deposited) amount))

      (if (and (is-eq previous-total u0) (> (var-get unallocated-rewards) u0))
          (begin
            (distribute-rewards (var-get unallocated-rewards))
            (var-set unallocated-rewards u0))
          true))
    (print {event: "deposit", user: tx-sender, amount: amount, lock: lock-choice})
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
      (caller tx-sender)
      (user-reward (begin (settle-rewards tx-sender)
                      (default-to u0 (map-get? accrued-rewards tx-sender))))
      (multiplier (get-multiplier user-lock))
      (final-reward (/ (* user-reward multiplier) u100))
      (total-to-withdraw (+ user-deposit final-reward))
    )
    (try! (assert-not-paused))
    (asserts! (> user-deposit u0) ERR_NO_DEPOSIT)
    (asserts! (>= (- stacks-block-height deposit-block) user-lock) ERR_LOCKED)

    (as-contract (try! (stx-transfer? total-to-withdraw tx-sender caller)))

    (map-set deposits tx-sender u0)
    (map-set deposit-time tx-sender u0)
    (map-set lock-period tx-sender u0)
    (map-set reward-debt tx-sender u0)
    (map-set accrued-rewards tx-sender u0)
    (var-set total-deposited (- (var-get total-deposited) user-deposit))

    (print {event: "withdraw", user: tx-sender, principal: user-deposit, rewards: final-reward})
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

;; ===================== OWNER FUNCTIONS =====================
(define-public (add-rewards (amount uint))
  (begin
    (try! (assert-owner))
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? amount tx-sender CONTRACT_PRINCIPAL))
    (var-set total-rewards (+ (var-get total-rewards) amount))
    (distribute-rewards amount)
    (print {event: "add-rewards", amount: amount})
    (ok true)
  )
)

(define-public (emergency-drain)
  (begin
    (try! (assert-owner))
    (let ((balance (stx-get-balance CONTRACT_PRINCIPAL)))
      (as-contract (try! (stx-transfer? balance tx-sender (var-get vault-owner))))
      (print {event: "emergency-drain", amount: balance})
      (ok balance)
    )
  )
)

(define-public (set-owner (new-owner principal))
  (begin
    (try! (assert-owner))
    (asserts! (not (is-eq new-owner (var-get vault-owner))) ERR_INVALID_OWNER)
    (asserts! (not (is-eq new-owner CONTRACT_PRINCIPAL)) ERR_INVALID_OWNER)
    (var-set vault-owner new-owner)
    (print {event: "set-owner", old-owner: tx-sender, new-owner: new-owner})
    (ok true)
  )
)

(define-public (pause)
  (begin
    (try! (assert-owner))
    (var-set paused true)
    (print {event: "pause", by: tx-sender})
    (ok true)
  )
)

(define-public (unpause)
  (begin
    (try! (assert-owner))
    (var-set paused false)
    (print {event: "unpause", by: tx-sender})
    (ok true)
  )
)

;; Read-only
(define-read-only (get-user-deposit (user principal))
  (ok (default-to u0 (map-get? deposits user))))

(define-read-only (get-user-lock-period (user principal))
  (ok (default-to u0 (map-get? lock-period user))))

(define-read-only (get-total-deposited)
  (ok (var-get total-deposited)))

(define-read-only (get-user-rewards (user principal))
  (ok (default-to u0 (map-get? accrued-rewards user))))

(define-read-only (get-owner)
  (ok (var-get vault-owner)))

(define-read-only (get-paused)
  (ok (var-get paused)))