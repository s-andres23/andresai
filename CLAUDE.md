# AndresAI – Claude Development Instructions

## Project

AndresAI is a personal AI assistant application for:

- iOS
- Android
- macOS
- Windows

The project uses a monorepo.

## Tech Stack

### Client
- Flutter
- Dart

### Backend
- NestJS
- TypeScript

### Data
- Supabase PostgreSQL
- Supabase Auth
- Supabase Storage
- Supabase Realtime

### AI
- Claude as the initial AI provider
- AI access only through the backend
- AI provider abstraction required

---

# Architecture Rules

1. Follow the existing architecture.
2. Do not introduce new frameworks without explicit approval.
3. Architectural changes require explicit approval.
4. Keep code modular and easy to navigate.
5. Prefer readability over cleverness.
6. Do not refactor unrelated working code.
7. Avoid unnecessary abstraction.
8. Avoid large monolithic files.
9. Reuse shared logic instead of copy/paste.
10. Remove unused code.

---

# Backend Rules

Backend structure:

controller → service → repository

AI tools call services.

AI tools must never access repositories or databases directly.

Business logic belongs in services.

Database access belongs in repositories.

External integrations must use provider interfaces.

Examples:

- CalendarProvider
- EmailProvider
- MessagingProvider
- StorageProvider
- AIProvider

Never expose secrets to the client or AI model.

---

# Flutter Rules

Flutter is a client.

Do not place backend business logic inside Flutter.

Organize features under:

lib/features/

Only add subfolders when they are actually useful.

Avoid artificial folder nesting.

Shared reusable code belongs in:

lib/shared/

Core infrastructure belongs in:

lib/core/

---

# AI Rules

Claude must never receive direct database access.

AI requests flow through:

User
→ AI Orchestrator
→ Context Manager
→ Claude
→ Tool Call
→ Permission Layer
→ Service
→ Repository / Integration

Only load context relevant to the current user request.

Structured data such as tasks, calendar events, goals, and reminders should not be duplicated as AI memory.

---

# Permission Rules

Actions are classified as:

READ
WRITE
DESTRUCTIVE
EXTERNAL_COMMUNICATION

Rules:

READ:
No confirmation required.

Small WRITE actions:
Usually execute directly.

Large or significant WRITE actions:
May require confirmation.

DESTRUCTIVE:
Require confirmation.

EXTERNAL_COMMUNICATION:
Always require confirmation.

---

# Security Rules

- API keys only in backend environment variables.
- Never commit secrets.
- Never place secrets in Flutter.
- Validate all backend input.
- Use authentication for protected endpoints.
- All user-owned database records must include user_id.
- Supabase RLS must be enabled on user-owned tables.
- Do not log sensitive user information.
- Use HTTPS.
- Do not weaken security to simplify development.

---

# Coding Style

- Use descriptive English names.
- Avoid unclear abbreviations.
- Keep functions focused.
- Keep classes focused.
- Comments should explain why, not repeat what the code already says.
- Maintain consistency with surrounding code.

---

# Tests

Do not weaken valid tests to make them pass.

After significant changes:

1. Run formatter.
2. Run linter.
3. Run relevant tests.
4. Verify compilation/build.
5. Fix errors.
6. Summarize the changes.

---

# Git

The main branch must remain stable.

Use feature branches for larger work when appropriate.

Examples:

feature/auth
feature/tasks
feature/calendar
feature/ai-chat

Commit messages should follow patterns such as:

feat(tasks): add task creation endpoint
feat(calendar): add event editing
fix(auth): restore expired session handling
test(memory): add ownership tests
docs(api): update chat endpoints

---

# V0.1 Scope

V0.1 includes:

- Login / Account
- Onboarding
- Home Dashboard
- AI Chat
- Tasks
- Internal Calendar
- Reminders
- Profile
- Basic Memory
- Chat History
- Notifications
- Multi-Device Sync

Do not implement out-of-scope features unless explicitly requested.

Examples of features NOT in V0.1:

- Fitness
- Learning
- Goals
- Habits
- Projects
- PDF RAG
- NAS
- Email
- SMS / Messaging
- Contacts
- Google Calendar
- Outlook
- Voice
- Widgets
- Desktop Quick Chat
- Health
- Payments
