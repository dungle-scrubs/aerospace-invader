# Contributing

## Development Setup

1. Clone the repository
   ```bash
   git clone https://github.com/dungle-scrubs/aerospace-invader.git
   cd aerospace-invader
   ```

2. Install dependencies
   ```bash
   brew install swiftlint swift-format
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

## Testing

Tests require full Xcode (not just Command Line Tools):

```bash
# Check current selection
xcode-select -p

# If needed, switch to Xcode:
sudo xcode-select -s /Applications/Xcode.app

# Run tests
make test
```
