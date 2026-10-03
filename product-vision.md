# Product vision — Project Integrity Platform

> A transparent, auditable project management and accountability platform for organizations managing people, funds, assets, procurement, and field operations.

This document preserves the detailed product material formerly in the root README. For installation and current application scope see [README.md](README.md); for technical decisions see [architecture.md](architecture.md), [api-design.md](api-design.md), [auth-access.md](auth-access.md), [ai-analytics.md](ai-analytics.md), and [decisions.md](decisions.md). Historical development status is kept separately in the local development records.

The sections below describe product intent and examples, not an implemented feature list or a mandatory project-management methodology. Organizations configure structured policies within mandatory security rules.

---

## Overview

Projects often fail for reasons that have little to do with the original plan.

Money is spent without sufficient visibility. Assets disappear between procurement and deployment. Deadlines change without clear justification. Work is reported without verifiable evidence. Decisions are made by a small number of people while the people affected by those decisions have limited visibility into what is actually happening.

The **Project Integrity Platform** is designed to address this problem through transparency, traceability, accountability, and verifiable project history.

The platform provides a shared environment where project participants can manage and monitor:

- Projects
- Funds and budgets
- Expenses
- Procurement
- Assets
- Workers
- Tasks
- Milestones
- Deadlines
- Documents
- Evidence
- Approvals
- Project events
- Field operations

The system is designed around a simple principle:

> **Important project activity should be observable, attributable, and difficult to change without leaving evidence of the change.**

---

# Vision

The goal is not simply to build another project-management application.

The goal is to build a **project accountability system**.

A project should have a continuously evolving, auditable record of what happened.

For example:

```text
Funding Received
       ↓
Budget Allocated
       ↓
Purchase Requested
       ↓
Purchase Approved
       ↓
Asset Received
       ↓
Asset Inspected
       ↓
Asset Assigned
       ↓
Work Performed
       ↓
Evidence Submitted
       ↓
Work Verified
       ↓
Payment Released
```

Every important transition should have:

* an actor
* a timestamp
* a reason where applicable
* relevant supporting evidence
* an authorization context
* a traceable history

The platform should make it difficult for important activity to disappear silently.

---

# Core Principles

## 1. Auditability

Important changes should leave an immutable or tamper-evident record.

The system should be able to answer:

* Who performed this action?
* What changed?
* When did it happen?
* What was the previous state?
* Why was the change made?
* Who approved it?
* What evidence supports it?

---

## 2. Transparency

Information should be visible to the people who are legitimately entitled to see it.

Transparency does not mean that every user sees everything.

Instead, the platform uses explicit access policies to determine what each participant can see and do.

---

## 3. Accountability

Actions are associated with identifiable actors.

The system should avoid anonymous or untraceable changes to important project data.

---

## 4. Evidence

Important claims should be supported by evidence whenever possible.

Examples:

```text
Expense
 ├── Invoice
 ├── Receipt
 ├── Approval
 └── Payment Record
```

```text
Task Completed
 ├── Photos
 ├── GPS Location
 ├── Timestamp
 ├── Worker
 └── Verification
```

```text
Asset Transferred
 ├── Previous Holder
 ├── New Holder
 ├── Timestamp
 ├── Location
 └── Authorization
```

---

## 5. Offline-First Field Operations

The mobile application must assume that connectivity can disappear.

Users should be able to continue performing essential operations while offline.

Local changes should be persisted and synchronized when connectivity becomes available.

Synchronization uses explicit push/pull with server revalidation. Offline actions are pending proposals, not authoritative approvals. Revocation reaches a disconnected device only later; pending work must be retained encrypted for controlled reconciliation. Seven-day offline access, five-minute local lock, 30-day exceptions and online-by-default approvals are provisional recommendations, not accepted defaults.

```text
              ┌──────────────┐
              │ Mobile Device│
              └──────┬───────┘
                     │
              Local State
                     │
              Pending Changes
                     │
               No Network
                     │
                     ▼
              Continue Working
                     │
               Network Returns
                     │
                     ▼
                 Synchronize
```

Offline operation is a core architectural requirement rather than an optional feature.

---

## 6. History Over Silent Mutation

The platform should distinguish between:

```text
changing the current state
```

and

```text
recording that the state changed
```

For important domain operations, the latter is preferred.

For example:

