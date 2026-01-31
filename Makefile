.PHONY: docs help

help:
	@echo "Available targets:"
	@echo "  make docs  - Regenerate README.md and doc/mkdnflow.txt"

docs:
	@echo "Generating documentation..."
	@python3 scripts/generate_docs.py
