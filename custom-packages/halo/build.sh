TERMUX_PKG_HOMEPAGE=https://example.invalid
TERMUX_PKG_DESCRIPTION="Contoh paket sendiri toolAPKAI"
TERMUX_PKG_LICENSE="Apache-2.0"
TERMUX_PKG_MAINTAINER="@isbah"
TERMUX_PKG_VERSION=1.0
TERMUX_PKG_SKIP_SRC_EXTRACT=true

termux_step_make_install() {
	cat > "$TERMUX_PREFIX/bin/halo" <<'EOF'
#!/bin/sh
echo "halo dari paket sendiri"
EOF
	chmod 0755 "$TERMUX_PREFIX/bin/halo"
}
