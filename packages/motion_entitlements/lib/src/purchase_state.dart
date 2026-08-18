/// `unknown -> loading -> entitled | notEntitled | recoverableError`.
/// [entitled] is the ONLY state that ever grants access — see
/// `EntitlementStatus.grantsAccessAt`. In particular [recoverableError]
/// (a transient network/store failure) must resolve the same as
/// [notEntitled] for access purposes: a flaky adapter can never leak paid
/// content.
enum PurchaseState { unknown, loading, entitled, notEntitled, recoverableError }
