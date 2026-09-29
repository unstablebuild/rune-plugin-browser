TAR=browser.tar.gz

# Upstream release repackaged by this plugin. Bump TB_VERSION and the four
# checksums together (shasum -a 256 on the release assets).
TB_VERSION=v0.11.1
TB_URL=https://github.com/zenbu-labs/terminal-browser/releases/download/$(TB_VERSION)
TB_SHA256_darwin-arm64=9b21729e47bcc07e969913223705ce1ae5bcaa8e49094d6c9705c4cca8311d90
TB_SHA256_darwin-x64=9454b1467402049e0d08d07a69eb76b67e94f3c4c60ca2b8aadf4158c193c0f4
TB_SHA256_linux-arm64=ef34c68333c4352e5107d5bd6c5cf7fe840a05c9a48a37084b9fc65fc986385c
TB_SHA256_linux-x64=b08327655aa3190260cf34807294be7c7c6685aa2639a393055b7c649eeb3a4a

# Nothing is compiled, so any host can package any target.
HOST_OS=$(shell uname | tr '[:upper:]' '[:lower:]')
HOST_ARCH=$(shell uname -m | sed -e 's/^x86_64$$/amd64/' -e 's/^aarch64$$/arm64/')
TARGET_OS?=$(HOST_OS)
TARGET_ARCH?=$(HOST_ARCH)

# Upstream names amd64 "x64".
UPSTREAM_TARGET=$(TARGET_OS)-$(subst amd64,x64,$(TARGET_ARCH))
UPSTREAM_TAR=upstream/$(TB_VERSION)/terminal-browser-$(UPSTREAM_TARGET).tar.gz

ifeq ($(HOST_OS),darwin)
GTAR ?= gtar
else
GTAR ?= tar
endif

BLUECTL_CONFIG_ROOT := $(abspath deploy/bluectl)

DIST_TARGETS := \
	dist-prod-darwin-arm64 dist-prod-darwin-amd64 \
	dist-prod-linux-arm64  dist-prod-linux-amd64  \
	dist-staging-darwin-arm64 dist-staging-darwin-amd64 \
	dist-staging-linux-arm64  dist-staging-linux-amd64

.PHONY: $(DIST_TARGETS) clean test stage
default: $(TAR)

$(UPSTREAM_TAR):
	@mkdir -p $(dir $@)
	curl -fL --retry 3 -o $@.tmp $(TB_URL)/$(notdir $@)
	echo "$(TB_SHA256_$(UPSTREAM_TARGET))  $@.tmp" | shasum -a 256 -c -
	mv $@.tmp $@

# Stage upstream's release under pkg/. Rune copies every executable file in a
# package onto PATH, so the exec bit is cleared on files that are interpreted
# or dlopen'd rather than executed (scripts, shared libraries, framework
# binaries, and Squirrel's unused ShipIt updater). This keeps the macOS app's
# signature valid: codesign seals contents, not modes.
stage: $(UPSTREAM_TAR)
	rm -rf pkg && mkdir -p pkg
	tar -xzf $(UPSTREAM_TAR) -C pkg --strip-components 1
	python3 scripts/patch-release.py pkg
	find pkg -type f -perm -u+x \( -name '*.js' -o -name '*.sh' \
		-o -name '*.dylib' -o -name '*.so' -o -name '*.so.*' -o -name ShipIt \) \
		-exec chmod a-x {} +
	find pkg -type f -perm -u+x -path '*.framework/Versions/A/*' ! -path '*/Helpers/*' \
		-exec chmod a-x {} +
	cp terminal-browser.sh pkg/bin/terminal-browser
	chmod 755 pkg/bin/terminal-browser
	cp config.yaml pkg
	@mkdir -p pkg/licenses/terminal-browser
	curl -fsSL -o pkg/licenses/terminal-browser/LICENSE \
		https://raw.githubusercontent.com/zenbu-labs/terminal-browser/$(TB_VERSION)/LICENSE

# The launcher is appended last: on macOS the Electron executable is also
# named terminal-browser, and Rune publishes executables in archive order, so
# the last one wins the $RUNE_DATADIR/bin/terminal-browser slot.
$(TAR): stage
	rm -f pkg.tar
	cd pkg && $(GTAR) --no-xattrs --no-acls --exclude=./bin/terminal-browser -cf ../pkg.tar .
	cd pkg && $(GTAR) --no-xattrs --no-acls -rf ../pkg.tar ./bin/terminal-browser
	gzip -c pkg.tar > $(TAR)
	rm -f pkg.tar

test: $(TAR)
	TAR=$(TAR) TARGET_OS=$(TARGET_OS) ./scripts/test.sh

$(DIST_TARGETS): dist-%:
	@env=$$(echo $* | cut -d- -f1); \
	 os=$$(echo $*  | cut -d- -f2); \
	 arch=$$(echo $* | cut -d- -f3); \
	 $(MAKE) clean; \
	 $(MAKE) test TARGET_OS=$$os TARGET_ARCH=$$arch && \
	 BLUECTL_CONFIG_DIR=$(BLUECTL_CONFIG_ROOT)/$$env/$$os-$$arch \
	 BLUE_TARGET_OS=$$os BLUE_TARGET_ARCH=$$arch ./dist.sh

clean:
	rm -rf $(TAR) pkg.tar pkg/