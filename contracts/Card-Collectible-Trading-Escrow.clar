(define-constant ERR-NOT-AUTHORIZED (err u1001))
(define-constant ERR-ALREADY-EXISTS (err u1002))
(define-constant ERR-NOT-FOUND (err u1003))
(define-constant ERR-INVALID-STATE (err u1004))
(define-constant ERR-INSUFFICIENT-FUNDS (err u1005))
(define-constant ERR-EXPIRED (err u1006))
(define-constant ERR-NOT-EXPIRED (err u1007))
(define-constant ERR-INVALID-AMOUNT (err u1008))
(define-constant ERR-SAME-TRADER (err u1009))

(define-constant CONTRACT-OWNER tx-sender)
(define-constant TRADE-TIMEOUT u144)
(define-constant MIN-ESCROW-FEE u1000)

(define-data-var next-trade-id uint u1)
(define-data-var contract-fee-rate uint u100)
(define-data-var collected-fees uint u0)

(define-map trades 
  { trade-id: uint }
  {
    initiator: principal,
    counterparty: principal,
    initiator-card-id: uint,
    counterparty-card-id: uint,
    initiator-deposit: uint,
    counterparty-deposit: uint,
    status: (string-ascii 20),
    created-at: uint,
    expires-at: uint,
    initiator-confirmed: bool,
    counterparty-confirmed: bool
  }
)

(define-map user-cards
  { owner: principal, card-id: uint }
  {
    card-name: (string-ascii 50),
    rarity: (string-ascii 20),
    collection: (string-ascii 30),
    condition: (string-ascii 20),
    value: uint,
    is-tradeable: bool
  }
)

(define-map card-ownership
  { card-id: uint }
  { owner: principal }
)

(define-map user-balances
  { user: principal }
  { balance: uint }
)

(define-map trade-disputes
  { trade-id: uint }
  {
    disputant: principal,
    reason: (string-ascii 100),
    created-at: uint,
    resolved: bool
  }
)

(define-private (get-trade-fee (amount uint))
  (/ (* amount (var-get contract-fee-rate)) u10000)
)

(define-private (is-valid-card-owner (owner principal) (card-id uint))
  (match (map-get? card-ownership { card-id: card-id })
    card-data (is-eq (get owner card-data) owner)
    false
  )
)

(define-private (transfer-card (from principal) (to principal) (card-id uint))
  (begin
    (asserts! (is-valid-card-owner from card-id) ERR-NOT-AUTHORIZED)
    (map-set card-ownership { card-id: card-id } { owner: to })
    (ok true)
  )
)

(define-public (register-card (card-id uint) (card-name (string-ascii 50)) 
                              (rarity (string-ascii 20)) (collection (string-ascii 30))
                              (condition (string-ascii 20)) (value uint))
  (begin
    (asserts! (is-none (map-get? card-ownership { card-id: card-id })) ERR-ALREADY-EXISTS)
    (asserts! (> value u0) ERR-INVALID-AMOUNT)
    (map-set user-cards 
      { owner: tx-sender, card-id: card-id }
      {
        card-name: card-name,
        rarity: rarity,
        collection: collection,
        condition: condition,
        value: value,
        is-tradeable: true
      }
    )
    (map-set card-ownership { card-id: card-id } { owner: tx-sender })
    (ok card-id)
  )
)

(define-public (deposit-funds (amount uint))
  (begin
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (let ((current-balance (default-to u0 (get balance (map-get? user-balances { user: tx-sender })))))
      (map-set user-balances { user: tx-sender } { balance: (+ current-balance amount) })
      (ok amount)
    )
  )
)

(define-public (withdraw-funds (amount uint))
  (let ((current-balance (default-to u0 (get balance (map-get? user-balances { user: tx-sender })))))
    (asserts! (>= current-balance amount) ERR-INSUFFICIENT-FUNDS)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
    (map-set user-balances { user: tx-sender } { balance: (- current-balance amount) })
    (ok amount)
  )
)

