# Repository Guidelines

## Project Structure & Module Organization
- `src/main.zig`: executable entrypoint.
- `src/core/`: application orchestration and interfaces (`app.zig`, `interfaces.zig`).
- `src/adapters/`: platform and data-source adapters.
- `src/adapters/windows/`: Win32-specific integration (clipboard, timer/tick, Win32 bindings).
- `src/adapters/text/`: text providers (fixed or incrementing sources).
- `src/root.zig`: library root and module-level tests.
- `docs/`: technical notes and design references.
- Tests are colocated in `test` blocks inside `.zig` files.

## Build, Test, and Development Commands
- `zig build`: compile the project and install artifacts to `zig-out/`.
- `zig build run`: build and run the app locally.
- `zig build test`: run all module and executable tests.
- `zig build --help`: list available build steps and options.

Example:
```powershell
zig build test
zig build run
```

## Coding Style & Naming Conventions
- Language: Zig (current toolchain declared by project files).
- Use 4-space indentation and keep code ASCII unless file already needs Unicode.
- File names: `snake_case.zig`.
- Types/structs: `PascalCase` (e.g., `WindowsPasteAdapter`).
- Functions/variables: `camelCase` (e.g., `runApp`, `setClipboardUnicodeText`).
- Keep adapters focused: one responsibility per adapter (tick, paste, text source).

## Testing Guidelines
- Prefer unit tests in the same file as implementation using Zig `test` blocks.
- Name tests by behavior, e.g., `test "runApp updates clipboard on tick callback"`.
- Cover critical flow changes (tick loop, text generation, clipboard write path).
- Run `zig build test` before opening a PR.

## Commit & Pull Request Guidelines
- Follow concise Conventional Commit style used in history:
  - `feat: ...`
  - `fix: ...`
  - `docs: ...`
  - `chore: ...`
- Keep commits focused and atomic; avoid mixing refactors with behavior changes.
- PRs should include:
  - Summary of what changed and why.
  - Test evidence (`zig build test` result).
  - Notes on Windows-specific behavior when touching `src/adapters/windows/`.

## Architecture Notes
- The app composes `AppAdapters` (`tick`, `text_source`, `paste`) in `main.zig`.
- `core/app.zig` coordinates flow; adapters implement platform/details.
- This separation is intentional to ease future replacement of tick simulation with websocket input.
