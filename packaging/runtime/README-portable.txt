Aeterna portable package
========================

This package bundles the Qt runtime, plugins, and QML modules required by Aeterna.

Linux: this is a Qt bundle, not an AppImage. It still uses compatible host graphics,
font, DBus, X11/Wayland, and libc libraries.

Windows: Qt DLLs and plugins are included. If Windows reports a missing Microsoft
Visual C++ runtime, install the supported Microsoft Visual C++ Redistributable.

macOS: the application bundle is unsigned and not notarized. Gatekeeper may require
right-clicking the application and selecting Open on its first launch.
