(define-constant ERR-NOT-AUTHORIZED (err u1001))
(define-constant ERR-ALREADY-EXISTS (err u1002))
(define-constant ERR-NOT-FOUND (err u1003))
(define-constant ERR-INVALID-STATE (err u1004))
(define-constant ERR-INSUFFICIENT-FUNDS (err u1005))
(define-constant ERR-EXPIRED (err u1006))
(define-constant ERR-NOT-EXPIRED (err u1007))
(define-constant ERR-INVALID-AMOUNT (err u1008))
(define-constant ERR-SAME-TRADER (err u1009))
(define-constant ERR-AUCTION-ENDED (err u1010))
(define-constant ERR-BID-TOO-LOW (err u1011))
(define-constant ERR-AUCTION-ACTIVE (err u1012))

(define-constant CONTRACT-OWNER tx-sender)
(define-constant TRADE-TIMEOUT u144)
(define-constant MIN-ESCROW-FEE u1000)
(define-constant AUCTION-DURATION u288)
(define-constant MIN-BID-INCREMENT u100)

(define-data-var next-trade-id uint u1)
(define-data-var contract-fee-rate uint u100)
(define-data-var collected-fees uint u0)
(define-data-var next-auction-id uint u1)
(define-data-var next-listing-id uint u1)

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

(define-map auctions
  { auction-id: uint }
  {
    seller: principal,
    card-id: uint,
    starting-price: uint,
    current-bid: uint,
    highest-bidder: (optional principal),
    end-block: uint,
    status: (string-ascii 20),
    created-at: uint
  }
)

(define-map listings
  { listing-id: uint }
  {
    seller: principal,
    card-id: uint,
    price: uint,
    status: (string-ascii 20),
    created-at: uint
  }
)

(define-map auction-bids
  { auction-id: uint, bidder: principal }
  { bid-amount: uint, bid-time: uint }
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

(define-public (create-auction (card-id uint) (starting-price uint))
  (let ((auction-id (var-get next-auction-id)))
    (asserts! (is-valid-card-owner tx-sender card-id) ERR-NOT-AUTHORIZED)
    (asserts! (> starting-price u0) ERR-INVALID-AMOUNT)
    (let ((card-info (unwrap! (map-get? user-cards { owner: tx-sender, card-id: card-id }) ERR-NOT-FOUND)))
      (asserts! (get is-tradeable card-info) ERR-INVALID-STATE)
      (map-set auctions
        { auction-id: auction-id }
        {
          seller: tx-sender,
          card-id: card-id,
          starting-price: starting-price,
          current-bid: starting-price,
          highest-bidder: none,
          end-block: (+ stacks-block-height AUCTION-DURATION),
          status: "active",
          created-at: stacks-block-height
        }
      )
      (var-set next-auction-id (+ auction-id u1))
      (ok auction-id)
    )
  )
)

(define-public (place-bid (auction-id uint) (bid-amount uint))
  (let ((auction (unwrap! (map-get? auctions { auction-id: auction-id }) ERR-NOT-FOUND))
        (user-balance (default-to u0 (get balance (map-get? user-balances { user: tx-sender })))))
    (asserts! (not (is-eq tx-sender (get seller auction))) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status auction) "active") ERR-INVALID-STATE)
    (asserts! (<= stacks-block-height (get end-block auction)) ERR-AUCTION-ENDED)
    (asserts! (>= bid-amount (+ (get current-bid auction) MIN-BID-INCREMENT)) ERR-BID-TOO-LOW)
    (asserts! (>= user-balance bid-amount) ERR-INSUFFICIENT-FUNDS)
    (let ((previous-highest-bidder (get highest-bidder auction))
          (previous-bid (get current-bid auction)))
      (match previous-highest-bidder
        prev-bidder
        (let ((prev-balance (default-to u0 (get balance (map-get? user-balances { user: prev-bidder })))))
          (map-set user-balances { user: prev-bidder } { balance: (+ prev-balance previous-bid) }))
        true
      )
      (map-set user-balances { user: tx-sender } { balance: (- user-balance bid-amount) })
      (map-set auctions
        { auction-id: auction-id }
        (merge auction {
          current-bid: bid-amount,
          highest-bidder: (some tx-sender)
        })
      )
      (map-set auction-bids
        { auction-id: auction-id, bidder: tx-sender }
        { bid-amount: bid-amount, bid-time: stacks-block-height }
      )
      (ok true)
    )
  )
)