```text
ExpenseCreated
       ↓
ExpenseSubmitted
       ↓
ExpenseApproved
       ↓
PaymentRecorded
```

If a correction is required:

```text
CorrectionRequested
       ↓
CorrectionReviewed
       ↓
CorrectionApproved
```

The original event should remain part of the historical record.

---

# Major Domains

## Projects

A project represents a managed initiative with:

* objectives
* participants
* budget
* milestones
* deadlines
* tasks
* assets
* workers
* financial activity
* evidence
* project history

---

## Funds & Finance

The financial subsystem tracks the lifecycle of project funds.

The system distinguishes between concepts such as:

```text
Funds Received
Funds Allocated
Funds Committed
Expenses Recorded
Payments Made
Funds Returned
```

This allows the platform to represent the actual financial lifecycle rather than exposing only a single mutable balance.

---

## Expenses

Expenses should contain enough information to establish accountability.

Example:

```text
Expense #4921

Amount: 12,500
Category: Materials
Project: Project A

Created By: User A
Approved By: User B
Paid By: User C

Supplier: Supplier X

Evidence:
  - Invoice
  - Receipt

Created At: ...
Approved At: ...
Paid At: ...
```

---

## Procurement

Procurement tracks the process from requirement to acquisition.

```text
Requirement
    ↓
Purchase Request
    ↓
Quotation / Supplier Selection
    ↓
Approval
    ↓
Purchase
    ↓
Delivery
    ↓
Inspection
    ↓
Asset Registration
```

The goal is to make procurement activity traceable.

---

## Assets

Physical assets should have a complete lifecycle.

```text
Purchased
   ↓
Received
   ↓
Inspected
   ↓
Registered
   ↓
Assigned
   ↓
Transferred
   ↓
Returned
   ↓
Maintained
   ↓
Disposed
```

Assets may be identified using mechanisms such as:

* QR codes
* barcodes
* NFC
* unique identifiers

The mobile application can be used to inspect and transfer assets in the field.

---

## Workers

Workers can be associated with:

* projects
* assignments
* tasks
* attendance
* work submissions
* inspections
* payments

The platform should establish relationships between work performed and the corresponding project activity.

---

## Tasks & Milestones

Tasks represent operational work.

Milestones represent significant project outcomes.

The system tracks:

* assignments
* deadlines
* status
* progress
* evidence
* verification
* changes to deadlines
* completion

Deadline changes should be traceable rather than silently overwriting the previous deadline.

---

# Mobile Application

The mobile application is the field interface of the platform.

It is designed for workers, inspectors, project managers, and other field participants.

Potential capabilities include:

* Offline operation
* GPS
* Camera
* QR/barcode scanning
* NFC
* Push notifications
* Background synchronization
* Local persistence
* Evidence collection
* Asset inspection
* Asset transfer
* Task execution
* Field reports
* Location-aware activity

The mobile application is expected to operate under:

* intermittent connectivity
* low battery
* limited storage
* limited memory
* application suspension
* process termination
* network switching
* varying device capabilities

---

# Desktop Application

The desktop/web application provides the management and oversight interface.

Potential capabilities include:

* Project dashboards
* Financial management
* Budget management
* Procurement
* Asset management
* Workforce management
* Task management
* Approval workflows
* Audit history
* Evidence review
* Project analytics
* Risk monitoring
* Administration

The desktop application is optimized for complex information management rather than field operations.

---

# Synchronization

Synchronization is one of the core technical challenges of the platform.

The system must support:

* local persistence
* offline mutations
* synchronization
* retries
* duplicate detection
* idempotency
* conflict detection
* conflict resolution
* reconnect handling
* partial synchronization
* interrupted synchronization

A mobile client must be able to recover after:

```text
Network Loss
    ↓
Application Backgrounded
    ↓
Application Terminated
    ↓
Device Restarted
    ↓
Application Relaunched
    ↓
Synchronization Resumes
```

---

# Audit & Event History

The platform maintains a historical record of important domain activity.

Examples include:

```text
ProjectCreated
ProjectMemberAdded

FundReceived
BudgetAllocated

ExpenseCreated
ExpenseSubmitted
ExpenseApproved
ExpenseRejected
PaymentRecorded

PurchaseRequested
PurchaseApproved
PurchaseCompleted

AssetRegistered
AssetAssigned
AssetTransferred
AssetInspected

TaskCreated
TaskAssigned
TaskStarted
TaskCompleted

MilestoneCreated
DeadlineChanged
MilestoneCompleted
```

