#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 <vX.Y.Z|--unreleased> [RELEASE.md]" >&2
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 2
fi

selector="$1"
release_file="${2:-RELEASE.md}"

if [[ ! -f "${release_file}" ]]; then
  echo "release notes file not found: ${release_file}" >&2
  exit 1
fi

if [[ "${selector}" == "--unreleased" ]]; then
  awk '
    BEGIN {
      capture = 0
      started = 0
      has_body = 0
    }

    tolower($0) == "## unreleased" {
      capture = 1
      next
    }

    capture && /^## / {
      exit
    }

    capture {
      if (!started && $0 ~ /^[[:space:]]*$/) {
        next
      }
      started = 1
      body = body $0 "\n"
      if ($0 ~ /[^[:space:]]/ && $0 !~ /^### /) {
        has_body = 1
      }
    }

    END {
      if (has_body) {
        printf "%s", body
      }
    }
  ' "${release_file}"
  exit 0
fi

version="${selector#v}"

awk -v version="${version}" '
  BEGIN {
    plain_heading = "## " version
    tagged_heading = "## v" version
  }

  $0 == plain_heading || $0 == tagged_heading {
    capture = 1
    found = 1
    print
    next
  }

  capture && /^## / {
    exit
  }

  capture {
    print
  }

  END {
    if (!found) {
      printf "release notes not found for v%s\n", version > "/dev/stderr"
      exit 1
    }
  }
' "${release_file}"
