# Backend workspace

- [x] Verify workspace instructions exist.
- [x] Clarify requirements: Java backend alongside Flutter; root local documentation only.
- [x] Scaffold with Java 21, Spring Boot and Maven wrapper.
- [x] Customize: Step 02a liveness API, default-deny HTTP boundary, internal policy primitive.
- [x] Extensions: none required by the selected setup instructions.
- [ ] Compile and validate using Maven verify.
- [ ] Create verification/run tasks.
- [x] Launch interactively: deferred; no debug launch requested.
- [ ] Verify documentation reflects actual test results.

Keep this a modular monolith. All future business endpoints need trusted tenant context, membership checks, explicit capabilities and tests. SSO is not implemented; never add a permissive development authentication fallback. Approval and delegation rules are configurable domain policy, not fixed role-name checks. Do not confuse a tested policy primitive with complete authorization.

Use Java 21 and the Maven wrapper. Do not change sibling Flutter source for a backend-only increment. Local AI context and plans are in the repository-root docs directory and must remain Git-ignored. Read only context and the active plan instead of loading the full roadmap.