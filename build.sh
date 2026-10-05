#!/bin/sh
# Build static DTC binaries for all targets into ./bin using Docker + zig cc.
#
#   ./build.sh [build]   build everything into ./bin (default)
#   ./build.sh clean     remove ./bin
set -eu

ROOT=$(cd "$(dirname "$0")" && pwd)
BIN=$ROOT/bin
SUBMODULES="dtc libyaml"
ZIG_VERSION=${ZIG_VERSION:-0.16.0}

# Describe one git checkout: version, commit and clean/dirty state.
describe() {
	dir=$1
	if ! commit=$(git -C "$dir" rev-parse --verify -q HEAD); then
		echo "  Commit:  (none - no commits yet)"
		UNCLEAN=1
		return
	fi
	version=$(git -C "$dir" describe --tags --always 2>/dev/null || echo "$commit")
	if [ -n "$(git -C "$dir" status --porcelain)" ]; then
		state="dirty (uncommitted changes)"
		UNCLEAN=1
	else
		state="clean"
	fi
	echo "  Version: $version"
	echo "  Commit:  $commit"
	echo "  Status:  $state"
}

release_notes() {
	UNCLEAN=0
	echo "DTC static cross-build"
	echo "======================"
	echo
	echo "Built:       $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
	echo "Zig version: $ZIG_VERSION"
	echo
	echo "Project"
	describe "$ROOT"
	echo
	for m in $SUBMODULES; do
		url=$(git -C "$ROOT" config -f .gitmodules --get "submodule.$m.url")
		echo "Submodule: $m"
		echo "  URL:     $url"
		describe "$ROOT/$m"
		# '+' means the checkout differs from the commit recorded in the project.
		case "$(git -C "$ROOT" submodule status -- "$m" | cut -c1)" in
			+) echo "  Note:    checked-out commit differs from the one recorded in the project"
			   UNCLEAN=1 ;;
		esac
		echo
	done
	if [ "$UNCLEAN" = 1 ]; then
		echo "WARNING: some sources were not in a committed state; this build"
		echo "may not be exactly reproducible."
	else
		echo "All sources were clean; checking out the commits above and"
		echo "rebuilding should reproduce these binaries."
	fi
}

cmd_build() {
	for m in $SUBMODULES; do
		if [ ! -e "$ROOT/$m/.git" ]; then
			echo "Submodule '$m' is missing; run: git submodule update --init" >&2
			exit 1
		fi
	done

	# Gather the notes before building, so they reflect the built sources.
	notes=$(mktemp)
	trap 'rm -f "$notes"' EXIT
	release_notes > "$notes"

	rm -rf "$BIN"
	docker build -f "$ROOT/docker/Dockerfile" \
		--build-arg ZIG_VERSION="$ZIG_VERSION" \
		--build-arg DTC_VERSION="$(git -C "$ROOT/dtc" describe --tags --always --dirty)" \
		--output "type=local,dest=$BIN" "$ROOT"
	cp "$notes" "$BIN/RELEASE_NOTES.txt"
	echo "Binaries written to $BIN"
}

cmd_clean() {
	rm -rf "$BIN"
	echo "Removed $BIN"
}

case "${1:-build}" in
	build) cmd_build ;;
	clean) cmd_clean ;;
	*) echo "usage: $0 [build|clean]" >&2; exit 1 ;;
esac
