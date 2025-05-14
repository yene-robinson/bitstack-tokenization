;; Title: BitStack Tokenization Protocol (BSTP)
;;
;; Summary:
;; A compliant tokenization protocol for real-world assets on the Stacks Layer 2 with Bitcoin security.
;; Provides fractional ownership, KYC integration, and decentralized governance.
;;
;; Description:
;; This smart contract implements a financial tokenization system that enables the fractionalization
;; of high-value assets in a regulatory-compliant framework. Built on Stacks L2, it leverages Bitcoin's
;; security while providing governance mechanisms, dividend distributions, and KYC enforcement
;; to ensure compliance with financial regulations. Suitable for tokenizing real estate, commodities,
;; securities, and other high-value assets with built-in safety controls.

;; Constants

;; Administrative
(define-constant contract-owner tx-sender)

;; Error codes - Access control
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u104))

;; Error codes - Asset management
(define-constant err-not-found (err u101))
(define-constant err-already-listed (err u102))
(define-constant err-invalid-amount (err u103))

;; Error codes - Compliance
(define-constant err-kyc-required (err u105))
(define-constant err-price-expired (err u108))

;; Error codes - Governance
(define-constant err-vote-exists (err u106))
(define-constant err-vote-ended (err u107))

;; Error codes - Validation
(define-constant err-invalid-uri (err u110))
(define-constant err-invalid-value (err u111))
(define-constant err-invalid-duration (err u112))
(define-constant err-invalid-kyc-level (err u113))
(define-constant err-invalid-expiry (err u114))
(define-constant err-invalid-votes (err u115))
(define-constant err-invalid-address (err u116))
(define-constant err-invalid-title (err u117))

;; Value limits and thresholds
(define-constant MAX-ASSET-VALUE u1000000000000) ;; 1 trillion
(define-constant MIN-ASSET-VALUE u1000) ;; 1 thousand
(define-constant MAX-DURATION u144) ;; ~1 day in blocks
(define-constant MIN-DURATION u12) ;; ~1 hour in blocks
(define-constant MAX-KYC-LEVEL u5)
(define-constant MAX-EXPIRY u52560) ;; ~1 year in blocks

;; Tokenization settings
(define-constant tokens-per-asset u100000) ;; SFTs per asset - defines the total supply for each tokenized asset

;; Data Variables

;; Asset and proposal counters
(define-data-var last-asset-id uint u0)
(define-data-var last-proposal-id uint u0)

;; Data Maps

;; Core asset information
(define-map assets
  { asset-id: uint }
  {
    owner: principal,
    metadata-uri: (string-ascii 256),
    asset-value: uint,
    is-locked: bool,
    creation-height: uint,
    last-price-update: uint,
    total-dividends: uint,
  }
)

;; Token ownership records
(define-map token-balances
  {
    owner: principal,
    asset-id: uint,
  }
  { balance: uint }
)

;; KYC status tracking
(define-map kyc-status
  { address: principal }
  {
    is-approved: bool,
    level: uint,
    expiry: uint,
  }
)

;; Governance proposal tracking
(define-map proposals
  { proposal-id: uint }
  {
    title: (string-ascii 256),
    asset-id: uint,
    start-height: uint,
    end-height: uint,
    executed: bool,
    votes-for: uint,
    votes-against: uint,
    minimum-votes: uint,
  }
)

;; Vote records
(define-map votes
  {
    proposal-id: uint,
    voter: principal,
  }
  { vote-amount: uint }
)

;; Dividend distribution tracking
(define-map dividend-claims
  {
    asset-id: uint,
    claimer: principal,
  }
  { last-claimed-amount: uint }
)

;; Price oracle integration
(define-map price-feeds
  { asset-id: uint }
  {
    price: uint,
    decimals: uint,
    last-updated: uint,
    oracle: principal,
  }
)

;; Validation Functions

;; Validate that an asset value is within acceptable limits
(define-private (validate-asset-value (value uint))
  (and
    (>= value MIN-ASSET-VALUE)
    (<= value MAX-ASSET-VALUE)
  )
)

;; Validate that a proposal duration is within acceptable limits
(define-private (validate-duration (duration uint))
  (and
    (>= duration MIN-DURATION)
    (<= duration MAX-DURATION)
  )
)

;; Validate that a KYC level is within acceptable limits
(define-private (validate-kyc-level (level uint))
  (<= level MAX-KYC-LEVEL)
)

