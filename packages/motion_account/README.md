# Motion account foundation

One Supabase identity serves Ostinato, Gravita, Choreia, JabLab, and Lissom.
Subscription rights remain scoped to the signed-in user **and** one app.
Version 0.2.0 adds the recovery listenable below and requires the deletion
response upgrade described here. Entitlement fixes ship as version 0.1.1.

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
