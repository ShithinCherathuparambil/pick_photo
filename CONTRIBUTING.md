# Contributing to pick_photo

Thank you for contributing to `pick_photo`!

## Code of Conduct

Please be respectful and constructive in all communication and issue discussions.

## Development Workflow

1. Fork and clone the repository.
2. Install the latest stable Flutter SDK.
3. Install dependencies:
   ```bash
   flutter pub get
   ```
4. Regenerate Pigeon platform bindings if altering native channel definitions:
   ```bash
   dart run pigeon --input pigeons/messages.dart
   ```
5. Run the analyzer and test suites:
   ```bash
   flutter analyze
   flutter test
   ```

## Commit Guidelines

- Write clear, concise commit messages following Conventional Commits (e.g. `feat:`, `fix:`, `docs:`, `test:`).
- Verify that tests pass and formatting is clean (`dart format .`).
- Keep diffs focused and minimal.
