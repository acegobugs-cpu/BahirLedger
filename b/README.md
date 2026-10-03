# BahirLedger backend

Java 21 / Spring Boot 4.1.1 modular backend. **BahirLedger-managed email/password
sign-in is the default; organization SSO is optional future work.** Backend email
verification and the [Flutter verification UI](../ui/README.md) are implemented,
including link capture, token entry and the pending-account gate. Live HTTP/file-delivery
and browser-link/CORS checks passed; the full interactive browser login → verification
→ account journey remains unvalidated. See [validation limits](#verification-validation--2026-10-03).

## Private properties workflow

**All backend runtime configuration belongs in the private
[src/main/resources/application.properties](src/main/resources/application.properties),
not a run script or environment setup.** This file is ignored and untracked;
removing it from Git's index preserved the file on disk. The committable
[src/main/resources/application.properties.example](src/main/resources/application.properties.example)
is the credential-free template, not a file Spring loads automatically.

1. If the private file already exists, **keep it; do not overwrite it with the
	example**. Its existing database values are preserved. Only for a new checkout
	where it is absent, copy the example in the editor to the private file beside it.
2. Edit private values in the editor. The template leaves database credentials,
	SMTP sender, username and password blank. It selects Gmail SMTP on port **587**
	with required STARTTLS, both frontend origins at `http://localhost:8765`, and
	explicit `bahirledger.mail.allow-loopback-http=true` for development.
3. In the existing private file the sender is already filled; the SMTP password
	is still blank. Enter your Google app password into
	`bahirledger.mail.smtp.password` **in the editor, never in chat**. For a fresh
	copy, also fill database credentials and matching Gmail sender/login. Blank
	required credentials are not a usable startup configuration.
4. With a full JDK 21 selected and PostgreSQL available at the configured address,
	run the normal `./mvnw spring-boot:run` from the backend directory after filling
	credentials. Register through the UI; legacy local provisioning is not needed.

No launcher is required. The existing local environment file is untouched and is
not loaded. Neither properties file nor the optional local profile uses environment
placeholders; the backend reads canonical `bahirledger.database.*` properties
directly, without a custom `BAHIRLEDGER_DB_*` override. Editing a file does not
reconfigure an already-running process; this documentation update does not start
or restart the backend.

**Secret hygiene:** ignoring/untracking a file does not erase previous commits.
Rotate any real credentials previously committed; do not assume Git history is
clean. Maven resource copying and packaging include the private configuration in
build output and executable JARs. **Do not publish JARs or other build artifacts
containing secrets.** Keep the template credential-free and protect private files,
backups and artifacts with appropriate access controls.

## HTTP contract

The [OpenAPI contract](src/main/resources/contracts/openapi.yaml) is committed, not served publicly.

| Operation | Success | Failure |
| --- | --- | --- |
| `POST /api/v1/auth/register`, JSON `{email,displayName,password}` | `200 {accessToken,expiresAt,user:{id,email,displayName,emailVerified:false}}`, after email acceptance | `400` validation, `409` duplicate, `429` throttled, `503` delivery/database unavailable |
| `POST /api/v1/auth/login`, JSON `{email,password}` | `200 {accessToken,expiresAt,user:{id,email,displayName,emailVerified}}` | `400` validation, `401` invalid credentials, `429` throttled |
| `GET /api/v1/me`, `Authorization: Bearer <token>` | `200 {id,email,displayName,emailVerified}` | `401` missing/invalid/expired/revoked token or inactive account |
| `POST /api/v1/auth/email-verification/confirm`, same bearer, JSON `{token}` | `200 {id,email,displayName,emailVerified:true}` (same shape as `/me`) | `400` invalid token/request, `401` bearer/inactive account, `429` throttled, `503` database unavailable |
| `POST /api/v1/auth/email-verification/resend`, same bearer, **no body** | `204`, delivery accepted or already verified (no email) | `400` nonempty body, `401` bearer/inactive account, `429` throttled/cooldown, `503` delivery/database unavailable |
| `POST /api/v1/auth/logout`, same bearer header | `204`, empty body; revoke this session only | `401`, including repeated logout |
| `GET /api/v1/health` | `200 {"status":"UP"}`, process liveness only | Not database readiness |

- Only registration, login and GET health are public application operations. Explicit CORS
	preflights for these listed operations are also allowed. **Everything else is
	denied**, including the unimplemented `/auth/signup` alias, refresh, membership, business APIs, form login,
	HTTP Basic, actuator and contract-file serving.
- Unknown email, wrong password and inactive account return exactly
	`{"code":"invalid_credentials","message":"Email or password is incorrect."}`.
- Other errors are generic JSON `{code,message}` with no exception, SQL, account,
	submitted field or credential details. Database failures are `503`; unexpected
	controller failures are `500`. CORS/CSRF/authorized-but-denied requests are `403`.
- Authentication and identity responses (including errors) use `Cache-Control:
	no-store`. No authentication cookies, redirects or HTTP sessions are created.
- Email is stripped and lowercased with `Locale.ROOT`, then validated (maximum
	254 characters). Password is never trimmed: nonblank, at most **72 UTF-8 bytes**,
	also at most 72 Java characters. Registration display names are nonblank and at
	most 72 characters. Login, registration and confirmation bodies are bounded to **4096 bytes**,
	including chunked requests. Unsupported media types return generic `400`.
- Accounts expose only a stable UUID, normalized email, display name and required
	boolean `emailVerified`. `/me`
	**does not return organization/project membership or authorization grants**.

### Verification lifecycle

- New, migrated and locally provisioned accounts have `emailVerified=false`.
	Nothing implicitly verifies existing accounts. Login, `/me`, account-only
	sessions and logout remain available while pending. Login does not send mail.
- Registration sends once for the newly inserted account. A duplicate email,
	including a simultaneous unique-constraint race, returns `409` and sends no mail.
	Successful signup/login still issue **30-minute account-only** sessions.
- Delivery failure during registration returns generic `503`; the pending account
	can remain. No bearer session is allocated before successful delivery. The frontend
	should offer **login, then resend after cooldown**, not a phantom verified success
	or repeated registration. Session-capacity failure can likewise leave an account
	and accepted email without a returned session; login after backing off.
- Confirmation requires a **current bearer for the same active account** plus the
	43-character base64url token. Invalid, expired, replayed, rotated or wrong-account
	tokens return exactly `400 {"code":"invalid_verification_token","message":
	"Verification token is invalid or expired."}`. Missing/null/malformed token
	strings share that response. Malformed/missing JSON, wrong media type or oversized
	bodies use `400 invalid_request`. Bearer errors and deactivated accounts use `401`.
- Tokens contain 32 secure random bytes, expire strictly at 30 minutes, and are
	stored only as SHA-256 digests with account FK and expiry. Database timestamps
	use microsecond precision. Resend replaces the previous token. Confirmation clears
	the digest and sets the account flag in one transaction. Both operations lock the
	account row, so concurrent consumption has one winner and resend cannot race past it.
- Resend has a **persistent 60-second account cooldown**, including delivery failures.
	A failed send clears the newly rotated token; the previous token is no longer valid.
	Verified-account resend is `204` without delivery (source limits still apply).
- Verification does not renew sessions or grant tenant access. All tenant routes
	remain denied equally for pending and verified users. Future tenant endpoints
	must check **verified email AND tenant membership**; no organization API is added.

### Frontend integration requirements

Store the opaque bearer token **only in frontend memory, including on web**.
Never put it in cookies, localStorage, sessionStorage, persistent preferences,
URLs, logs or analytics. Send it only in the Authorization header; never use
`credentials: include`. Clear it on logout, expiry or an authentication `401`;
client reload/restart requires signing in again. The Flutter client implements this
memory-only session model and loads `/me` before showing the account screen.

Tokens contain 32 securely random bytes encoded as 43 base64url characters (not
JWTs). `expiresAt` is an absolute UTC ISO-8601 timestamp, **30 minutes** from
issuance. `/me` does not extend expiry, and there is **no refresh token**. Backend
memory stores only SHA-256 token digests plus account IDs and expiry. Restarting
the backend invalidates every session but **does not delete durable accounts**.
The active account is checked in JDBC on each authenticated request.

Verification email links use the configured public frontend origin and fixed
fragment route `/#/verify-email?token=TOKEN`. The fragment is not sent to an HTTP
server or in HTTP referrers. Email also includes the token for manual paste/native
clients. The [Flutter client](../ui/README.md) captures it ephemerally and scrubs the
current URL/history entry before UI handling, then requires matching-account sign-in
and explicit confirmation. Never log/track it or automatically submit from a GET;
do not change the link to an API/query-string URL. Native manual paste is implemented,
not OS universal/app links. Scrubbing cannot erase pre-startup browser/provider
records. The backend does not serve this page.

## Verification delivery setup

Configure these properties directly in the [private runtime file](src/main/resources/application.properties).
The template explicitly selects **SMTP**; the adapter's fallback when no mode is
configured is **disabled**, not simulated success. Disabled registration and
pending-account resend return `503`; ordinary login still works. Invalid enabled
SMTP configuration fails startup. All errors are sanitized. Links are built from
configuration, **never Host, Origin or forwarded request headers**.

| Property | Meaning |
| --- | --- |
| `bahirledger.mail.mode` | `smtp` in the template; `disabled` fallback, or explicit-local-only `file` |
| `bahirledger.mail.verification-web-origin` | Exact frontend origin, no path/trailing slash/query/fragment/userinfo. Template: `http://localhost:8765`. HTTPS outside loopback development |
| `bahirledger.mail.allow-loopback-http` | Explicit `true` in the development template permits HTTP email links only for localhost/127.0.0.1/::1 without selecting H2; otherwise false by default, with an exclusively local-profile exception. Does not permit external HTTP or plaintext Gmail SMTP; use false and HTTPS for deployment |
| `bahirledger.mail.smtp.host` | `smtp.gmail.com` in the template |
| `bahirledger.mail.smtp.port` | `587` in the template; implicit TLS/465 is not supported |
| `bahirledger.mail.smtp.from` | Explicit single sender email address; blank in the template |
| `bahirledger.mail.smtp.username` / `bahirledger.mail.smtp.password` | Gmail sender login and Google app password; blank in the template. Both required for Gmail; both empty is only for a trusted relay |
| `bahirledger.mail.smtp.starttls` | `true` in the template, requires STARTTLS and server certificate/hostname validation. `false` allowed only with exclusively `local` active and a literal loopback SMTP host |
| `bahirledger.auth.web-origin` | Separate exact browser CORS origin; template: `http://localhost:8765`. Empty disables cross-origin access; current policy is loopback-only. Change both frontend origins together if the web port changes |

SMTP uses Spring Mail with **5-second connection, read and write timeouts**, no
mail debug/wire logging, and at most four concurrent delivery operations. STARTTLS
is mandatory outside the explicit local loopback exception; implicit TLS/port 465
is not implemented by this adapter. Invalid enabled-mail configuration fails
startup with a generic configuration message; unavailable delivery fails requests
with `503`. Do not enable request/JDBC-bind/mail debug logging in deployment.

### Explicit local file outbox

In the private runtime file, explicitly set `spring.profiles.active=local` (not
combined with another profile), `bahirledger.mail.mode=file`, and
`bahirledger.mail.verification-web-origin` to your local frontend origin. This
also selects H2 instead of PostgreSQL; it is not needed for Gmail. No SMTP settings
are required for file mode. Mail is written outside the
checkout under `$HOME/.local/share/bahirledger/mail` (Java `user.home`), with a
**0700 directory and 0600 randomly named `.eml` files**. Paths are traversed using
POSIX secure directory handles with no symlink following; files use exclusive
creation and cannot overwrite a collision. Unsupported filesystems, symlink paths,
permission failures or writes fail with `503`. This mode does not send email to an
inbox and is never allowed outside the exclusively local profile.

Outbox files intentionally contain verification tokens, so keep them private,
never commit/share them, and delete them after use. No automatic retention cleanup
is implemented. Tests use a separate in-memory capturing sender and temporary test
outbox directories, never this real user outbox.

### Gmail SMTP for development

Gmail can deliver to other providers, including Outlook and Yahoo; recipients do
not need Gmail accounts. Use a Gmail/Google Workspace sender with 2-Step
Verification and a Google **app password**, not the normal account password.
Account/organization policy may disable app passwords. Create one through
[Google App passwords](https://myaccount.google.com/apppasswords).

Follow the [private properties workflow](#private-properties-workflow): enter the
app password without grouping spaces in the editor, keeping the SMTP sender and
login matched. The template already sets `smtp.gmail.com:587` and required STARTTLS.
No script, environment exports or H2 profile is required; existing PostgreSQL
settings stay in use. The explicit loopback-HTTP flag affects email links only,
not SMTP encryption or database selection.

For a previously created pending account, **sign in and resend verification** after
the 60-second cooldown; do not repeatedly register. SMTP acceptance still does not
guarantee inbox delivery—check spam and provider limits. Never share app passwords,
verification tokens or secret-bearing build artifacts.

### Reliability limits

Delivery is synchronous under a database account lock, not a durable mail worker.
`204`/registration `200` means adapter/relay acceptance, **not inbox delivery**.
SMTP can accept mail and then lose its acknowledgment, or a database commit can
fail after acceptance; the resulting email may contain an unusable token. There
is no automatic retry, delivery-status tracking, bounce processing or atomic
database/SMTP transaction. Partial file writes may leave an unusable local message.
Log in and resend after cooldown. Transport timeouts bound individual I/O operations,
not every possible DNS/provider delay; upstream request/time/abuse limits are still
required. This slice does not claim reliable background delivery or production readiness.

## Build and tests

Use a **full JDK 21**, not a JRE (the shell default may be Java 17).
From the backend directory, run `./mvnw verify` with that JDK selected.

Use `mvnw.cmd verify` on Windows. The Maven wrapper downloads dependencies; global
Maven is not required. Tests supply a **test-only H2 in-memory DataSource** and a
controllable clock, with no database server or real credentials. There is no
runtime `test` profile that enables an embedded database. Dedicated test-only
configuration keeps tests independent of private database/SMTP values; tests do
not require a Gmail app password or contact the real database/mail service. The
parent change owns that test configuration; this documentation pass does not add
or rerun tests. The production DataSource requires PostgreSQL configuration and
never falls back to H2. Existing private database values are preserved.

Boot manages Spring JDBC, Flyway 12.4.0, PostgreSQL JDBC 42.7.13 and H2 2.4.240.
Flyway's H2 adapter currently emits a warning that its latest verified H2 version
is 2.3.232; the Boot-managed 2.4.240 migration and JDBC behavior are exercised by
these tests. No dependency is downgraded just to hide the warning.

### Verification validation — 2026-10-03

Implementation-agent results: **112 backend tests pass**; **198 Flutter tests pass**,
zero analyzer issues and release web build passes. These were not rerun by the parent
or this documentation pass; generated source is unchanged. The parent live checks used
an isolated packaged backend with full JDK 21, explicit local profile, port 18080 and
private disposable HOME/H2/file outbox, applying real V1 + V2 migrations. HTTP signup,
0600 file delivery, immediate resend cooldown, same-account file-token confirmation,
verified `/me`, replay denial and project denial passed. Actual signed-out browser
navigation scrubbed the emailed fragment token and displayed the matching-account
sign-in prompt; verification preflights and browser-origin login/confirm/replay/me/logout
Fetch requests passed CORS. An exploratory project Fetch was correctly CORS-denied,
not an authentication failure; project `403` was checked separately over HTTP.

**Not full browser UI end to end:** keystrokes did not reliably update Flutter
controllers, so form-click login → verification → account and remaining manual paths
are still pending despite automated UI coverage. Live SMTP/inbox delivery, PostgreSQL
and native-device checks remain unvalidated. The user's current server/database were
untouched; the parent owns cleanup of only its temporary preview and test data.

## Explicit local development profile

Set `spring.profiles.active=local` in the private runtime file **only when explicitly
choosing H2 on a developer machine**. The
[src/main/resources/application-local.properties](src/main/resources/application-local.properties)
profile binds the server to loopback and uses
file-backed H2 under `$HOME/.local/share/bahirledger/accounts` (H2 adds its file
extension). The database is not ephemeral and is outside the checkout. H2 has no
TCP listener/console here; its local `sa`/empty database login is not an application
account or a deployment credential. Protect the directory with OS permissions.

The profile inherits CORS and mail settings from the private runtime file; it
does not replace them with environment placeholders. It is **not required for
normal PostgreSQL/Gmail startup**. Register through the UI. Optional legacy local
account provisioning remains create-only and is unnecessary for this workflow;
there are no default application credentials or startup password resets. Do not
activate the local profile in production, including alongside other profiles.
Accounts persist across restart; in-memory bearer sessions do not.

**Repository hygiene:** the private runtime file is ignored/untracked. The default external data
directory needs no Git exclusion. If relocating H2 or PostgreSQL data inside the
checkout, first arrange a local exclusion for that chosen data directory (for
example `b/data/`) and database files (`*.mv.db`, `*.trace.db`, lock files); those
paths are **not added to the repository's ignore rules by this change**. Do not
commit accounts, database dumps, passwords or tokens.

## PostgreSQL deployment target

With no local profile, the DataSource reads these canonical properties directly
from the private runtime configuration; no custom database environment override
is required or supported:

| Property | Purpose |
| --- | --- |
| `bahirledger.database.url` | PostgreSQL JDBC URL; template: `jdbc:postgresql://localhost:5433/bahir_ledger`. Adjust to the actual service; use verified TLS for deployment |
| `bahirledger.database.username` | Database service identity; blank in the template, fill privately |
| `bahirledger.database.password` | Database password; blank in the template, fill privately |

**The current database property values were deliberately preserved, not replaced.**
They are private, not checked-in configuration. Before deployment, review protected
configuration/artifact handling and secret management; never publish the development
JAR with embedded credentials. Use a private database with TLS, suitable permissions
and backups.
Keep credentials out of the JDBC URL, command arguments and logs. Flyway applies
[V1 account migration](src/main/resources/db/migration/V1__accounts.sql) and
[additive V2 verification migration](src/main/resources/db/migration/V2__email_verification.sql)
at startup, validates checksums, and disables clean. Its schema contains stable
UUID IDs, a unique normalized email, display name, BCrypt hash, active flag and
default-false verification flag, plus the rotating verification digest/cooldown table.
There is no destructive schema recreation or startup password overwrite. The
database identity currently needs migration privileges; separating migration and
runtime identities is a deployment-hardening follow-up.

Run with the completed private properties via `./mvnw spring-boot:run`. An executable
JAR produced by `verify` also contains resource configuration and must remain private
if it includes credentials. Public managed registration is implemented, but production
invitations and tenant membership are not. PostgreSQL is the implemented target, but
this test suite does not certify a live PostgreSQL deployment. V1-to-V2 preservation,
token storage and concurrent transactions are tested with H2 only. Live HTTP/file-delivery
and browser-link/CORS checks are recorded [above](#verification-validation--2026-10-03),
not live SMTP, PostgreSQL or full interactive browser UI validation. No migrations
were run against an existing user server/database during these checks.

## Security boundary and limits

- BCrypt cost is fixed at 12 with a dummy match for unknown users. Up to four
	password checks run concurrently; excess work returns `429` rather than queuing.
- Five-minute per-process fixed windows allow 5 attempts per normalized email,
	20 per direct source IP and 100 globally, including successes. Invalid JSON
	counts toward source/global limits. Windows are reclaimed lazily. No account
	existence information is used to decide throttling.
- Throttle state is capped at 10,000 hashed keys; sessions at 10,000 entries.
	Saturation fails closed with `429` instead of evicting live limits/sessions.
	Expired entries are reclaimed lazily before checks/issuance. There is no
	`Retry-After` promise: session capacity may require logout/expiry; a client
	should back off. In-memory limits reset on restart; the verification resend
	cooldown is persisted and does not reset.
- Verification has separate five-minute budgets: confirmation **10/account,
  20/direct source, 100/global**; resend **3/unverified account, 10/direct source,
  30/global**. Malformed authenticated requests and successes count. Source budgets
  apply to verified resend no-ops too. Source checks precede confirmation body parsing;
	account limits cannot be reset by issuing another bearer. The verification budget
	map is capped at 10,000 hashed keys and fails closed. Signup email sends remain
  bounded by registration's shared login/source/password-work limits and durable cooldown.
- Forwarded source-IP headers are intentionally ignored. Behind a proxy, clients
	will share its source-IP limit until trusted-proxy/distributed rate limiting is
	deliberately implemented. TLS termination, request timeouts and upstream
	connection/body/rate limits are deployment responsibilities.
- CORS accepts only one exact configured loopback origin, the listed methods per
	route, Authorization and Content-Type headers. No wildcards or credentials.
	Different ports, `null` origins, unlisted routes/methods/headers are denied.
	The private template explicitly configures localhost port 8765 independently of
	the local database profile. Non-loopback browser
	origins require a subsequent reviewed deployment policy, not a wildcard workaround.
- CSRF ignores only exact **POST** login, register, logout, email-verification/confirm
	and email-verification/resend, since credentials/tokens are explicit
	and no ambient cookie authentication exists. Every other unsafe route retains
	CSRF enforcement and is denied. Its nonpersisting CSRF repository deliberately
	cannot create sessions or issue usable CSRF tokens for nonexistent write APIs.
- Request bodies/headers, passwords and raw tokens are never logged by application
	code. Error responses and credential DTO diagnostic strings are sanitized. Do
	not enable request-body/JDBC bind/HTTP wire logging or add credentials to proxy
	access logs. Generic errors intentionally omit exception details.

## Not production-ready

Still missing: invitations, password recovery/change,
MFA, optional organization SSO and account linking/recovery, distributed durable
session/revocation and throttle storage, comprehensive audit/abuse monitoring,
deployment-scale rate policy, tenant isolation and membership/business endpoints.
Single-process throttling may be used for denial of service, and restarting the
process resets it. Do not deploy multiple independent replicas and assume sessions
or limits are shared. HTTPS is mandatory outside loopback development.

Internal `AccessPolicy` remains a separately tested policy primitive, not a
membership API or full authorization implementation. VS Code backend verify/run
tasks can still be used with a full JDK 21 and completed private properties. Do not disable
the fail-closed boundary to experiment with future endpoints.
