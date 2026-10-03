package com.bahirledger.backend.onboarding;

import java.security.SecureRandom;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;
import java.util.Base64;
import java.util.List;
import java.util.UUID;
import com.bahirledger.backend.auth.AccountStore;
import com.bahirledger.backend.auth.ApiException;
import com.bahirledger.backend.auth.SessionStore;
import com.bahirledger.backend.auth.UserView;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/** Account -> organization -> invitation lock order, also for reads and retries.
 * OWNER only manages invitations; these roles never feed project/finance AccessPolicy.
 */
@Service
public class OnboardingService {
    public static final Duration BOOTSTRAP_LIFETIME = Duration.ofHours(24);
    public static final Duration INVITATION_LIFETIME = Duration.ofDays(7);
    private final JdbcTemplate jdbc;
    private final Clock clock;
    private final TransactionTemplate transaction;
    private final SecureRandom random = new SecureRandom();

    public OnboardingService(JdbcTemplate jdbc, Clock clock, PlatformTransactionManager transactions) {
        this.jdbc = jdbc;
        this.clock = clock;
        transaction = new TransactionTemplate(transactions);
        transaction.setTimeout(30);
    }

    public record Membership(UUID organizationId, String organizationName, String role) {}
    public record Bootstrap(UUID id, String name, Instant expiresAt) {}
    public record Context(Membership membership, Bootstrap bootstrap) {}
    public record Invitation(UUID id, String email, String status, Instant expiresAt) {}
    public record InvitationList(List<Invitation> invitations) {}
    public record Preview(String organizationName, Instant expiresAt) {}
    public record IssuedInvitation(Invitation invitation, String token) {
        @Override public String toString() { return "IssuedInvitation[redacted]"; }
    }
    private record Setup(UUID id, String name, String status, Instant expiresAt, UUID organizationId) {}
    private record Organization(UUID id, String name, String status) {}
    private record Member(UUID organizationId, String role, String status) {}
    private record Invite(UUID id, UUID organizationId, String email, String status, Instant expiresAt) {}

    public Context context(UUID account) {
        return transaction.execute(tx -> { lockAccount(account); return current(account); });
    }

    public Context bootstrap(UUID account, String name) {
        return transaction.execute(tx -> {
            lockAccount(account);
            noMembership(account);
            String normalized = name == null ? "" : name.strip();
            if (normalized.isBlank() || normalized.length() > 120
                    || normalized.chars().anyMatch(character -> character < 32 || character == 127)) {
                throw ApiException.validation();
            }
            Setup setup = setup(account);
            if (pending(setup)) {
                jdbc.update("UPDATE organization_bootstraps SET name = ? WHERE account_id = ?", normalized, account);
                audit(account, null, setup.id(), "BOOTSTRAP_UPDATED");
            } else {
                if (setup != null && setup.status().equals("PENDING")) {
                    audit(account, null, setup.id(), "BOOTSTRAP_EXPIRED");
                }
                UUID id = UUID.randomUUID();
                jdbc.update("DELETE FROM organization_bootstraps WHERE account_id = ?", account);
                jdbc.update("INSERT INTO organization_bootstraps (account_id, id, name, status, expires_at) VALUES (?, ?, ?, 'PENDING', ?)",
                        account, id, normalized, timestamp(now().plus(BOOTSTRAP_LIFETIME)));
                audit(account, null, id, "BOOTSTRAP_STARTED");
            }
            return current(account);
        });
    }

    public Context activate(UUID account, UUID bootstrapId) {
        return transaction.execute(tx -> {
            lockAccount(account);
            Setup setup = setup(account);
            if (setup == null || !setup.id().equals(bootstrapId)) throw ApiException.bootstrapUnavailable();
            if (setup.status().equals("ACTIVATED")) {
                Context existing = current(account);
                if (existing.membership() != null && existing.membership().organizationId().equals(setup.organizationId())) return existing;
                throw ApiException.bootstrapUnavailable();
            }
            if (!pending(setup)) throw ApiException.bootstrapUnavailable();
            noMembership(account);
            UUID organization = UUID.randomUUID();
            jdbc.update("INSERT INTO organizations (id, name, status, created_at) VALUES (?, ?, 'ACTIVE', ?)",
                    organization, setup.name(), timestamp(now()));
            audit(account, organization, organization, "ORGANIZATION_ACTIVATED");
            addMember(account, organization, "OWNER");
            jdbc.update("UPDATE organization_bootstraps SET status = 'ACTIVATED', organization_id = ? WHERE account_id = ?",
                    organization, account);
            audit(account, organization, setup.id(), "BOOTSTRAP_ACTIVATED");
            return current(account);
        });
    }

    public void cancel(UUID account, UUID bootstrapId) {
        transaction.executeWithoutResult(tx -> {
            lockAccount(account);
            // A revoked membership must never acquire onboarding privileges again.
            if (member(account) != null) current(account);
            Setup setup = setup(account);
            if (!pending(setup) || !setup.id().equals(bootstrapId)) throw ApiException.bootstrapUnavailable();
            cancelSetup(account, setup, null);
        });
    }

