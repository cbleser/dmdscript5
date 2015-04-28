EXTENDTEST:=yes
EMPTY:=

#DC?=dmd-2.065.b1
DC?=dmd
include default.mk

.PHONY:getjs

REPOROOT?=$(shell git rev-parse --show-toplevel)

#Source root
ROOT?=$(REPOROOT)
REVNO?=$(shell git rev-parse HEAD)

define MKDIR
test -d $1 || mkdir -p $1
endef


#DFLAGS+=-v
DFLAGS+=-version=Ecmascript5
ifndef RELEASE
#DFLAGS+=-debug
DFLAGS+=-g
DFLAGS+=-unittest
endif

ifdef PROFILE
DFLAGS+=-profile
endif

ifeq ($(ARCH),x86_64)
DFLAGS+=-m64 -I.
DVERSION=2.060

BITS:=64
else
DFLAGS+=-m32 -I.
DVERSION=2.059
BITS:=32
endif

LOGDIR:=log

BIN:=bin$(BITS)

ifdef TANGO
LIBNAME:=tango
INC+=-I$(REPOROOT)/tango
LDTANGS+=$(REPOROOT)/tango/tango-dmd.a
DFLAGS+=-version=Tango -version=NoPhobos
else
LIBNAME:=phobos
endif

ifndef TANGO
#DC=dmd-$(DVERSION)
#DMD=gdmd
#LDFLAGS:=-L-L/home/cbr/.dvm/compilers/dmd-2.055/lib/
#LDFLAGS:=/home/cbr/.dvm/compilers/dmd-$(DVERSION)/lib/libphobos2.a
#DFLAGS+=-unittest
#-debug=regexp
#DFLAGS+=-version=ddate_unittest
#DFLAGS+=-version=regexp
endif

#INC:=-I/opt/cad/gdc/4.7.2/include/d/4.7.2/

#RFLAGS+=-m32 -I. -O -release -inline  -d
COMPILER:=$(DC)

ifdef RELEASE
#DFLAGS+=-O -release -inline  -d
DFLAGS+=-release -O
#-inline
endif

BINDIR=$(ROOT)/obj/$(LIBNAME)/$(DC)/$(BIN)/
DMDSCRIPTLIB:=libdmdscript-$(LIBNAME)-$(DC)-$(ARCH).a

.PHONY: test262

help:
	@echo "make all"
	@echo "Compiles the default $(DMDSCRIPTLIB)"
	@echo
	@echo "make run"
	@echo "Runs and compiles the test programs"
	@echo
	@echo "make clean"
	@echo "Clears the default library"
	@echo
	@echo "make world-<tag>"
	@echo "Does the same as above but for each combination"
	@echo "of compile(dmd,gdc) and"
	@echo "library (tango,phobos) and"
	@echo "cpu (x86,x86_64)"
	@echo
	@echo "Ex."
	@echo "make world-run"
	@echo "wold compiles an run all combination"
	@echo
	@echo "Note."
	@echo "The default flavor is set up in the default.mk file"


LIB_SRC+=dmdscript/date.d
LIB_SRC+=dmdscript/darguments.d
LIB_SRC+=dmdscript/darray.d
LIB_SRC+=dmdscript/dboolean.d
LIB_SRC+=dmdscript/ddate.d
LIB_SRC+=dmdscript/ddeclaredfunction.d
LIB_SRC+=dmdscript/derror.d
LIB_SRC+=dmdscript/dfunction.d
LIB_SRC+=dmdscript/dglobal.d
LIB_SRC+=dmdscript/dmath.d
LIB_SRC+=dmdscript/dnative.d
LIB_SRC+=dmdscript/dnumber.d
LIB_SRC+=dmdscript/dobject.d
LIB_SRC+=dmdscript/dregexp.d
LIB_SRC+=dmdscript/dstring.d
LIB_SRC+=dmdscript/errmsgs.d
LIB_SRC+=dmdscript/expression.d
LIB_SRC+=dmdscript/functiondefinition.d
LIB_SRC+=dmdscript/identifier.d
LIB_SRC+=dmdscript/ir.d
LIB_SRC+=dmdscript/irstate.d
LIB_SRC+=dmdscript/iterator.d
LIB_SRC+=dmdscript/lexer.d
LIB_SRC+=dmdscript/opcodes.d
LIB_SRC+=dmdscript/parse.d
LIB_SRC+=dmdscript/program.d
LIB_SRC+=dmdscript/property.d
LIB_SRC+=dmdscript/protoerror.d
LIB_SRC+=dmdscript/RandAA.d
LIB_SRC+=dmdscript/scopex.d
LIB_SRC+=dmdscript/script.d
LIB_SRC+=dmdscript/statement.d
LIB_SRC+=dmdscript/symbol.d
LIB_SRC+=dmdscript/text.d
LIB_SRC+=dmdscript/threadcontext.d
LIB_SRC+=dmdscript/utf.d
LIB_SRC+=dmdscript/value.d
LIB_SRC+=dmdscript/extending.d
LIB_SRC+=dmdscript/dateparse.d
LIB_SRC+=dmdscript/datebase.d
LIB_SRC+=dmdscript/regexp.d
LIB_SRC+=dmdscript/djson.d
LIB_SRC+=dmdscript/dconsole.d
#dmdscript/outbuffer.d \


