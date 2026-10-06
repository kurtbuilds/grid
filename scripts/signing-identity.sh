#!/bin/bash
# Prints the Apple codesigning identity builds use: $GRID_SIGN_IDENTITY if set, else the first
# Developer ID Application, else the first Apple Development identity. Prints nothing if none.
if [[ -n "${GRID_SIGN_IDENTITY:-}" ]]; then echo "$GRID_SIGN_IDENTITY"; exit 0; fi
identities="$(security find-identity -v -p codesigning 2>/dev/null)"
for prefix in "Developer ID Application:" "Apple Development:"; do
  name="$(grep -o "\"$prefix[^\"]*\"" <<<"$identities" | head -1 | tr -d '"')"
  if [[ -n "$name" ]]; then echo "$name"; exit 0; fi
done
