# motion_platform_signals

Store/platform signals for the Yula Motion family (Flutter plugin, iOS +
Android). Every call answers `null` where the platform API is unavailable —
callers keep their own fallback.

| API | iOS | Android |
|---|---|---|
| `MotionPlatformSignals.appTransactionId()` | StoreKit 2 `AppTransaction.appTransactionID`, iOS 16+, verified only | `null` |

Used by `motion_account` to request the server-signed App Store
introductory-offer eligibility (one Motion+ free trial per Motion account).