(define-public (initiate-trade (counterparty principal) (initiator-card-id uint) 
                               (counterparty-card-id uint) (deposit-amount uint))
  (let ((trade-id (var-get next-trade-id))
        (current-balance (default-to u0 (get balance (map-get? user-balances { user: tx-sender }))))
        (fee (get-trade-fee deposit-amount))
        (total-required (+ deposit-amount fee)))
    (asserts! (not (is-eq tx-sender counterparty)) ERR-SAME-TRADER)
    (asserts! (>= deposit-amount MIN-ESCROW-FEE) ERR-INVALID-AMOUNT)
    (asserts! (>= current-balance total-required) ERR-INSUFFICIENT-FUNDS)
    (asserts! (is-valid-card-owner tx-sender initiator-card-id) ERR-NOT-AUTHORIZED)
    (asserts! (is-valid-card-owner counterparty counterparty-card-id) ERR-NOT-AUTHORIZED)
    
    (map-set user-balances { user: tx-sender } { balance: (- current-balance total-required) })
    (var-set collected-fees (+ (var-get collected-fees) fee))
    
    (map-set trades
      { trade-id: trade-id }
      {
        initiator: tx-sender,
        counterparty: counterparty,
        initiator-card-id: initiator-card-id,
        counterparty-card-id: counterparty-card-id,
        initiator-deposit: deposit-amount,
        counterparty-deposit: u0,
        status: "pending",
        created-at: stacks-block-height,
        expires-at: (+ stacks-block-height TRADE-TIMEOUT),
        initiator-confirmed: false,
        counterparty-confirmed: false
      }
    )
    
    (var-set next-trade-id (+ trade-id u1))
    (ok trade-id)
  )
)

(define-public (accept-trade (trade-id uint) (deposit-amount uint))
  (let ((trade (unwrap! (map-get? trades { trade-id: trade-id }) ERR-NOT-FOUND))
        (current-balance (default-to u0 (get balance (map-get? user-balances { user: tx-sender }))))
        (fee (get-trade-fee deposit-amount))
        (total-required (+ deposit-amount fee)))
    
    (asserts! (is-eq tx-sender (get counterparty trade)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status trade) "pending") ERR-INVALID-STATE)
    (asserts! (<= stacks-block-height (get expires-at trade)) ERR-EXPIRED)
    (asserts! (>= current-balance total-required) ERR-INSUFFICIENT-FUNDS)
    (asserts! (>= deposit-amount MIN-ESCROW-FEE) ERR-INVALID-AMOUNT)
    
    (map-set user-balances { user: tx-sender } { balance: (- current-balance total-required) })
    (var-set collected-fees (+ (var-get collected-fees) fee))
    
    (map-set trades
      { trade-id: trade-id }
      (merge trade { 
        counterparty-deposit: deposit-amount,
        status: "active"
      })
    )
    
    (ok true)
  )
)

(define-public (confirm-trade (trade-id uint))
  (let ((trade (unwrap! (map-get? trades { trade-id: trade-id }) ERR-NOT-FOUND)))
    (asserts! (is-eq (get status trade) "active") ERR-INVALID-STATE)
    (asserts! (<= stacks-block-height (get expires-at trade)) ERR-EXPIRED)
    (asserts! (or (is-eq tx-sender (get initiator trade)) 
                  (is-eq tx-sender (get counterparty trade))) ERR-NOT-AUTHORIZED)
    
    (let ((updated-trade 
           (if (is-eq tx-sender (get initiator trade))
               (merge trade { initiator-confirmed: true })
               (merge trade { counterparty-confirmed: true }))))
      
      (map-set trades { trade-id: trade-id } updated-trade)
      
      (if (and (get initiator-confirmed updated-trade) (get counterparty-confirmed updated-trade))
          (complete-trade trade-id)
          (ok true))
    )
  )
)

(define-private (complete-trade (trade-id uint))
  (let ((trade (unwrap! (map-get? trades { trade-id: trade-id }) ERR-NOT-FOUND)))
    (try! (transfer-card (get initiator trade) (get counterparty trade) (get initiator-card-id trade)))
    (try! (transfer-card (get counterparty trade) (get initiator trade) (get counterparty-card-id trade)))
    
    (let ((initiator-balance (default-to u0 (get balance (map-get? user-balances { user: (get initiator trade) }))))
          (counterparty-balance (default-to u0 (get balance (map-get? user-balances { user: (get counterparty trade) })))))
      
      (map-set user-balances 
        { user: (get initiator trade) } 
        { balance: (+ initiator-balance (get initiator-deposit trade)) })
      
      (map-set user-balances 
        { user: (get counterparty trade) } 
        { balance: (+ counterparty-balance (get counterparty-deposit trade)) })
    )
    
    (map-set trades { trade-id: trade-id } (merge trade { status: "completed" }))
    (ok true)
  )
)

