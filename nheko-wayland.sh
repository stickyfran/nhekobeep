#!/usr/bin/env bash
# ============================================================================
#  nheko-wayland.sh  —  Optimised Nheko launch wrapper (native Wayland)
#
#  Forces the Nheko Matrix client to run strictly under a native Wayland
#  session with recommended hardware-acceleration environment variables for
#  Qt Multimedia / GStreamer (VAAPI).
#
#  Usage
#  -----
#      ./nheko-wayland.sh                            # binary in $PWD
#      ./nheko-wayland.sh /path/to/custom/nheko      # explicit binary path
#
#  Environment
#  -----------
#  NHEKO_BINARY       Path to the nheko executable (overrides auto-detect).
#  NHEKO_EXTRA_OPTS   Extra CLI flags passed to the nheko binary.
# ============================================================================
set -euo pipefail

# ---- discover binary --------------------------------------------------------
if [[ -n "${NHEKO_BINARY:-}" ]]; then
    BINARY="${NHEKO_BINARY}"
elif [[ $# -ge 1 ]]; then
    BINARY="$1"
else
    # Fall back to a reasonable default: look beside the script, then in PATH.
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -x "${SCRIPT_DIR}/build/nheko" ]]; then
        BINARY="${SCRIPT_DIR}/build/nheko"
    elif [[ -x "${SCRIPT_DIR}/nheko" ]]; then
        BINARY="${SCRIPT_DIR}/nheko"
    else
        BINARY="$(command -v nheko 2>/dev/null)" || {
            echo "ERROR: nheko binary not found."
            echo "Set NHEKO_BINARY or pass the path as the first argument."
            exit 1
        }
    fi
fi

echo "nheko-wayland: launching ${BINARY}"

# ---- Qt platform: force native Wayland (no XWayland fallback) ---------------
export QT_QPA_PLATFORM=wayland

# Tell Qt's QPA to prefer the Wayland backend even if XDG_SESSION_TYPE is
# ambiguous; disable any automatic fallback to xcb.
export QT_QPA_PLATFORM_DISABLE_WAYLAND=0
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"

# ---- Qt Multimedia / GStreamer: VAAPI hardware acceleration -----------------
#
# These variables encourage GStreamer to use VAAPI elements for video decode
# and encoding (animated stickers, voice/video calls), offloading CPU.
#
# Use the GStreamer backend explicitly (default on Linux, but be explicit).
export QT_MEDIA_BACKEND=gstreamer

# Rank VAAPI elements above software decoders.
export GST_PLUGIN_FEATURE_RANK=vaapi:Full

# Allow VAAPI to open the DRM render node directly (required on modern Mesa).
export GST_VAAPI_ALLOW_DRM=1

# Prefer the OpenGL GLX/EGL interop for VAAPI rendering.
export GST_GL_API=gles2+gles3

# ---- Mesa / GPU hints -------------------------------------------------------
export MESA_GL_VERSION_OVERRIDE=4.6
export __GLX_VENDOR_LIBRARY_NAME=mesa

# ---- exec ---------------------------------------------------------------
exec "${BINARY}" ${NHEKO_EXTRA_OPTS:-}
