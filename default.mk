#
# Release version
#
#RELEASE:=yes

ifndef DMD
#
# DMD Compiler
#
#DMD:=dmd
#DMD:=dmd-2.059
#
# GDC Compiler
#
DMD:=gdmd
endif

ifndef ARCH
#
# CPU i386 32bits
#
#ARCH:=x86
#
# CPU i386 32bits
#
ARCH:=x86_64
#
# Library (phobos,tango
#
endif
#TANGO:=yes
