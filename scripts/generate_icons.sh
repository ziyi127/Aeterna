#!/bin/bash
# Generates SF Symbol style PNG icons for Aeterna from inline SVG.
# Outputs to resources/icons/{name}_{size}.png with sizes 16, 20, 24.

set -e
OUT="/home/archlinux/桌面/aeterna/resources/icons"
SIZES=(16 20 24)

mkdir -p "$OUT"

# Helper: convert a single SVG to PNGs at all sizes
gen() {
    local name="$1"
    local svg="$2"
    local tmp="$OUT/${name}.svg"
    printf '%s' "$svg" > "$tmp"
    for sz in "${SIZES[@]}"; do
        rsvg-convert -w "$sz" -h "$sz" "$tmp" -o "$OUT/${name}_${sz}.png"
    done
    rm -f "$tmp"
}

# ───────────────────────────────────────────────────────────────────
# Common style: 24x24 viewBox, solid black, stroke width 1.6,
# rounded line caps/joins. Each icon is filled-or-stroked monochrome
# and will be tinted by Icon.qml at runtime.
# ───────────────────────────────────────────────────────────────────

# house (home)
gen "house" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M12 3.2 3.6 10v10.4h6.4v-6h4v6h6.4V10L12 3.2z"/></svg>'

# magnifyingglass (search)
gen "magnifyingglass" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="#000" stroke-width="1.8" stroke-linecap="round" d="M10.5 3a7.5 7.5 0 1 1 0 15 7.5 7.5 0 0 1 0-15zm5.3 12.1 4.7 4.7"/></svg>'

# film (player / window)
gen "film" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M4 4h16v16H4V4zm2 2v2h2V6H6zm0 4v2h2v-2H6zm0 4v2h2v-2H6zm10-8v2h2V6h-2zm0 4v2h2v-2h-2zm0 4v2h2v-2h-2z"/></svg>'

# gear (settings)
gen "gear" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M12 8.4a3.6 3.6 0 1 0 0 7.2 3.6 3.6 0 0 0 0-7.2zm9 4.8-1.95-.6a7.4 7.4 0 0 0-.7-1.7l1-1.7-2.2-2.2-1.7 1a7.4 7.4 0 0 0-1.7-.7L13.1 4h-2.2l-.6 1.95a7.4 7.4 0 0 0-1.7.7l-1.7-1-2.2 2.2 1 1.7a7.4 7.4 0 0 0-.7 1.7L3 12.2v2.2l1.95.6c.18.6.4 1.18.7 1.7l-1 1.7 2.2 2.2 1.7-1c.52.3 1.1.52 1.7.7l.6 1.95h2.2l.6-1.95a7.4 7.4 0 0 0 1.7-.7l1.7 1 2.2-2.2-1-1.7c.3-.52.52-1.1.7-1.7l1.95-.6v-2.2zM12 16.2a4.2 4.2 0 1 1 0-8.4 4.2 4.2 0 0 1 0 8.4z"/></svg>'

# doc.text (editor)
gen "doc" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M5 2h10l4 4v16H5V2zm9 1.5V7h3.5L14 3.5zM7 10h10v1.4H7V10zm0 3h10v1.4H7V13zm0 3h7v1.4H7V16z"/></svg>'

# play.fill
gen "play" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M7 4.8v14.4a.8.8 0 0 0 1.22.68L19.6 12.7a.8.8 0 0 0 0-1.36L8.22 4.12A.8.8 0 0 0 7 4.8z"/></svg>'

# link (URL)
gen "link" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="#000" stroke-width="1.8" stroke-linecap="round" d="M9.2 14.8 14.8 9.2M10 6.4l1.4-1.4a4.2 4.2 0 1 1 5.94 5.94L15.94 12.4M14 17.6l-1.4 1.4a4.2 4.2 0 1 1-5.94-5.94L8.06 11.6"/></svg>'

# puzzle (plugin)
gen "puzzle" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M9 2h6v3.5a2 2 0 0 0 4 0V4h3v6h-1.5a2 2 0 0 0 0 4H22v6h-6v-1.5a2 2 0 0 0-4 0V20H6v-6h1.5a2 2 0 0 0 0-4H6V4h3V2z"/></svg>'

# questionmark.circle
gen "questionmark" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm-.6 14.6a1.2 1.2 0 1 1 0-2.4 1.2 1.2 0 0 1 0 2.4zm.6-4.4c-.6 0-1 .4-1 1H9.6c0-1.7 1.1-2.6 2.5-2.6 1.5 0 2.5.9 2.5 2.3 0 1-.5 1.6-1.4 2.2-.7.5-.8.7-.8 1.1v.4h-1.4v-.4c0-1 .4-1.5 1.2-2.1.7-.5 1-.8 1-1.3 0-.4-.3-.6-.9-.6z"/></svg>'

# info.circle
gen "info" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm-.8 6h1.6v1.6h-1.6V8zm0 3h1.6V17h-1.6v-6z"/></svg>'

