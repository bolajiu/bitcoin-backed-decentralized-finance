;; Title:
;; sBTC Lending Protocol on Stacks Layer 2: Bitcoin-Backed Decentralized Finance
;; Summary:
;; A decentralized lending platform enabling Bitcoin holders to leverage sBTC collateral for stablecoin loans
;; while maintaining Bitcoin's security through Stacks Layer 2 infrastructure. Features risk-managed loans,
;; automated liquidations, and institutional-grade protocol controls with Bitcoin-compliant operations.

;; Description:
;; The sBTC Lending Engine is a non-custodial DeFi primitive built on Stacks Layer 2 that enables:
;; - Bitcoin-backed lending through sBTC collateralization
;; - Programmatic stablecoin loans with dynamic interest rates
;; - Autonomous risk management with collateral ratio checks
;; - Trust-minimized liquidations via decentralized exchange integration
;; - Protocol-level safeguards compliant with Bitcoin ecosystem standards

;; Designed for seamless Bitcoin interoperability, this protocol implements:
;; 1. sBTC Collateral Vaults: Non-custodial custodianship of wrapped Bitcoin assets
;; 2. Risk Parameters: Configurable collateral ratios (150%+), liquidation thresholds (125%), and penalty fees
;; 3. Oracle Integration: Real-time price feeds for collateral valuation
;; 4. Liquidation Engine: DEX-powered asset recovery mechanism
;; 5. Protocol Controls: Emergency pause and parameter governance functions

;; Built for institutional DeFi participants, the system maintains:
;; - Transparent debt accounting with block-based interest accrual
;; - Real-time collateral health monitoring
;; - Regulatory-ready operations through permissioned admin controls
;; - Bitcoin-native asset compliance via sBTC integration
;; - Stacks Layer 2 efficiency with Bitcoin finality

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-INSUFFICIENT-BALANCE (err u1001))
(define-constant ERR-COLLATERAL-RATIO-TOO-LOW (err u1002))
(define-constant ERR-BORROW-LIMIT-REACHED (err u1003))
(define-constant ERR-NOT-LIQUIDATABLE (err u1004))
(define-constant ERR-ALREADY-INITIALIZED (err u1005))
(define-constant ERR-NOT-INITIALIZED (err u1006))
(define-constant ERR-INVALID-AMOUNT (err u1007))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u1008))
(define-constant ERR-REPAY-EXCEEDS-DEBT (err u1009))
(define-constant ERR-ORACLE-ERROR (err u1010))
(define-constant ERR-PAUSED (err u1011))
(define-constant ERR-LOAN-DOES-NOT-EXIST (err u1012))

;; Protocol configuration
(define-data-var minimum-collateral-ratio uint u150) ;; 150% represented as uint
(define-data-var liquidation-threshold uint u125) ;; 125% represented as uint
(define-data-var liquidation-penalty uint u10) ;; 10% penalty
(define-data-var interest-rate-per-block uint u100) ;; 0.01% per block (represented as basis points)
(define-data-var protocol-fee uint u10) ;; 1% fee on interest
(define-data-var protocol-paused bool false)
(define-data-var protocol-initialized bool false)
(define-data-var oracle-contract principal 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.btc-oracle)
(define-data-var dex-contract principal 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.dex)
(define-data-var stablecoin-contract principal 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.usda-token)
(define-data-var sbtc-contract principal 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.sbtc-token)
(define-data-var total-sbtc-locked uint u0)
(define-data-var total-stablecoin-borrowed uint u0)
(define-data-var last-block-interest-calculated uint u0)

;; Data maps
(define-map user-collateral
  { user: principal }
  { amount: uint }
)

(define-map user-loans
  { user: principal }
  {
    borrowed-amount: uint,
    interest-accumulated: uint,
    last-interest-block: uint,
    liquidated: bool
  }
)

(define-map authorized-addresses
  { address: principal }
  { authorized: bool }
)

;; Initialization function - can only be called once
(define-public (initialize (sbtc-token-contract principal) (stablecoin-token-contract principal) (oracle-contract-address principal) (dex-contract-address principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (not (var-get protocol-initialized)) ERR-ALREADY-INITIALIZED)
    
    (var-set sbtc-contract sbtc-token-contract)
    (var-set stablecoin-contract stablecoin-token-contract)
    (var-set oracle-contract oracle-contract-address)
    (var-set dex-contract dex-contract-address)
    (var-set protocol-initialized true)
    (var-set last-block-interest-calculated block-height)
    
    (ok true)
  )
)

;; Helper functions for permissions
(define-private (is-authorized)
  (or (is-eq tx-sender CONTRACT-OWNER)
      (default-to false (get authorized bool (map-get? authorized-addresses { address: tx-sender }))))
)

(define-public (add-authorized-address (address principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-addresses { address: address } { authorized: true }))
  )
)

(define-public (remove-authorized-address (address principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-addresses { address: address } { authorized: false }))
  )
)

;; Protocol pause controls for emergency situations
(define-public (pause-protocol)
  (begin
    (asserts! (is-authorized) ERR-NOT-AUTHORIZED)
    (ok (var-set protocol-paused true))
  )
)

(define-public (unpause-protocol)
  (begin
    (asserts! (is-authorized) ERR-NOT-AUTHORIZED)
    (ok (var-set protocol-paused false))
  )
)

;; Parameter management functions - only authorized addresses can update these
(define-public (update-minimum-collateral-ratio (new-ratio uint))
  (begin
    (asserts! (is-authorized) ERR-NOT-AUTHORIZED)
    (ok (var-set minimum-collateral-ratio new-ratio))
  )
)

(define-public (update-liquidation-threshold (new-threshold uint))
  (begin
    (asserts! (is-authorized) ERR-NOT-AUTHORIZED)
    (ok (var-set liquidation-threshold new-threshold))
  )
)

(define-public (update-liquidation-penalty (new-penalty uint))
  (begin
    (asserts! (is-authorized) ERR-NOT-AUTHORIZED)
    (ok (var-set liquidation-penalty new-penalty))
  )
)

(define-public (update-interest-rate (new-rate uint))
  (begin
    (asserts! (is-authorized) ERR-NOT-AUTHORIZED)
    ;; Update global interest before changing the rate
    (try! (update-global-interest))
    (ok (var-set interest-rate-per-block new-rate))
  )
)

(define-public (update-protocol-fee (new-fee uint))
  (begin
    (asserts! (is-authorized) ERR-NOT-AUTHORIZED)
    (ok (var-set protocol-fee new-fee))
  )
)

;; Oracle price getter with error handling
(define-read-only (get-sbtc-price)
  (let ((price-response (contract-call? (var-get oracle-contract) get-price)))
    (match price-response
      price (ok price)
      error ERR-ORACLE-ERROR
    )
  )
)