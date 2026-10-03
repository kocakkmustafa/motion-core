# motion_telemetry

Telemetry requires the event allowlist, explicit consent and a bounded typed
attribute policy. `content_validation_result` also enforces its closed field
schema independently of caller-provided allowlist implementations. Raw content,
sensor readings and media are not fields in that schema.
Consent is checked again immediately before dispatch, after caller-owned value
getters have been snapshotted. Revocation during that work suppresses dispatch.

## 0.4.0 diagnostic policy migration

`DiagnosticExporter` keeps the explicit preview and confirmation requirement,
the four canonical field shapes, and the 4 KiB hard output limit. It now accepts
at most **64 approved code entries** in `DiagnosticExportPolicy.allowedCodes`.
Larger policies must be narrowed before adoption. The existing const policy
constructor and `Set<String>` input remain available.

Membership is checked by bounded enumeration with exact string equality.
Overridden `contains` is ignored. Oversized or inconsistent enumeration and
failing caller-owned policy getters are rejected with the closed
`disallowedPolicyValue` reason. Configured byte limits are fixed internally;
overriding the public getter cannot widen them.

These are local source privacy boundaries. Passing local tests does not prove
provider consent, device behavior or production telemetry acceptance.
