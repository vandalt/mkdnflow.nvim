# Contributing to Mkdnflow

Thanks for considering contributing to Mkdnflow!

## How to contribute

### Reporting bugs

To submit a bug report, use the bug report issue template and follow the instructions within the template.

* Use a clear and descriptive title for the issue to identify the problem.
* Describe the exact steps which reproduce the problem in as many details as possible.
* Provide specific examples to demonstrate the steps.

### Suggesting features and enhancements

Suggestions are welcome, including completely new features or minor improvements to existing functionality.

* Use a clear and descriptive title for the issue to identify the suggestion.
* Provide a step-by-step description of the suggested enhancement in as many details as possible.
* Provide specific examples to demonstrate the steps.

### Pull requests

Pull requests are welcome for both bugfixes and new features. I reserve the right not to merge a PR in any case. In all such cases, I will communicate with you on the PR to let you know whether/what changes need to be made to the PR before it can be merged.

* Clearly describe what the pull request does
* Include screenshots or animated GIFs in your pull request when sensible.
* Use [**Conventional Commits**](https://www.conventionalcommits.org/)! Otherwise, I will ask you to revise your PR.
* When a PR adds or changes a feature, update the documentation as well (see [Documentation](#documentation) below).

## Documentation

Both `README.md` and `doc/mkdnflow.txt` are generated from a single source: `scripts/generate_docs.py`. **Do not edit README.md or doc/mkdnflow.txt directly**—your changes will be overwritten.

To update documentation:

1. Edit the content in `scripts/generate_docs.py`
2. Run `make docs` to regenerate both files
3. Commit all three files together (`generate_docs.py`, `README.md`, `doc/mkdnflow.txt`)

CI will verify that documentation is in sync. If you forget to run `make docs`, the CI check will fail.

## Development

### Running tests

Tests use the [mini.test](https://github.com/echasnovski/mini.test) framework. To run tests:

```bash
make deps/mini.nvim   # One-time: download test dependency
make test             # Run all tests
make test_file FILE=tests/test_foo.lua  # Run a specific test file
```

### Multi-version compatibility testing

The plugin supports Neovim 0.9.5+. To test across all supported versions locally, use [bob](https://github.com/MordechaiHadad/bob) (a Neovim version manager):

```bash
# Install bob (macOS)
brew install bob

# Install the versions we test against
bob install 0.9.5
bob install 0.10.0
bob install stable

# Run tests on all versions
make test-compat
```

CI automatically tests against 0.9.5, 0.10.0, and stable on every push.

## Styleguides

### Git commit messages

This project now uses the [Conventional Commits](https://www.conventionalcommits.org/) specification for its commit messages. This provides a number of benefits, including better human and machine readability and compliance with the requirements for automatic versioning, which is used in the main branch.

In addition to using conventional commits, please adhere to the following when writing commit messages:

1. Use the present tense in the imperative mood ("Add feature", not "Added feature" or "Adds feature")
2. Limit the first line to 72 characters or less
3. Reference issues and pull requests liberally after the first line

Examples:

```
feat: Add new mapping for buffer navigation
fix: Resolve issue with autocmd not firing
docs: Update installation instructions in README
refactor: Simplify autocommand setup
```