(define-public (cancel-trade (trade-id uint))
  (let ((trade (unwrap! (map-get? trades { trade-id: trade-id }) ERR-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get initiator trade)) ERR-NOT-AUTHORIZED)
    (asserts! (or (is-eq (get status trade) "pending") 
                  (> stacks-block-height (get expires-at trade))) ERR-INVALID-STATE)
    
    (let ((initiator-balance (default-to u0 (get balance (map-get? user-balances { user: (get initiator trade) })))))
      (map-set user-balances 
        { user: (get initiator trade) } 
        { balance: (+ initiator-balance (get initiator-deposit trade)) })
      
      (if (> (get counterparty-deposit trade) u0)
          (let ((counterparty-balance (default-to u0 (get balance (map-get? user-balances { user: (get counterparty trade) })))))
            (map-set user-balances 
              { user: (get counterparty trade) } 
              { balance: (+ counterparty-balance (get counterparty-deposit trade)) }))
          true)
    )
    
    (map-set trades { trade-id: trade-id } (merge trade { status: "cancelled" }))
    (ok true)
  )
)

(define-public (create-dispute (trade-id uint) (reason (string-ascii 100)))
  (let ((trade (unwrap! (map-get? trades { trade-id: trade-id }) ERR-NOT-FOUND)))
    (asserts! (or (is-eq tx-sender (get initiator trade)) 
                  (is-eq tx-sender (get counterparty trade))) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status trade) "active") ERR-INVALID-STATE)
    (asserts! (is-none (map-get? trade-disputes { trade-id: trade-id })) ERR-ALREADY-EXISTS)
    
    (map-set trade-disputes
      { trade-id: trade-id }
      {
        disputant: tx-sender,
        reason: reason,
        created-at: stacks-block-height,
        resolved: false
      }
    )
    
    (map-set trades { trade-id: trade-id } (merge trade { status: "disputed" }))
    (ok true)
  )
)

(define-public (resolve-dispute (trade-id uint) (winner principal))
  (let ((trade (unwrap! (map-get? trades { trade-id: trade-id }) ERR-NOT-FOUND))
        (dispute (unwrap! (map-get? trade-disputes { trade-id: trade-id }) ERR-NOT-FOUND)))
    
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status trade) "disputed") ERR-INVALID-STATE)
    (asserts! (not (get resolved dispute)) ERR-INVALID-STATE)
    
    (let ((total-deposits (+ (get initiator-deposit trade) (get counterparty-deposit trade)))
          (winner-balance (default-to u0 (get balance (map-get? user-balances { user: winner })))))
      
      (map-set user-balances 
        { user: winner } 
        { balance: (+ winner-balance total-deposits) })
    )
    
    (map-set trade-disputes { trade-id: trade-id } (merge dispute { resolved: true }))
    (map-set trades { trade-id: trade-id } (merge trade { status: "resolved" }))
    (ok true)
  )
)

(define-public (set-card-tradeable (card-id uint) (tradeable bool))
  (let ((card-data (unwrap! (map-get? user-cards { owner: tx-sender, card-id: card-id }) ERR-NOT-FOUND)))
    (asserts! (is-valid-card-owner tx-sender card-id) ERR-NOT-AUTHORIZED)
    (map-set user-cards 
      { owner: tx-sender, card-id: card-id }
      (merge card-data { is-tradeable: tradeable }))
    (ok true)
  )
)

(define-public (update-contract-fee (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-rate u1000) ERR-INVALID-AMOUNT)
    (var-set contract-fee-rate new-rate)
    (ok true)
  )
)

(define-public (withdraw-fees (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (<= amount (var-get collected-fees)) ERR-INSUFFICIENT-FUNDS)
    (try! (as-contract (stx-transfer? amount tx-sender CONTRACT-OWNER)))
    (var-set collected-fees (- (var-get collected-fees) amount))
    (ok amount)
  )
)

(define-read-only (get-trade (trade-id uint))
  (map-get? trades { trade-id: trade-id })
)

(define-read-only (get-card-info (owner principal) (card-id uint))
  (map-get? user-cards { owner: owner, card-id: card-id })
)

(define-read-only (get-card-owner (card-id uint))
  (map-get? card-ownership { card-id: card-id })
)

(define-read-only (get-user-balance (user principal))
  (default-to u0 (get balance (map-get? user-balances { user: user })))
)

(define-read-only (get-dispute (trade-id uint))
  (map-get? trade-disputes { trade-id: trade-id })
)

(define-read-only (get-contract-stats)
  {
    next-trade-id: (var-get next-trade-id),
    fee-rate: (var-get contract-fee-rate),
    collected-fees: (var-get collected-fees),
    current-block: stacks-block-height
  }
)

;; title: Card-Collectible-Trading-Escrow
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

