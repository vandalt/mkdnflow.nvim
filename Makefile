.PHONY: docs help test test_file

help:
	@echo "Available targets:"
	@echo "  make docs       - Regenerate README.md and doc/mkdnflow.txt"
	@echo "  make test       - Run all tests"
	@echo "  make test_file FILE=<path>  - Run a specific test file"

docs:
	@echo "Generating documentation..."
	@python3 scripts/generate_docs.py

# Run all tests
test: deps/mini.nvim
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()"

# Run a specific test file
test_file: deps/mini.nvim
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)')"

# Download mini.nvim dependency for testing
deps/mini.nvim:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/nvim-mini/mini.nvim deps/mini.nvim
