ROUTER ?= 192.168.6.1
SSH ?= ssh
SCP ?= scp
REMOTE ?= root@$(ROUTER)
IPK_DIR ?= bin/packages
CORE_ARCH ?= arm64

.PHONY: ipk deploy deploy-core

# Build luci-app-omnihive_*.ipk locally without the OpenWrt SDK (no compiled
# code in this package). Output goes to $(IPK_DIR).
ipk:
	./scripts/build-ipk.sh luci-app-omnihive $(IPK_DIR)

deploy:
	$(SCP) $$(find $(IPK_DIR) -name 'luci-app-omnihive_*.ipk' | head -n 1) $(REMOTE):/tmp/
	$(SSH) $(REMOTE) 'opkg install --force-reinstall /tmp/luci-app-omnihive_*.ipk'

deploy-core:
	$(SCP) $$(find $(IPK_DIR) -name 'omnihive-core-$(CORE_ARCH)_*.ipk' | head -n 1) $(REMOTE):/tmp/
	$(SSH) $(REMOTE) 'opkg install /tmp/omnihive-core-$(CORE_ARCH)_*.ipk'
