# Contributing

## Development Setup

1. Clone the repository
   ```bash
   git clone https://github.com/dungle-scrubs/aerospace-invader.git
   cd aerospace-invader
   ```

2. Install dependencies
   ```bash
   brew install swiftlint swift-format lefthook trufflehog
   lefthook install
   ```

3. Build and run
   ```bash
   make build
   make run
   ```

## Making Changes

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests (`make test`)
5. Run linter (`make lint`)
6. Commit your changes
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

## Code Style

- SwiftLint is configured in `.swiftlint.yml`
- Run `make lint` before committing
- Run `make format` to auto-format code

## Commit Messages

This project uses [Release Please](https://github.com/googleapis/release-please) and
[Conventional Commits](https://www.conventionalcommits.org/) to generate the
changelog and version bumps. Use these prefixes:

- `feat:` - new feature (minor bump pre-1.0, patch post-1.0 per config)
- `fix:` - bug fix (patch)
- `perf:` / `refactor:` / `deps:` - changed behavior (patch)
- `docs:` - documentation only
- `chore:` / `ci:` / `test:` - maintenance (no release notes)

Examples: `feat: add drag-to-reorder`, `fix: handle nil workspace`.
Breaking changes use `feat!:` or `fix!:` with `BREAKING CHANGE:` footer.

## Testing

The tests use the [Swift Testing](https://developer.apple.com/documentation/testing) framework,
which requires Xcode 16+ (Swift 6 toolchain) — Command Line Tools alone are not sufficient:

```bash
# Check current selection
xcode-select -p

# If needed, switch to Xcode:
sudo xcode-select -s /Applications/Xcode.app

# Run tests
make test
```
