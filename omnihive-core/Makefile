include $(TOPDIR)/rules.mk

PKG_NAME:=omnihive-core
OMNIHIVE_VERSION?=v1.6.1
PKG_VERSION:=$(patsubst v%,%,$(OMNIHIVE_VERSION))
PKG_RELEASE:=1
PKG_LICENSE:=Proprietary
PKG_MAINTAINER:=OmniHive
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/omnihive-core/Default
  SECTION:=utils
  CATEGORY:=Utilities
  DEPENDS:=
  PKGARCH:=all
endef

define Package/omnihive-core-arm64
  $(call Package/omnihive-core/Default)
  TITLE:=OmniHive core binary (arm64)
  CONFLICTS:=omnihive-core omnihive-core-amd64 omnihive-core-armv7
endef

define Package/omnihive-core-amd64
  $(call Package/omnihive-core/Default)
  TITLE:=OmniHive core binary (amd64)
  CONFLICTS:=omnihive-core omnihive-core-arm64 omnihive-core-armv7
endef

define Package/omnihive-core-armv7
  $(call Package/omnihive-core/Default)
  TITLE:=OmniHive core binary (armv7)
  CONFLICTS:=omnihive-core omnihive-core-arm64 omnihive-core-amd64
endef

define Package/omnihive-core-arm64/description
  Preinstalled OmniHive linux_arm64 core binary for luci-app-omnihive.
endef

define Package/omnihive-core-amd64/description
  Preinstalled OmniHive linux_amd64 core binary for luci-app-omnihive.
endef

define Package/omnihive-core-armv7/description
  Preinstalled OmniHive linux_armv7 core binary for luci-app-omnihive.
endef

define Build/Compile
endef

define Package/omnihive-core/install
	$(INSTALL_DIR) $(1)/etc/omnihive/bin
	$(INSTALL_BIN) ./files/omnihive-$(2) $(1)/etc/omnihive/bin/omnihive
	if [ -f ./files/.version-$(2) ]; then \
		core_ver=$$(cat ./files/.version-$(2)); \
	else \
		core_ver="$(OMNIHIVE_VERSION)"; \
	fi; \
	echo "$$core_ver" > $(1)/etc/omnihive/bin/version; \
	echo "$(2)" > $(1)/etc/omnihive/bin/arch
endef

define Package/omnihive-core/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	if [ -x /etc/init.d/omnihive ] && /etc/init.d/omnihive running >/dev/null 2>&1; then
		/etc/init.d/omnihive restart || true
	fi
}
exit 0
endef

define Package/omnihive-core-arm64/install
	$(call Package/omnihive-core/install,$(1),arm64)
endef

define Package/omnihive-core-amd64/install
	$(call Package/omnihive-core/install,$(1),amd64)
endef

define Package/omnihive-core-armv7/install
	$(call Package/omnihive-core/install,$(1),armv7)
endef

define Package/omnihive-core-arm64/postinst
$(Package/omnihive-core/postinst)
endef

define Package/omnihive-core-amd64/postinst
$(Package/omnihive-core/postinst)
endef

define Package/omnihive-core-armv7/postinst
$(Package/omnihive-core/postinst)
endef

$(eval $(call BuildPackage,omnihive-core-arm64))
$(eval $(call BuildPackage,omnihive-core-amd64))
$(eval $(call BuildPackage,omnihive-core-armv7))
