# BahirLedger backend

Java 21 / Spring Boot 4.1.1 modular backend. **BahirLedger-managed email/password
sign-in is the default; organization SSO is optional future work.** This increment
provides the managed sign-in service used by the [Flutter client](../ui/README.md).

## HTTP contract

The [OpenAPI contract](src/main/resources/contracts/openapi.yaml) is committed, not served publicly.

| Operation | Success | Failure |
| --- | --- | --- |
| `POST /api/v1/auth/login`, JSON `{email,password}` | `200 {accessToken,expiresAt,user:{id,email,displayName}}` | `400` validation, `401` invalid credentials, `429` throttled |
| `GET /api/v1/me`, `Authorization: Bearer <token>` | `200 {id,email,displayName}` | `401` missing/invalid/expired/revoked token or inactive account |
| `POST /api/v1/auth/logout`, same bearer header | `204`, empty body; revoke this session only | `401`, including repeated logout |
| `GET /api/v1/health` | `200 {"status":"UP"}`, process liveness only | Not database readiness |

- Only login and GET health are public application operations. Explicit CORS
	preflights for these listed operations are also allowed. **Everything else is
	denied**, including signup, refresh, membership, business APIs, form login,
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
	also at most 72 Java characters. JSON login bodies are bounded to **4096 bytes**,
	including chunked requests. Unsupported media types return generic `400`.
- Accounts expose only a stable UUID, normalized email and display name. `/me`
	**does not return organization/project membership or authorization grants**.

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
runtime `test` profile that enables an embedded database. Production startup
without explicit database configuration fails closed instead of falling back to H2.

Boot manages Spring JDBC, Flyway 12.4.0, PostgreSQL JDBC 42.7.13 and H2 2.4.240.
Flyway's H2 adapter currently emits a warning that its latest verified H2 version
is 2.3.232; the Boot-managed 2.4.240 migration and JDBC behavior are exercised by
these tests. No dependency is downgraded just to hide the warning.

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

With no local profile, startup requires all of:

| Environment variable | Purpose |
| --- | --- |
| `BAHIRLEDGER_DB_URL` | PostgreSQL JDBC URL, e.g. `jdbc:postgresql://db-host:5432/bahirledger?sslmode=verify-full` |
| `BAHIRLEDGER_DB_USERNAME` | Database service identity, supplied by deployment secrets |
| `BAHIRLEDGER_DB_PASSWORD` | Database password, supplied by deployment secrets |
| `BAHIRLEDGER_WEB_ORIGIN` | Optional single exact localhost HTTP(S) origin with explicit port; empty disables cross-origin access |

No application/database production credentials are hardcoded. Use a private
database with TLS, suitable permissions, backups and an external secret manager.
Keep credentials out of the JDBC URL, command arguments and logs. Flyway applies
[versioned account migrations](src/main/resources/db/migration/V1__accounts.sql)
at startup, validates checksums, and disables clean. Its schema contains stable
UUID IDs, a unique normalized email, display name, BCrypt hash and active flag.
There is no destructive schema recreation or startup password overwrite. The
database identity currently needs migration privileges; separating migration and
runtime identities is a deployment-hardening follow-up.

Run with the configured environment via `./mvnw spring-boot:run` or the executable
JAR produced by `verify`. There is **no production bootstrap/signup endpoint**:
production invitation/provisioning requires the next increment. `BAHIRLEDGER_DEV_*`
has no effect without the local profile. PostgreSQL is the implemented target, but
this test suite does not certify a live PostgreSQL deployment.

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
	should back off. All limits reset on restart.
- Forwarded source-IP headers are intentionally ignored. Behind a proxy, clients
	will share its source-IP limit until trusted-proxy/distributed rate limiting is
	deliberately implemented. TLS termination, request timeouts and upstream
	connection/body/rate limits are deployment responsibilities.
- CORS accepts only one exact configured loopback origin, the listed methods per
	route, Authorization and Content-Type headers. No wildcards or credentials.
	Different ports, `null` origins, unlisted routes/methods/headers are denied.
	The development default applies **only** in the local profile. Non-local browser
	origins require a subsequent reviewed deployment policy, not a wildcard workaround.
- CSRF ignores only **POST** login and logout, since credentials/tokens are explicit
	and no ambient cookie authentication exists. Every other unsafe route retains
	CSRF enforcement and is denied. Its nonpersisting CSRF repository deliberately
	cannot create sessions or issue usable CSRF tokens for nonexistent write APIs.
- Request bodies/headers, passwords and raw tokens are never logged by application
	code. Error responses and credential DTO diagnostic strings are sanitized. Do
	not enable request-body/JDBC bind/HTTP wire logging or add credentials to proxy
	access logs. Generic errors intentionally omit exception details.

## Not production-ready

Still missing: email verification, invitations/signup, password recovery/change,
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