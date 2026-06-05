# Contributing

Thanks for your interest in IHaskell (Haskell-AI fork)!

## How to Contribute

### Report Bugs

Open a [GitHub Issue](https://github.com/jjunho/IHaskell/issues) with:
- GHC version (`ghc --version`)
- IHaskell version (`cabal exec ihaskell -- --version`)
- Steps to reproduce
- Expected vs actual behavior

### Suggest Features

Open an issue with the "enhancement" label describing the feature and use case.

### Pull Requests

1. Fork the repository
2. Create a branch: `git checkout -b feature/my-feature`
3. Make changes
4. Ensure it builds: `cabal build`
5. Ensure tests pass: `cabal test`
6. Commit with clear messages
7. Push and open a PR

## Development Setup

```bash
git clone https://github.com/jjunho/IHaskell
cd IHaskell
cabal build
cabal test
```

### Code Style

- Follow existing patterns in the codebase
- Add tests for new functionality
- Avoid adding new dependencies when base libraries suffice
- CPP guards for GHC version compat go in `Compat.hs`

### Testing

```bash
cabal test
# Expect: 102 examples, 0 failures
```

For display package changes, build individually:
```bash
cabal build ihaskell-blaze
cabal build ihaskell-diagrams
```

## Project Structure

See `README.md` for full project structure overview.

## License

By contributing, you agree your contributions will be licensed under the MIT License.
