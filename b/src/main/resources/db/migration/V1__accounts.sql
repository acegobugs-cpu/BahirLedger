CREATE TABLE accounts (
    id UUID PRIMARY KEY,
    email VARCHAR(254) NOT NULL,
    display_name VARCHAR(120) NOT NULL,
    password_hash VARCHAR(60) NOT NULL,
    active BOOLEAN NOT NULL,
    CONSTRAINT accounts_email_unique UNIQUE (email),
    CONSTRAINT accounts_email_normalized CHECK (email = LOWER(TRIM(email)))
);