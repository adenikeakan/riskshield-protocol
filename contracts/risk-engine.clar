;; title: risk-engine
;; version: 1.0.0
;; summary: Core risk calculation and scoring system for Bitcoin DeFi positions
;; description: RiskShield Protocol - Risk Engine Contract

;; Error constants
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-POSITION-NOT-FOUND (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-INVALID-RISK-PARAMS (err u103))

;; Contract constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant BASIS-POINTS u10000)
(define-constant MAX-RISK-SCORE u10000)
(define-constant MIN-LIQUIDATION-THRESHOLD u5000)

;; Data variables
(define-data-var volatility-multiplier uint u150)
(define-data-var total-positions uint u0)

;; Data maps
(define-map positions
  uint
  {
    owner: principal,
    asset: (string-ascii 12),
    amount: uint,
    collateral: uint,
    collateral-ratio: uint,
    risk-score: uint,
    last-updated: uint,
    is-active: bool
  }
)

(define-map asset-risk-params
  (string-ascii 12)
  {
    base-risk: uint,
    volatility: uint,
    liquidity-score: uint,
    correlation-btc: uint
  }
)

;; Initialize default asset parameters
(map-set asset-risk-params "STX" 
  { base-risk: u2000, volatility: u3500, liquidity-score: u8000, correlation-btc: u6500 })

(map-set asset-risk-params "sBTC"
  { base-risk: u1000, volatility: u2500, liquidity-score: u9500, correlation-btc: u9800 })

;; Public functions
(define-public (create-position 
    (position-id uint)
    (asset (string-ascii 12))
    (amount uint)
    (collateral uint))
  (begin
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (> collateral u0) ERR-INVALID-AMOUNT)
    (asserts! (is-none (map-get? positions position-id)) ERR-POSITION-NOT-FOUND)
    
    (let ((collateral-ratio (/ (* collateral BASIS-POINTS) amount)))
      (map-set positions position-id
        {
          owner: tx-sender,
          asset: asset,
          amount: amount,
          collateral: collateral,
          collateral-ratio: collateral-ratio,
          risk-score: u0,
          last-updated: stacks-block-height,
          is-active: true
        })
      
      (var-set total-positions (+ (var-get total-positions) u1))
      
      (print {
        action: "position-created",
        position-id: position-id,
        owner: tx-sender,
        asset: asset,
        collateral-ratio: collateral-ratio
      })
      
      (ok position-id))))

(define-public (update-collateral-ratio (position-id uint) (new-collateral uint))
  (let ((position-opt (map-get? positions position-id)))
    (match position-opt
      position-data
      (let ((owner (get owner position-data))
            (amount (get amount position-data))
            (new-ratio (/ (* new-collateral BASIS-POINTS) amount)))
        (asserts! (or (is-eq tx-sender owner) 
                     (is-eq tx-sender CONTRACT-OWNER)) ERR-UNAUTHORIZED)
        
        (map-set positions position-id
          (merge position-data {
            collateral: new-collateral,
            collateral-ratio: new-ratio,
            last-updated: stacks-block-height
          }))
        
        (print {
          action: "collateral-updated",
          position-id: position-id,
          new-collateral: new-collateral,
          new-ratio: new-ratio
        })
        
        (ok new-ratio))
      ERR-POSITION-NOT-FOUND)))

;; Read-only functions
(define-read-only (get-position (position-id uint))
  (map-get? positions position-id))

(define-read-only (get-asset-risk-params (asset (string-ascii 12)))
  (map-get? asset-risk-params asset))

(define-read-only (calculate-position-risk (position-id uint))
  (let ((position-opt (map-get? positions position-id)))
    (match position-opt
      position-data
      (let ((asset (get asset position-data))
            (collateral-ratio (get collateral-ratio position-data)))
        (let ((asset-params-opt (map-get? asset-risk-params asset)))
          (match asset-params-opt
            asset-params
            (let ((base-risk (get base-risk asset-params))
                  (volatility (get volatility asset-params))
                  (liquidity-score (get liquidity-score asset-params))
                  (volatility-adjustment (/ (* volatility (var-get volatility-multiplier)) BASIS-POINTS))
                  (liquidity-adjustment (/ (* liquidity-score u50) BASIS-POINTS))
                  (collateral-risk (if (< collateral-ratio u15000)
                                     (/ (* (- u15000 collateral-ratio) u50) BASIS-POINTS)
                                     u0))
                  (raw-risk-score (+ (+ base-risk volatility-adjustment) collateral-risk))
                  (adjusted-risk-score (if (> raw-risk-score liquidity-adjustment)
                                         (- raw-risk-score liquidity-adjustment)
                                         u0))
                  (final-risk-score (if (> adjusted-risk-score MAX-RISK-SCORE)
                                       MAX-RISK-SCORE
                                       adjusted-risk-score)))
              (ok final-risk-score))
            ERR-INVALID-RISK-PARAMS)))
      ERR-POSITION-NOT-FOUND)))

(define-read-only (get-system-risk-metrics)
  {
    total-positions: (var-get total-positions)
  })

;; Administrative functions
(define-public (update-asset-risk-params 
    (asset (string-ascii 12))
    (base-risk uint)
    (volatility uint) 
    (liquidity-score uint)
    (correlation-btc uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (<= base-risk MAX-RISK-SCORE) ERR-INVALID-RISK-PARAMS)
    (asserts! (<= volatility MAX-RISK-SCORE) ERR-INVALID-RISK-PARAMS)
    (asserts! (<= liquidity-score MAX-RISK-SCORE) ERR-INVALID-RISK-PARAMS)
    (asserts! (<= correlation-btc MAX-RISK-SCORE) ERR-INVALID-RISK-PARAMS)
    
    (map-set asset-risk-params asset
      {
        base-risk: base-risk,
        volatility: volatility,
        liquidity-score: liquidity-score,
        correlation-btc: correlation-btc
      })
    
    (print {
      action: "asset-params-updated",
      asset: asset,
      base-risk: base-risk,
      volatility: volatility
    })
    
    (ok true)))