    public InvitationList invitations(UUID account) {
        return transaction.execute(tx -> {
            lockAccount(account);
            Membership owner = owner(account);
            return new InvitationList(jdbc.query("SELECT id, organization_id, email, status, expires_at FROM organization_invitations WHERE organization_id = ? ORDER BY created_at DESC, id DESC LIMIT 100",
                    (rs, row) -> view(invite(rs)), owner.organizationId()));
        });
    }

    public IssuedInvitation issue(UUID account, String email) {
        return transaction.execute(tx -> {
            lockAccount(account);
            Membership owner = owner(account);
            String normalized = AccountStore.normalizeEmail(email);
            if (normalized == null || normalized.length() > 254 || !normalized.matches("[^\\s@]+@[^\\s@]+")) throw ApiException.validation();
            int open = jdbc.queryForObject("SELECT COUNT(*) FROM organization_invitations WHERE organization_id = ? AND status = 'PENDING' AND expires_at > ?",
                    Integer.class, owner.organizationId(), timestamp(now()));
            int recent = jdbc.queryForObject("SELECT COUNT(*) FROM organization_invitations WHERE issued_by = ? AND created_at > ?",
                    Integer.class, account, timestamp(now().minus(Duration.ofHours(24))));
            if (open >= 100 || recent >= 10) throw ApiException.tenantThrottled();
            byte[] bytes = new byte[32];
            random.nextBytes(bytes);
            String token = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
            UUID id = UUID.randomUUID();
            Instant issued = now();
            Instant expires = issued.plus(INVITATION_LIFETIME);
            jdbc.update("INSERT INTO organization_invitations (id, organization_id, issued_by, email, token_digest, status, created_at, expires_at) VALUES (?, ?, ?, ?, ?, 'PENDING', ?, ?)",
                    id, owner.organizationId(), account, normalized, SessionStore.digest(token), timestamp(issued), timestamp(expires));
            audit(account, owner.organizationId(), id, "INVITATION_ISSUED");
            return new IssuedInvitation(new Invitation(id, normalized, "PENDING", expires), token);
        });
    }

    public void revoke(UUID account, UUID invitationId) {
        transaction.executeWithoutResult(tx -> {
            lockAccount(account);
            Membership owner = owner(account);
            var found = jdbc.query("SELECT id, organization_id, email, status, expires_at FROM organization_invitations WHERE id = ? AND organization_id = ? FOR UPDATE",
                    (rs, row) -> invite(rs), invitationId, owner.organizationId());
            if (found.isEmpty()) throw ApiException.invitationNotFound();
            Invite invitation = found.getFirst();
            if (invitation.status().equals("ACCEPTED")) throw ApiException.invitationUnavailable();
            if (invitation.status().equals("REVOKED")) return;
            jdbc.update("UPDATE organization_invitations SET status = 'REVOKED' WHERE id = ?", invitationId);
            audit(account, owner.organizationId(), invitationId, "INVITATION_REVOKED");
        });
    }

    public Preview preview(UUID account, String token) {
        return transaction.execute(tx -> {
            UserView user = lockAccount(account);
            Invite invitation = redeemable(user, token);
            noMembership(account);
            // Organization was locked by redeemable; reading its name cannot disclose a wrong-recipient tenant.
            return new Preview(jdbc.queryForObject("SELECT name FROM organizations WHERE id = ?", String.class, invitation.organizationId()), invitation.expiresAt());
        });
    }

    public Context accept(UUID account, String token) {
        return transaction.execute(tx -> {
            UserView user = lockAccount(account);
            Invite invitation = redeemable(user, token);
            noMembership(account);
            Setup setup = setup(account);
            if (setup != null && setup.status().equals("PENDING")) cancelSetup(account, setup, invitation.organizationId());
            addMember(account, invitation.organizationId(), "MEMBER");
            jdbc.update("UPDATE organization_invitations SET status = 'ACCEPTED', accepted_by = ? WHERE id = ?", account, invitation.id());
            audit(account, invitation.organizationId(), invitation.id(), "INVITATION_ACCEPTED");
            return current(account);
        });
    }

    private Invite redeemable(UserView user, String token) {
        if (token == null || !token.matches("[A-Za-z0-9_-]{43}")) throw ApiException.invalidInvitation();
        String digest = SessionStore.digest(token);
        // Unlocked digest lookup is ONLY a locator. Re-read all security data after the org lock.
        var ids = jdbc.query("SELECT organization_id FROM organization_invitations WHERE token_digest = ?",
                (rs, row) -> rs.getObject(1, UUID.class), digest);
        if (ids.isEmpty()) throw ApiException.invalidInvitation();
        Organization organization = lockOrganization(ids.getFirst());
        var found = jdbc.query("SELECT id, organization_id, email, status, expires_at FROM organization_invitations WHERE token_digest = ? AND organization_id = ? FOR UPDATE",
                (rs, row) -> invite(rs), digest, organization.id());
        if (found.isEmpty()) throw ApiException.invalidInvitation();
        Invite invitation = found.getFirst();
        if (!organization.status().equals("ACTIVE") || !invitation.status().equals("PENDING")
                || !clock.instant().isBefore(invitation.expiresAt()) || !user.email().equals(invitation.email())) {
            throw ApiException.invalidInvitation();
        }
        return invitation;
    }

