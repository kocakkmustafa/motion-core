/// Camera coaching, live measurement and scoring stay closed in the first
/// release. Hosts gate camera/measurement launch on this constant only.
const bool motionCameraCoachingAvailable = false;

/// Founder decision (23 Oct 2026): the first release of all five Motion apps
/// sells the app's own subscription and Motion+. This opens the membership
/// surface and the paid-lesson gate; it never opens camera sessions.
const bool motionSubscriptionSalesAvailable = true;

/// Former single gate for "paid features". Its value stays false because
/// hosts used it as their camera launch gate; switching it on would open
/// camera coaching. Use [motionCameraCoachingAvailable] for camera and
/// measurement, [motionSubscriptionSalesAvailable] for sales and paywalls.
@Deprecated(
  'Use motionCameraCoachingAvailable (camera/measurement) or '
  'motionSubscriptionSalesAvailable (sales/paywall)',
)
const bool motionPaidFeaturesAvailable = motionCameraCoachingAvailable;
