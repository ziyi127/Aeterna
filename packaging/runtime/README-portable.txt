Aeterna portable package
========================

This package bundles only the Qt libraries, QML modules, and platform plugins required by Aeterna. It does not contain the Qt SDK, headers, build tools, or unrelated Qt modules. The package also includes the GNU GPLv3 license and third-party attribution notices.

Linux: this is a Qt bundle, not an AppImage. It still uses compatible host graphics,
font, DBus, X11/Wayland, libc, and GPU driver libraries.

Windows: only the runtime dependencies discovered by windeployqt are included. The
Microsoft Visual C++ runtime is expected to be installed on the system.

macOS: the application bundle contains the deployment-time Qt framework and plugins,
but is unsigned and not notarized. Gatekeeper may require right-clicking the
application and selecting Open on its first launch.
