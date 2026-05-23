GODOT   := godot
DIST    := dist
VERSION := 4.6.2.stable

# Template install path on macOS
TEMPLATE_DIR := $(HOME)/Library/Application Support/Godot/export_templates/$(VERSION)

.PHONY: all windows windows-debug macos linux clean templates check-templates release check-clean check-gh

all: windows macos linux

## Download and install export templates (one-time setup)
templates:
	@echo "Opening Godot export template manager..."
	@echo "Go to: Editor → Export → Manage Export Templates → Download"
	$(GODOT) --path . --editor

## Check that templates are installed before exporting
check-templates:
	@if [ ! -d "$(TEMPLATE_DIR)" ]; then \
		echo ""; \
		echo "ERROR: Export templates not found at:"; \
		echo "  $(TEMPLATE_DIR)"; \
		echo ""; \
		echo "Install them with:  make templates"; \
		echo "  (Editor → Export → Manage Export Templates → Download)"; \
		echo ""; \
		exit 1; \
	fi

## Windows standalone .exe
windows: check-templates
	@mkdir -p $(DIST)/windows
	$(GODOT) --path . --export-release "Windows" $(DIST)/windows/TankArena.exe
	@echo "✓ Windows build: $(DIST)/windows/TankArena.exe"

## Windows debug build (shows console, full error output)
windows-debug: check-templates
	@mkdir -p $(DIST)/windows-debug
	$(GODOT) --path . --export-debug "Windows" $(DIST)/windows-debug/TankArena.exe
	@echo "✓ Windows debug build: $(DIST)/windows-debug/TankArena.exe"

## macOS .dmg — ad-hoc codesigned (no Apple Developer cert needed).
##
## Without any signature, recent macOS versions show "TankArena is damaged
## and can't be opened" on first launch and refuse to run the app even via
## right-click. Ad-hoc signing (the `-` identity) downgrades that to the
## standard "developer cannot be verified" dialog, which users can clear
## with one right-click → Open. No notarization, no $99 cert.
##
## Flow: export to .app → codesign → re-package into .dmg via hdiutil.
macos: check-templates
	@mkdir -p $(DIST)/macos
	@rm -rf "$(DIST)/macos/TankArena.app" "$(DIST)/macos/TankArena.dmg"
	$(GODOT) --path . --export-release "macOS" $(DIST)/macos/TankArena.app
	@echo "→ Ad-hoc codesigning..."
	codesign --force --deep --sign - "$(DIST)/macos/TankArena.app"
	@codesign --verify --deep --strict "$(DIST)/macos/TankArena.app"
	@echo "→ Packaging signed .app into .dmg..."
	@hdiutil create -volname "TankArena" -srcfolder "$(DIST)/macos/TankArena.app" \
		-ov -quiet -format UDZO "$(DIST)/macos/TankArena.dmg"
	@rm -rf "$(DIST)/macos/TankArena.app"
	@echo "✓ macOS build: $(DIST)/macos/TankArena.dmg (ad-hoc signed)"

## Linux x86_64 binary
linux: check-templates
	@mkdir -p $(DIST)/linux
	$(GODOT) --path . --export-release "Linux" $(DIST)/linux/TankArena.x86_64
	@chmod +x $(DIST)/linux/TankArena.x86_64
	@echo "✓ Linux build: $(DIST)/linux/TankArena.x86_64"

## Remove all build output
clean:
	rm -rf $(DIST)
	@echo "✓ dist/ removed"

# ---------------------------------------------------------------------------
# Release
# ---------------------------------------------------------------------------

# Auto-generated release tag: yyyy.mm.dd.HHMMSS (UTC).
# Evaluated once when the Makefile is parsed, so a single `make release`
# invocation uses a single consistent tag across all sub-steps.
RELEASE_TAG := $(shell date -u +%Y.%m.%d.%H%M%S)

## Build all platforms, then create a GitHub release tagged yyyy.mm.dd.HHMMSS
## with the three binaries attached. Requires a clean working tree and `gh` CLI.
release: check-gh check-clean all
	@echo ""
	@echo "→ Pushing current branch to origin..."
	git push origin HEAD
	@echo ""
	@echo "→ Creating release $(RELEASE_TAG)..."
	gh release create "$(RELEASE_TAG)" \
		--title "$(RELEASE_TAG)" \
		--target "$$(git rev-parse HEAD)" \
		--notes "Automated release built from $$(git rev-parse --short HEAD)." \
		"$(DIST)/windows/TankArena.exe" \
		"$(DIST)/macos/TankArena.dmg" \
		"$(DIST)/linux/TankArena.x86_64"
	@echo ""
	@echo "✓ Release $(RELEASE_TAG) is live."
	@echo "  https://github.com/rossille/tta/releases/tag/$(RELEASE_TAG)"

## Ensure the working tree is clean before releasing (so the tag is reproducible).
check-clean:
	@if [ -n "$$(git status --porcelain)" ]; then \
		echo ""; \
		echo "ERROR: working tree is dirty. Commit or stash changes before releasing."; \
		echo ""; \
		git status --short; \
		echo ""; \
		exit 1; \
	fi

## Ensure the GitHub CLI is installed and authenticated.
check-gh:
	@command -v gh >/dev/null 2>&1 || { \
		echo "ERROR: gh CLI not found. Install: https://cli.github.com/"; \
		exit 1; \
	}
	@gh auth status >/dev/null 2>&1 || { \
		echo "ERROR: gh CLI is not authenticated. Run: gh auth login"; \
		exit 1; \
	}
