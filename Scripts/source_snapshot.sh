#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"

cd "$PROJECT_DIR"
{
  for source_root in \
    Package.swift \
    README.md \
    THIRD_PARTY_NOTICES.md \
    Sources \
    Tests/KernelProcessFixture \
    Tests/LoopForgeTests \
    Scripts \
    Resources; do
    if [[ -e "$source_root" ]]; then
      /usr/bin/find "$source_root" -type f ! -name .DS_Store -print
    fi
  done
} | LC_ALL=C /usr/bin/sort | while IFS= read -r source_file; do
  file_digest="$(/usr/bin/shasum -a 256 "$source_file" | /usr/bin/awk '{print $1}')"
  print -r -- "$file_digest  $source_file"
done | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
