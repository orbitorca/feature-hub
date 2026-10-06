#!/bin/sh
# Checks the app's image against the platform's size limit, measured the way the platform measures
# it: every layer of the built image after decompression (what it takes on disk). `docker images`
# shows a different number depending on the Docker version, so it is not used here.
#
# Run in the project root, next to the Dockerfile:
#   curl -fsSL https://raw.githubusercontent.com/orbitorca/feature-hub/main/deploy/check-image-size.sh | sh
#
# Needs Docker with buildx. Prints OK or TOO LARGE with both numbers in bytes; exits 1 when too large.
set -eu

# Keep in step with the platform's limit (contracts IMAGE_SIZE_LIMIT_BYTES).
LIMIT_BYTES=5000000000
BUILDER=orbitorca-size-check

gb() { awk -v b="$1" -v up="$2" 'BEGIN {
  h = b / 10000000; r = (up == "up") ? (h == int(h) ? h : int(h) + 1) : int(h)
  printf "%.2f GB", r / 100 }'; }

command -v docker >/dev/null 2>&1 || { echo "Docker is required." >&2; exit 2; }
[ -f Dockerfile ] || { echo "No Dockerfile here. Run this in the project root." >&2; exit 2; }

# The default docker driver cannot export an OCI layout on every Docker version; a small builder
# of our own can, the same way the platform builds.
docker buildx inspect "$BUILDER" >/dev/null 2>&1 ||
  docker buildx create --name "$BUILDER" --driver docker-container >/dev/null

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

# linux/amd64 like the platform: the same image for another architecture can differ in size.
docker buildx build --builder "$BUILDER" --platform linux/amd64 \
  --output "type=oci,dest=$OUT/image,tar=false,compression=gzip" .

total=0
for blob in "$OUT"/image/blobs/sha256/*; do
  # Layers are the gzip blobs; manifests and configs are small JSON and not part of the size.
  magic="$(head -c 2 "$blob" | od -An -tx1 | tr -d ' \n')"
  [ "$magic" = "1f8b" ] || continue
  total=$((total + $(gzip -dc "$blob" | wc -c | tr -d ' ')))
done

if [ "$total" -le "$LIMIT_BYTES" ]; then
  echo "OK: the image is $(gb "$total" down) ($total bytes) unpacked; the limit is $(gb "$LIMIT_BYTES" down) ($LIMIT_BYTES bytes)."
else
  echo "TOO LARGE: the image is $(gb "$total" up) ($total bytes) unpacked; the limit is $(gb "$LIMIT_BYTES" down) ($LIMIT_BYTES bytes)."
  exit 1
fi
