#!/bin/sh
# Cross-build static, stripped DTC binaries (with libyaml) for all targets
# using zig cc.
set -eu

DTC_SRC=${DTC_SRC:-/src/dtc}
YAML_SRC=${YAML_SRC:-/src/libyaml}
OUT=${OUT:-/out}
WORK=${WORK:-/work}
TOOLS="dtc fdtget fdtput fdtdump fdtoverlay"

TARGETS="
linux-x86:x86-linux-musl
linux-x64:x86_64-linux-musl
linux-arm:arm-linux-musleabihf
linux-aarch64:aarch64-linux-musl
linux-riscv64:riscv64-linux-musl
windows-x86:x86-windows-gnu
windows-x64:x86_64-windows-gnu
windows-aarch64:aarch64-windows-gnu
"

# libyaml version, read from the submodule so updates are picked up.
yaml_ver() { sed -n "s/^m4_define(\[YAML_$1\], *\([0-9]*\))/\1/p" "$YAML_SRC/configure.ac"; }
YAML_MAJOR=$(yaml_ver MAJOR)
YAML_MINOR=$(yaml_ver MINOR)
YAML_PATCH=$(yaml_ver PATCH)
YAML_VERSION="$YAML_MAJOR.$YAML_MINOR.$YAML_PATCH"

# Build a static libyaml for one target into $1 (a prefix dir).
build_libyaml() {
	prefix=$1 triple=$2
	obj=$WORK/yaml-obj
	rm -rf "$obj" && mkdir -p "$obj" "$prefix/lib/pkgconfig" "$prefix/include"
	for c in "$YAML_SRC"/src/*.c; do
		zig cc -target "$triple" -Os -c "$c" -o "$obj/$(basename "$c" .c).o" \
			-I"$YAML_SRC/include" -DYAML_DECLARE_STATIC \
			-DYAML_VERSION_MAJOR="$YAML_MAJOR" \
			-DYAML_VERSION_MINOR="$YAML_MINOR" \
			-DYAML_VERSION_PATCH="$YAML_PATCH" \
			-DYAML_VERSION_STRING="\"$YAML_VERSION\""
	done
	zig ar rcs "$prefix/lib/libyaml.a" "$obj"/*.o
	cp "$YAML_SRC/include/yaml.h" "$prefix/include/"
	cat > "$prefix/lib/pkgconfig/yaml-0.1.pc" <<PC
prefix=$prefix
Name: LibYAML
Description: Library to parse and emit YAML
Version: $YAML_VERSION
Cflags: -I\${prefix}/include -DYAML_DECLARE_STATIC
Libs: -L\${prefix}/lib -lyaml
PC
}

# Build in a scratch copy so the submodule checkout is never modified.
rm -rf "$WORK" && mkdir -p "$WORK"
cp -a "$DTC_SRC" "$WORK/dtc"

for entry in $TARGETS; do
	name=${entry%%:*}
	triple=${entry#*:}
	ext=""
	case "$triple" in *windows*) ext=".exe" ;; esac

	echo "=== $name ($triple) ==="
	prefix=$WORK/sysroot/$name
	build_libyaml "$prefix" "$triple"

	cd "$WORK/dtc"
	make clean >/dev/null
	PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig" \
	make -j"$(nproc)" $TOOLS \
		CC="zig cc -target $triple" \
		AR="zig ar" \
		NO_PYTHON=1 NO_VALGRIND=1 \
		STATIC_BUILD=1 \
		EXTRA_CFLAGS="-Wno-error" \
		LDFLAGS="-static -s"

	mkdir -p "$OUT/$name"
	for t in $TOOLS; do
		cp "$t" "$OUT/$name/$t$ext"
	done
done

cd "$OUT"
find . -type f ! -name SHA256SUMS | sort | xargs sha256sum > SHA256SUMS