# list.bullet (log)
gen "list" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M3 5h4v2H3V5zm6 0h12v2H9V5zM3 11h4v2H3v-2zm6 0h12v2H9v-2zM3 17h4v2H3v-2zm6 0h12v2H9v-2z"/></svg>'

# clock
gen "clock" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm.8 4.6v5.2l4.4 2.6-1 1.6-5-3V6.6h1.6z"/></svg>'

# network
gen "network" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm6.9 6h-2.95a15.6 15.6 0 0 0-1.38-3.56A8 8 0 0 1 18.92 8zM12 4.04c.83 1.2 1.48 2.53 1.91 4H10.1A14 14 0 0 1 12 4.04zM4.26 14a8 8 0 0 1 0-4h3.38a17 17 0 0 0 0 4H4.26zm.82 2h2.95c.32 1.25.78 2.45 1.38 3.56A8 8 0 0 1 5.08 16zm2.95-8H5.08a8 8 0 0 1 4.33-3.56A15.6 15.6 0 0 0 8.03 8zM12 19.96c-.83-1.2-1.48-2.53-1.91-4h3.82A14 14 0 0 1 12 19.96zM14.34 14H9.66a14 14 0 0 1 0-4h4.68a14 14 0 0 1 0 4zm.25 5.56c.6-1.11 1.06-2.31 1.38-3.56h2.95a8 8 0 0 1-4.33 3.56zM16.36 14a17 17 0 0 0 0-4h3.38a8 8 0 0 1 0 4h-3.38z"/></svg>'

# antenna (cast)
gen "antenna" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M12 16a3 3 0 1 0 0 6 3 3 0 0 0 0-6zM5 11.4a10 10 0 0 1 14 0l-1.4 1.4a8 8 0 0 0-11.2 0L5 11.4zM2 8a15 15 0 0 1 20 0l-1.4 1.4a13 13 0 0 0-17.2 0L2 8z"/></svg>'

# paintbrush (appearance)
gen "paintbrush" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M14 3.4 20.6 10l-9.2 9.2-2.8-.6L2 17.6 6.4 13.2 5.8 10.4 14 3.4zm-1.4 1.4L7.4 12l3.6 3.6 5.2-5.2-3.6-3.6z"/></svg>'

# star
gen "star" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="m12 2 2.9 6.5 7.1.7-5.3 4.7 1.5 7-6.2-3.7L5.8 21l1.5-7L2 9.2l7.1-.7L12 2z"/></svg>'

# download (arrow.down.circle)
gen "arrow.down.circle" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm.8 13.6V8h-1.6v7.6H8.4L12 19.2l3.6-3.6h-2.8z"/></svg>'

# checkmark.circle (success)
gen "checkmark.circle" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm-1.2 14.4-4-4 1.4-1.4 2.6 2.6 5.6-5.6 1.4 1.4-7 7z"/></svg>'

# exclamationmark.triangle (warning)
gen "exclamationmark.triangle" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M12 2 1 21h22L12 2zm.8 6h-1.6v6.4h1.6V8zm0 8.4h-1.6V18h1.6v-1.6z"/></svg>'

# circle.fill (status)
gen "circle.fill" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><circle cx="12" cy="12" r="10" fill="#000"/></svg>'

# xmark.circle (close/danger)
gen "xmark" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="#000" stroke-width="1.8" stroke-linecap="round" d="M6 6 18 18M18 6 6 18"/></svg>'

# plus
gen "plus" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="#000" stroke-width="1.8" stroke-linecap="round" d="M12 5v14M5 12h14"/></svg>'

# minus
gen "minus" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="#000" stroke-width="1.8" stroke-linecap="round" d="M5 12h14"/></svg>'

# arrow.left
gen "arrow.left" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="#000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" d="M19 12H5m6-7-7 7 7 7"/></svg>'

# arrow.right
gen "arrow.right" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="#000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" d="M5 12h14m-6-7 7 7-7 7"/></svg>'

# power (quit)
gen "power" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="#000" stroke-width="1.8" stroke-linecap="round" d="M12 4v8M6 8a8 8 0 1 0 12 0"/></svg>'

# window (rect)
gen "window" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M3 4h18v16H3V4zm2 2v2h14V6H5z"/></svg>'

# display (rect for hub/cast screen)
gen "display" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M3 4h18v13H3V4zm14 14h2v2H5v-2h2v-1h10v1z"/></svg>'