Events should contain enough metadata to reconstruct meaningful project history.

---

# Integrity Engine

The platform may contain an integrity-analysis subsystem responsible for identifying unusual or suspicious patterns.

This system should not automatically accuse users of corruption.

Instead, it should identify **events or patterns that require human review**.

Examples:

```text
Unusual Expense Pattern
```

```text
Repeated Deadline Changes
```

```text
Unexpected Asset Movement
```

```text
Large Expense With Missing Evidence
```

```text
Project Spending Increasing Faster Than Reported Progress
```

```text
Multiple Related Purchases From the Same Supplier
```

The integrity engine may combine:

* deterministic rules
* statistical analysis
* historical project data
* anomaly detection
* AI-assisted analysis

AI should assist investigation rather than become the authority for financial or disciplinary decisions.

---

# Agent

The platform may include an intelligent project-monitoring agent.

The agent observes project information and generates findings such as:

```text
Project Health
      ↓
Financial Activity
      ↓
Procurement
      ↓
Asset Movement
      ↓
Work Progress
      ↓
Deadlines
      ↓
Evidence
      ↓
Agent Analysis
      ↓
Findings / Recommendations
```

Example:

> Project expenditure increased by 38% over the last reporting period while verified progress increased by only 9%.

The agent should provide:

* the observation
* supporting evidence
* relevant events
* reasoning/context
* confidence
* recommended human action

It should not silently modify financial or project state.

---

# Authorization

The approved direction is structured organization/project-scoped authorization; complete enforcement is not yet implemented.

Optional role templates may include (not a fixed hierarchy):

* Project Owner
* Project Manager
* Finance Officer
* Procurement Officer
* Worker
* Inspector
* Auditor
* Administrator
* Observer

Permissions are scoped to the organization and either all projects or selected projects. Authorized administrators can delegate role assignment and approval authority within their permitted scope. Organization policy controls defaults and delegated project overrides; mandatory rules cannot be weakened. RACI or a job title is not itself an access grant.

For example, an organization may choose:

```text
Finance Officer
    ↓
Can propose expense
    ↓
Cannot approve own expense
```

This is an optional separation-of-duties rule, not a universal requirement. Self-approval can be allowed or denied by explicit policy; it never replaces the need for scoped permission and an applicable approval rule. Review-before-preparation and required rejection/amendment reasons in the current UI are legacy prototype choices, not mandatory rules for every organization.

An **organization is an independent workspace/tenant, not a legal entity**. Creation is self-service through controlled bootstrap; existing-organization membership is invite-only, with one organization per application account. Organization SSO is mandatory from the outset; initial device scope is personal devices only.

---

# Security Model

Security is a core requirement.

The system should consider:

* Authentication
* Authorization
* Secure token handling
* Secure mobile storage
* Encryption in transit
* Encryption at rest
* Audit trails
* Device security
* Session management
* Credential revocation
* Evidence access control
* Tamper detection

Sensitive operations should require appropriate authorization.

Use an established identity provider (vendor unselected; MVP OIDC proposed). Pending SSO bootstrap has no tenant-data access: verify provider control and test sign-in before activation. Stable issuer+subject identifies a user; email/domain does not confer membership. Invitations must bind organization/recipient, expire and be consumed once. Trust reviewed provider registries, not arbitrary issuer URLs. Flutter uses external-browser authorization code + PKCE with no app secret. Concrete interoperability, delegated precedence, recovery/last-owner protection and offline defaults remain open decisions.

---

# Evidence

Evidence may include:

* photographs
* videos
* receipts
* invoices
* documents
* signatures
* GPS coordinates
* timestamps
* inspection reports

Evidence should be associated with the domain event or entity it supports.

For example:

```text
Expense
   │
   └── Evidence
        ├── Invoice
        └── Receipt
```

and:

```text
Work Completion
   │
   └── Evidence
        ├── Photos
        ├── GPS
        └── Inspection
```

---

# Architectural Direction

The approved architecture is a **Java Spring Boot modular monolith with PostgreSQL**, serving Flutter through versioned REST/JSON APIs described by a committed OpenAPI contract. PostgreSQL is authoritative; a local client store and explicit push/pull synchronization support eventual reconciliation rather than offline server authority.

