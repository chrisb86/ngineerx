PREFIX=/usr/local

all:

help:
	@echo "make deploy         #=> Copy files to the right place in the filesystem"
	@echo "make update         #=> Fetch changes for this repo"
	@echo "make install        #=> Run make update, deploy"

deploy:
	@echo "+++ Copying files. Prefix is '${PREFIX}'."
	cp -r etc/* ${PREFIX}/etc/
	cp -r share/* ${PREFIX}/share/
	cp ngineerx.sh ${PREFIX}/bin/ngineerx

update:
	@echo "+++ Updating git repository of ngineerx."
	git pull origin master

	@echo "+++ Updating git repository of submodules."
	git submodule init
	git submodule update
	git submodule foreach git pull origin master

install: update deploy
	@echo "+++ Installed ngineerx."

	@echo "+++ Remember to change settings in ${PREFIX}/etc/ngineerx/ngineerx.conf."
	@echo "+++ Run '${PREFIX}/bin/ngineerx install' to bootstrap the stack."