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
    (var-set last-block-interest-calculated stacks-block-height)
    
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

;; Collateral management
(define-public (deposit-collateral (amount uint))
  (begin
    (asserts! (var-get protocol-initialized) ERR-NOT-INITIALIZED)
    (asserts! (not (var-get protocol-paused)) ERR-PAUSED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    ;; Transfer sBTC from user to contract
    (let ((transfer-result (contract-call? (var-get sbtc-contract) transfer amount tx-sender (as-contract tx-sender))))
      (match transfer-result
        success 
        (let (
          (current-collateral (default-to { amount: u0 } (map-get? user-collateral { user: tx-sender })))
          (new-amount (+ (get amount current-collateral) amount))
        )
          ;; Update user's collateral
          (map-set user-collateral { user: tx-sender } { amount: new-amount })
          
          ;; Update total locked sBTC
          (var-set total-sbtc-locked (+ (var-get total-sbtc-locked) amount))
          
          (ok true)
        )
        error (err error)
      )
    )
  )
)

(define-public (withdraw-collateral (amount uint))
  (begin
    (asserts! (var-get protocol-initialized) ERR-NOT-INITIALIZED)
    (asserts! (not (var-get protocol-paused)) ERR-PAUSED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    (let (
      (current-collateral (default-to { amount: u0 } (map-get? user-collateral { user: tx-sender })))
      (current-loan (default-to { borrowed-amount: u0, interest-accumulated: u0, last-interest-block: u0, liquidated: false } 
                            (map-get? user-loans { user: tx-sender })))
    )
      ;; Check if user has enough collateral
      (asserts! (>= (get amount current-collateral) amount) ERR-INSUFFICIENT-BALANCE)
      
      ;; Calculate updated collateral
      (let ((new-collateral-amount (- (get amount current-collateral) amount)))
        
        ;; If there's an outstanding loan, check if collateral ratio remains sufficient
        (if (> (+ (get borrowed-amount current-loan) (get interest-accumulated current-loan)) u0)
          (let (
            (price-response (try! (get-sbtc-price)))
            (collateral-value-after-withdrawal (* new-collateral-amount price-response))
            (total-debt (+ (get borrowed-amount current-loan) (get interest-accumulated current-loan)))
            (collateral-ratio (if (> total-debt u0)
                                 (/ (* collateral-value-after-withdrawal u100) total-debt)
                                 u0))
          )
            ;; Ensure collateral ratio stays above minimum
            (asserts! (>= collateral-ratio (var-get minimum-collateral-ratio)) ERR-COLLATERAL-RATIO-TOO-LOW)
            
            ;; Update user's collateral if check passes
            (map-set user-collateral { user: tx-sender } { amount: new-collateral-amount })
            
            ;; Update total locked sBTC
            (var-set total-sbtc-locked (- (var-get total-sbtc-locked) amount))
            
            ;; Transfer sBTC from contract to user
            (as-contract 
              (contract-call? (var-get sbtc-contract) transfer amount tx-sender tx-sender)
            )
          )
          (begin
            ;; No loan, simply withdraw
            (map-set user-collateral { user: tx-sender } { amount: new-collateral-amount })
            (var-set total-sbtc-locked (- (var-get total-sbtc-locked) amount))
            
            ;; Transfer sBTC from contract to user
            (as-contract 
              (contract-call? (var-get sbtc-contract) transfer amount tx-sender tx-sender)
            )
          )
        )
      )
    )
  )
)

;; Interest calculation helpers
(define-private (calculate-interest (principal uint) (interest-rate uint) (blocks uint))
  ;; Interest = principal * rate * blocks / 10000 / 10000
  ;; Rate is in basis points (0.01%), so we divide by 10000
  ;; We divide by another 10000 for scaling purposes
  (/ (* (* principal interest-rate) blocks) u10000 u10000)
)

(define-private (update-loan-interest (user principal))
  (let (
    (current-loan (map-get? user-loans { user: user }))
  )
    (match current-loan
      loan 
      (let (
        (blocks-elapsed (- stacks-block-height (get last-interest-block loan)))
        (new-interest (calculate-interest (get borrowed-amount loan) (var-get interest-rate-per-block) blocks-elapsed))
        (updated-interest (+ (get interest-accumulated loan) new-interest))
      )
        (map-set user-loans 
          { user: user }
          {
            borrowed-amount: (get borrowed-amount loan),
            interest-accumulated: updated-interest,
            last-interest-block: stacks-block-height,
            liquidated: (get liquidated loan)
          }
        )
        true
      )
      false
    )
  )
)

(define-public (update-global-interest)
  (begin
    (asserts! (var-get protocol-initialized) ERR-NOT-INITIALIZED)
    (var-set last-block-interest-calculated stacks-block-height)
    (ok true)
  )
)

;; Loan functions
(define-public (borrow (amount uint))
  (begin
    (asserts! (var-get protocol-initialized) ERR-NOT-INITIALIZED)
    (asserts! (not (var-get protocol-paused)) ERR-PAUSED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    ;; Update interest on existing loan if any
    (update-loan-interest tx-sender)
    
    (let (
      (current-collateral (default-to { amount: u0 } (map-get? user-collateral { user: tx-sender })))
      (current-loan (default-to { borrowed-amount: u0, interest-accumulated: u0, last-interest-block: stacks-block-height, liquidated: false } 
                          (map-get? user-loans { user: tx-sender })))
      (price-response (try! (get-sbtc-price)))
    )
      ;; Calculate collateral value
      (let (
        (collateral-value (* (get amount current-collateral) price-response))
        (existing-debt (+ (get borrowed-amount current-loan) (get interest-accumulated current-loan)))
        (new-total-debt (+ existing-debt amount))
        (new-collateral-ratio (if (> new-total-debt u0)
                               (/ (* collateral-value u100) new-total-debt)
                               u0))
      )
        ;; Check collateral ratio
        (asserts! (>= new-collateral-ratio (var-get minimum-collateral-ratio)) ERR-COLLATERAL-RATIO-TOO-LOW)
        
        ;; Update loan information
        (map-set user-loans
          { user: tx-sender }
          {
            borrowed-amount: (+ (get borrowed-amount current-loan) amount),
            interest-accumulated: (get interest-accumulated current-loan),
            last-interest-block: stacks-block-height,
            liquidated: false
          }
        )
        
        ;; Update total borrowed
        (var-set total-stablecoin-borrowed (+ (var-get total-stablecoin-borrowed) amount))
        
        ;; Transfer stablecoin to borrower
        (as-contract
          (contract-call? (var-get stablecoin-contract) transfer amount tx-sender tx-sender)
        )
      )
    )
  )
)

(define-public (repay (amount uint))
  (begin
    (asserts! (var-get protocol-initialized) ERR-NOT-INITIALIZED)
    (asserts! (not (var-get protocol-paused)) ERR-PAUSED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    ;; Update interest on existing loan
    (update-loan-interest tx-sender)
    
    (let (
      (current-loan (map-get? user-loans { user: tx-sender }))
    )
      (match current-loan
        loan
        (let (
          (total-debt (+ (get borrowed-amount loan) (get interest-accumulated loan)))
        )
          ;; Check if repayment exceeds debt
          (asserts! (<= amount total-debt) ERR-REPAY-EXCEEDS-DEBT)
          
          ;; Calculate how much of the payment goes to interest vs principal
          (let (
            (interest-payment (if (< (get interest-accumulated loan) amount) 
                                 (get interest-accumulated loan)
                                 amount))
            (principal-payment (- amount interest-payment))
            (new-interest-accumulated (- (get interest-accumulated loan) interest-payment))
            (new-borrowed-amount (- (get borrowed-amount loan) principal-payment))
          )
            ;; Update loan information
            (map-set user-loans
              { user: tx-sender }
              {
                borrowed-amount: new-borrowed-amount,
                interest-accumulated: new-interest-accumulated,
                last-interest-block: stacks-block-height,
                liquidated: false
              }
            )
            
            ;; Update total borrowed
            (var-set total-stablecoin-borrowed (- (var-get total-stablecoin-borrowed) principal-payment))
            
            ;; Calculate protocol fee on interest
            (let (
              (protocol-fee-amount (/ (* interest-payment (var-get protocol-fee)) u100))
              (user-transfer-amount (- amount protocol-fee-amount))
            )
              ;; Transfer stablecoin from user to contract
              (contract-call? (var-get stablecoin-contract) transfer amount tx-sender (as-contract tx-sender))
            )
          )
        )
        ERR-LOAN-DOES-NOT-EXIST
      )
    )
  )
)

;; Liquidation functions
(define-public (check-liquidation (user principal))
  (begin
    (asserts! (var-get protocol-initialized) ERR-NOT-INITIALIZED)
    (asserts! (not (var-get protocol-paused)) ERR-PAUSED)
    
    ;; Update interest on the loan
    (update-loan-interest user)
    
    (let (
      (current-collateral (default-to { amount: u0 } (map-get? user-collateral { user: user })))
      (current-loan (map-get? user-loans { user: user }))
    )
      (match current-loan
        loan
        (let (
          (price-response (try! (get-sbtc-price)))
          (collateral-value (* (get amount current-collateral) price-response))
          (total-debt (+ (get borrowed-amount loan) (get interest-accumulated loan)))
          (collateral-ratio (if (> total-debt u0)
                              (/ (* collateral-value u100) total-debt)
                              u0))
        )
          ;; Check if loan is liquidatable
          (if (< collateral-ratio (var-get liquidation-threshold))
            (ok true)  ;; Can be liquidated
            (ok false)  ;; Cannot be liquidated
          )
        )
        (ok false)  ;; No loan exists
      )
    )
  )
)

(define-public (liquidate (user principal))
  (begin
    (asserts! (var-get protocol-initialized) ERR-NOT-INITIALIZED)
    (asserts! (not (var-get protocol-paused)) ERR-PAUSED)
    
    ;; First check if the loan can be liquidated
    (let ((can-liquidate (try! (check-liquidation user))))
      (asserts! can-liquidate ERR-NOT-LIQUIDATABLE)
      
      (let (
        (current-collateral (default-to { amount: u0 } (map-get? user-collateral { user: user })))
        (current-loan (unwrap! (map-get? user-loans { user: user }) ERR-LOAN-DOES-NOT-EXIST))
        (price-response (try! (get-sbtc-price)))
        (total-debt (+ (get borrowed-amount current-loan) (get interest-accumulated current-loan)))
      )
        ;; Calculate liquidation amounts with penalty
        (let (
          (debt-with-penalty (/ (* total-debt (+ u100 (var-get liquidation-penalty))) u100))
          (collateral-to-liquidate (get amount current-collateral))
          (collateral-value (* collateral-to-liquidate price-response))
        )
          ;; Execute liquidation through DEX
          (let (
            (liquidation-result (as-contract (contract-call? (var-get dex-contract) sell-sbtc collateral-to-liquidate)))
          )
            (match liquidation-result
              stablecoin-amount
              (let (
                (debt-repaid (if (> stablecoin-amount total-debt) total-debt stablecoin-amount))
                (excess-stablecoin (- stablecoin-amount debt-repaid))
              )
                ;; Mark loan as liquidated
                (map-set user-loans
                  { user: user }
                  {
                    borrowed-amount: u0,
                    interest-accumulated: u0,
                    last-interest-block: stacks-block-height,
                    liquidated: true
                  }
                )
                
                ;; Remove collateral
                (map-set user-collateral { user: user } { amount: u0 })
                
                ;; Update total locked sBTC
                (var-set total-sbtc-locked (- (var-get total-sbtc-locked) collateral-to-liquidate))
                
                ;; Update total borrowed
                (var-set total-stablecoin-borrowed (- (var-get total-stablecoin-borrowed) (get borrowed-amount current-loan)))
                
                ;; Return excess stablecoin to the liquidated user if any
                (if (> excess-stablecoin u0)
                  (as-contract (contract-call? (var-get stablecoin-contract) transfer excess-stablecoin tx-sender user))
                  true
                )
                
                (ok true)
              )
              error (err error)
            )
          )
        )
      )
    )
  )
)

;; Read-only functions for data access
(define-read-only (get-user-collateral (user principal))
  (default-to { amount: u0 } (map-get? user-collateral { user: user }))
)

(define-read-only (get-user-loan (user principal))
  (map-get? user-loans { user: user })
)

(define-read-only (get-collateral-ratio (user principal))
  (let (
    (current-collateral (default-to { amount: u0 } (map-get? user-collateral { user: user })))
    (current-loan (map-get? user-loans { user: user }))
  )
    (match current-loan
      loan
      (let (
        (price-response (get-sbtc-price))
      )
        (match price-response
          price
          (let (
            (collateral-value (* (get amount current-collateral) price))
            (total-debt (+ (get borrowed-amount loan) (get interest-accumulated loan)))
          )
            (if (> total-debt u0)
              (ok (/ (* collateral-value u100) total-debt))
              (ok u0)
            )
          )
          error (err error)
        )
      )
      (err ERR-LOAN-DOES-NOT-EXIST)
    )
  )
)

(define-read-only (get-protocol-stats)
  {
    total-sbtc-locked: (var-get total-sbtc-locked),
    total-stablecoin-borrowed: (var-get total-stablecoin-borrowed),
    minimum-collateral-ratio: (var-get minimum-collateral-ratio),
    liquidation-threshold: (var-get liquidation-threshold),
    interest-rate-per-block: (var-get interest-rate-per-block),
    protocol-paused: (var-get protocol-paused)
  }
)

;; Test helper function - only available in dev environments
(define-public (set-stacks-block-height (new-height uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (print (tuple (new-height new-height)))
    (ok true)
  )
)