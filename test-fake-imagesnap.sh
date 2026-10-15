#!/bin/bash
if [[ "$1" == "-l" ]]; then
  printf '=> Test Camera\n'
  exit 0
fi
count=0
for ((i=1; i<=$#; i++)); do
  if [[ "${!i}" == "-n" ]]; then
    j=$((i+1))
    count="${!j}"
  fi
done
base="${!#}"
for ((i=1; i<=count; i++)); do
  if [[ "${CAMERA_FAKE_SKIP_FRAME:-}" == "$i" ]]; then
    continue
  fi
  file="${base%.jpg}-$(printf '%05d' "$i").jpg"
  printf 'fake image %d\n' "$i" > "$file"
  printf '%s\n' "$file"
  /bin/sleep 0.5
done
