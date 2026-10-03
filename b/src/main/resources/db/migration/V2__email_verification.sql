-- Existing and provisioned accounts are pending too; never infer ownership from email.
ALTER TABLE accounts ADD COLUMN email_verified BOOLEAN DEFAULT FALSE NOT NULL;

-- One rotating token per account. Clearing its digest consumes it without losing cooldown.
CREATE TABLE email_verifications (
    account_id UUID PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    token_digest VARCHAR(64) UNIQUE,
    expires_at TIMESTAMP WITH TIME ZONE,
    next_send_at TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT verification_token_pair CHECK (
        (token_digest IS NULL AND expires_at IS NULL) OR
        (token_digest IS NOT NULL AND expires_at IS NOT NULL)
    )
);