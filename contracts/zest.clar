;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ZEST Token - SIP-010
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(use-trait sip-010-trait-ft-standard 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sip-010-trait-ft-standard.sip-010-trait)
(impl-trait sip-010-trait-ft-standard)

;; ============================================================================
;; CONSTANTS
;; ============================================================================

(define-constant DECIMALS (pow u10 u6))
(define-constant ERR-UNAUTHORIZED (err u3000))
(define-constant ERR-NOT-TOKEN-OWNER (err u4))

;; ============================================================================
;; TOKEN DEFINITION
;; ============================================================================

(define-fungible-token zest (* u1000000000 DECIMALS))

;; ============================================================================
;; STATE
;; ============================================================================

(define-data-var token-name (string-ascii 32) "Zest")
(define-data-var token-symbol (string-ascii 32) "ZEST")
(define-data-var token-uri (optional (string-utf8 256)) none)
(define-map approved-contracts principal bool)

;; ============================================================================
;; AUTH
;; ============================================================================

(define-private (check-dao-auth)
  (ok (asserts! (is-eq tx-sender .dao-executor) ERR-UNAUTHORIZED)))

(define-private (check-is-approved)
  (ok (asserts! (default-to false (map-get? approved-contracts contract-caller)) ERR-UNAUTHORIZED)))

;; ============================================================================
;; SIP-010 FUNCTIONS
;; ============================================================================

(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
  (begin
    (asserts! (or (is-eq sender tx-sender) (is-eq sender contract-caller)) ERR-NOT-TOKEN-OWNER)
    (try! (ft-transfer? zest amount sender recipient))
    (match memo to-print (print to-print) 0x)
    (ok true)))

(define-read-only (get-name)
  (ok (var-get token-name)))

(define-read-only (get-symbol)
  (ok (var-get token-symbol)))

(define-read-only (get-decimals)
  (ok u6))

(define-read-only (get-balance (who principal))
  (ok (ft-get-balance zest who)))

(define-read-only (get-total-supply)
  (ok (ft-get-supply zest)))

(define-read-only (get-token-uri)
  (ok (var-get token-uri)))

;; ============================================================================
;; ADMIN - DAO only
;; ============================================================================

(define-public (set-name (new-name (string-ascii 32)))
  (begin
    (try! (check-dao-auth))
    (ok (var-set token-name new-name))))

(define-public (set-symbol (new-symbol (string-ascii 32)))
  (begin
    (try! (check-dao-auth))
    (ok (var-set token-symbol new-symbol))))

(define-public (set-token-uri (new-uri (optional (string-utf8 256))))
  (begin
    (try! (check-dao-auth))
    (ok (var-set token-uri new-uri))))

(define-public (set-approved-contract (contract principal) (approved bool))
  (begin
    (try! (check-dao-auth))
    (ok (map-set approved-contracts contract approved))))

;; ============================================================================
;; MINT / BURN - DAO or approved contract
;; ============================================================================

(define-public (mint (amount uint) (recipient principal))
  (begin
    (asserts! (or (is-ok (check-dao-auth)) (is-ok (check-is-approved))) ERR-UNAUTHORIZED)
    (ft-mint? zest amount recipient)))

(define-public (burn (amount uint) (owner principal))
  (begin
    (asserts! (or (is-ok (check-dao-auth)) (is-ok (check-is-approved))) ERR-UNAUTHORIZED)
    (ft-burn? zest amount owner)))

(define-private (mint-many-iter (item {amount: uint, recipient: principal}))
  (ft-mint? zest (get amount item) (get recipient item)))

(define-public (mint-many (recipients (list 200 {amount: uint, recipient: principal})))
  (begin
    (try! (check-dao-auth))
    (ok (map mint-many-iter recipients))))

;; ============================================================================
;; HELPER
;; ============================================================================

(define-read-only (is-approved (contract principal))
  (default-to false (map-get? approved-contracts contract)))
