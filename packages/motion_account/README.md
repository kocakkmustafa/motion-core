# Motion account foundation

One Supabase identity serves Ostinato, Gravita, Choreia, JabLab, and Lissom.
Subscription rights remain scoped to the signed-in user **and** one app.

Host apps initialize `MotionAccountRuntime` once before `runApp` with the same
Motion project URL and publishable key, their own `MotionApp` value, and the
matching callback `com.yulalab.<app>://auth/callback`. The native iOS and
Android callback registrations and the Supabase Auth redirect allow-list must
match that exact URI. The runtime exposes `account` for `MotionAccountPage` and
`userId` as a `ValueListenable<String?>` for local-data ownership. Hosts must
wrap their shell in `MotionIdentityGate`: null ID may mean signed out, still
verifying, or network unavailable. Only `signedOut` may open guest history;
only `verified` may open account history. A stored session does not prove that
the account still exists until the Auth server confirms it.
If verification is unavailable, the gate offers a local-only guest path. It
discards the unverified cached session without deleting account-owned files;
the user must sign in again to reopen that account's history.
Pass `runtime.isPasswordRecovery` to the page's `initialPasswordRecovery`
parameter when routing rebuilds after an auth callback.

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

The package rejects non-HTTPS remote service URLs in development and release.
Loopback HTTP is accepted only outside release builds for the local test stack.
Never embed a service-role key in a mobile app. The publishable key is public
configuration and access depends on RLS and server-side verification.

The current five-app work may use a local path dependency for development.
Before a release candidate, every app must pin the same reviewed Core commit
by immutable Git SHA; a developer-machine path is not a releasable dependency.

Local checks: `flutter analyze --no-pub` and `flutter test --no-pub
test/account_page_test.dart test/runtime_configuration_test.dart
test/runtime_identity_test.dart`. The
`local_account_integration_test.dart` also requires the dedicated local Motion
Supabase and Mailpit environment variables documented in that test file.
