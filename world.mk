
world-%:
	$(MAKE) DC=dmd $*
	$(MAKE) M64=yes DC=dmd $*
	$(MAKE) M64=yes DC=gdmd $*
