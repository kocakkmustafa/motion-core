# Motion account foundation

One Supabase identity serves Ostinato, Gravita, Choreia, JabLab, and Lissom.
Subscription rights remain scoped to the signed-in user **and** one app.
Version 0.2.0 adds the recovery listenable below and requires the deletion
response upgrade described here. Entitlement fixes ship as version 0.1.1.
Version 0.3.0 adds per-method deadlines and typed unknown mutation outcomes
(`MotionOperationUnknown`, K08): hosts that caught raw SDK errors from account
mutations must also handle it.

Host apps initialize `MotionAccountRuntime` once before `runApp` with the same
Motion project URL and publishable key, their own `MotionApp` value, and the
matching callback `com.yulalab.<app>://auth/callback`. The native iOS and
Android callback registrations and the Supabase Auth redirect allow-list must
match that exact URI. The runtime exposes `account` for `MotionAccountPage` and
`userId` as a `ValueListenable<String?>` for local-data ownership. Hosts must
wrap their shell in `MotionIdentityGate`: null ID may mean signed out, still
verifying, or network unavailable. Only `signedOut` may open guest history;
only a live, undisposed runtime with `verified` and current identity proof may first
open account history. Guest also requires actual Session null plus `signedOut`.
A stored session does not prove that
the account still exists until the Auth server confirms it.
If verification is unavailable, the gate offers a local-only guest path. It
discards the unverified cached session without deleting account-owned files;
the user must sign in again to reopen that account's history.

This isolated source proposal adds live `isCurrentSessionVerified`, read-only
`identityVerification` (`Listenable`), and read-only `isDisposed`. It is UNRUN and
not adopted in canonical Core or consumer apps. The proof bool binds successful
Auth verification to the exact actual Session, including its captured UUID and
token. Same-UUID/token replacement Sessions do not inherit proof. An unchanged
already verified Session keeps its prior proof while ordinary refresh is pending;
the latest matching denial, mismatch, error or timeout invalidates it. Normal
credential refresh requires proof for the new Session and does not itself change
the host's UUID storage epoch or erase data.

Hosts query the live bool when the proof listenable notifies and at admission
boundaries. A same-UUID accepted Session notifies even if userId and phase did not
change. Eventless external SDK mutation can make the live getter false immediately,
but cannot automatically notify the UI until runtime or host observes replacement.
Hosts still observe their Session boundary and initiate runtime refresh there.
The proposed default Gate listens to phase, proof, recovery and the public
asynchronous Auth stream with a safe error handler. Guest admission requires
actual currentSession null, signedOut and an undisposed runtime.

The Gate keeps its public StatelessWidget facade and constructor. Its private
State never mounts an account-private child before the first matching proof.
After admission it retains one owned child/configuration and the existing
Navigator/State/resources during genuine same-owner tokenRefreshed while proof
for the distinct current Session is pending. It hides paint, focus and semantics
and blocks new admission. It does not hand unverified replacement configuration
to didUpdateWidget. Actual owner equality is required; a tokenRefreshed label
can accompany an owner change and supplies no lifetime authority by itself.

Pass the host's existing UUID/E/resource ticket as the Gate Widget.key, stable
on ordinary credential refresh and changed on retirement. A child ticket key
can also force cold admission when the facade is unkeyed. Do not key by JWT or
every new Session: that would retire the same resources on token refresh again.
Different owner, guest/account or recovery transition, fresh matching signedIn
with a distinct actual Session, a new runtime reference, changed ticket key or
runtime disposal discards the old slot. Cold replacement removes the old Element
before admitting a fresh one. Resource/Navigator GlobalKeys must belong to that
owner ticket and must not be reparented by the host across retired tickets.

The Gate separately remembers the last event-handled actual Session; a fast
getUser success does not overwrite this classification before signedIn delivery.
Identical-Session replay is stable and stale event snapshots cannot assign an
owner. For an unknown eventless same-UUID replacement, positive proof alone
does not reveal or rebind the prior State. Reset the existing host ticket key
or use a host-owned admission adapter. Eventless mutation cannot automatically
notify the UI until runtime/host observation. Default/no-key callers cover only
observable current Auth/owner/runtime transitions, not arbitrary unobserved host
E retirement or an intermediate fresh sign-in whose event is already stale.
Their full consumer E/ticket acceptance remains open.