# globe (http/web)
gen "globe" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm6.9 6h-2.95a15.6 15.6 0 0 0-1.38-3.56A8 8 0 0 1 18.92 8zM12 4.04c.83 1.2 1.48 2.53 1.91 4H10.1A14 14 0 0 1 12 4.04zM4.26 14a8 8 0 0 1 0-4h3.38a17 17 0 0 0 0 4H4.26zm.82 2h2.95c.32 1.25.78 2.45 1.38 3.56A8 8 0 0 1 5.08 16zm2.95-8H5.08a8 8 0 0 1 4.33-3.56A15.6 15.6 0 0 0 8.03 8zM12 19.96c-.83-1.2-1.48-2.53-1.91-4h3.82A14 14 0 0 1 12 19.96zM14.34 14H9.66a14 14 0 0 1 0-4h4.68a14 14 0 0 1 0 4zm.25 5.56c.6-1.11 1.06-2.31 1.38-3.56h2.95a8 8 0 0 1-4.33 3.56zM16.36 14a17 17 0 0 0 0-4h3.38a8 8 0 0 1 0 4h-3.38z"/></svg>'

# speaker.wave.2
gen "speaker" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M4 9v6h4l5 4V5L8 9H4zm12.5 3a4.5 4.5 0 0 0-2.5-4v8a4.5 4.5 0 0 0 2.5-4zM14 3.23v2.06a7 7 0 0 1 0 13.42v2.06a9 9 0 0 0 0-17.54zM16 1v2a10 10 0 0 1 0 18v2a12 12 0 0 0 0-22z"/></svg>'

# chart.bar (data)
gen "chart" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M3 21h18v-1.5H3V21zM5 17h3V8H5v9zm5 0h3V3h-3v14zm5 0h3v-6h-3v6z"/></svg>'

# tray (tray)
gen "tray" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M3 4h18l-2 9h-4.4a2.6 2.6 0 0 1-5.2 0H5L3 4z"/></svg>'

# archivebox (backup)
gen "archivebox" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M3 3h18v4H3V3zm0 6h18v12H3V9zm6 3h6v2H9v-2z"/></svg>'

# bell (notification)
gen "bell" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M12 2a6 6 0 0 0-6 6v4l-2 3v1h16v-1l-2-3V8a6 6 0 0 0-6-6zm-2 17a2 2 0 0 0 4 0h-4z"/></svg>'

# timer (countdown)
gen "timer" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M9 2h6v2H9V2zm10 5-1.4-1.4-1.4 1.4A8 8 0 1 1 7.8 7L6.4 5.6 5 7a10 10 0 1 0 14 0zM11 8h2v5h-2V8zm0 6h2v2h-2v-2z"/></svg>'

# keyboard
gen "keyboard" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M3 6h18a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1zm2 3v2h2V9H5zm4 0v2h2V9H9zm4 0v2h2V9h-2zm4 0v2h2V9h-2zM5 13v2h2v-2H5zm4 0v2h2v-2H9zm4 0v2h2v-2h-2zm4 0v2h2v-2h-2zm-10 4v2h10v-2H7z"/></svg>'

# undo (arrow.uturn.backward)
gen "arrow.uturn.backward" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="#000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" d="M9 14 4 9l5-5M4 9h11a5 5 0 0 1 0 10h-3"/></svg>'

# redo (arrow.uturn.forward)
gen "arrow.uturn.forward" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="#000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" d="m15 14 5-5-5-5M20 9H9a5 5 0 0 0 0 10h3"/></svg>'

# export (square.and.arrow.up)
gen "square.and.arrow.up" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M11 3h2v9l3-3 1.4 1.4L12 16l-5.4-5.6L8 9l3 3V3zM4 18h16v3H4v-3z"/></svg>'

# printer
gen "printer" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M6 3h12v4H6V3zm-3 5h18a1 1 0 0 1 1 1v7h-4v4H6v-4H2V9a1 1 0 0 1 1-1zm3 4v6h12v-6H6z"/></svg>'

# trash (uninstall)
gen "trash" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M9 3h6l1 2h4v2H4V5h4l1-2zm-3 6h12l-1 12H7L6 9zm3 2v8h2v-8H9zm4 0v8h2v-8h-2z"/></svg>'

# square.grid.2x2 (compact)
gen "square.grid.2x2" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M3 3h8v8H3V3zm0 10h8v8H3v-8zm10-10h8v8h-8V3zm0 10h8v8h-8v-8z"/></svg>'

# viewfinder (zoom in)
gen "viewfinder" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M3 3h6v2H5v4H3V3zm12 0h6v6h-2V5h-4V3zM3 15h2v4h4v2H3v-6zm16 0h2v6h-6v-2h4v-4z"/></svg>'

# list.dash (log)
gen "list.dash" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#000" d="M3 5h4v2H3V5zm0 6h4v2H3v-2zm0 6h4v2H3v-2zm6-12h12v2H9V5zm0 6h12v2H9v-2zm0 6h12v2H9v-2z"/></svg>'

# scale (resize)
gen "arrow.up.left.and.arrow.down.right" '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" stroke="#000" stroke-width="1.8" stroke-linecap="round" d="M4 20 20 4M4 8V4h4M16 20h4v-4"/></svg>'

echo "Generated icons in $OUT:"
ls -la "$OUT" | head -20
