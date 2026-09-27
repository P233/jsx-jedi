#!/usr/bin/env bash
# Build pinned parsers from checked-in C sources; no grammar generator needed.
set -euo pipefail

deps_dir=${1:-.test-deps}
mkdir -p "$deps_dir"
deps_dir=$(cd "$deps_dir" && pwd)
if [[ -n $(ls -A "$deps_dir") ]]; then
  echo "Dependency directory must be empty: $deps_dir" >&2
  exit 1
fi

case $(uname -s) in
  Darwin) library_flag=-dynamiclib; library_suffix=dylib ;;
  Linux) library_flag=-shared; library_suffix=so ;;
  *) echo 'This helper supports macOS and Linux' >&2; exit 1 ;;
esac

fetch_revision() {
  local name=$1 url=$2 revision=$3 attempt
  git init -q "$deps_dir/$name"
  git -C "$deps_dir/$name" remote add origin "$url"
  for attempt in 1 2 3; do
    if git -C "$deps_dir/$name" fetch --quiet --depth 1 origin "$revision"; then
      break
    fi
    if [[ $attempt -eq 3 ]]; then return 1; fi
    sleep "$attempt"
  done
  git -C "$deps_dir/$name" checkout --quiet --detach FETCH_HEAD
  [[ $(git -C "$deps_dir/$name" rev-parse HEAD) == "$revision" ]]
  printf '%s %s\n' "$name" "$revision" >> "$deps_dir/versions.txt"
}

# Avy 0.5.0 and grammar releases using language ABI 14.
fetch_revision avy https://github.com/abo-abo/avy.git \
  f2cf43b5372a6e2a7c101496c47caaf03338de36
fetch_revision tree-sitter-typescript https://github.com/tree-sitter/tree-sitter-typescript.git \
  f975a621f4e7f532fe322e13c4f79495e0a7b2e7
fetch_revision tree-sitter-javascript https://github.com/tree-sitter/tree-sitter-javascript.git \
  3a837b6f3658ca3618f2022f8707e29739c91364
# js-ts-mode in Emacs 31 also compiles JSDoc font-lock queries.
fetch_revision tree-sitter-jsdoc https://github.com/tree-sitter/tree-sitter-jsdoc.git \
  b253abf68a73217b7a52c0ec254f4b6a7bb86665

mkdir "$deps_dir/grammars"
build_grammar() {
  local language=$1 source_dir=$2
  local sources=("$source_dir/src/parser.c")
  if [[ -f "$source_dir/src/scanner.c" ]]; then
    sources+=("$source_dir/src/scanner.c")
  fi
  "${CC:-cc}" -O2 -fPIC "$library_flag" -I "$source_dir/src" \
    "${sources[@]}" \
    -o "$deps_dir/grammars/libtree-sitter-$language.$library_suffix"
}
build_grammar javascript "$deps_dir/tree-sitter-javascript"
build_grammar typescript "$deps_dir/tree-sitter-typescript/typescript"
build_grammar tsx "$deps_dir/tree-sitter-typescript/tsx"
build_grammar jsdoc "$deps_dir/tree-sitter-jsdoc"
cat "$deps_dir/versions.txt"
printf 'Ready. Set JSX_JEDI_AVY_DIR=%s/avy and JSX_JEDI_GRAMMAR_DIR=%s/grammars\n' \
  "$deps_dir" "$deps_dir"
