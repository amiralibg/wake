# Linux build and test environment for Wake's desktop app: Rust, WebKitGTK
# (webkit2gtk-4.1, the API wry uses), Node for the UI, and a virtual X display
# with tools to screenshot and drive it.
#
#   docker build -t wake-linux-dev -f desktop/docker/linux-dev.Dockerfile desktop/docker
#   desktop/docker/run.sh <command>
FROM ubuntu:25.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential curl ca-certificates pkg-config git file \
      libwebkit2gtk-4.1-dev libgtk-3-dev libsoup-3.0-dev libjavascriptcoregtk-4.1-dev \
      libayatana-appindicator3-dev librsvg2-dev libxdo-dev libssl-dev \
      xvfb xauth x11-utils xdotool imagemagick dbus-x11 at-spi2-core \
      fonts-dejavu fonts-noto-core fonts-noto-color-emoji \
      mesa-utils libgl1-mesa-dri gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-libav \
      nodejs npm sqlite3 \
    && rm -rf /var/lib/apt/lists/*

ENV RUSTUP_HOME=/usr/local/rustup CARGO_HOME=/usr/local/cargo PATH=/usr/local/cargo/bin:$PATH
RUN curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable \
    && chmod -R a+w /usr/local/rustup /usr/local/cargo

WORKDIR /wake

# Windows cross-compile check (x86_64-pc-windows-gnu): proves the WebView2 code
# builds. It can't run here; the real Windows build comes from CI.
RUN apt-get update && apt-get install -y --no-install-recommends gcc-mingw-w64-x86-64 g++-mingw-w64-x86-64 \
    && rm -rf /var/lib/apt/lists/* \
    && rustup target add x86_64-pc-windows-gnu