all: makeway samples

info:
	echo BINDIR= $(BINDIR)

$(DMDSCRIPTLIB) : $(LIB_SRC)
	$(DC) $(INC) -lib $(DFLAGS) $(LIB_SRC) -of$@


libs: $(DMDSCRIPTLIB)

samples: $(BINDIR)/ds$(EXT) $(BINDIR)/ext$(EXT)

makeway:
	$(call MKDIR,$(BINDIR))


$(BINDIR)/ds$(EXT): testscript.d $(DMDSCRIPTLIB)
	$(call MKDIR,$(@D))
	$(DC) $(INC) $(LDFLAGS) $(DFLAGS) $(DMDSCRIPTLIB) testscript.d -of$@
	rm -f ds$(EXT); ln -s $@ ds$(EXT)

$(BINDIR)/ext$(EXT): samples/ext.d $(DMDSCRIPTLIB)
	$(call MKDIR,$(@D))
	$(DC) $(INC) $(LDFLAGS) $(DFLAGS) $(DMDSCRIPTLIB) samples/ext.d -of$@

redist:
	tar -jc dmdscript/*.d dmdscript/*.visualdproj samples/*.d samples/*.ds *.d posix.mak win32.mak README.txt LICENSE_1_0.txt *.visualdproj dmdscript.sln > dmdscript.tar.bz2
world: world-run

include world.mk


$(LOGDIR)/%.log: %.js
	$(call MKDIR,$(@D))
	$(BINDIR)/ds $< |tee $@


run: all
	cp $(ROOT)/samples/ext.js $(BINDIR)/
	cd $(BINDIR); ./ext
	cd samples; $(BINDIR)/ds seive.ds
	cd samples; echo "Borge"|$(BINDIR)/ds simple.ds

run-ext: all
	cp $(ROOT)/samples/ext.js $(BINDIR)/
	cd $(BINDIR); ./ext

ddd-ext: all
	cp $(ROOT)/samples/ext.js $(BINDIR)/
	ln -s $(ROOT)/dmdscript $(BINDIR)/dmdscript
	cd $(BINDIR); ddd ./ext

#
# test262
# test setup for Ecmascript 5
#
SPUTNIK:=$(REPOROOT)/tools/sputnik.py

ifdef EXTENDTEST
TEST262_HARNESS_DIR:=$(REPOROOT)/test262/test/suite
SUBTEST:=ch15/15.1/15.1.1
SUBTEST:=ch11
SUBTEST:=

TEST262LOG:=test262_extended.log
else
SUBTEST:=

TEST262_HARNESS_DIR:=$(REPOROOT)/test262/external/contributions/Google/sputniktests/
SUBTEST:=tests/Conformance/$(SUBTEST)
TEST262LOG:=test262.log

endif


SCRIPTEXE:=$(BINDIR)/ds$(EXT)
#SCRIPTEXE:=seed
#SCRIPTEXE:=gjs
#SCRIPTEXE=node

SPUTNIK_FLAGS:=--command=$(SCRIPTEXE)
SPUTNIK_FLAGS+=--tests=$(TEST262_HARNESS_DIR)
ifdef SUBTEST
SPUTNIK_FLAGS+=--subtest=$(SUBTEST)
endif
SPUTNIK_FLAGS+=--full-summary

ifndef TEST262LOG
TEST262LOG:=test262.log
endif

TEST262LOGTEE:=| tee -a $(TEST262LOG)

getjs:
	find $(TEST262_HARNESS_DIR) -name "$(JS).js" -printf "cat tools/base.js %p > %f\n" > /tmp/dump.sh
	. /tmp/dump.sh

test262: all
	@echo "Revsion $(REVNO)" > $(TEST262LOG)
	$(SPUTNIK) $(SPUTNIK_FLAGS) $(TEST262LOGTEE)

test262-extend:
	$(MAKE) DC=$(DC) EXTENDTEST=yes test262

clean:
	rm -f $(DMDSCRIPTLIB) $(BINDIR)/*
	rm -f test262.lst
	rm -fR log
