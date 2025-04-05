# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands
- Linting/Formatting: Use Stylua with the configuration in `.stylua.toml`
- No specific build or test commands

## Code Style

### Formatting
- Column width: 100 characters
- Indent: 4 spaces
- Quote style: Prefer single quotes when possible

### Naming Conventions
- Module files: snake_case (`utils.lua`)
- Functions: camelCase (`getFileType`)
- Variables: snake_case (`start_row`)

### Code Structure
- Organize functionality in modules under `lua/mkdnflow/`
- Use `local M = {}` pattern for module exports
- Keep related functions grouped together
- Functions exposed as properties of the module table

### Git Commits
- Follow Conventional Commits (feat:, fix:, docs:, etc.)
- Use imperative present tense ("Add feature", not "Added feature")
- First line limited to 72 characters
- Reference issues/PRs after first line

### Error Handling
- Use `vim.api.nvim_echo()` with proper highlighting
- Return nil/false on failure instead of throwing errors
- Validate inputs when necessary