;; Validate that an expiry is within acceptable limits
(define-private (validate-expiry (expiry uint))
  (and
    (> expiry stacks-block-height)
    (<= (- expiry stacks-block-height) MAX-EXPIRY)
  )
)

;; Validate that a vote count threshold is reasonable
(define-private (validate-minimum-votes (vote-count uint))
  (and
    (> vote-count u0)
    (<= vote-count tokens-per-asset)
  )
)

;; Validate that a metadata URI is properly formed
(define-private (validate-metadata-uri (uri (string-ascii 256)))
  (and
    (> (len uri) u0)
    (<= (len uri) u256)
  )
)

;; Public Functions

;; Register a new asset for tokenization
(define-public (register-asset
    (metadata-uri (string-ascii 256))
    (asset-value uint)
  )
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (validate-metadata-uri metadata-uri) err-invalid-uri)
    (asserts! (validate-asset-value asset-value) err-invalid-value)
    (let ((asset-id (get-next-asset-id)))
      ;; Set the new assets data
      (map-set assets { asset-id: asset-id } {
        owner: contract-owner,
        metadata-uri: metadata-uri,
        asset-value: asset-value,
        is-locked: false,
        creation-height: stacks-block-height,
        last-price-update: stacks-block-height,
        total-dividends: u0,
      })
      ;; Set initial token balance for the asset owner
      (map-set token-balances {
        owner: contract-owner,
        asset-id: asset-id,
      } { balance: tokens-per-asset }
      )
      ;; Increment the last-asset-id variable
      (var-set last-asset-id asset-id)
      (ok asset-id)
    )
  )
)

;; Claim outstanding dividends for a specific asset
(define-public (claim-dividends (asset-id uint))
  (let (
      (asset (unwrap! (get-asset-info asset-id) err-not-found))
      (balance (get-balance tx-sender asset-id))
      (last-claim (get-last-claim asset-id tx-sender))
      (total-dividends (get total-dividends asset))
      (claimable-amount (/ (* balance (- total-dividends last-claim)) tokens-per-asset))
    )
    (asserts! (> claimable-amount u0) err-invalid-amount)
    (ok (map-set dividend-claims {
      asset-id: asset-id,
      claimer: tx-sender,
    } { last-claimed-amount: total-dividends }
    ))
  )
)

;; Create a new governance proposal for an asset
(define-public (create-proposal
    (asset-id uint)
    (title (string-ascii 256))
    (duration uint)
    (minimum-votes uint)
  )
  (begin
    (asserts! (validate-duration duration) err-invalid-duration)
    (asserts! (validate-minimum-votes minimum-votes) err-invalid-votes)
    (asserts! (validate-metadata-uri title) err-invalid-title)
    (asserts! (>= (get-balance tx-sender asset-id) (/ tokens-per-asset u10))
      err-not-authorized
    )
    (let ((proposal-id (get-next-proposal-id)))
      ;; Set the new proposal data
      (map-set proposals { proposal-id: proposal-id } {
        title: title,
        asset-id: asset-id,
        start-height: stacks-block-height,
        end-height: (+ stacks-block-height duration),
        executed: false,
        votes-for: u0,
        votes-against: u0,
        minimum-votes: minimum-votes,
      })
      ;; Increment the last-proposal-id variable
      (var-set last-proposal-id proposal-id)
      (ok proposal-id)
    )
  )
)

;; Vote on an existing proposal
(define-public (vote
    (proposal-id uint)
    (vote-for bool)
    (amount uint)
  )
  (let (
      (proposal (unwrap! (get-proposal proposal-id) err-not-found))
      (asset-id (get asset-id proposal))
      (balance (get-balance tx-sender asset-id))
    )
    (begin
      (asserts! (>= balance amount) err-invalid-amount)
      (asserts! (< stacks-block-height (get end-height proposal)) err-vote-ended)
      (asserts! (is-none (get-vote proposal-id tx-sender)) err-vote-exists)
      (map-set votes {
        proposal-id: proposal-id,
        voter: tx-sender,
      } { vote-amount: amount }
      )
      (ok (map-set proposals { proposal-id: proposal-id }
        (merge proposal {
          votes-for: (if vote-for
            (+ (get votes-for proposal) amount)
            (get votes-for proposal)
          ),
          votes-against: (if vote-for
            (get votes-against proposal)
            (+ (get votes-against proposal) amount)
          ),
        })
      ))
    )
  )
)