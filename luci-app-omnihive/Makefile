include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-omnihive
PKG_VERSION?=0.1.35
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=OmniHive
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-omnihive
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI support for OmniHive
  DEPENDS:=+luci-base +rpcd +rpcd-mod-file +curl +ca-bundle +jsonfilter
  PKGARCH:=all
endef

define Package/luci-app-omnihive/description
  LuCI management page for installing, configuring, and controlling OmniHive.
endef

define Build/Compile
endef

define Package/luci-app-omnihive/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DIR) $(1)/usr/share/omnihive
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/omnihive

	$(INSTALL_BIN) ./root/etc/uci-defaults/omnihive $(1)/etc/uci-defaults/omnihive
	$(INSTALL_BIN) ./root/etc/init.d/omnihive $(1)/etc/init.d/omnihive
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-omnihive.json $(1)/usr/share/luci/menu.d/
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-omnihive.json $(1)/usr/share/rpcd/acl.d/
	$(INSTALL_BIN) ./root/usr/share/omnihive/*.sh $(1)/usr/share/omnihive/
	$(INSTALL_DATA) ./root/www/luci-static/resources/view/omnihive/index.js $(1)/www/luci-static/resources/view/omnihive/
	echo "$(PKG_VERSION)" > $(1)/usr/share/omnihive/plugin_version
endef

define Package/luci-app-omnihive/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	mkdir -p /etc/omnihive/bin /etc/omnihive/config /etc/omnihive/data /tmp/omnihive/logs /tmp/omnihive/download
	chmod 0755 /etc/init.d/omnihive /usr/share/omnihive/*.sh 2>/dev/null || true
	if [ -x /etc/init.d/rpcd ]; then
		/etc/init.d/rpcd reload >/dev/null 2>&1 || /etc/init.d/rpcd restart >/dev/null 2>&1 || true
	fi
}
exit 0
endef

$(eval $(call BuildPackage,luci-app-omnihive))
