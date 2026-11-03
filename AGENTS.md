# Project UI workflow

- Before changing UI, read and apply the installed `frontend-design` skill. If unavailable, tell the user before substituting another design workflow.
- Preserve the user's current visual direction: cyan accents, light surfaces, and a #292929 dark theme. Prioritize their reference images and latest corrections over generic redesigns.
- Review hierarchy, alignment, spacing, contrast, readable text, touch targets, and both directions of navigation motion before completing UI work.
- Do not run, install on, or interact with emulators for testing until the user explicitly authorizes emulator testing again. Use Dart analysis, source/layout review and Android builds in the meantime. Do not add or run automated test cases unless requested.
- Keep network work deferred unless the user explicitly requests it. Do not introduce advertising, tracking, cloud features, or background network behavior.
