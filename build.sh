#!/bin/bash
TIMESTAMP=$(date -u +"%Y%m%d%H%M%S")
echo "{\"version\": \"$TIMESTAMP\"}" > web/version.json
echo "Building with version $TIMESTAMP..."
flutter build web --release
echo "Done. Deploy the build/web folder."