Readiness and lifetime are separate. Never substitute identityVerification into
a channel whose every notification retires the owner, resets navigation or
destroys resources. In particular, the current Choreia phase-based retirement
channel needs a separate readiness seam before adoption. Offstage State remains
active: timers, HTTP, camera streams and native decoders are not paused or
retired by hiding it. Retained Gate State fixes only mounting behavior. Every
host initiation, new acquisition, publication and post-await completion must
check the captured actual Session, current positive proof, live owner/E ticket,
and runtime ownership/liveness. An old S1 completion is rejected after S2
replaces it even if S2 has proof and the resource ticket remains unchanged.
Transient proof loss must not toggle a terminal media admission/retirement flag.
No second host getUser or new host epoch API is introduced. Five-consumer
operation/write/finish integration and real camera/media acceptance remain open.

The existing final proof pulse reports isDisposed true before notifier cleanup.
A retained Gate retires on that pulse; first mount with a disposed runtime admits
neither private account nor guest and does not register disposed notifiers.
A new runtime cannot inherit the prior runtime's admitted State or proof. Hosts
still own removal/drain ordering before SDK/runtime disposal and async tickets.
Hidden State, positive proof or network failure never provides UUID erasure
authority: confirmed ALL_A cleanup still requires its independent per-UUID erase
admission fence and shared writer drain, including after listener retirement.

A proof listener may call runtime.dispose() synchronously. The runtime is fenced
immediately and the live proof becomes false; private notifier disposal waits
until its notification frames unwind. No new runtime verification or guest
sign-out begins after such retirement. A confirmed UUID receipt or explicit
user_not_found that already admitted cleanup still completes that UUID callback;
proof invalidation or runtime retirement does not revoke deletion authority.

`refreshIdentity()` retains its `Future<void>` signature. Normal completion
can mean superseded work and does not prove that this call verified the Session.
Capture the public actual Session and the host's existing Session/E/resource ticket
before awaiting it. Before admission/publication, require the captured Session
to remain identical to actual currentSession, live isCurrentSessionVerified to
be true, and the existing host ticket to remain current. Recheck those conditions
after each further await. Another latest verification may supply valid current
proof for that same captured Session. No second host getUser or private SDK hook
is required. Positive identity proof is not deletion proof or erasure authority.

Pass `runtime.isPasswordRecovery` to the page's `initialPasswordRecovery`
parameter when routing rebuilds after an auth callback.
For callbacks that retain the same user and route, listen to
`runtime.passwordRecovery` (`ValueListenable<bool>`) and rebuild the account
page with that value. The existing bool getter remains available as a snapshot.
The page also responds when `initialPasswordRecovery` changes on an existing
widget. Password-update success, sign-out, and account changes clear recovery.
Identity verification has a ten-second deadline. A latest matching stalled
request closes the gate with Retry and Continue as guest; a late response cannot
reopen it.

Both account widgets handle raw SDK auth-stream errors separately from the
runtime. The account page keeps entered credentials and the recovery form,
shows a safe retry message, and suppresses a pending profile result. The
membership page retires its current sale lifetime: retained purchase actions,
pending offers and cached auth events cannot reopen it after an auth error.
Retry verified identity in the host before opening a new membership page.
These handlers never delete local history or enable the closed paid gate.

`MotionAccountPage.clearLocalData` receives the captured user ID and erases this
app's local records after confirmed remote common-account deletion. The host owns its
local data and must clear only that user's records. On a restored session,
`onDeletedAccount` erases records if Auth explicitly returns `user_not_found`.
The `localAccountIds` callback lists this app's existing user-owned files. At
startup and after sign-out, a separate anonymous client checks the server's
deletion receipt for each ID. Only a confirmed receipt allows local cleanup;
ordinary sign-out and network failure keep files. The server retains only a
digest of each deleted random account ID. Store subscriptions are managed
through the Apple or Google account; this package does not cancel them.

