\# UI \& Frontend Rules



\## Component Design

\- Components should do one thing well.

\- Keep components small and composable.

\- Extract reusable UI patterns.

\- Avoid large, messy JSX blocks.



\## State Management

\- Keep state local when possible.

\- Do not lift state unnecessarily.

\- Derive values instead of duplicating state.

\- Avoid prop drilling when composition solves it.



\## Effects

\- Avoid unnecessary useEffect.

\- Do not use useEffect for logic that can run during render.

\- Ensure dependencies are correct.



\## Tailwind CSS

\- Use Tailwind consistently.

\- Keep class names readable and structured.

\- Group classes logically:

&#x20; - layout

&#x20; - spacing

&#x20; - typography

&#x20; - colors

&#x20; - effects

\- Extract reusable components instead of repeating long class strings.



\## Design Quality

\- Build clean, modern, premium UI.

\- Maintain strong visual hierarchy.

\- Use consistent spacing and typography.

\- Avoid clutter.



\## Responsiveness

\- Design mobile-first.

\- Ensure layouts work across breakpoints.

\- Avoid fragile UI structures.



\## Interaction States

Always consider:

\- hover

\- active

\- focus

\- disabled

\- loading

\- empty



\## UX

\- Make UI predictable and intuitive.

\- Avoid confusing interactions.

\- Provide feedback for user actions.

