.PHONY: docs docs-verify help test test_file test-compat demos demo demos-publish

help:
	@echo "Available targets:"
	@echo "  make docs       - Regenerate README.md and doc/mkdnflow.txt"
	@echo "  make docs-verify - Verify docs are in sync with YAML sources"
	@echo "  make test       - Run all tests"
	@echo "  make test_file FILE=<path>  - Run a specific test file"
	@echo "  make test-compat - Run tests on all supported Neovim versions (requires bob)"
	@echo "  make demos [VARIANT=light|dark]  - Generate all demo GIFs (requires vhs)"
	@echo "  make demo TAPE=<name> [VARIANT=light|dark]  - Generate one demo (e.g. TAPE=todo)"
	@echo "  make demos-publish - Copy generated GIFs to media repo"

docs:
	@echo "Generating documentation..."
	@python3 scripts/generate_docs.py

# Verify documentation is in sync with YAML sources
docs-verify:
	@echo "Verifying documentation..."
	@old_readme=$$(shasum README.md) && \
	old_vimdoc=$$(shasum doc/mkdnflow.txt) && \
	python3 scripts/generate_docs.py && \
	new_readme=$$(shasum README.md) && \
	new_vimdoc=$$(shasum doc/mkdnflow.txt) && \
	if [ "$$old_readme" = "$$new_readme" ] && [ "$$old_vimdoc" = "$$new_vimdoc" ]; then \
		echo "✓ Documentation is in sync"; \
	else \
		echo "✗ Documentation out of sync. Run 'make docs' and commit the changes."; \
		exit 1; \
	fi

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

# Generate demo GIFs (requires vhs: https://github.com/charmbracelet/vhs)
# Both variants by default, or specify VARIANT=light|dark
demos:
	@command -v vhs >/dev/null 2>&1 || { echo "Error: vhs is not installed. See https://github.com/charmbracelet/vhs"; exit 1; }
	@command -v envsubst >/dev/null 2>&1 || { echo "Error: envsubst is not installed (part of gettext)."; exit 1; }
	@for tape in scripts/demos/*.tape; do \
		if [ -z "$(VARIANT)" ] || [ "$(VARIANT)" = "light" ]; then \
			echo "Recording $$tape (light)..."; \
			MARGIN_FILL="#ffffff" SUFFIX="_light" envsubst '$$MARGIN_FILL $$SUFFIX' < "$$tape" | vhs || exit 1; \
		fi; \
		if [ -z "$(VARIANT)" ] || [ "$(VARIANT)" = "dark" ]; then \
			echo "Recording $$tape (dark)..."; \
			MARGIN_FILL="#212830" SUFFIX="_dark" envsubst '$$MARGIN_FILL $$SUFFIX' < "$$tape" | vhs || exit 1; \
		fi; \
	done
	@echo "All demos recorded."

# Generate a single demo GIF (both variants by default, or specify VARIANT=light|dark)
demo:
	@test -n "$(TAPE)" || { echo "Usage: make demo TAPE=<name> [VARIANT=light|dark]"; exit 1; }
	@test -f "scripts/demos/$(TAPE).tape" || { echo "Error: scripts/demos/$(TAPE).tape not found."; exit 1; }
	@command -v vhs >/dev/null 2>&1 || { echo "Error: vhs is not installed. See https://github.com/charmbracelet/vhs"; exit 1; }
	@command -v envsubst >/dev/null 2>&1 || { echo "Error: envsubst is not installed (part of gettext)."; exit 1; }
	@if [ -z "$(VARIANT)" ] || [ "$(VARIANT)" = "light" ]; then \
		echo "Recording $(TAPE) (light)..."; \
		MARGIN_FILL="#ffffff" SUFFIX="_light" envsubst '$$MARGIN_FILL $$SUFFIX' < "scripts/demos/$(TAPE).tape" | vhs || exit 1; \
	fi
	@if [ -z "$(VARIANT)" ] || [ "$(VARIANT)" = "dark" ]; then \
		echo "Recording $(TAPE) (dark)..."; \
		MARGIN_FILL="#212830" SUFFIX="_dark" envsubst '$$MARGIN_FILL $$SUFFIX' < "scripts/demos/$(TAPE).tape" | vhs || exit 1; \
	fi

# Copy generated demo GIFs to the media repo
MEDIA_REPO ?= ../mkdnflow-media
demos-publish:
	@test -d "$(MEDIA_REPO)" || { echo "Error: Media repo not found at $(MEDIA_REPO). Clone it or set MEDIA_REPO=<path>."; exit 1; }
	@ls scripts/demos/gif/*_light.gif scripts/demos/gif/*_dark.gif >/dev/null 2>&1 || { echo "Error: No GIFs found. Run 'make demos' first."; exit 1; }
	@mkdir -p "$(MEDIA_REPO)/demos"
	@cp scripts/demos/gif/*_light.gif scripts/demos/gif/*_dark.gif "$(MEDIA_REPO)/demos/"
	@echo "GIFs copied to $(MEDIA_REPO)/demos/"

# Download mini.nvim dependency for testing
deps/mini.nvim:
	@mkdir -p deps
	git clone --filter=blob:none https://github.com/nvim-mini/mini.nvim deps/mini.nvim