Deletion captures the initiating UUID, Session reference and token before dispatch. The
client requires HTTP 200 with `deleted: true` and the same `userId` before local
cleanup, and it never signs out a replacement session after cleanup. Deploy the
matching `motion-delete-account` response before pinning this Core revision in
consumer release builds. The new endpoint accepts older clients that omit
`expectedUserId`; the verified token remains its authority. A legacy or malformed
response makes the new client preserve files until independent receipt cleanup
confirms deletion. This source change does not prove provider deployment.
Membership checks and purchase verification pin their initiating session token
and Session reference too. A changed account or any replacement Session discards
the response, even when its UUID and token values are unchanged. Identity replies
and cleanup-side sign-out also require the original Session reference; a silent
same-user `recoverSession` cannot inherit an older request's authority. Confirmed
UUID cleanup still runs for that UUID independently of this sign-out guard.
The default membership page belongs to its opening Session: replacing it retires
retained sale actions and held store acknowledgements. Reopen the page after
verified identity retry, including when credential refresh replaces the Session.
Auth-stream replay of an unchanged opening Session keeps the page usable.

The account deletion dialog captures its account client, Session, UUID and local
cleanup callback when opened. Confirmation dispatches only while that page and
the captured Supabase client/Session remain current; a host may rebuild a wrapper
around that same client without losing an unchanged-session confirmation.
A retained dialog reads translations
from its own context, so a disposed account page or a locale change cannot make
it use a defunct State. Hosts still capture their storage epoch and resource
handles before opening the page; the Core Session guard does not replace that
local ownership ticket or change the host's ordinary token-refresh epoch policy.
The generic purchase coordinator remains UUID-scoped; other hosts must bind its
existing `currentUserId` callback to their own admitted identity lifetime.
Verified expired/revoked restores replace the matching cached right;
unavailable or unverified checks preserve cache and leave store work retryable.

The package rejects non-HTTPS remote service URLs in development and release.
Loopback HTTP is accepted only outside release builds for the local test stack.
Never embed a service-role key in a mobile app. The publishable key is public
configuration and access depends on RLS and server-side verification.

The current five-app work may use a local path dependency for development.
Before a release candidate, every app must pin the same reviewed Core commit
by immutable Git SHA; a developer-machine path is not a releasable dependency.

Local checks: `flutter analyze --no-pub` and `flutter test --no-pub
test/account_page_test.dart test/runtime_configuration_test.dart
test/runtime_identity_test.dart test/account_lifecycle_race_test.dart`. The
`local_account_integration_test.dart` also requires the dedicated local Motion
Supabase and Mailpit environment variables documented in that test file.

This V4 source proposal's compiler, formatter, analyzer, SDK discovery and test execution
are UNRUN. Test definitions use public SDK setInitialSession/recoverSession,
refreshSession, signInWithPassword, verifyOTP and signOut, held mock HTTP replies
and synchronous lifecycle/resource/Navigator spies. These spies are not native
media, filesystem, provider or five-consumer acceptance. The widget harness
constructs storage, HTTP/receipt/publication Completers in its owned real zone,
unmounts/pumps UI explicitly before real-zone teardown, retains taken replies,
drains all holds and joins observed work with a two-second close budget. It
awaits SupabaseClient.dispose and closes the supplied HTTP client; cached GoTrue
controller close is unawaited internally, so arbitrary internal SDK stream-close
Future settlement is not claimed. Unexpected fixture timeout/failure is
UNACCEPTED, never evidence of Gate correctness. No package version change is
proposed beyond the still-unpublished 0.2.0 baseline.

The isolated V4 successor corrects only the semantics test/public API fixture
and its documentation. Runtime/Gate behavior and all 69 named definitions are
identical to V3. The enabled actual semantics-tree finder
find.semantics.byLabel('PRIVATE_ACCOUNT') checks positive before refresh,
negative while held and positive after reveal. The tester.ensureSemantics()
handle is owned by fake UI teardown: unmount/pump, dispose once, then real SDK
work drain. A count matcher accepts FinderBase<dynamic> in the selected cached
SDK. These are source-backed preparation corrections, not compiler/test GREEN;
V3 remains preserved with REVISE_PREPARATION_ONLY_UNRUN disposition.

## Account copy and host locale integration

