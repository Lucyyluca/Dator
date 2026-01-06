# Dator Contract

Parametric insurance contract scaffold focused on signer participation outages. The contract tracks a 100-block rolling window of signer offline percentages reported by a designated oracle and can open an incident when the window is fully breached.

## Constants
- `THRESHOLD`: offline percent (u30) required to mark a block as breached.
- `WINDOW-SIZE`: sample window length (u100).
- `MAX-PERCENT`: max allowed offline percent (u100).
- `COOLDOWN`: burn-block cooldown between incidents (u100).
- `CLAIM-WINDOW`: burn-block window for claims (u1000).
- Error codes `u100` through `u115` cover init, auth, validation, and claim flow failures.

## State
- Admin/oracle principals: `admin`, `oracle`.
- Rolling window tracking: `last-recorded-burn-height`, `sample-count`, `breach-count`.
- Incident snapshot: `incident-id`, `incident-active`, `incident-height`, `incident-pool`, `incident-total-coverage`, `last-payout-height`.
- Coverage pool: `pool-balance`, `total-coverage`.

## Maps
- `signer-window`: ring buffer keyed by `index` with `{ height, offline, breached }`.
- `coverage`: STX coverage per `owner`.
- `claims`: last `incident-id` claimed per `owner`.

## Public Functions
- `init(new-oracle)`: one-time initialization; sets admin and optional oracle.
- `set-oracle(new-oracle)`: admin-only oracle update.
- `record-signer-participation(burn-height, offline-percent)`: oracle-only; sequential burn heights only; validates burn header exists; updates rolling breach window.
- `buy-coverage(amount)`: deposits STX into the pool and increases coverage.
- `withdraw-coverage(amount)`: withdraws STX when no incident is active.
- `claim-payout()`: opens an incident when all 100 samples are breached, cooldown passed, and pool/coverage are nonzero; snapshots pool and coverage.
- `claim()`: pro-rata payout from the incident pool for covered users during the claim window.
- `close-incident()`: closes an incident after the claim window or when the pool is empty.

## Notes
- Coverage and payouts use STX transfers via `stx-transfer?`.
- The contract assumes an off-chain oracle feeds signer offline percentages; header existence is verified on-chain.
