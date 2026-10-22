#!/bin/sh
set -eu
rp_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# Parse the block before an update can replace this launcher file.
{
  if [ -f "$rp_dir/.raceprep-update/ready.json" ]; then
    "$rp_dir/.raceprep-update/payload/bjrme-generator/bjrme-generator" --beammp "$rp_dir" --update-apply
  fi
  exec "$rp_dir/bjrme-generator/bjrme-generator" --beammp "$rp_dir" --server "${1:-BeamMP-Server}"
}
