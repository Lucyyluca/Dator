
(define-constant THRESHOLD u30) ;; 30% offline
(define-constant WINDOW-SIZE u100)
(define-constant MAX-PERCENT u100)
(define-constant COOLDOWN u100)
(define-constant CLAIM-WINDOW u1000)

(define-constant ERR-ALREADY-INIT u100)
(define-constant ERR-NOT-ADMIN u101)
(define-constant ERR-NOT-ORACLE u102)
(define-constant ERR-INVALID-PERCENT u103)
(define-constant ERR-INVALID-HEIGHT u104)
(define-constant ERR-NOT-SEQUENTIAL u105)
(define-constant ERR-NO-SAMPLES u106)
(define-constant ERR-NOT-BREACHED u107)
(define-constant ERR-INCIDENT-ACTIVE u108)
(define-constant ERR-COOLDOWN u109)
(define-constant ERR-NO-POOL u110)
(define-constant ERR-NO-COVERAGE u111)
(define-constant ERR-CLAIM-NOT-ACTIVE u112)
(define-constant ERR-ALREADY-CLAIMED u113)
(define-constant ERR-CLAIM-WINDOW u114)
(define-constant ERR-INVALID-AMOUNT u115)

(define-data-var admin (optional principal) none)
(define-data-var oracle (optional principal) none)

(define-data-var last-recorded-burn-height uint u0)
(define-data-var sample-count uint u0)
(define-data-var breach-count uint u0)

(define-data-var incident-id uint u0)
(define-data-var incident-active bool false)
(define-data-var incident-height uint u0)
(define-data-var incident-pool uint u0)
(define-data-var incident-total-coverage uint u0)
(define-data-var last-payout-height uint u0)

(define-data-var pool-balance uint u0)
(define-data-var total-coverage uint u0)

(define-map signer-window
  { index: uint }
  { height: uint, offline: uint, breached: bool }
)

(define-map coverage
  { owner: principal }
  { amount: uint }
)

(define-map claims
  { owner: principal }
  { incident-id: uint }
)

(define-private (is-admin (caller principal))
  (match (var-get admin)
    admin-principal (is-eq admin-principal caller)
    false
  )
)

(define-private (is-oracle (caller principal))
  (match (var-get oracle)
    oracle-principal (is-eq oracle-principal caller)
    false
  )
)

(define-private (get-coverage (owner principal))
  (match (map-get? coverage { owner: owner })
    record (get amount record)
    u0
  )
)

(define-private (get-last-claimed (owner principal))
  (match (map-get? claims { owner: owner })
    record (get incident-id record)
    u0
  )
)

(define-public (init (new-oracle (optional principal)))
  (begin
    (asserts! (is-none (var-get admin)) (err ERR-ALREADY-INIT))
    (var-set admin (some tx-sender))
    (var-set oracle new-oracle)
    (ok true)
  )
)

(define-public (set-oracle (new-oracle principal))
  (begin
    (asserts! (is-admin tx-sender) (err ERR-NOT-ADMIN))
    (var-set oracle (some new-oracle))
    (ok true)
  )
)

(define-public (record-signer-participation (burn-height uint) (offline-percent uint))
  (let (
    (last-height (var-get last-recorded-burn-height))
  )
    (asserts! (is-oracle tx-sender) (err ERR-NOT-ORACLE))
    (asserts! (<= offline-percent MAX-PERCENT) (err ERR-INVALID-PERCENT))
    (asserts! (is-some (get-burn-block-info? header-hash burn-height)) (err ERR-INVALID-HEIGHT))
    (asserts! (or (is-eq last-height u0) (is-eq burn-height (+ last-height u1))) (err ERR-NOT-SEQUENTIAL))
    (let (
      (index (mod burn-height WINDOW-SIZE))
      (old-entry (map-get? signer-window { index: index }))
      (new-breached (> offline-percent THRESHOLD))
      (current-count (var-get sample-count))
    )
      (match old-entry
        entry
          (if (get breached entry)
            (var-set breach-count (- (var-get breach-count) u1))
            (var-set breach-count (var-get breach-count))
          )
        (var-set breach-count (var-get breach-count))
      )
      (if new-breached
        (var-set breach-count (+ (var-get breach-count) u1))
        (var-set breach-count (var-get breach-count))
      )
      (if (< current-count WINDOW-SIZE)
        (var-set sample-count (+ current-count u1))
        (var-set sample-count current-count)
      )
      (map-set signer-window
        { index: index }
        { height: burn-height, offline: offline-percent, breached: new-breached }
      )
      (var-set last-recorded-burn-height burn-height)
      (ok true)
    )
  )
)

