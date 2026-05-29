#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MLX_CMLX_DIR="$REPO_ROOT/.build/checkouts/mlx-swift/Source/Cmlx"
GENERATED_METAL_DIR="$MLX_CMLX_DIR/mlx-generated/metal"
OUTPUT_PATH="${1:-"$REPO_ROOT/.build/mlx.metallib"}"

if [ ! -d "$GENERATED_METAL_DIR" ]; then
    echo "Missing MLX generated metal directory: $GENERATED_METAL_DIR" >&2
    exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$(dirname "$OUTPUT_PATH")"

find "$GENERATED_METAL_DIR" -name '*.metal' -print | while IFS= read -r metal_file; do
    relative="${metal_file#$GENERATED_METAL_DIR/}"
    air_name="${relative//\//_}.air"
    xcrun -sdk macosx metal \
        -std=metal3.1 \
        -I "$GENERATED_METAL_DIR" \
        -I "$MLX_CMLX_DIR/mlx/mlx/backend/metal/kernels" \
        -c "$metal_file" \
        -o "$TMP_DIR/$air_name"
done

xcrun -sdk macosx metallib "$TMP_DIR"/*.air -o "$OUTPUT_PATH"
echo "$OUTPUT_PATH"