Evidence will use S3-compatible private storage with tenant-scoped access. Python will own AI-provider integration, AI processing and derived analytics; Java retains authoritative business rules and transactions. Introduce the Python worker with the first concrete AI feature, not as a prerequisite for the core application. Python produces advisory findings, not approvals or transaction authority. OpenAI is a candidate, not a selected provider. Mandatory organization SSO will use an established provider; the vendor and concrete protocol interoperability remain to be settled (OIDC proposed for MVP).

The project will be designed around several architectural principles:

* Domain-driven design
* Strong domain boundaries
* Transactional integrity
* Offline-first mobile architecture
* Event-driven workflows where appropriate
* Append-only audit history
* Explicit authorization
* Idempotent operations
* Reliable synchronization
* Observable system behavior
* Evidence-backed state transitions

Backend technology direction is approved; provider choice, client storage/platform support, detailed policy precedence, recovery and offline defaults still require decisions. Implement one testable slice at a time; architecture approval is not a claim that these capabilities exist.

---

# Non-Goals

The project is **not** intended to:

* Guarantee that corruption is impossible
* Automatically determine that a person is corrupt
* Replace human auditors
* Replace legal or financial institutions
* Assume every piece of submitted information is truthful
* Use blockchain simply for the sake of using blockchain
* Make AI the final authority over financial decisions

The objective is to make project activity **more transparent, traceable, auditable, and difficult to manipulate without detection**.

---

# Initial Product Scope

The initial system will focus on:

### Project Management

* Projects
* Members
* Roles
* Tasks
* Milestones
* Deadlines

### Financial Management

* Funding
* Budgets
* Allocations
* Expenses
* Payments
* Financial history

### Asset Management

* Asset registration
* Assignment
* Transfer
* Inspection
* Asset history

### Workforce

* Worker records
* Assignments
* Work submissions
* Verification

### Evidence

* Documents
* Receipts
* Photos
* Field evidence

### Mobile

* Offline-first operation
* Local persistence
* Synchronization
* GPS
* Camera
* QR/barcode scanning
* Push notifications

### Accountability

* Audit history
* Approval workflows
* Event history
* Integrity rules

---

# Future Scope

Potential future capabilities include:

* Peer-to-peer mobile synchronization
* Bluetooth communication
* NFC-based asset management
* Advanced anomaly detection
* AI project-monitoring agent
* Predictive project analytics
* Advanced financial analysis
* Geospatial project analytics
* Public transparency portals
* External auditor access
* Cryptographically verifiable audit logs
* Cross-organization collaboration, if separately designed (multiple isolated tenants are the baseline; one organization per application account remains the current rule)

---

# Engineering Challenges

The project intentionally targets difficult engineering problems.

### Mobile Systems

* Offline-first architecture
* Background execution
* Application lifecycle
* Process death
* Battery constraints
* Memory constraints
* Storage management
* Sensor integration
* Camera/media processing
* Push notifications
* Secure local storage

### Distributed Systems

* Synchronization
* Event ordering
* Idempotency
* Conflict resolution
* Eventual consistency
* Network failures
* Partial failures
* Retry behavior
* Duplicate delivery

### Backend Systems

* Domain modeling
* Transaction integrity
* Authorization
* Concurrency
* Event processing
* Auditability
* Evidence management
* Financial invariants

### Security

* Identity
* Access control
* Credential security
* Tamper resistance
* Audit integrity
* Evidence integrity

### AI / Data Systems

* Anomaly detection
* Pattern recognition
* Project health analysis
* Explainable findings
* Human-in-the-loop workflows

---

# Development Philosophy

The project will be developed incrementally.

Complexity should be introduced because the system requires it, not because a technology is fashionable.

For example:

```text
Start
  ↓
Modular Backend
  ↓
Reliable Domain Model
  ↓
Audit / Events
  ↓
Mobile Offline Architecture
  ↓
Synchronization
  ↓
Background Processing
  ↓
Integrity Engine
  ↓
Advanced Distributed Infrastructure
```

Infrastructure should evolve alongside actual system requirements.

---

# Guiding Principle

> **A project should not only report what its current state is. It should be able to explain how that state came to exist.**

That principle is the foundation of the Project Integrity Platform.

Projects,
Funds,
Expenses,
Workers,
Assets,
Procurement,
Deadlines,
Evidence,
Mobile,
Desktop,
Transparency,
Agent