The account, identity gate, recovery, deletion and membership surfaces use the
exported `MotionAccountLocalizations` catalog. Its 82 typed
`MotionAccountString` keys contain complete copy for `tr`, `en`, `es-419`,
`pt-BR`, `de`, `fr`, `ja`, `ar`, `it`, `ko`, `id`, `pl`, `hi` and `zh-Hans`. `membershipForApp(String)` owns the named
`{appName}` placeholder; do not concatenate translated membership fragments.
Store-provided `localizedPrice` remains opaque text with its original amount and
currency. Catalog completeness and placeholder parity do not establish native
speaker, legal, screen reader, font or real-device acceptance.

For a host that does not already own localization delegates and a resolver:

```dart
MaterialApp(
  locale: selectedLocale,
  supportedLocales: MotionAccountLocalizations.supportedLocales,
  localizationsDelegates: MotionAccountLocalizations.delegates,
  localeListResolutionCallback:
      MotionAccountLocalizations.localeListResolutionCallback,
  home: accountOrAppHome,
)
```

Hosts with an existing app catalog keep their own locale selection and resolver;
add `MotionAccountLocalizations.delegate` alongside their Material, Widgets and
Cupertino delegates. The selected locale must be in the host's supported list.
The Core lookup uses that inherited locale, including when the host has not
registered the Core delegate. Existing constructors and TR/EN hosts remain valid.
The optional Core resolver selects Latin American Spanish or Brazilian Portuguese
for other variants of those languages and falls back to English for unsupported
languages. The ordered resolver skips preferences absent from a narrower host
list before falling back. Explicit Traditional Chinese (Hant/TW/HK/MO) and other
unsupported scripts do not silently select Hans; the next supported preference
is considered. An explicit Hans script takes precedence over a region hint. Arabic direction comes from `GlobalWidgetsLocalizations`.

The identity gate's nested blocker inherits the parent's selected locale; without
a parent localization scope it resolves the ordered platform preference list. Open status/error
messages retain typed keys and resolve during build. The retained deletion dialog
looks up its own context, so changing locale or removing its account page does not
make it use a disposed State. Paid sales stay disabled by the existing release
policy. Deleting a common account still does not cancel Apple/Google subscriptions;
the translated dialog preserves that separate store-account action.

## Profile read and draft intent

An untouched empty controller is not evidence that a remote profile is empty.
`Save profile` stays disabled until a successful profile read, including a
successful no-row/empty result, or an explicit edit. Editing and then clearing a
name is explicit intent and remains saveable when a read is pending or fails.
Read failure is visible with a separate `Retry profile` button; `Refresh account`
continues to invoke the host's identity callback. A same-owner `userUpdated`
event can retry the profile read while preserving dirty draft intent.

Only this read has a ten-second UI deadline. Timeout exposes retry and cannot
publish a late response. Superseding reads, save, owner change and disposal cancel
the owned timer/local wait; they do not assert that the transport was aborted.
The existing owner, request-generation and mounted checks reject late publication.
A profile save captures the displayed user's ID and name. Its separate UI action
generation/busy lifetime is retired on owner change: an old save success, error
or finally block cannot change the new owner's draft, message or busy indicator.
A retained save callback also checks the captured user before dispatch and the
widget must still be mounted. This is form ownership, not server-side identity
proof, transport cancellation or a backend write-isolation test.

Per-method total deadlines and unknown mutation outcomes are described in
"Deadlines and unknown outcomes (K08)" below; provider deployment and
Choreia's readiness/owner seam still require separate acceptance.

The candidate adds `test/account_localizations_test.dart` and updates
`test/profile_draft_test.dart`. Catalog/source checks using Python are not Flutter
product tests. Compiler, formatter, analyzer and widget execution remain UNRUN
until the execution coordinator grants its owner checkpoint. The current consumer
Git pins and package caches are unchanged; local Core edits do not update the
five apps or deployed packages. No dependency, SDK, SQL, migration, session-store,
store configuration or package version change is part of this candidate.


### Identity gate appearance and host locale

