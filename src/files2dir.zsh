#!/bin/zsh
# files2dir.zsh - move files with a common prefix, or move files into dirs
# based on their own basename (when called with an existing file).
#
# Usage:
#   files2dir [--force] [--dry-run] [--include-directories] [--year YYYY|YYYY-YYYY] ARG [ARG...]

set -o nounset
set -o errexit
set -o pipefail

VERSION="1.6.0-2025.12.14"

setopt extended_glob null_glob

print_usage() {
  cat <<'EOF'
Usage:
  files2dir [OPTIONS] ARG [ARG...]

If ARG is not an existing file:
  Treat ARG as a prefix and move filesystem entries whose names start with ARG
  into a directory named ARG.

  If a filename begins with a leading "[...]" tag, that tag and any following
  spaces are ignored for matching. Matching is case-insensitive.

If ARG begins with a leading "[...]" tag, that tag and any following spaces
are ignored for the directory name.

If ARG is an existing file with an extension:
  For each such file X.ext, create a directory "X" (if needed) and move
  X.ext into that directory.

Options:
  --force                Overwrite existing files in the target directory.
                         (Does not overwrite existing directories; those are skipped.)
  --dry-run              Show what would be done, but do not move anything.
  --include-directories  In prefix mode, include matching directories in addition to files.
  --year Y               Append year or year-range to created directory name, e.g.
                         "Foo (2004)" or "Foo (2001-2012)". Not used for matching.
  --help                 Show this help message and exit.
  --version              Show version and exit.

Examples:
  files2dir --year 2004 Black
    Creates ./Black (2004)/ and moves matching files into it.

  files2dir --include-directories Black
    Also moves matching directories into ./Black/
EOF
}

FORCE=false
DRY_RUN=false
INCLUDE_DIRECTORIES=false
YEAR_SUFFIX=""

validate_year_arg() {
  local y="$1"
  if [[ "$y" =~ '^[0-9]{4}$' ]]; then
    return 0
  fi
  if [[ "$y" =~ '^[0-9]{4}-[0-9]{4}$' ]]; then
    return 0
  fi
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)               FORCE=true; shift ;;
    --dry-run)             DRY_RUN=true; shift ;;
    --include-directories) INCLUDE_DIRECTORIES=true; shift ;;
    --year)
      shift
      if [[ $# -lt 1 ]]; then
        print -u2 "Error: --year requires YYYY or YYYY-YYYY."
        exit 1
      fi
      if ! validate_year_arg "$1"; then
        print -u2 "Error: invalid --year value: '$1' (expected YYYY or YYYY-YYYY)."
        exit 1
      fi
      YEAR_SUFFIX=" ($1)"
      shift
      ;;
    --help)     print_usage; exit 0 ;;
    --version)  print "$VERSION"; exit 0 ;;
    --)         shift; break ;;
    --*)        print -u2 "Error: unknown option: $1"; print -u2 "Use --help for usage."; exit 1 ;;
    *)          break ;;
  esac
done

