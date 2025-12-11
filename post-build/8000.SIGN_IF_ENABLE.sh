#!/bin/bash

. "$KAM_HOOKS_ROOT/lib/utils.sh"

# Sign artifacts in $KAM_DIST_DIR if KAM_SIGN_ENABLED=1
if [ "$KAM_SIGN_ENABLED" != "1" ]; then
	log_info "KAM_SIGN_ENABLED != 1, skipping signing"
	exit 0
fi

require_command kam

DIST=${KAM_DIST_DIR:-$KAM_PROJECT_ROOT/dist}

if [ ! -d "$DIST" ]; then
	log_warn "Dist directory $DIST not found; nothing to sign"
	exit 0
fi

log_info "Signing artifacts in $DIST using 'kam sign' (and cosign OIDC on GitHub Actions if available)"

# If running in GitHub Actions (or GH token present) and cosign is available, attempt keyless OIDC signing.
# This allows cosign to obtain an ephemeral cert (via Fulcio) proving the build environment.
if { [ -n "${GITHUB_ACTIONS:-}" ] || [ -n "${GH_TOKEN:-}" ] || [ -n "${GITHUB_TOKEN:-}" ]; } && has_command cosign; then
    log_info "Detected GitHub Actions + cosign; performing keyless OIDC signing (cosign) for artifacts in $DIST"
    for artifact in "$DIST/$KAM_MODULE_ID-"*.zip; do
        if [ -f "$artifact" ]; then
            log_info "Signing with cosign (keyless/OIDC): ${artifact}"
            # Try to sign with cosign using keyless OIDC flow. If we are in GH Actions with proper permissions,
            # cosign will fetch a GitHub Actions OIDC token and request a certificate from Fulcio.
            if ! cosign sign --keyless "$artifact"; then
                log_warn "cosign keyless sign failed for ${artifact}"
            else
                log_info "cosign keyless sign succeeded for ${artifact}"
            fi
        fi
    done
else
    if [ -n "${GITHUB_ACTIONS:-}" ] || [ -n "${GH_TOKEN:-}" ] || [ -n "${GITHUB_TOKEN:-}" ]; then
        log_warn "GitHub Actions detected but 'cosign' not installed; skipping keyless OIDC sign"
    fi
fi

# Always perform 'kam' signing as the project's signing step for DSSE/sigstore bundles and timestamping.
# This ensures repository-specific signature bundles and timestamps are generated as before.
kam sign "$DIST/$KAM_MODULE_ID-"*.zip --out $DIST --sigstore -t
