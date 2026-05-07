\# Next.js Rules (App Router)



\## General

\- Use Next.js App Router conventions.

\- Prefer server components by default.

\- Use client components only when necessary:

&#x20; - local state

&#x20; - event handlers

&#x20; - browser APIs

&#x20; - animations



\## File Structure

\- Keep `page.tsx` and `layout.tsx` clean and minimal.

\- Do not place heavy business logic inside route files.

\- Extract logic into `features/`, `lib/`, or hooks.



\## Data Fetching

\- Fetch data on the server whenever possible.

\- Avoid unnecessary client-side fetching.

\- Keep fetching logic separate from UI when appropriate.

\- Always handle:

&#x20; - loading states

&#x20; - error states

&#x20; - empty states



\## Routing

\- Use clean, semantic route structures.

\- Avoid deeply nested routes without clear purpose.

\- Keep route segments predictable.



\## Server vs Client

\- Default to server components.

\- Add `"use client"` only when required.

\- Do not mix client/server logic unnecessarily.



\## Forms \& Actions

\- Use typed forms.

\- Validate inputs properly.

\- Keep server actions clean and isolated.



\## Performance

\- Avoid unnecessary re-renders.

\- Avoid heavy client-side logic when server can handle it.

\- Do not prematurely optimize.