(define-public (end-auction (auction-id uint))
  (let ((auction (unwrap! (map-get? auctions { auction-id: auction-id }) ERR-NOT-FOUND)))
    (asserts! (is-eq (get status auction) "active") ERR-INVALID-STATE)
    (asserts! (> stacks-block-height (get end-block auction)) ERR-AUCTION-ACTIVE)
    (match (get highest-bidder auction)
      winner
      (begin
        (try! (transfer-card (get seller auction) winner (get card-id auction)))
        (let ((seller-balance (default-to u0 (get balance (map-get? user-balances { user: (get seller auction) }))))
              (auction-fee (get-trade-fee (get current-bid auction)))
              (seller-proceeds (- (get current-bid auction) auction-fee)))
          (map-set user-balances
            { user: (get seller auction) }
            { balance: (+ seller-balance seller-proceeds) }
          )
          (var-set collected-fees (+ (var-get collected-fees) auction-fee))
          (map-set auctions { auction-id: auction-id } (merge auction { status: "completed" }))
          (ok true)
        )
      )
      (begin
        (map-set auctions { auction-id: auction-id } (merge auction { status: "no-bids" }))
        (ok true)
      )
    )
  )
)

(define-public (cancel-auction (auction-id uint))
  (let ((auction (unwrap! (map-get? auctions { auction-id: auction-id }) ERR-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get seller auction)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status auction) "active") ERR-INVALID-STATE)
    (asserts! (is-none (get highest-bidder auction)) ERR-INVALID-STATE)
    (map-set auctions { auction-id: auction-id } (merge auction { status: "cancelled" }))
    (ok true)
  )
)

(define-public (create-listing (card-id uint) (price uint))
  (let ((listing-id (var-get next-listing-id)))
    (asserts! (is-valid-card-owner tx-sender card-id) ERR-NOT-AUTHORIZED)
    (asserts! (> price u0) ERR-INVALID-AMOUNT)
    (let ((card-info (unwrap! (map-get? user-cards { owner: tx-sender, card-id: card-id }) ERR-NOT-FOUND)))
      (asserts! (get is-tradeable card-info) ERR-INVALID-STATE)
      (map-set listings
        { listing-id: listing-id }
        {
          seller: tx-sender,
          card-id: card-id,
          price: price,
          status: "active",
          created-at: stacks-block-height
        }
      )
      (var-set next-listing-id (+ listing-id u1))
      (ok listing-id)
    )
  )
)

(define-public (purchase-listing (listing-id uint))
  (let ((listing (unwrap! (map-get? listings { listing-id: listing-id }) ERR-NOT-FOUND))
        (buyer-balance (default-to u0 (get balance (map-get? user-balances { user: tx-sender }))))
        (platform-fee (get-trade-fee (get price listing)))
        (total-cost (get price listing))
        (seller (get seller listing)))
    (asserts! (is-eq (get status listing) "active") ERR-INVALID-STATE)
    (asserts! (not (is-eq tx-sender seller)) ERR-SAME-TRADER)
    (asserts! (>= buyer-balance total-cost) ERR-INSUFFICIENT-FUNDS)
    (asserts! (is-valid-card-owner seller (get card-id listing)) ERR-NOT-AUTHORIZED)
    (map-set user-balances
      { user: tx-sender }
      { balance: (- buyer-balance total-cost) }
    )
    (let ((seller-balance (default-to u0 (get balance (map-get? user-balances { user: seller }))))
          (seller-proceeds (- total-cost platform-fee)))
      (map-set user-balances
        { user: seller }
        { balance: (+ seller-balance seller-proceeds) }
      )
      (var-set collected-fees (+ (var-get collected-fees) platform-fee))
    )
    (try! (transfer-card seller tx-sender (get card-id listing)))
    (map-set listings
      { listing-id: listing-id }
      (merge listing { status: "completed" })
    )
    (ok true)
  )
)

(define-public (cancel-listing (listing-id uint))
  (let ((listing (unwrap! (map-get? listings { listing-id: listing-id }) ERR-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get seller listing)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status listing) "active") ERR-INVALID-STATE)
    (map-set listings
      { listing-id: listing-id }
      (merge listing { status: "cancelled" })
    )
    (ok true)
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

(define-read-only (get-auction (auction-id uint))
  (map-get? auctions { auction-id: auction-id })
)

(define-read-only (get-listing (listing-id uint))
  (map-get? listings { listing-id: listing-id })
)

(define-read-only (get-bid (auction-id uint) (bidder principal))
  (map-get? auction-bids { auction-id: auction-id, bidder: bidder })
)

(define-read-only (get-contract-stats)
  {
    next-trade-id: (var-get next-trade-id),
    next-auction-id: (var-get next-auction-id),
    fee-rate: (var-get contract-fee-rate),
    collected-fees: (var-get collected-fees),
    current-block: stacks-block-height
  }
)