    private UserView lockAccount(UUID account) {
        UserView user = jdbc.query("SELECT id, email, display_name, email_verified FROM accounts WHERE id = ? AND active = TRUE FOR UPDATE",
                (rs, row) -> new UserView(rs.getObject("id", UUID.class), rs.getString("email"), rs.getString("display_name"), rs.getBoolean("email_verified")), account)
                .stream().findFirst().orElseThrow(ApiException::unauthorized);
        if (!user.emailVerified()) throw ApiException.emailVerificationRequired();
        return user;
    }

    private Member member(UUID account) {
        return jdbc.query("SELECT organization_id, role, status FROM organization_memberships WHERE account_id = ?",
                (rs, row) -> new Member(rs.getObject(1, UUID.class), rs.getString(2), rs.getString(3)), account).stream().findFirst().orElse(null);
    }
    private void noMembership(UUID account) { if (member(account) != null) throw ApiException.membershipExists(); }
    private Organization lockOrganization(UUID id) {
        return jdbc.query("SELECT id, name, status FROM organizations WHERE id = ? FOR UPDATE",
                (rs, row) -> new Organization(rs.getObject(1, UUID.class), rs.getString(2), rs.getString(3)), id)
                .stream().findFirst().orElseThrow(ApiException::organizationUnavailable);
    }
    private Context current(UUID account) {
        Member member = member(account);
        if (member != null) {
            Organization organization = lockOrganization(member.organizationId());
            member = member(account);
            if (member == null || !member.organizationId().equals(organization.id()) || !member.status().equals("ACTIVE") || !organization.status().equals("ACTIVE")) {
                throw ApiException.organizationUnavailable();
            }
            return new Context(new Membership(organization.id(), organization.name(), member.role()), null);
        }
        Setup setup = setup(account);
        return new Context(null, pending(setup) ? new Bootstrap(setup.id(), setup.name(), setup.expiresAt()) : null);
    }
    private Membership owner(UUID account) {
        Membership membership = current(account).membership();
        if (membership == null || !membership.role().equals("OWNER")) throw ApiException.forbidden();
        return membership;
    }
    private Setup setup(UUID account) {
        return jdbc.query("SELECT id, name, status, expires_at, organization_id FROM organization_bootstraps WHERE account_id = ?",
                (rs, row) -> new Setup(rs.getObject(1, UUID.class), rs.getString(2), rs.getString(3), rs.getObject(4, OffsetDateTime.class).toInstant(), rs.getObject(5, UUID.class)), account)
                .stream().findFirst().orElse(null);
    }
    private boolean pending(Setup setup) { return setup != null && setup.status().equals("PENDING") && clock.instant().isBefore(setup.expiresAt()); }
    private void cancelSetup(UUID account, Setup setup, UUID organization) {
        jdbc.update("UPDATE organization_bootstraps SET status = 'CANCELLED' WHERE account_id = ?", account);
        audit(account, organization, setup.id(), "BOOTSTRAP_CANCELLED");
    }
    private void addMember(UUID account, UUID organization, String role) {
        jdbc.update("INSERT INTO organization_memberships (account_id, organization_id, role, status, created_at) VALUES (?, ?, ?, 'ACTIVE', ?)",
                account, organization, role, timestamp(now()));
        audit(account, organization, account, "MEMBERSHIP_CREATED");
    }
    private void audit(UUID actor, UUID organization, UUID subject, String action) {
        jdbc.update("INSERT INTO onboarding_audit (id, actor_account_id, organization_id, subject_id, action, occurred_at) VALUES (?, ?, ?, ?, ?, ?)",
                UUID.randomUUID(), actor, organization, subject, action, timestamp(now()));
    }
    private Invite invite(ResultSet rs) throws SQLException {
        return new Invite(rs.getObject("id", UUID.class), rs.getObject("organization_id", UUID.class), rs.getString("email"), rs.getString("status"), rs.getObject("expires_at", OffsetDateTime.class).toInstant());
    }
    private Invitation view(Invite invite) {
        return new Invitation(invite.id(), invite.email(), invite.status().equals("PENDING") && !clock.instant().isBefore(invite.expiresAt()) ? "EXPIRED" : invite.status(), invite.expiresAt());
    }
    private Instant now() { return clock.instant().truncatedTo(ChronoUnit.MICROS); }
    private static OffsetDateTime timestamp(Instant instant) { return instant.atOffset(ZoneOffset.UTC); }
}