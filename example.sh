#!/bin/sh
# Make a parq from NHS England's GP registrations with DuckDB, oras, jq and curl.
# Made with DuckDB 1.4.1: another version can write different bytes from the same rows.
# Set REPO_URL and REVISION to name the repository and commit holding this script.
set -eu
REG=${REG:?set REG to a registry namespace you can push to, like ghcr.io/me}
ZIP=gp-reg-pat-prac-quin-age.zip
URL=https://files.digital.nhs.uk/86/375B51/$ZIP
PAGE=https://digital.nhs.uk/data-and-information/publications/statistical/patients-registered-at-a-gp-practice/september-2026
LICENSES='[{"name":"OGL-UK-3.0","path":"https://spdx.org/licenses/OGL-UK-3.0.html"}]'

# 1. the source: the publisher's file, unchanged, described with OCI's standard annotations
curl -sfLO "$URL"
printf '{}' > empty.json   # the empty config
jq -n --arg page "$PAGE" '{"$manifest": {
  "org.opencontainers.image.title": "Patients Registered at a GP Practice, September 2026",
  "org.opencontainers.image.version": "2026-09-10",
  "org.opencontainers.image.created": "2026-09-10T00:00:00Z",
  "org.opencontainers.image.vendor": "NHS England",
  "org.opencontainers.image.url": $page,
  "org.opencontainers.image.licenses": "OGL-UK-3.0"}}' > source.annotations.json
oras push "$REG/gp-regions-source:2026-09-10" --artifact-type application/vnd.fyi.parq.source.v1 \
  --config empty.json:application/vnd.oci.empty.v1+json --annotation-file source.annotations.json "$ZIP:application/zip"
SOURCE=$(oras resolve "$REG/gp-regions-source:2026-09-10")
FILE=$(oras manifest fetch "$REG/gp-regions-source:2026-09-10" | jq -c '.layers[0] | {hash: .digest, bytes: .size}')

# 2. a table, with its licence and the file it was read from in its metadata (jq -cS is JCS for values like these)
KEY=$(jq -cnS --argjson licenses "$LICENSES" --argjson file "$FILE" '{licenses: $licenses, sources: [$file]}')
unzip -oq "$ZIP" gp-reg-pat-prac-quin-age.csv
duckdb -c "COPY (
    SELECT org_code AS region_code, ONS_CODE AS ons_code, number_of_patients AS patients
    FROM read_csv('gp-reg-pat-prac-quin-age.csv')
    WHERE org_type = 'Comm Region' AND sex = 'ALL' AND age_group_5 = 'ALL'
    ORDER BY region_code)
  TO 'regions.parquet' (FORMAT parquet, COMPRESSION zstd, KV_METADATA {datapackage: '$KEY'})"

# 3. the dataset: the tables as layers, naming the source image they were made from as their base,
#    and the commit holding this script when there is one
jq -n --arg base "$REG/gp-regions-source:2026-09-10" --arg digest "$SOURCE" \
  --arg repo "${REPO_URL:-}" --arg revision "${REVISION:-}" '{"$manifest": ({
  "org.opencontainers.image.created": "2026-09-10T00:00:00Z",
  "org.opencontainers.image.licenses": "OGL-UK-3.0",
  "org.opencontainers.image.base.name": $base,
  "org.opencontainers.image.base.digest": $digest}
  + if $repo == "" then {} else {
  "org.opencontainers.image.source": $repo,
  "org.opencontainers.image.revision": $revision} end)}' > dataset.annotations.json
oras push "$REG/gp-regions:2026-09-10" --artifact-type application/vnd.fyi.parq.dataset.v1 \
  --config empty.json:application/vnd.oci.empty.v1+json --annotation-file dataset.annotations.json \
  regions.parquet:application/vnd.apache.parquet
