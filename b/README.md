# BahirLedger backend

Java 21 / Spring Boot 4.1.1 modular backend. **BahirLedger-managed email/password
sign-in is the default; organization SSO is optional future work.** Backend email
verification and the [Flutter verification UI](../ui/README.md) are implemented,
including link capture, token entry and the pending-account gate. Live HTTP/file-delivery
and browser-link/CORS checks passed; the full interactive browser login → verification
→ account journey remains unvalidated. See [validation limits](#verification-validation--2026-10-03).

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

Delivery defaults to **disabled**, not simulated success. Unconfigured registration
and pending-account resend return `503`; ordinary login still works. All errors are
sanitized. Links are built from configuration, **never Host, Origin or forwarded
request headers**.

| Environment variable | Meaning |
| --- | --- |
| `BAHIRLEDGER_MAIL_MODE` | `disabled` (default), `smtp`, or explicit-local-only `file` |
| `BAHIRLEDGER_VERIFICATION_WEB_ORIGIN` | Required when delivery is enabled: exact public frontend origin, no path/trailing slash/query/fragment/userinfo. HTTPS required; HTTP allowed only for localhost/127.0.0.1/::1 with exclusively `local` active. Example `https://app.example.test` or local `http://localhost:8765` |
| `BAHIRLEDGER_SMTP_HOST` | Required SMTP host in `smtp` mode; no provider assumed |
| `BAHIRLEDGER_SMTP_PORT` | SMTP port, default `587` |
| `BAHIRLEDGER_SMTP_FROM` | Required explicit single sender email address in `smtp` mode |
| `BAHIRLEDGER_SMTP_USERNAME` / `BAHIRLEDGER_SMTP_PASSWORD` | Both supplied for SMTP AUTH, or both empty for a trusted relay; use deployment secrets |
| `BAHIRLEDGER_SMTP_STARTTLS` | `true` by default, requires STARTTLS and server certificate/hostname validation. `false` allowed only with exclusively `local` active and a literal loopback SMTP host |
| `BAHIRLEDGER_WEB_ORIGIN` | Separate existing browser CORS origin; now environment-configurable outside local too, empty disables browser cross-origin access. Still restricted to the existing exact loopback-origin policy |

SMTP uses Spring Mail with **5-second connection, read and write timeouts**, no
mail debug/wire logging, and at most four concurrent delivery operations. STARTTLS
is mandatory outside the explicit local loopback exception; implicit TLS/port 465
is not implemented by this adapter. Invalid enabled-mail configuration fails
startup with a generic configuration message; unavailable delivery fails requests
with `503`. Do not enable request/JDBC-bind/mail debug logging in deployment.

### Explicit local file outbox

With `SPRING_PROFILES_ACTIVE=local` (not combined with another profile), opt in with
`BAHIRLEDGER_MAIL_MODE=file` and set `BAHIRLEDGER_VERIFICATION_WEB_ORIGIN` to your
local frontend origin. No SMTP settings are required. Mail is written outside the
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

Use a **full JDK 21**, not a JRE (the shell default may be Java 17). On this machine
the verified installation is `/home/ace/.cache/bahirledger/jdk-21`.

From the backend directory:

```sh
export JAVA_HOME=/home/ace/.cache/bahirledger/jdk-21
export PATH="$JAVA_HOME/bin:$PATH"
./mvnw verify
```

Use `mvnw.cmd verify` on Windows. The Maven wrapper downloads dependencies; global
Maven is not required. Tests supply a **test-only H2 in-memory DataSource** and a
controllable clock, with no database server or real credentials. There is no
runtime `test` profile that enables an embedded database. The production DataSource
requires PostgreSQL configuration and never falls back to H2. Current checked-in
local database property values are preserved by this change; tests override the
DataSource and do not connect to them.

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

Set `SPRING_PROFILES_ACTIVE=local` **only on a developer machine**. It binds the
server to loopback, defaults the web origin to `http://localhost:8765`, and uses
file-backed H2 under `$HOME/.local/share/bahirledger/accounts` (H2 adds its file
extension). The database is not ephemeral and is outside the checkout. H2 has no
TCP listener/console here; its local `sa`/empty database login is not an application
account or a deployment credential. Protect the directory with OS permissions.

Account provisioning is opt-in: supply **all three** environment variables
`BAHIRLEDGER_DEV_EMAIL`, `BAHIRLEDGER_DEV_PASSWORD`, `BAHIRLEDGER_DEV_NAME`.
There are **no default application credentials**. Unset all three to skip it;
partial/invalid values stop startup. The display name must be nonblank and at most
120 characters after stripping. Existing normalized emails are left completely
unchanged (password, display name, ID and active status); startup is not a password
reset facility. A database unique constraint also handles simultaneous provisioning.

Example interactive Bash setup, without storing the password in command history:

```sh
umask 077
mkdir -p "$HOME/.local/share/bahirledger"
chmod 700 "$HOME/.local/share/bahirledger"
read -r -p 'Development email: ' BAHIRLEDGER_DEV_EMAIL
read -r -p 'Development display name: ' BAHIRLEDGER_DEV_NAME
read -r -s -p 'Development password: ' BAHIRLEDGER_DEV_PASSWORD
printf '\n'
export BAHIRLEDGER_DEV_EMAIL BAHIRLEDGER_DEV_NAME BAHIRLEDGER_DEV_PASSWORD
SPRING_PROFILES_ACTIVE=local ./mvnw spring-boot:run
unset BAHIRLEDGER_DEV_EMAIL BAHIRLEDGER_DEV_NAME BAHIRLEDGER_DEV_PASSWORD
```

Only the BCrypt encoding (cost 12) is persisted, never plaintext. The bootstrap
component exists only in the local profile. Do not activate that profile in
production, including alongside other profiles. Subsequent local runs need only
the local profile; the database retains the original account. Environment variables
are not a secret vault; use only disposable development credentials and unset them
when no longer needed. The application does not automatically load `.env` files.

**Repository hygiene:** no ignore files were changed. The default external data
directory needs no Git exclusion. If relocating H2 or PostgreSQL data inside the
checkout, first arrange a local exclusion for that chosen data directory (for
example `b/data/`) and database files (`*.mv.db`, `*.trace.db`, lock files); those
paths are **not added to the repository's ignore rules by this change**. Do not
commit accounts, database dumps, passwords or tokens.

## PostgreSQL deployment target

With no local profile, the DataSource accepts these environment overrides (nonblank
environment values take precedence over existing database properties):

| Environment variable | Purpose |
| --- | --- |
| `BAHIRLEDGER_DB_URL` | PostgreSQL JDBC URL, e.g. `jdbc:postgresql://db-host:5432/bahirledger?sslmode=verify-full` |
| `BAHIRLEDGER_DB_USERNAME` | Database service identity, supplied by deployment secrets |
| `BAHIRLEDGER_DB_PASSWORD` | Database password, supplied by deployment secrets |
| `BAHIRLEDGER_WEB_ORIGIN` | Optional single exact localhost HTTP(S) origin with explicit port; empty disables cross-origin access |

**The current database property values were deliberately preserved, not replaced.**
Review and externalize machine-local database settings before any
deployment; environment secrets are the intended deployment mechanism. Use a private
database with TLS, suitable permissions, backups and an external secret manager.
Keep credentials out of the JDBC URL, command arguments and logs. Flyway applies
[V1 account migration](src/main/resources/db/migration/V1__accounts.sql) and
[additive V2 verification migration](src/main/resources/db/migration/V2__email_verification.sql)
at startup, validates checksums, and disables clean. Its schema contains stable
UUID IDs, a unique normalized email, display name, BCrypt hash, active flag and
default-false verification flag, plus the rotating verification digest/cooldown table.
There is no destructive schema recreation or startup password overwrite. The
database identity currently needs migration privileges; separating migration and
runtime identities is a deployment-hardening follow-up.

Run with the configured environment via `./mvnw spring-boot:run` or the executable
JAR produced by `verify`. Public managed registration is implemented, but production
invitations and tenant membership are not. `BAHIRLEDGER_DEV_*`
has no effect without the local profile. PostgreSQL is the implemented target, but
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
	The development default applies **only** in the local profile. Non-local browser
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
tasks can still be used with the correct Java/database environment. Do not disable
the fail-closed boundary to experiment with future endpoints.
