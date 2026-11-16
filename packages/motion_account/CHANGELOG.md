# Changelog

## 0.9.0

Additive, opt-in under-13 parental consent (ADR-008 / VELI-01). Defaults keep
the first-release behavior exactly.

- `MotionAgeBand.underThirteenConsentRequired` (appended); `MotionAgePolicy.bandFor(..., underThirteenConsent: false)`.
- `MotionParentalConsent.withdrawn` (appended).
- `MotionAgeStatus.bandOn/restrictedOn`, `purchaseRestrictedOn`, `storeDecidesPurchaseOn` take `underThirteenConsent` (default false).
- `MotionConsentRequestError.invalidDeviceToken`, `alreadyDecided` (appended after `mailUnavailable`; existing indexes unchanged).
- New `MotionDeviceConsentToken`, `MotionDeviceConsentStatus`, `MotionParentalConsentMachine`, `MotionConsentEvent`.
- `MotionAccountClient.requestDeviceConsent`, `deviceConsentStatus`, `signUpUnderThirteen`.
- `MotionAccountOperation.deviceConsent` (appended).
- `MotionAccountPage(underThirteenConsentEnabled: false, onUnderThirteen)` and `MotionMembershipPage(underThirteenConsentEnabled: false)`. With the flag on but no `onUnderThirteen`, the page keeps the permanent block.

Consumer note: exhaustive `switch` over `MotionAgeBand`, `MotionParentalConsent`,
`MotionConsentRequestError` or `MotionAccountOperation` must handle the new
values before pinning 0.9.0.

## 0.8.1 and earlier

See git history.
