#Makefile at top of application tree
TOP = .
include $(TOP)/config/CONFIG_APP

#directories in which to build
DIRS += src test docs

include $(TOP)/config/RULES_TOP

# Version number (used below)

VERSION = $(shell cat src/Version)

# Override "tar" rules with rule that runs tar from one level up, generates
# sub-directory with version number in it, and gzips the result (this rule
# is not a replacement for the "tar" rule; it does not support .current_rel_-
# hist and EPICS_BASE files)

tar:
	@MODULE=$(notdir $(shell pwd)); \
	TARNAME=$$MODULE-$(VERSION); \
	TARFILE=$$MODULE/$$TARNAME.tar; \
	echo "TOP: Creating $$TARNAME.tar file..."; \
	cd ..; $(RM) $$TARNAME; ln -s $$MODULE $$TARNAME; \
	ls $$TARNAME/Makefile* | xargs tar vcf $$TARFILE; \
	for DIR in ${DIRS}; do    \
	        find $$TARNAME/$$DIR -name CVS -prune -o ! -type d -print \
	        | grep -v "/O\..*$$" | xargs tar vrf $$TARFILE; \
	done; \
	gzip -f $$TARFILE; \
	$(RM) $$TARNAME

