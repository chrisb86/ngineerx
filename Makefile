PREFIX=/usr/local

all:

help:
	@echo "make deploy         #=> Copy files to their designated places in the filesystem"
	@echo "make update         #=> Fetch changes for this repo"
	@echo "make install        #=> Run make update and deploy"

deploy:
	@echo "Copying files to their designated places."
	@cp -r share/* ${PREFIX}/share/
	@mkdir ${PREFIX}/etc/ngineerx
	@cp ${PREFIX}/share/ngineerx/ngineerx/ngineerx.conf.dist ${PREFIX}/etc/ngineerx/
	@cp ngineerx.sh ${PREFIX}/bin/ngineerx

	@echo "All files deployed."
	@echo "You may want change settings in ${PREFIX}/etc/ngineerx/ngineerx.conf but it's not necessary."
	@echo "Run '${PREFIX}/bin/ngineerx install' to bootstrap the stack."

update:
	@echo "Updating ngineerx. from git repository."
	git pull origin master

install: update deploy
