GODOT   := godot
DIST    := dist
VERSION := 4.6.2.stable

# Template install path on macOS
TEMPLATE_DIR := $(HOME)/Library/Application Support/Godot/export_templates/$(VERSION)

.PHONY: all windows macos linux clean templates check-templates

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

## macOS .dmg
macos: check-templates
	@mkdir -p $(DIST)/macos
	$(GODOT) --path . --export-release "macOS" $(DIST)/macos/TankArena.dmg
	@echo "✓ macOS build: $(DIST)/macos/TankArena.dmg"

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
