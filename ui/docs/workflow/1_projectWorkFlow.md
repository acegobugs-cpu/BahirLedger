# Workflow 01 — Project Lifecycle

First, let's define the lifecycle we want the UI to represent.

At a high level:

```
Project Idea
    ↓
Project Draft
    ↓
Project Submitted
    ↓
Project Review
    ↓
Project Approved
    ↓
Project Active
    ↓
Project Completed
    ↓
Project Closed
```
But I don't want us to blindly accept that lifecycle. Each transition needs to answer a real question.

For example:

## 1. Project Draft

Someone creates:
```
Project
├── Name
├── Description
├── Objective
├── Location
├── Start Date
├── Expected End Date
├── Organization
└── Project Manager
```

At this point, it's just a proposal/draft.

---

## 2. Project Submitted

The creator says:

 "This project is ready for someone to review." 

Now we have a workflow transition:
```
DRAFT
  ↓
SUBMITTED
```
We immediately discover our first questions:

- Who is allowed to submit?
- Does every project require approval?
- Who reviews it?
- Can the reviewer send it back?
- What happens if it is rejected?
- Can the creator edit it after submission?


These are domain decisions.

Don't worry about answering them perfectly yet. We'll record them.

## 3. Project Review

The reviewer sees something like:
```

┌─────────────────────────────────────────────┐
│ Project Review                              │
├─────────────────────────────────────────────┤
│                                             │
│ Community Water Infrastructure              │
│                                             │
│ Objective                                   │
│ Provide reliable water access to...         │
│                                             │
│ Location                                    │
│ Haramaya, Ethiopia                          │
│                                             │
│ Timeline                                    │
│ Jan 2027 → Dec 2027                         │
│                                             │
│ Estimated Budget                            │
│ $250,000                                    │
│                                             │
│ Project Manager                             │
│ Abebe K.                                    │
│                                             │
│ ─────────────────────────────────────────── │
│                                             │
│ [ Request Changes ]  [ Reject ]  [ Approve ]│
└─────────────────────────────────────────────┘
```

Notice that we're already discovering that budget may be part of project creation, which will later connect to the financial domain.

## 4. Project Approved

After approval:
```
SUBMITTED
    ↓
APPROVED
```
But approval shouldn't necessarily mean the project has started.

There could be a preparation stage:
```
APPROVED
    ↓
PREPARING
    ↓
ACTIVE
```
During preparation:

- funding is received
- budget is established
- workers are assigned
- procurement begins
- assets may be acquired
- milestones are created

This is where the project starts becoming a real operational entity.

## 5. Active Project

The main project screen might eventually look something like:
```

┌─────────────────────────────────────────────────────────┐
│ Community Water Infrastructure                           │
│ ACTIVE                                                   │
├─────────────────────────────────────────────────────────┤
│                                                         │
│ 42%                    $91,420             37 / 84       │
│ Progress               Spent                Tasks        │
│                                                         │
├─────────────────────────────────────────────────────────┤
│                                                         │
│ FINANCIAL       WORK        ASSETS       PEOPLE         │
│                                                         │
│ $250K           42%         84           26             │
│ Budget          Progress    Assets      Workers         │
│                                                         │
├─────────────────────────────────────────────────────────┤
│                                                         │
│ Recent Activity                                         │
│                                                         │
│ ● Expense approved                       12 min ago     │
│ ● Asset transferred                      34 min ago     │
│ ● Inspection submitted                   1 hr ago      │
│ ● Milestone completed                    3 hrs ago     │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

This screen is important because it establishes a central idea:

The project dashboard is a projection of everything happening inside the project.

It shouldn't be the source of truth itself.

## 6. Project Completion

Eventually:
```
ACTIVE
  ↓
COMPLETION REQUESTED
  ↓
FINAL REVIEW
  ↓
COMPLETED
```
And again, we discover questions:

- Who can request completion?
- What must be complete?
- Must all expenses be settled?
- Must all assets be accounted for?
- Must all milestones be verified?
- Does someone inspect the project?
- Can completed projects be modified?
- What happens to outstanding tasks?

This is exactly the kind of discovery we're looking for.

## 7. Project Closed

I'd separate Completed and Closed.

For example:
```
COMPLETED
    │
    ├── Work finished
    ├── Final inspection
    └── Final reporting
             ↓
          CLOSED
```

A closed project becomes primarily a historical/audit record.

That distinction could become very important later.

Now let's design the actual UI workflow

I suggest we don't design every page simultaneously.

We'll go in this order:

```
01. Project List
        ↓
02. Create Project
        ↓
03. Project Draft
        ↓
04. Submit for Review
        ↓
05. Review Project
        ↓
06. Approved Project
        ↓
07. Project Dashboard
        ↓
08. Complete Project
        ↓
09. Closed Project
```

And at every step we'll ask:

1. What does the user need to know?

2. What can they do?

3. What can go wrong?

4. What happens to the project state?

Let's start with Screen 01 — Project List

I would make the first desktop screen something like:
```

PROJECTS

[ Search projects... ]    [ Filters ]    [ + New Project ]


All Projects                                    24

┌────────────────────────────────────────────────────────┐
│ Community Water Infrastructure             ACTIVE      │
│ Haramaya                                             │
│                                                        │
│ Progress     ███████████░░░░░░░░  42%                 │
│ Budget       $250,000                                  │
│ Spent        $91,420                                   │
│ Deadline     Dec 18, 2027                              │
│                                                        │
│ Manager      Abebe K.                                  │
└────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────┐
│ School Renovation                         REVIEW       │
│ Dire Dawa                                             │
│                                                        │
│ Submitted      2 hours ago                             │
│ Budget         $84,000                                 │
│                                                        │
│ Submitted by  Hana M.                                  │
└────────────────────────────────────────────────────────┘
```

But there's a subtle design decision here.

Should users see financial information on the project list?

Maybe.

Maybe not.

That depends on the user's role.

So already:
```
Project List
      ↓
Authorization
      ↓
Different users see different information
```
That's a backend requirement we just discovered from a UI.

First decisions to record

I'd start our docs/domain-discovery.md with these provisional decisions:

# Domain Discovery

## Workflow: Project Lifecycle

### Current lifecycle

DRAFT
→ SUBMITTED
→ APPROVED
→ PREPARING
→ ACTIVE
→ COMPLETION_REQUESTED
→ COMPLETED
→ CLOSED

---

## DEC-001 — Project has a lifecycle

A project is not simply created and immediately active.

Projects move through explicit states.

Reason:
Projects require review, preparation, execution, completion, and
historical closure.

Status:
PROVISIONAL

---

## DEC-002 — Completed and Closed are different states

COMPLETED means project work has finished.

CLOSED means final administrative/audit processing has finished.

Status:
PROVISIONAL

---

## OPEN QUESTIONS

- Who can create a project?
- Who can submit a project?
- Does every project require approval?
- Who can approve a project?
- Can the creator approve their own project?
- What happens when a project is rejected?
- Can a submitted project be edited?
- What is required before a project becomes ACTIVE?
- What is required before a project can be COMPLETED?
- What is required before a project can be CLOSED?
- Who can reopen a project?
- Can a CLOSED project ever be modified?
- Which project information is visible to each role?