`MotionIdentityGate` accepts optional `theme`, `darkTheme`, and `themeMode`
for its loading/recovery MaterialApp. Without `theme`, it inherits the effective
parent `Theme`. Locale precedence is explicit `locale`, then inherited parent
`Localizations`, then ordered `preferredLocales` or the full device preference
list. An unsupported explicit or inherited locale falls back to English; ordered
list resolution skips unsupported entries to find the next supported preference. `MotionAccountLocalizations.localeListResolutionCallback`
exposes the same ordered resolution to hosts. Presentation updates do not own
identity/admission tickets or change the retained child key.

This local follow-up is separate from published commit `8f38158e`; consumers
must adopt an exact remote commit and run their own regressions. Fourteen-locale
copy belongs to this separate local catalog checkpoint; the published eight-locale
CI result does not establish this checkpoint, a live-auth check or device acceptance.


## Deadlines and unknown outcomes (K08)

Every network method has one total budget started once (`MotionDeadline`):
stages race the same expiry, so per-stage timeouts never reset the total.

| Method | Budget | On expiry or lost reply |
|---|---|---|
| `refreshIdentity` | getUser 10 s inside a 20 s total | latest matching timeout closes the gate; a `user_not_found` cleanup still running at 20 s throws `MotionLocalCleanupPending` |
| reconciliation pass | 10 s per receipt read, 20 s per pass | the pass throws (inconclusive), single-flight is released and the retry timer runs; a stalled receipt is never `false` |
| `continueAsGuest` | 20 s | `MotionOperationUnknown(continueAsGuest)`; no guest success is fabricated. A retry completes locally (the SDK already dropped the token) |
| sign-up, sign-in, reset, resend, password update, sign-out | 20 s | `MotionOperationUnknown(operation)` |
| `saveDisplayName` | 20 s | `MotionOperationUnknown(saveProfile)` |
| `deleteCommonAccount` | 20 s + one 10 s receipt read | positive receipt for the captured UUID continues as a confirmed deletion; otherwise `MotionOperationUnknown(deleteAccount)` and every local file is kept |
| `loadProfile`, `membershipStatus`, receipt read | 10 s | `TimeoutException`; unknown membership never grants access |

Only a definite server rejection (HTTP 4xx, or a decoded PostgREST error) is
rethrown as-is. A timeout, transport loss, retryable/5xx reply or unknown error
after dispatch may follow a committed effect, so it becomes
`MotionOperationUnknown`. Nothing retries a mutation automatically. PostgREST
and Functions requests receive the budget as `abortSignal`, which releases the
local request but never rolls back a server effect. Auth methods have no
per-request abort: a late reply can still publish a Session or event, which the
runtime proof and the page's owner fences handle as an ordinary Auth change.

Admitted cleanup is a per-UUID ticket. Identity, receipt and later passes join
the running ticket instead of erasing twice; a caller's deadline ends only its
own wait. `localCleanupPending` (`ValueListenable<bool>`) is true while such a
ticket outlives its caller. It carries no UUID and is never a success receipt.
The ticket signs out only the exact deleted Session (identity + token), never a
replacement Session, and its logout is bounded too.

`MotionAccountPage` shows an operation-specific explanation for an unknown
outcome and keeps every mutation disabled until the user taps OK or the owner
changes. A delayed sign-in Session simply replaces the unknown state. An
unknown profile save reads the profile once (10 s) and reports whether the
current name equals the entry, without overwriting the draft or replaying the
write; equality is the current postcondition, not an exactly-once receipt. An
unknown sign-out with the local Session gone says the device is signed out and
the remote revoke is unconfirmed. Unknown results for an owner that already
changed are not published.