(define-public (buy-coverage (amount uint))
  (begin
    (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (let ((current (get-coverage tx-sender)))
      (map-set coverage { owner: tx-sender } { amount: (+ current amount) })
      (var-set total-coverage (+ (var-get total-coverage) amount))
      (var-set pool-balance (+ (var-get pool-balance) amount))
      (ok true)
    )
  )
)

(define-public (withdraw-coverage (amount uint))
  (let ((current (get-coverage tx-sender)))
    (asserts! (is-eq (var-get incident-active) false) (err ERR-INCIDENT-ACTIVE))
    (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
    (asserts! (>= current amount) (err ERR-NO-COVERAGE))
    (map-set coverage { owner: tx-sender } { amount: (- current amount) })
    (var-set total-coverage (- (var-get total-coverage) amount))
    (var-set pool-balance (- (var-get pool-balance) amount))
    (try! (stx-transfer? amount (as-contract tx-sender) tx-sender))
    (ok true)
  )
)

(define-public (claim-payout)
  (let ((last-payout (var-get last-payout-height)))
    (asserts! (is-eq (var-get incident-active) false) (err ERR-INCIDENT-ACTIVE))
    (asserts! (is-eq (var-get sample-count) WINDOW-SIZE) (err ERR-NO-SAMPLES))
    (asserts! (is-eq (var-get breach-count) WINDOW-SIZE) (err ERR-NOT-BREACHED))
    (asserts! (or (is-eq last-payout u0) (>= burn-block-height (+ last-payout COOLDOWN))) (err ERR-COOLDOWN))
    (asserts! (> (var-get pool-balance) u0) (err ERR-NO-POOL))
    (asserts! (> (var-get total-coverage) u0) (err ERR-NO-COVERAGE))
    (let ((new-id (+ (var-get incident-id) u1)))
      (var-set incident-id new-id)
      (var-set incident-active true)
      (var-set incident-height burn-block-height)
      (var-set incident-pool (var-get pool-balance))
      (var-set incident-total-coverage (var-get total-coverage))
      (var-set last-payout-height burn-block-height)
      (ok new-id)
    )
  )
)

(define-public (claim)
  (let (
    (user-coverage (get-coverage tx-sender))
    (current-incident-id (var-get incident-id))
    (current-incident-height (var-get incident-height))
    (current-incident-pool (var-get incident-pool))
    (current-incident-total (var-get incident-total-coverage))
  )
    (asserts! (var-get incident-active) (err ERR-CLAIM-NOT-ACTIVE))
    (asserts! (<= (- burn-block-height current-incident-height) CLAIM-WINDOW) (err ERR-CLAIM-WINDOW))
    (asserts! (< (get-last-claimed tx-sender) current-incident-id) (err ERR-ALREADY-CLAIMED))
    (asserts! (> user-coverage u0) (err ERR-NO-COVERAGE))
    (asserts! (> current-incident-total u0) (err ERR-NO-COVERAGE))
    (let ((payout (/ (* current-incident-pool user-coverage) current-incident-total)))
      (asserts! (> payout u0) (err ERR-NO-POOL))
      (try! (stx-transfer? payout (as-contract tx-sender) tx-sender))
      (var-set pool-balance (- (var-get pool-balance) payout))
      (map-set claims { owner: tx-sender } { incident-id: current-incident-id })
      (ok payout)
    )
  )
)

(define-public (close-incident)
  (let (
    (current-incident-height (var-get incident-height))
    (current-pool (var-get pool-balance))
  )
    (asserts! (var-get incident-active) (err ERR-CLAIM-NOT-ACTIVE))
    (asserts! (or (is-eq current-pool u0) (>= burn-block-height (+ current-incident-height CLAIM-WINDOW))) (err ERR-CLAIM-WINDOW))
    (var-set incident-active false)
    (ok true)
  )
)
