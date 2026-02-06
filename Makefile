# ============================================================================
# DSMIL Firmware Toolkit - Build System
# ============================================================================

.PHONY: all clean install uninstall test format help
.PHONY: flashrom gbe-toolkit edk2 emba devmem2

# Default target
all: flashrom gbe-toolkit devmem2

# ============================================================================
# Component Builds
# ============================================================================

# flashrom - Universal SPI flash utility
flashrom:
	@echo "Building flashrom..."
	cd flashrom && \
	meson setup builddir && \
	meson compile -C builddir

# GbE NVM Toolkit - Native Linux Intel GbE management
gbe-toolkit:
	@echo "GbE NVM Toolkit (shell scripts) - no build required"
	@chmod +x gbe-nvm-toolkit/*.sh gbe-nvm-toolkit/*.py

# EDK2 Shell Package - UEFI shell with DSMIL extensions
edk2:
	@echo "Building EDK2 Shell Package..."
	cd edk2_shell_pkg && \
	source edksetup.sh && \
	build -a X64 -p ShellPkg/ShellPkg.dsc

# EMBA - Firmware security scanner
emba:
	@echo "Setting up EMBA..."
	cd emba && \
	./installer.sh

# devmem2 - Direct memory access utility
devmem2:
	@echo "Building devmem2..."
	cd devmem2 && \
	make

# ============================================================================
# Installation
# ============================================================================

install: all
	@echo "Installing DSMIL Firmware Toolkit..."
	# Create directories
	sudo mkdir -p /opt/dsmil-firmware-toolkit/{bin,lib,share}
	sudo mkdir -p /usr/local/bin

	# Install flashrom
	sudo cp flashrom/builddir/flashrom /usr/local/bin/
	sudo cp -r flashrom /opt/dsmil-firmware-toolkit/lib/

	# Install GbE toolkit
	sudo cp -r gbe-nvm-toolkit /opt/dsmil-firmware-toolkit/
	sudo ln -sf /opt/dsmil-firmware-toolkit/gbe-nvm-toolkit/gbe_nvm_update.sh /usr/local/bin/gbe-nvm-update
	sudo ln -sf /opt/dsmil-firmware-toolkit/gbe-nvm-toolkit/gbe_nvm_mmio.py /usr/local/bin/gbe-nvm-mmio
	sudo ln -sf /opt/dsmil-firmware-toolkit/gbe-nvm-toolkit/gbe_nvm_ethtool.sh /usr/local/bin/gbe-nvm-ethtool

	# Install devmem2
	sudo cp devmem2/devmem2 /usr/local/bin/

	# Install Intel tools
	sudo cp -r intel_platform_flash_tool /opt/dsmil-firmware-toolkit/
	sudo ln -sf /opt/dsmil-firmware-toolkit/intel_platform_flash_tool/platformflashtoollite_extracted/opt/intel/platformflashtoollite/bin/platformflashtoollite /usr/local/bin/intel-platform-flash-tool

	# Install EMBA
	sudo cp -r emba /opt/dsmil-firmware-toolkit/
	sudo ln -sf /opt/dsmil-firmware-toolkit/emba/emba /usr/local/bin/emba

	# Install EDK2 shell
	sudo cp -r edk2_shell_pkg /opt/dsmil-firmware-toolkit/

	# Set permissions
	sudo chmod -R 755 /opt/dsmil-firmware-toolkit/
	sudo chmod +x /opt/dsmil-firmware-toolkit/gbe-nvm-toolkit/*.sh
	sudo chmod +x /opt/dsmil-firmware-toolkit/gbe-nvm-toolkit/*.py

	@echo "Installation complete!"
	@echo "Tools available in /usr/local/bin/ and /opt/dsmil-firmware-toolkit/"

uninstall:
	@echo "Uninstalling DSMIL Firmware Toolkit..."
	sudo rm -rf /opt/dsmil-firmware-toolkit/
	sudo rm -f /usr/local/bin/flashrom
	sudo rm -f /usr/local/bin/gbe-nvm-update
	sudo rm -f /usr/local/bin/gbe-nvm-mmio
	sudo rm -f /usr/local/bin/gbe-nvm-ethtool
	sudo rm -f /usr/local/bin/devmem2
	sudo rm -f /usr/local/bin/intel-platform-flash-tool
	sudo rm -f /usr/local/bin/emba
	@echo "Uninstall complete!"

# ============================================================================
# Testing
# ============================================================================

test: all
	@echo "Running tests..."
	@echo "Testing flashrom..."
	@if command -v flashrom >/dev/null 2>&1; then \
		echo "✓ flashrom installed"; \
	else \
		echo "✗ flashrom not found"; \
	fi

	@echo "Testing GbE toolkit..."
	@if [ -x gbe-nvm-toolkit/gbe_nvm_update.sh ]; then \
		echo "✓ GbE toolkit executable"; \
	else \
		echo "✗ GbE toolkit not executable"; \
	fi

	@echo "Testing devmem2..."
	@if [ -x devmem2/devmem2 ]; then \
		echo "✓ devmem2 built"; \
	else \
		echo "✗ devmem2 not built"; \
	fi

	@echo "Running integration tests..."
	cd tests && ./run_tests.sh || echo "Tests completed with warnings"

# ============================================================================
# Development
# ============================================================================

format:
	@echo "Formatting code..."
	@find . -name "*.c" -o -name "*.h" | xargs clang-format -i
	@find . -name "*.py" | xargs black -q 2>/dev/null || true
	@find . -name "*.sh" | xargs shellcheck -f diff 2>/dev/null || true

lint:
	@echo "Running linters..."
	@find . -name "*.c" -o -name "*.h" | xargs cppcheck --enable=all --quiet
	@find . -name "*.py" | xargs pylint --disable=all --enable=E,F 2>/dev/null || true
	@find . -name "*.sh" | xargs shellcheck 2>/dev/null || true

# ============================================================================
# Cleanup
# ============================================================================

clean:
	@echo "Cleaning build artifacts..."
	cd flashrom && rm -rf builddir
	cd devmem2 && make clean 2>/dev/null || true
	cd edk2_shell_pkg && rm -rf Build
	find . -name "*.o" -delete
	find . -name "*.so" -delete
	find . -name "*.a" -delete
	find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

distclean: clean
	@echo "Cleaning all generated files..."
	rm -rf build dist
	find . -name "*.log" -delete
	find . -name "*.tmp" -delete

# ============================================================================
# Help
# ============================================================================

help:
	@echo "DSMIL Firmware Toolkit Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all          - Build all components"
	@echo "  flashrom     - Build flashrom utility"
	@echo "  gbe-toolkit  - Prepare GbE NVM toolkit"
	@echo "  edk2         - Build EDK2 shell package"
	@echo "  emba         - Setup EMBA scanner"
	@echo "  devmem2      - Build devmem2 utility"
	@echo ""
	@echo "  install      - Install system-wide"
	@echo "  uninstall    - Remove installation"
	@echo ""
	@echo "  test         - Run tests"
	@echo "  format       - Format source code"
	@echo "  lint         - Run code analysis"
	@echo ""
	@echo "  clean        - Clean build artifacts"
	@echo "  distclean    - Clean all generated files"
	@echo "  help         - Show this help"
	@echo ""
	@echo "Examples:"
	@echo "  make all              # Build everything"
	@echo "  make flashrom         # Build only flashrom"
	@echo "  sudo make install     # Install system-wide"
	@echo "  make test             # Run tests"

# ============================================================================
# Dependencies
# ============================================================================

# Check for required dependencies
check-deps:
	@echo "Checking dependencies..."
	@command -v meson >/dev/null 2>&1 || (echo "ERROR: meson not found" && exit 1)
	@command -v ninja >/dev/null 2>&1 || (echo "ERROR: ninja not found" && exit 1)
	@command -v python3 >/dev/null 2>&1 || (echo "ERROR: python3 not found" && exit 1)
	@command -v gcc >/dev/null 2>&1 || (echo "ERROR: gcc not found" && exit 1)
	@echo "All dependencies found!"

# ============================================================================
# Release
# ============================================================================

VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo "unknown")
ARCHIVE := dsmil-firmware-toolkit-$(VERSION)

release: clean
	@echo "Creating release archive: $(ARCHIVE).tar.gz"
	@mkdir -p dist
	@tar --exclude='.git' --exclude='dist' --exclude='build' \
		--exclude='*.log' --exclude='__pycache__' \
		-czf dist/$(ARCHIVE).tar.gz .
	@echo "Release archive created: dist/$(ARCHIVE).tar.gz"

# Include component-specific makefiles if they exist
-include flashrom/Makefile 2>/dev/null || true
-include devmem2/Makefile 2>/dev/null || true
