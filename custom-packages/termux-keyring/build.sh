TERMUX_PKG_HOMEPAGE=https://github.com/
TERMUX_PKG_DESCRIPTION="Kunci GPG repo apt toolAPKAI (pengganti termux-keyring resmi)"
TERMUX_PKG_LICENSE="Apache-2.0"
TERMUX_PKG_MAINTAINER="@isbah"
TERMUX_PKG_VERSION=2026.11.02
TERMUX_PKG_SKIP_SRC_EXTRACT=true
TERMUX_PKG_PLATFORM_INDEPENDENT=true
TERMUX_PKG_ESSENTIAL=true

termux_step_make_install() {
	# toolapkai.gpg dimasukkan oleh scripts/patch-tp.sh dari secret GPG_PRIVATE_KEY.
	[ -s "$TERMUX_PKG_BUILDER_DIR/toolapkai.gpg" ] || termux_error_exit "toolapkai.gpg tidak ada di folder paket"
	mkdir -p "$TERMUX_PREFIX/etc/apt/trusted.gpg.d"
	install -m 0644 "$TERMUX_PKG_BUILDER_DIR/toolapkai.gpg" \
		"$TERMUX_PREFIX/etc/apt/trusted.gpg.d/toolapkai.gpg"
}
