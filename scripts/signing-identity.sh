#!/bin/bash
# Prints the Apple codesigning identity builds use: $GRID_SIGN_IDENTITY if set, else the first
# Developer ID Application, else the first Apple Development identity. With $GRID_TEAM_ID set,
# only certificates issued to that team count. Prints nothing if none match.
if [[ -n "${GRID_SIGN_IDENTITY:-}" ]]; then echo "$GRID_SIGN_IDENTITY"; exit 0; fi
identities="$(security find-identity -v -p codesigning 2>/dev/null)"
for prefix in "Developer ID Application:" "Apple Development:"; do
  # Each line: `  1) <SHA-1> "<name>"`
  while read -r hash name; do
    [[ -z "$hash" ]] && continue
    if [[ -n "${GRID_TEAM_ID:-}" ]]; then
      team="$(security find-certificate -a -Z -p -c "$name" 2>/dev/null \
        | awk -v h="$hash" '/^SHA-1 hash:/{keep=($3==h)} keep' \
        | sed -n '/BEGIN CERT/,/END CERT/p' \
        | /usr/bin/openssl x509 -noout -subject 2>/dev/null | grep -o 'OU *= *[A-Z0-9]*' | grep -o '[A-Z0-9]*$')"
      [[ "$team" == "$GRID_TEAM_ID" ]] || continue
    fi
    echo "$hash"
    exit 0
  done < <(grep -o "[0-9A-F]\{40\} \"$prefix[^\"]*\"" <<<"$identities" | sed 's/ "/ /; s/"$//')
done
