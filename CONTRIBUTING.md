# Contributing to KonexZero

Thank you for your interest in contributing to KonexZero! This document provides guidelines for contributing.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/konexzero.git`
3. Create a branch: `git checkout -b my-feature`
4. Make your changes
5. Run tests: `bundle exec rspec`
6. Run linter: `bin/rubocop`
7. Commit with a clear message
8. Push and open a Pull Request

## Development Setup

```bash
bin/setup    # Install dependencies, prepare database
bin/dev      # Start development servers
```

## Code Style

- We use `rubocop-rails-omakase` — run `bin/rubocop` before committing
- No `rubocop:disable` overrides without strong justification
- Follow existing patterns in the codebase

## Testing

- Write tests for all new features and bug fixes
- Run the full suite before submitting: `bundle exec rspec`
- Use factories (FactoryBot) for test data
- Stub external services (Cloudflare) with WebMock

## Commit Messages

- Use micro commits: each commit = one logical, atomic change
- Write clear, descriptive commit messages
- Every commit should leave the codebase in a working state

## Pull Requests

- Keep PRs focused — one feature or fix per PR
- Include tests
- Update documentation if needed
- Ensure CI passes

## Reporting Issues

- Use GitHub Issues for bugs and feature requests
- Include steps to reproduce for bugs
- Check existing issues before creating a new one

## Code of Conduct

Be respectful and constructive. We're building something together.

## License

By contributing, you agree that your contributions will be licensed under the Apache License 2.0.
