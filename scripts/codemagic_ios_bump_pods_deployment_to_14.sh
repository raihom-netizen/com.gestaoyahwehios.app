#!/usr/bin/env bash
# Legado — ML Kit exige iOS 15.5 (delega ao script actual).
exec "$(dirname "$0")/codemagic_ios_bump_pods_deployment_to_15.sh"
