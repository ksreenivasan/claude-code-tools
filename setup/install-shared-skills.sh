#!/bin/bash
set -euo pipefail

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  echo "Usage: $0 SOURCE_ROOT DESTINATION_ROOT BACKUP_ROOT [STAMP]" >&2
  exit 2
fi

SOURCE_ROOT="$1"
DESTINATION_ROOT="$2"
BACKUP_ROOT="$3"
STAMP="${4:-$(date '+%Y%m%d-%H%M%S')}"

if [ ! -d "$SOURCE_ROOT" ]; then
  echo "ERROR: shared skill source does not exist: $SOURCE_ROOT" >&2
  exit 1
fi

mkdir -p "$DESTINATION_ROOT" "$BACKUP_ROOT"

for source in "$SOURCE_ROOT"/*; do
  [ -d "$source" ] || continue
  [ -f "$source/SKILL.md" ] || continue

  name="$(basename "$source")"
  case "$name" in
    *[!a-z0-9-]*|''|-*|*-|*--*) echo "ERROR: invalid shared skill directory name: $name" >&2; exit 1 ;;
  esac

  destination="$DESTINATION_ROOT/$name"
  backup="$BACKUP_ROOT/$name/$name.backup.$STAMP"

  if [ ! -L "$destination" ] && [ -d "$destination" ] && diff -qr "$source" "$destination" >/dev/null; then
    echo "Unchanged skill: $destination"
    continue
  fi

  if [ -L "$destination" ] || [ -e "$destination" ]; then
    mkdir -p "$(dirname "$backup")"
    if [ -e "$backup" ] || [ -L "$backup" ]; then
      echo "ERROR: refusing to overwrite skill backup: $backup" >&2
      exit 1
    fi
    if [ -L "$destination" ]; then
      cp -P "$destination" "$backup"
    elif [ -d "$destination" ]; then
      cp -R "$destination" "$backup"
    else
      cp -p "$destination" "$backup"
    fi
    rm -rf -- "$destination"
    echo "Backed up skill: $backup"
  fi

  cp -R "$source" "$destination"
  echo "Installed skill: $destination"
done
