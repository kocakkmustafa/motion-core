# motion_platform_signals

Store/platform signals for the Yula Motion family (Flutter plugin, iOS +
Android). Every call answers `null` where the platform API is unavailable —
callers keep their own fallback.

| API | iOS | Android |
|---|---|---|
| `MotionPlatformSignals.appTransactionId()` | StoreKit 2 `AppTransaction.appTransactionID`, iOS 16+, verified only | `null` |
| `MotionPlatformSignals.requestAgeSignal()` | `AgeRangeService.requestAgeRange(ageGates: 13, 16, 18)`, iOS 26+; may show Apple's sharing sheet. The app needs the `com.apple.developer.declared-age-range` entitlement. | Play Age Signals 0.0.4: `requestAgeSignalsAccess` (Play may prompt) → `checkAgeSignals`; signals exist only where Play provides them (for example Texas, Brazil) |

`requestAgeSignal()` returns `MotionStoreAgeSignal{source, shared, lower,
upper, declaration}` or `null` (older OS, unsupported region, missing
entitlement, Play not available, errors). Bounds are inclusive; `upper == null`
is the open top band (18+).

Used by `motion_account`: the server-signed App Store introductory-offer
eligibility (one Motion+ free trial per Motion account) and the store age
range at sign-up (`MotionAgePolicy.storeCheck`: the store can only tighten the
declared age).
