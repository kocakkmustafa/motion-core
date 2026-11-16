import 'motion_account_client.dart';
import 'motion_age_policy.dart';

/// Camera coaching, live measurement and scoring stay closed in the first
/// release. Hosts gate camera/measurement launch on this constant only.
const bool motionCameraCoachingAvailable = false;

/// Founder decision (23 Oct 2026): the first release of all five Motion apps
/// sells the app's own subscription and Motion+. This opens the membership
/// surface and the paid-lesson gate; it never opens camera sessions.
const bool motionSubscriptionSalesAvailable = true;

/// Who decides a purchase by a teen below the country's consent age whose
/// parent has not approved the Motion account yet. Each host chooses it;
/// the default keeps the first-release behavior.
enum MotionTeenPurchasePolicy {
  /// No purchase is offered until the parent approves (restore stays).
  parentalConsentRequired,

  /// Offers stay open; the store's own family controls (Ask to Buy, Google
  /// Play parental approval) decide the payment. Account features stay
  /// closed until consent either way, and an under-13 band never buys.
  storeFamilyControls,
}

/// Purchase decisions for a signed-in account under a host's policy.
extension MotionTeenPurchaseStatus on MotionAgeStatus {
  /// Whether the membership page withholds new purchases under [policy].
  /// Only a consent-pending teen differs between the policies.
  ///
  /// With [underThirteenConsent] (default false: today's rule, an under-13
  /// band never buys) an under-13 account buys only once its parent
  /// approved; every other consent state, including `withdrawn`, is closed
  /// whatever the policy.
  bool purchaseRestrictedOn(
    DateTime today,
    MotionTeenPurchasePolicy policy, {
    bool underThirteenConsent = false,
  }) {
    final band = bandOn(today, underThirteenConsent: underThirteenConsent);
    if (band == MotionAgeBand.blocked) return true;
    if (band == MotionAgeBand.underThirteenConsentRequired) {
      return consent != MotionParentalConsent.approved;
    }
    return policy == MotionTeenPurchasePolicy.parentalConsentRequired &&
        restrictedOn(today, underThirteenConsent: underThirteenConsent);
  }

  /// A teen whose purchases are left to the store's family controls.
  bool storeDecidesPurchaseOn(
    DateTime today,
    MotionTeenPurchasePolicy policy, {
    bool underThirteenConsent = false,
  }) =>
      policy == MotionTeenPurchasePolicy.storeFamilyControls &&
      restrictedOn(today, underThirteenConsent: underThirteenConsent) &&
      !purchaseRestrictedOn(
        today,
        policy,
        underThirteenConsent: underThirteenConsent,
      );
}

/// Former single gate for "paid features". Its value stays false because
/// hosts used it as their camera launch gate; switching it on would open
/// camera coaching. Use [motionCameraCoachingAvailable] for camera and
/// measurement, [motionSubscriptionSalesAvailable] for sales and paywalls.
@Deprecated(
  'Use motionCameraCoachingAvailable (camera/measurement) or '
  'motionSubscriptionSalesAvailable (sales/paywall)',
)
const bool motionPaidFeaturesAvailable = motionCameraCoachingAvailable;
