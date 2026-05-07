\# TypeScript, Data, and API Rules



\## TypeScript

\- Always use strict typing.

\- Never use `any` unless absolutely necessary.

\- Prefer:

&#x20; - interfaces for structured objects

&#x20; - type aliases for unions and compositions

\- Explicitly type component props.

\- Avoid unsafe type assertions.



\## Functions

\- Keep functions small and single-purpose.

\- Prefer pure functions.

\- Make inputs and outputs explicit.



\## Data Handling

\- Ensure consistent data shapes.

\- Avoid mismatches between frontend and backend.

\- Safely handle null and undefined values.



\## Validation

\- Never trust user input.

\- Validate all critical data.

\- Return clear, user-friendly errors.



\## API Design

\- Keep endpoints/actions small and focused.

\- Separate:

&#x20; - validation

&#x20; - business logic

&#x20; - response formatting

\- Handle all failure cases explicitly.

\- Do not leak internal errors.



\## Async Handling

Always handle:

\- loading

\- success

\- error

\- empty state



\## Error Handling

\- Use try/catch where needed.

\- Do not allow silent failures.

\- Provide meaningful error messages.



\## Forms

\- Use typed form data.

\- Validate inputs before submission.

\- Ensure predictable behavior.

