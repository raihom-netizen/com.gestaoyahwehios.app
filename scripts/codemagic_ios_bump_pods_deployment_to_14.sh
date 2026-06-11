#!/usr/bin/env bash
# Legado — Firebase 12+ exige iOS 15.0 (delega ao script actual).
exec "$(dirname "$0")/codemagic_ios_bump_pods_deployment_to_15.sh"
