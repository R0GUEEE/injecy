NAME := injecy
SCHEME := injecy
DD := $(PWD)/.build-ipa
CERT_JSON_URL := https://backloop.dev/pack.json

.PHONY: ipa deps clean bump

# Auto-increment build + version patch in project.yml, then regenerate the project.
bump:
	@python3 scripts/bump.py
	@xcodegen generate >/dev/null

# Build an UNSIGNED .ipa (for the self-updater — the app re-signs it on-device
# with the user's certificate). Output: packages/injecy.ipa
# Each run auto-bumps the version/build first (via `bump`).
ipa: bump deps
	rm -rf _build
	GIT_CONFIG_VALUE_0=all xcodebuild \
		-project injecy.xcodeproj \
		-scheme $(SCHEME) \
		-configuration Release \
		-destination "generic/platform=iOS" \
		-derivedDataPath $(DD) \
		-skipPackagePluginValidation \
		CODE_SIGNING_ALLOWED=NO \
		ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES=NO \
		build
	mkdir -p _build/Payload
	cp -R "$(DD)/Build/Products/Release-iphoneos/$(NAME).app" _build/Payload/$(NAME).app
	chmod -R 0755 _build/Payload/$(NAME).app
	# Bundle the install-server certs BEFORE signing so the seal covers them.
	cp deps/server.crt deps/server.pem deps/commonName.txt _build/Payload/$(NAME).app/ || true
	# Strip any third-party signatures from embedded frameworks (e.g. OpenSSL.framework
	# ships signed by "Goodnotes Limited"). Sign DEEP + ad-hoc so every nested binary has a
	# consistent identity — otherwise on-device re-signing leaves a team mismatch and iOS
	# refuses to install with "integrity could not be verified".
	codesign --remove-signature _build/Payload/$(NAME).app/Frameworks/*.framework 2>/dev/null || true
	codesign --remove-signature _build/Payload/$(NAME).app/Frameworks/*.dylib 2>/dev/null || true
	codesign --force --deep --sign - --timestamp=none _build/Payload/$(NAME).app
	mkdir -p packages
	rm -f packages/$(NAME).ipa
	ditto -c -k --sequesterRsrc --keepParent _build/Payload "packages/$(NAME).ipa"
	@echo "✓ Built packages/$(NAME).ipa"

# Fetch the SSL certs bundled for the on-device install server.
deps:
	rm -rf deps && mkdir -p deps
	curl -fsSL "$(CERT_JSON_URL)" -o deps/cert.json
	jq -r '.cert' deps/cert.json > deps/server.crt
	jq -r '.key1, .key2' deps/cert.json > deps/server.pem
	jq -r '.info.domains.commonName' deps/cert.json > deps/commonName.txt

clean:
	rm -rf $(DD) _build packages deps
