.PHONY: docs help test test_file test-compat

help:
	@echo "Available targets:"
	@echo "  make docs       - Regenerate README.md and doc/mkdnflow.txt"
	@echo "  make test       - Run all tests"
	@echo "  make test_file FILE=<path>  - Run a specific test file"
	@echo "  make test-compat - Run tests on all supported Neovim versions (requires bob)"

docs:
	@echo "Generating documentation..."
	@python3 scripts/generate_docs.py

# Run all tests
test: deps/mini.nvim
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()"

# Run a specific test file
test_file: deps/mini.nvim
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)')"

# Run tests on all supported Neovim versions (requires bob: https://github.com/MordechaiHadad/bob)
test-compat: deps/mini.nvim
	@command -v bob >/dev/null 2>&1 || { echo "Error: bob is not installed. See https://github.com/MordechaiHadad/bob"; exit 1; }
	@for v in 0.9.5 0.10.0 stable; do \
		echo "=== Testing Neovim $$v ==="; \
		bob run $$v -- --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()" || exit 1; \
	done
	@echo "All versions passed!"

# Download mini.nvim dependency for testing
deps/mini.nvim:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/nvim-mini/mini.nvim deps/mini.nvim
