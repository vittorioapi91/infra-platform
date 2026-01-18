#!/bin/bash
#
# Docker Build Cache Cleanup Script
# Removes old build cache entries to free up disk space
#
# This script prunes build cache entries older than specified days
# and also removes all dangling/unused build cache.
#
# Usage:
#   ./cleanup-build-cache.sh [--dry-run] [--older-than-days=N]
#
# Options:
#   --dry-run              Show what would be deleted without deleting
#   --older-than-days=N    Remove cache older than N days (default: 7)
#
# Safe to run regularly - only removes old/unused cache

set -euo pipefail

# Default options
DRY_RUN=false
OLDER_THAN_DAYS=7

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --older-than-days=*)
            OLDER_THAN_DAYS="${1#*=}"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--dry-run] [--older-than-days=N]"
            exit 1
            ;;
    esac
done

echo "Docker Build Cache Cleanup"
echo "=========================="
echo "Dry run: ${DRY_RUN}"
echo "Remove cache older than: ${OLDER_THAN_DAYS} days"
echo ""

# Check build cache size before cleanup
BEFORE_SIZE=$(docker builder du 2>/dev/null | tail -1 | awk '{print $NF}' || echo "Unknown")
echo "Build cache size before cleanup: ${BEFORE_SIZE}"
echo ""

if [ "${DRY_RUN}" = "true" ]; then
    echo "[DRY-RUN] Would prune build cache older than ${OLDER_THAN_DAYS} days..."
    echo "[DRY-RUN] Would remove all dangling build cache..."
    echo ""
    echo "To actually clean up, run without --dry-run:"
    echo "  $0 --older-than-days=${OLDER_THAN_DAYS}"
else
    # Prune build cache older than specified days
    # Convert days to hours (Docker's until filter uses hours)
    OLDER_THAN_HOURS=$((OLDER_THAN_DAYS * 24))
    
    echo "Pruning dangling build cache older than ${OLDER_THAN_DAYS} days (${OLDER_THAN_HOURS}h)..."
    docker buildx prune -f --filter "until=${OLDER_THAN_HOURS}h" 2>&1 || {
        echo "Note: 'until' filter not available in this Docker version, pruning all dangling cache..."
        docker buildx prune -f 2>&1
    }
    
    # Also run general builder prune for old cache
    docker builder prune -f --filter "until=${OLDER_THAN_HOURS}h" 2>&1 || {
        echo "Note: 'until' filter not available, pruning all dangling build cache..."
        docker builder prune -f 2>&1
    }
fi

# Check build cache size after cleanup
if [ "${DRY_RUN}" != "true" ]; then
    AFTER_SIZE=$(docker builder du 2>/dev/null | tail -1 | awk '{print $NF}' || echo "Unknown")
    echo ""
    echo "Build cache size after cleanup: ${AFTER_SIZE}"
    echo ""
    echo "Cleanup completed!"
fi
