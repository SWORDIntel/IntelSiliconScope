#!/bin/bash
set -e

# Build script for DSMIL flashrom with local dependencies
# Handles missing system libraries (libpci, etc.)

echo "=== Setting up build environment ==="

# 1. Setup Python venv for build tools
if [ ! -d "venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv venv
    ./venv/bin/pip install meson ninja
fi
export PATH="$PWD/venv/bin:$PATH"

# 2. Build local pciutils if needed
if [ ! -d "pci-install" ]; then
    echo "Building local pciutils..."
    if [ ! -d "pciutils" ]; then
        git clone https://github.com/pciutils/pciutils.git
    fi
    
    cd pciutils
    make clean
    make CFLAGS="-O2 -fPIC"
    mkdir -p ../pci-install
    make install-lib DESTDIR="$PWD/../pci-install" PREFIX=/usr
    
    # Fix include path structure for meson
    ln -sf pci ../pci-install/usr/include/pciutils
    
    # Fix libpci.pc paths and flags
    cat > ../pci-install/usr/lib/pkgconfig/libpci.pc << EOF
prefix=$PWD/../pci-install/usr
includedir=\${prefix}/include
libdir=\${prefix}/lib
idsdir=\${prefix}/share

Name: libpci
Description: libpci
Version: 3.14.0
Libs: -L\${libdir} -lpci -lz -lresolv -ludev
Libs.private: -lz -lresolv -ludev
Cflags: -I\${includedir}
EOF
    cd ..
fi

export PKG_CONFIG_PATH="$PWD/pci-install/usr/lib/pkgconfig"

# 3. Configure and build flashrom
echo "=== Building flashrom ==="
# -Dtests=disabled: Avoid cmocka build errors
# -Dwerror=false: Avoid format string errors
# -Dc_link_args: Ensure static dependencies are linked
meson setup builddir --reconfigure \
    -Dtests=disabled \
    -Dwerror=false \
    -Dc_link_args="['-lz', '-ludev', '-lresolv']"

meson compile -C builddir

echo "=== Build Complete ==="
echo "Binary location: $PWD/builddir/flashrom"
./builddir/flashrom --version
