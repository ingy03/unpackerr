# This Makefile is written as generic as possible.
# Setting the variables in settings.sh and creating the paths in the repo makes this work.
# See more: https://github.com/golift/application-builder

# Suck in our application information.
IGNORED:=$(shell bash -c "source settings.sh ; env | grep -v BASH_FUNC | sed 's/=/:=/;s/^/export /' > /tmp/.metadata.make")

BUILD_FLAGS=-tags osusergo,netgo
GOFLAGS=-trimpath -mod=readonly -modcacherw

# Preserve the passed-in version & iteration (homebrew).
_VERSION:=$(VERSION)
_ITERATION:=$(ITERATION)
include /tmp/.metadata.make

# Travis CI passes the version in. Local builds get it from the current git tag.
ifneq ($(_VERSION),)
VERSION:=$(_VERSION)
ITERATION:=$(_ITERATION)
endif

# rpm is wierd and changes - to _ in versions.
RPMVERSION:=$(shell echo $(VERSION) | tr -- - _)

define PACKAGE_ARGS
--after-install init/systemd/after-install.sh \
--before-remove init/systemd/before-remove.sh \
--name unpackerr \
--deb-no-default-config-files \
--rpm-os linux \
--iteration $(ITERATION) \
--license $(LICENSE) \
--url $(SOURCE_URL) \
--maintainer "$(MAINT)" \
--vendor "$(VENDOR)" \
--description "$(DESC)" \
--config-files "/etc/unpackerr/unpackerr.conf" \
--freebsd-origin "$(SOURCE_URL)"
endef


VERSION_LDFLAGS:= -X \"$golift.io/version.Branch=$(BRANCH) ($(COMMIT))\" \
	-X \"golift.io/version.BuildDate=$(DATE)\" \
	-X \"golift.io/version.BuildUser=$(shell whoami)\" \
	-X \"golift.io/version.Revision=$(ITERATION)\" \
	-X \"golift.io/version.Version=$(VERSION)\"

WINDOWS_LDFLAGS:= -H=windowsgui

# Makefile targets follow.

all: clean build

####################
##### Releases #####
####################