if [[ $# -lt 1 ]]; then
  print -u2 "Error: missing ARG."
  print -u2 "Use --help for usage."
  exit 1
fi

# Remove a leading bracket tag "[...]" where ... may itself contain nested [].
# Also removes any spaces immediately following the closing bracket.
strip_leading_bracket_tag() {
  local s="$1"

  [[ "${s[1]}" == "[" ]] || { print -r -- "$s"; return 0; }

  local i=2
  local len=${#s}
  local depth=1
  local ch

  while (( i <= len )); do
    ch="${s[i]}"
    if [[ "$ch" == "[" ]]; then
      (( depth++ ))
    elif [[ "$ch" == "]" ]]; then
      (( depth-- ))
      if (( depth == 0 )); then
        s="${s[i+1,-1]}"
        s="${s##[[:space:]]#}"
        print -r -- "$s"
        return 0
      fi
    fi
    (( i++ ))
  done

  print -r -- "$1"
}

process_prefix() {
  local raw_prefix="$1"
  local prefix dir
  prefix="$(strip_leading_bracket_tag "$raw_prefix")"
  dir="${prefix}${YEAR_SUFFIX}"

  if [[ -z "$prefix" ]]; then
    print -u2 "Error: prefix resolved to empty after stripping leading [..] tag: $raw_prefix"
    return 1
  fi

  # Collect matching entries in the current directory.
  # Matching is case-insensitive literal prefix match, ignoring any leading "[...]" tag in entry names.
  local -a entries matches
  local f base norm_base
  local prefix_lc="${prefix:l}"

  entries=( ./*(N) )
  for f in "${entries[@]}"; do
    # In prefix mode, only files are included unless --include-directories is set.
    if [[ -f "$f" ]]; then
      :
    elif $INCLUDE_DIRECTORIES && [[ -d "$f" ]]; then
      :
    else
      continue
    fi

    base="${f##./}"
    norm_base="$(strip_leading_bracket_tag "$base")"
    if [[ "${norm_base:l}" == "$prefix_lc"* ]]; then
      matches+=( "$f" )
    fi
  done

  if (( ${#matches} == 0 )); then
    if $INCLUDE_DIRECTORIES; then
      print -u2 "Warning: no files or directories found starting with prefix (ignoring leading [..] tags): $prefix"
    else
      print -u2 "Warning: no files found starting with prefix (ignoring leading [..] tags): $prefix"
    fi
    return 0
  fi

  if [[ -e "$dir" && ! -d "$dir" ]]; then
    print -u2 "Error: '$dir' exists and is not a directory."
    return 1
  fi

  if [[ ! -d "$dir" ]]; then
    if $DRY_RUN; then
      print "mkdir \"$dir\""
    else
      mkdir "$dir"
    fi
  fi

  local src dest src_base
  for src in "${matches[@]}"; do
    src_base="${src##./}"

    # Never try to move the destination directory into itself.
    if [[ "$src_base" == "$dir" ]]; then
      print -u2 "Notice: matched destination directory '$dir' itself, skipping."
      continue
    fi

    dest="$dir/${src_base##*/}"

    # If dest exists:
    # - for files: allow overwrite only with --force
    # - for directories: always skip (mv won't safely overwrite/merge)
    if [[ -e "$dest" ]]; then
      if [[ -d "$src" ]]; then
        print -u2 "Warning: target '$dest' already exists; refusing to overwrite/merge directory '$src_base'. Skipping."
        continue
      fi
      if $FORCE == false; then
        print -u2 "Warning: '$dest' exists, use --force to overwrite. Skipping '$src_base'."
        continue
      fi
    fi

    if $DRY_RUN; then
      if [[ -d "$src" ]]; then
        print "mv \"$src\" \"$dir/\""
      else
        if $FORCE; then
          print "mv -f \"$src\" \"$dir/\""
        else
          print "mv -n \"$src\" \"$dir/\""
        fi
      fi
    else
      if [[ -d "$src" ]]; then
        mv "$src" "$dir/"
      else
        if $FORCE; then
          mv -f "$src" "$dir/"
        else
          mv -n "$src" "$dir/"
        fi
      fi
    fi
  done
}

process_file() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    print -u2 "Warning: '$file' is not a file, skipping."
    return 0
  fi

  local dirpath="${file:h}"
  local filename="${file:t}"
  local stem="${filename%.*}"

  # Year is appended to the created directory in file-mode too.
  local target_dir="$dirpath/${stem}${YEAR_SUFFIX}"
  local dest="$target_dir/$filename"

  if [[ -e "$target_dir" && ! -d "$target_dir" ]]; then
    print -u2 "Error: '$target_dir' exists but is not a directory."
    return 1
  fi

  if [[ ! -d "$target_dir" ]]; then
    if $DRY_RUN; then
      print "mkdir \"$target_dir\""
    else
      mkdir "$target_dir"
    fi
  fi

  if [[ -e "$dest" && $FORCE == false ]]; then
    print -u2 "Warning: '$dest' exists, skipping (use --force to overwrite)."
    return 0
  fi

  if $DRY_RUN; then
    if $FORCE; then
      print "mv -f \"$file\" \"$target_dir/\""
    else
      print "mv -n \"$file\" \"$target_dir/\""
    fi
  else
    if $FORCE; then
      mv -f "$file" "$target_dir/"
    else
      mv -n "$file" "$target_dir/"
    fi
  fi
}

for arg in "$@"; do
  if [[ -f "$arg" ]]; then
    process_file "$arg"
  else
    process_prefix "$arg"
  fi
done
