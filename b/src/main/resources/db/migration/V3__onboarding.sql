CREATE TABLE organizations (
    id UUID PRIMARY KEY,
    name VARCHAR(120) NOT NULL,
    status VARCHAR(16) NOT NULL CHECK (CASE status WHEN 'ACTIVE' THEN 1 WHEN 'SUSPENDED' THEN 1 WHEN 'REVOKED' THEN 1 ELSE 0 END = 1),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL
);

-- One membership per account, including suspended/revoked memberships. No silent switching.
CREATE TABLE organization_memberships (
    account_id UUID PRIMARY KEY REFERENCES accounts(id),
    organization_id UUID NOT NULL REFERENCES organizations(id),
    role VARCHAR(8) NOT NULL CHECK (CASE role WHEN 'OWNER' THEN 1 WHEN 'MEMBER' THEN 1 ELSE 0 END = 1),
    status VARCHAR(16) NOT NULL CHECK (CASE status WHEN 'ACTIVE' THEN 1 WHEN 'SUSPENDED' THEN 1 WHEN 'REVOKED' THEN 1 ELSE 0 END = 1),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL
);
CREATE INDEX memberships_organization ON organization_memberships(organization_id);

-- Keep the activated ID for retry-safe activation. A pending edit never changes expires_at.
CREATE TABLE organization_bootstraps (
    account_id UUID PRIMARY KEY REFERENCES accounts(id),
    id UUID NOT NULL UNIQUE,
    name VARCHAR(120) NOT NULL,
    status VARCHAR(16) NOT NULL CHECK (CASE status WHEN 'PENDING' THEN 1 WHEN 'ACTIVATED' THEN 1 WHEN 'CANCELLED' THEN 1 WHEN 'EXPIRED' THEN 1 ELSE 0 END = 1),
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    organization_id UUID REFERENCES organizations(id),
    CHECK ((status = 'ACTIVATED' AND organization_id IS NOT NULL) OR
           (status <> 'ACTIVATED' AND organization_id IS NULL))
);

CREATE TABLE organization_invitations (
    id UUID PRIMARY KEY,
    organization_id UUID NOT NULL REFERENCES organizations(id),
    issued_by UUID NOT NULL REFERENCES accounts(id),
    email VARCHAR(254) NOT NULL CHECK (email = LOWER(TRIM(email))),
    token_digest VARCHAR(64) NOT NULL UNIQUE,
    status VARCHAR(16) NOT NULL CHECK (CASE status WHEN 'PENDING' THEN 1 WHEN 'ACCEPTED' THEN 1 WHEN 'REVOKED' THEN 1 ELSE 0 END = 1),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    accepted_by UUID REFERENCES accounts(id),
    CHECK ((status = 'ACCEPTED' AND accepted_by IS NOT NULL) OR
           (status <> 'ACCEPTED' AND accepted_by IS NULL))
);
CREATE INDEX invitations_organization ON organization_invitations(organization_id, created_at);
CREATE INDEX invitations_issuer ON organization_invitations(issued_by, created_at);

-- Attributable append-only application audit; no raw tokens, email bodies or credentials.
CREATE TABLE onboarding_audit (
    id UUID PRIMARY KEY,
    actor_account_id UUID NOT NULL REFERENCES accounts(id),
    organization_id UUID REFERENCES organizations(id),
    subject_id UUID NOT NULL,
    action VARCHAR(40) NOT NULL,
    occurred_at TIMESTAMP WITH TIME ZONE NOT NULL
);