# Prepare a release.
release: clean linux_packages freebsd_packages windows
	# Preparing a release!
	mkdir -p $@
	mv unpackerr.*.linux unpackerr.*.freebsd $@/
	gzip -9r $@/
	for i in unpackerr*.exe ; do zip -9qj $@/$$i.zip $$i examples/*.example *.html; rm -f $$i;done
	mv *.rpm *.deb *.txz $@/
	# Generating File Hashes
	openssl dgst -r -sha256 $@/* | sed 's#release/##' | tee $@/checksums.sha256.txt

# requires a mac.
signdmg: Unpackerr.app
	bash init/macos/makedmg.sh

# Delete all build assets.
clean:
	rm -f unpackerr unpackerr.*.{macos,freebsd,linux,exe}{,.gz,.zip} unpackerr.1{,.gz} unpackerr.rb
	rm -f unpackerr{_,-}*.{deb,rpm,txz} v*.tar.gz.sha256 examples/MANUAL .metadata.make rsrc_*.syso
	rm -f cmd/unpackerr/README{,.html} README{,.html} ./unpackerr_manual.html rsrc.syso Unpackerr.*.app.zip
	rm -f PKGBUILD pkg/bindata/bindata.go
	rm -rf package_build_* release Unpackerr.*.app Unpackerr.app

####################
##### Sidecars #####
####################

# Build a man page from a markdown file using md2roff.
# This also turns the repo readme into an html file.
# md2roff is needed to build the man file and html pages from the READMEs.
man: unpackerr.1.gz
unpackerr.1.gz:
	# Building man page. Build dependency first: md2roff
	go run github.com/davidnewhall/md2roff@v0.0.1 --manual unpackerr --version $(VERSION) --date "$(DATE)" examples/MANUAL.md
	gzip -9nc examples/MANUAL > $@
	mv examples/MANUAL.html unpackerr_manual.html

# TODO: provide a template that adds the date to the built html file.
readme: README.html
README.html: 
	# This turns README.md into README.html
	go run github.com/davidnewhall/md2roff@v0.0.1 --manual unpackerr --version $(VERSION) --date "$(DATE)" README.md

rsrc: rsrc.syso
rsrc.syso: init/windows/application.ico init/windows/manifest.xml 
	go run github.com/akavel/rsrc@latest -arch amd64 -ico init/windows/application.ico -manifest init/windows/manifest.xml

####################
##### Binaries #####
####################

build: unpackerr
unpackerr: generate main.go
	go build $(BUILD_FLAGS) -o unpackerr -ldflags "-w -s $(VERSION_LDFLAGS) $(EXTRA_LDFLAGS) "

linux: unpackerr.amd64.linux
unpackerr.amd64.linux: generate main.go
	# Building linux 64-bit x86 binary.
	GOOS=linux GOARCH=amd64 go build $(BUILD_FLAGS) -o $@ -ldflags "-w -s $(VERSION_LDFLAGS) $(EXTRA_LDFLAGS) "

linux386: unpackerr.386.linux
unpackerr.386.linux: generate main.go
	# Building linux 32-bit x86 binary.
	GOOS=linux GOARCH=386 go build $(BUILD_FLAGS) -o $@ -ldflags "-w -s $(VERSION_LDFLAGS) $(EXTRA_LDFLAGS) "

arm: arm64 armhf

arm64: unpackerr.arm64.linux
unpackerr.arm64.linux: generate main.go
	# Building linux 64-bit ARM binary.
	GOOS=linux GOARCH=arm64 go build $(BUILD_FLAGS) -o $@ -ldflags "-w -s $(VERSION_LDFLAGS) $(EXTRA_LDFLAGS) "

armhf: unpackerr.arm.linux
unpackerr.arm.linux: generate main.go
	# Building linux 32-bit ARM binary.
	GOOS=linux GOARCH=arm GOARM=6 go build $(BUILD_FLAGS) -o $@ -ldflags "-w -s $(VERSION_LDFLAGS) $(EXTRA_LDFLAGS) "

macos: unpackerr.universal.macos
unpackerr.universal.macos: unpackerr.amd64.macos unpackerr.arm64.macos
	# Building darwin 64-bit universal binary.
	lipo -create -output $@ unpackerr.amd64.macos unpackerr.arm64.macos
unpackerr.amd64.macos: generate main.go
	# Building darwin 64-bit x86 binary.
	GOOS=darwin GOARCH=amd64 CGO_ENABLED=1 CGO_LDFLAGS=-mmacosx-version-min=10.8 CGO_CFLAGS=-mmacosx-version-min=10.8 go build $(BUILD_FLAGS) -o $@ -ldflags "-v -w -s $(VERSION_LDFLAGS) $(EXTRA_LDFLAGS) "
unpackerr.arm64.macos: generate main.go
	# Building darwin 64-bit arm binary.
	GOOS=darwin GOARCH=arm64 CGO_ENABLED=1 CGO_LDFLAGS=-mmacosx-version-min=10.8 CGO_CFLAGS=-mmacosx-version-min=10.8 go build $(BUILD_FLAGS) -o $@ -ldflags "-v -w -s $(VERSION_LDFLAGS) $(EXTRA_LDFLAGS) "


freebsd: unpackerr.amd64.freebsd
unpackerr.amd64.freebsd: generate main.go
	GOOS=freebsd GOARCH=amd64 go build $(BUILD_FLAGS) -o $@ -ldflags "-w -s $(VERSION_LDFLAGS) $(EXTRA_LDFLAGS) "

freebsd386: unpackerr.i386.freebsd
unpackerr.i386.freebsd: generate main.go
	GOOS=freebsd GOARCH=386 go build $(BUILD_FLAGS) -o $@ -ldflags "-w -s $(VERSION_LDFLAGS) $(EXTRA_LDFLAGS) "

freebsdarm: unpackerr.armhf.freebsd
unpackerr.armhf.freebsd: generate main.go
	GOOS=freebsd GOARCH=arm go build $(BUILD_FLAGS) -o $@ -ldflags "-w -s $(VERSION_LDFLAGS) $(EXTRA_LDFLAGS) "

exe: unpackerr.amd64.exe
windows: unpackerr.amd64.exe
unpackerr.amd64.exe: generate rsrc.syso main.go
	# Building windows 64-bit x86 binary.
	GOOS=windows GOARCH=amd64 go build $(BUILD_FLAGS) -o $@ -ldflags "-w -s $(VERSION_LDFLAGS) $(EXTRA_LDFLAGS) $(WINDOWS_LDFLAGS)"

####################
##### Packages #####
####################

linux_packages: rpm deb rpm386 deb386 debarm rpmarm debarmhf rpmarmhf

freebsd_packages: freebsd_pkg freebsd386_pkg freebsdarm_pkg

macapp: Unpackerr.app
Unpackerr.app: unpackerr.universal.macos
	cp -rp init/macos/Unpackerr.app Unpackerr.app
	mkdir -p Unpackerr.app/Contents/MacOS
	cp unpackerr.universal.macos Unpackerr.app/Contents/MacOS/Unpackerr
	sed -i '' -e "s/{{VERSION}}/$(VERSION)/g" Unpackerr.app/Contents/Info.plist

rpm: unpackerr-$(RPMVERSION)-$(ITERATION).x86_64.rpm
unpackerr-$(RPMVERSION)-$(ITERATION).x86_64.rpm: package_build_linux_rpm check_fpm
	@echo "Building 'rpm' package for unpackerr version '$(RPMVERSION)-$(ITERATION)'."
	fpm -s dir -t rpm $(PACKAGE_ARGS) -a x86_64 -v $(RPMVERSION) -p $@ -C $< $(EXTRA_FPM_FLAGS)
	[ "$(SIGNING_KEY)" = "" ] || rpmsign --key-id=$(SIGNING_KEY) --resign $@

deb: unpackerr_$(VERSION)-$(ITERATION)_amd64.deb
unpackerr_$(VERSION)-$(ITERATION)_amd64.deb: package_build_linux_deb check_fpm
	@echo "Building 'deb' package for unpackerr version '$(VERSION)-$(ITERATION)'."
	fpm -s dir -t deb $(PACKAGE_ARGS) -a amd64 -v $(VERSION) -p $@ -C $< $(EXTRA_FPM_FLAGS)
	[ "$(SIGNING_KEY)" = "" ] || debsigs --default-key="$(SIGNING_KEY)" --sign=origin $@

rpm386: unpackerr-$(RPMVERSION)-$(ITERATION).i386.rpm
unpackerr-$(RPMVERSION)-$(ITERATION).i386.rpm: package_build_linux_386_rpm check_fpm
	@echo "Building 32-bit 'rpm' package for unpackerr version '$(RPMVERSION)-$(ITERATION)'."
	fpm -s dir -t rpm $(PACKAGE_ARGS) -a i386 -v $(RPMVERSION) -p $@ -C $< $(EXTRA_FPM_FLAGS)
	[ "$(SIGNING_KEY)" = "" ] || rpmsign --key-id=$(SIGNING_KEY) --resign $@

deb386: unpackerr_$(VERSION)-$(ITERATION)_i386.deb
unpackerr_$(VERSION)-$(ITERATION)_i386.deb: package_build_linux_386_deb check_fpm
	@echo "Building 32-bit 'deb' package for unpackerr version '$(VERSION)-$(ITERATION)'."
	fpm -s dir -t deb $(PACKAGE_ARGS) -a i386 -v $(VERSION) -p $@ -C $< $(EXTRA_FPM_FLAGS)
	[ "$(SIGNING_KEY)" = "" ] || debsigs --default-key="$(SIGNING_KEY)" --sign=origin $@

rpmarm: unpackerr-$(RPMVERSION)-$(ITERATION).aarch64.rpm
unpackerr-$(RPMVERSION)-$(ITERATION).aarch64.rpm: package_build_linux_arm64_rpm check_fpm
	@echo "Building 64-bit ARM8 'rpm' package for unpackerr version '$(RPMVERSION)-$(ITERATION)'."
	fpm -s dir -t rpm $(PACKAGE_ARGS) -a arm64 -v $(RPMVERSION) -p $@ -C $< $(EXTRA_FPM_FLAGS)
	[ "$(SIGNING_KEY)" = "" ] || rpmsign --key-id=$(SIGNING_KEY) --resign $@

debarm: unpackerr_$(VERSION)-$(ITERATION)_arm64.deb
unpackerr_$(VERSION)-$(ITERATION)_arm64.deb: package_build_linux_arm64_deb check_fpm
	@echo "Building 64-bit ARM8 'deb' package for unpackerr version '$(VERSION)-$(ITERATION)'."
	fpm -s dir -t deb $(PACKAGE_ARGS) -a arm64 -v $(VERSION) -p $@ -C $< $(EXTRA_FPM_FLAGS)
	[ "$(SIGNING_KEY)" = "" ] || debsigs --default-key="$(SIGNING_KEY)" --sign=origin $@

rpmarmhf: unpackerr-$(RPMVERSION)-$(ITERATION).armhf.rpm
unpackerr-$(RPMVERSION)-$(ITERATION).armhf.rpm: package_build_linux_armhf_rpm check_fpm
	@echo "Building 32-bit ARM6/7 HF 'rpm' package for unpackerr version '$(RPMVERSION)-$(ITERATION)'."
	fpm -s dir -t rpm $(PACKAGE_ARGS) -a armhf -v $(RPMVERSION) -p $@ -C $< $(EXTRA_FPM_FLAGS)
	[ "$(SIGNING_KEY)" = "" ] || rpmsign --key-id=$(SIGNING_KEY) --resign $@

debarmhf: unpackerr_$(VERSION)-$(ITERATION)_armhf.deb
unpackerr_$(VERSION)-$(ITERATION)_armhf.deb: package_build_linux_armhf_deb check_fpm
	@echo "Building 32-bit ARM6/7 HF 'deb' package for unpackerr version '$(VERSION)-$(ITERATION)'."
	fpm -s dir -t deb $(PACKAGE_ARGS) -a armhf -v $(VERSION) -p $@ -C $< $(EXTRA_FPM_FLAGS)
	[ "$(SIGNING_KEY)" = "" ] || debsigs --default-key="$(SIGNING_KEY)" --sign=origin $@

freebsd_pkg: unpackerr-$(VERSION)_$(ITERATION).amd64.txz
unpackerr-$(VERSION)_$(ITERATION).amd64.txz: package_build_freebsd check_fpm
	@echo "Building 'freebsd pkg' package for unpackerr version '$(VERSION)-$(ITERATION)'."
	fpm -s dir -t freebsd $(PACKAGE_ARGS) -a amd64 -v $(VERSION) -p $@ -C $< $(EXTRA_FPM_FLAGS)

freebsd386_pkg: unpackerr-$(VERSION)_$(ITERATION).i386.txz
unpackerr-$(VERSION)_$(ITERATION).i386.txz: package_build_freebsd_386 check_fpm
	@echo "Building 32-bit 'freebsd pkg' package for unpackerr version '$(VERSION)-$(ITERATION)'."
	fpm -s dir -t freebsd $(PACKAGE_ARGS) -a 386 -v $(VERSION) -p $@ -C $< $(EXTRA_FPM_FLAGS)

freebsdarm_pkg: unpackerr-$(VERSION)_$(ITERATION).armhf.txz
unpackerr-$(VERSION)_$(ITERATION).armhf.txz: package_build_freebsd_arm check_fpm
	@echo "Building 32-bit ARM6/7 HF 'freebsd pkg' package for unpackerr version '$(VERSION)-$(ITERATION)'."
	fpm -s dir -t freebsd $(PACKAGE_ARGS) -a arm -v $(VERSION) -p $@ -C $< $(EXTRA_FPM_FLAGS)

# Build an environment that can be packaged for linux.
package_build_linux_rpm: readme man linux
	# Building package environment for linux.
	mkdir -p $@/usr/bin $@/etc/unpackerr $@/usr/share/man/man1 $@/usr/share/doc/unpackerr $@/usr/lib/unpackerr
	# Copying the binary, config file, unit file, and man page into the env.
	cp unpackerr.amd64.linux $@/usr/bin/unpackerr
	cp *.1.gz $@/usr/share/man/man1
	cp examples/unpackerr.conf.example $@/etc/unpackerr/
	cp examples/unpackerr.conf.example $@/etc/unpackerr/unpackerr.conf
	cp LICENSE *.html examples/*?.?* $@/usr/share/doc/unpackerr/
	mkdir -p $@/lib/systemd/system
	cp init/systemd/unpackerr.service $@/lib/systemd/system/
	[ ! -d "init/linux/rpm" ] || cp -r init/linux/rpm/* $@

# Build an environment that can be packaged for linux.
package_build_linux_deb: readme man linux
	# Building package environment for linux.
	mkdir -p $@/usr/bin $@/etc/unpackerr $@/usr/share/man/man1 $@/usr/share/doc/unpackerr $@/usr/lib/unpackerr
	# Copying the binary, config file, unit file, and man page into the env.
	cp unpackerr.amd64.linux $@/usr/bin/unpackerr
	cp *.1.gz $@/usr/share/man/man1
	cp examples/unpackerr.conf.example $@/etc/unpackerr/
	cp examples/unpackerr.conf.example $@/etc/unpackerr/unpackerr.conf
	cp LICENSE *.html examples/*?.?* $@/usr/share/doc/unpackerr/
	mkdir -p $@/lib/systemd/system
	cp init/systemd/unpackerr.service $@/lib/systemd/system/
	[ ! -d "init/linux/deb" ] || cp -r init/linux/deb/* $@

package_build_linux_386_deb: package_build_linux_deb linux386
	mkdir -p $@
	cp -r $</* $@/
	cp unpackerr.386.linux $@/usr/bin/unpackerr

package_build_linux_arm64_deb: package_build_linux_deb arm64
	mkdir -p $@
	cp -r $</* $@/
	cp unpackerr.arm64.linux $@/usr/bin/unpackerr

package_build_linux_armhf_deb: package_build_linux_deb armhf
	mkdir -p $@
	cp -r $</* $@/
	cp unpackerr.arm.linux $@/usr/bin/unpackerr
package_build_linux_386_rpm: package_build_linux_rpm linux386
	mkdir -p $@
	cp -r $</* $@/
	cp unpackerr.386.linux $@/usr/bin/unpackerr

package_build_linux_arm64_rpm: package_build_linux_rpm arm64
	mkdir -p $@
	cp -r $</* $@/
	cp unpackerr.arm64.linux $@/usr/bin/unpackerr

package_build_linux_armhf_rpm: package_build_linux_rpm armhf
	mkdir -p $@
	cp -r $</* $@/
	cp unpackerr.arm.linux $@/usr/bin/unpackerr

# Build an environment that can be packaged for freebsd.
package_build_freebsd: readme man freebsd
	mkdir -p $@/usr/local/bin $@/usr/local/etc/unpackerr $@/usr/local/share/man/man1 $@/usr/local/share/doc/unpackerr
	cp unpackerr.amd64.freebsd $@/usr/local/bin/unpackerr
	cp *.1.gz $@/usr/local/share/man/man1
	cp examples/unpackerr.conf.example $@/usr/local/etc/unpackerr/
	cp examples/unpackerr.conf.example $@/usr/local/etc/unpackerr/unpackerr.conf
	cp LICENSE *.html examples/*?.?* $@/usr/local/share/doc/unpackerr/
	mkdir -p $@/usr/local/etc/rc.d
	cp init/bsd/freebsd.rc.d $@/usr/local/etc/rc.d/unpackerr
	chmod +x $@/usr/local/etc/rc.d/unpackerr

package_build_freebsd_386: package_build_freebsd freebsd386
	mkdir -p $@
	cp -r $</* $@/
	cp unpackerr.i386.freebsd $@/usr/local/bin/unpackerr

package_build_freebsd_arm: package_build_freebsd freebsdarm
	mkdir -p $@
	cp -r $</* $@/
	cp unpackerr.armhf.freebsd $@/usr/local/bin/unpackerr

check_fpm:
	@fpm --version > /dev/null || (echo "FPM missing. Install FPM: https://fpm.readthedocs.io/en/latest/installing.html" && false)

##################
##### Extras #####
##################

# Run code tests and lint.
test: lint
	# Testing.
	go test -race -covermode=atomic ./...
lint: generate
	# Checking lint.
	golangci-lint version
	GOOS=linux golangci-lint run
	GOOS=freebsd golangci-lint run
	GOOS=windows golangci-lint run

generate: pkg/bindata/bindata.go
pkg/bindata/bindata.go: pkg/bindata/files/*
	find pkg -name .DS\* -delete
	go generate ./...

##################
##### Docker #####
##################

docker:
	init/docker/makedocker.sh

####################
##### Homebrew #####
####################

# Used for Homebrew only. Other distros can create packages.
install: man readme unpackerr 
	@echo -  Done Building  -
	@echo -  Local installation with the Makefile is only supported on macOS.
	@echo -  Otherwise, build and install a package: make rpm -or- make deb
	@[ "$(shell uname)" = "Darwin" ] || (echo "Unable to continue, not a Mac." && false)
	@[ "$(PREFIX)" != "" ] || (echo "Unable to continue, PREFIX not set. Use: make install PREFIX=/usr/local ETC=/usr/local/etc" && false)
	@[ "$(ETC)" != "" ] || (echo "Unable to continue, ETC not set. Use: make install PREFIX=/usr/local ETC=/usr/local/etc" && false)
	# Copying the binary, config file, unit file, and man page into the env.
	/usr/bin/install -m 0755 -d $(PREFIX)/bin $(PREFIX)/share/man/man1 $(ETC)/unpackerr $(PREFIX)/share/doc/unpackerr $(PREFIX)/lib/unpackerr
	/usr/bin/install -m 0755 -cp unpackerr $(PREFIX)/bin/unpackerr
	/usr/bin/install -m 0644 -cp unpackerr.1.gz $(PREFIX)/share/man/man1
	/usr/bin/install -m 0644 -cp examples/unpackerr.conf.example $(ETC)/unpackerr/
	[ -f $(ETC)/unpackerr/unpackerr.conf ] || /usr/bin/install -m 0644 -cp  examples/unpackerr.conf.example $(ETC)/unpackerr/unpackerr.conf
	/usr/bin/install -m 0644 -cp LICENSE *.html examples/* $(PREFIX)/share/doc/unpackerr/