Host startup (`Supabase.initialize` before `runApp`) is not bounded by Core:
hosts show a first waiting frame and own a startup observer and late-runtime
disposal (Choreia's 20 s pattern). Store purchase/provider budgets stay with
the paid path, which remains closed for the first release.

## 13+ age gate and parental consent

The shared account is 13+ in every country. `MotionAgePolicy` maps an ISO
3166-1 alpha-2 region to its digital-consent age (EU/EEA GDPR Art. 8 values,
US 13, others in the source table; unknown regions use 16). These are
engineering defaults pending counsel review, not legal advice; the SQL copy in
`supabase/migrations/20261021190000_motion_age_consent_retention.sql` must stay
identical (a package test checks parity).

`MotionAccountPage` asks a neutral birth month and year (no preselection, no
day) before sign-up. Pass the store/device region as `countryCode`. Under 13 no
request is sent, `onAgeBlocked` fires so the host can persist the result, and
`ageBlocked: true` keeps sign-up closed on later visits. `signUpWithAge(age:)` sends
only `{birth_year_month, country, policy_version}` as Auth metadata; a server
trigger stores it in `motion_age_declarations`, strips it from metadata and
rejects an under-13 declaration.

Region source (founder decision 23 Oct): an explicit `countryCode` wins;
otherwise the page reads the store account region once at sign-up or age
confirmation (`storefrontCountry`, default `motionStorefrontCountry` from
`motion_entitlements`: App Store storefront alpha-3 or Play billing alpha-2,
normalised to alpha-2, bounded to 3 s) and falls back to the device region.

Signed-in hosts read `ageStatus()` (`MotionAgeStatus`): `declared`, `consent`
and `restrictedOn(today)`. A restricted account (below its consent age without
parent approval) keeps local practice but cannot write the shared profile
(RLS). The page shows the parent/guardian request form and calls
`requestParentalConsent(parentEmail:, locale:)`; refusals arrive as
`MotionConsentRequestRefused` and a lost reply as `MotionOperationUnknown`.
An undeclared legacy account is asked once (`recordAgeDeclaration`).
`MotionAgePolicy.marketingAllowed(band)` is false and
`analyticsNeedsOptIn(band)` is true for every user under 18: hosts must not
send teen marketing, personalised ads, or default-on analytics.

The parent approves or declines on the YULAlab site consent page through the
`motion-parental-consent` Edge Function. Approval lifts the restriction; denial
deletes the account (deletion receipt included). The parent address is stored
only as a digest. Mail delivery needs `MOTION_MAIL_API_URL`, `MOTION_MAIL_API_KEY`
and `MOTION_MAIL_FROM`; without them the request fails closed with
`mail_unavailable`. The consent page calls `view`/`decide` from the browser:
origins listed in `MOTION_CONSENT_ALLOWED_ORIGINS` (comma-separated, default
`https://yulalab.com`) receive CORS headers; no wildcard, and app requests
without an `Origin` header are unchanged. Retention and restore re-application are described in
`docs/compliance/YAS-VELI-VE-SAKLAMA.md`.

## Subscription sales (first release)

`motionSubscriptionSalesAvailable` is true (founder decision 23 Oct 2026): all
five apps sell their own subscription and Motion+. Camera coaching,
measurement and scoring stay closed behind `motionCameraCoachingAvailable`
(false). Since 0.4.0:

- `MotionAccountPage(membershipAvailable:)` defaults to the sales constant, so
  the page shows the membership row and checks membership on open. Pass
  `membershipAvailable: false` for a build that does not sell. The old
  `paidFeaturesAvailable` parameter is a deprecated alias that wins when set.
- `requireMotionPaidAccess` (paid lesson / practice start) follows the sales
  constant through `salesAvailable`; the old `paidFeaturesAvailable` is a
  deprecated alias. A host that relied on the old closed default to keep a
  camera path shut must gate that path with `requireMotionCameraAccess` (or
  `motionCameraCoachingAvailable`) first.
- `motionPaidFeaturesAvailable` is deprecated and stays false; it was the
  camera gate in every host. Never switch it on.
- The free-lesson rule (paywall A) lives in `motion_entitlements`:
  `motionFreeLessonLimit`, `isLessonUnlocked` (with a `freeLessonLimit`
  override for an approved per-course count) and `isPracticeUnlocked`.
  Recorded progress is always readable.

Free trial (0.5.0): `StoreProductRef.freeTrialPeriod` is filled only when the
store offers this account a free trial — on Google Play a free-trial offer
attached to the base plan (bought through that offer's token), on the App
Store the StoreKit 2 introductory free trial confirmed by
`isIntroductoryOfferEligible`. The membership page then shows "N days free,
then {store price} per month/year" and the trial renewal/cancellation terms;
without a store trial nothing about a trial is shown. No price or trial length
is hard-coded.

`MotionMembershipPage` offers no purchase to an account restricted by missing
parental consent; restoring an existing store purchase stays available and
server verification is unchanged (a paid store purchase is never refused).
