! DESCRIP.MMS - build GNU grep for OpenVMS (IA64, x86-64)
!
! Run from the top of the prepared source tree via [.VMS]BUILD.COM, which
! passes ARCH (IA64 or X86_64) and creates the output directories.
! Source lists and per-object rules come from [.VMS]SOURCES.MMS, generated
! by tools/prepare.sh on the host.

.IFDEF ARCH
.ELSE
ARCH = IA64
.ENDIF

OBJ = [.OBJ_$(ARCH)]
LOBJ = [.OBJ_$(ARCH).LIB]
BIN = [.BIN_$(ARCH)]

.INCLUDE [.VMS]SOURCES.MMS

CC = CC
CFLAGS = $(CC_QUAL)/NOLIST/INCLUDE_DIRECTORY=("./","./lib","./src","./vms")/DEFINE=($(CC_DEFS),HAVE_CONFIG_H)

LIB = $(OBJ)GREPUTILS.OLB
EXE = $(BIN)GREP.EXE

ALL : $(EXE)
	@ CONTINUE

$(EXE) : $(SRC_OBJS), $(EXTRA_OBJS), $(LIB)
	LINK/EXECUTABLE=$(MMS$TARGET)/MAP=$(OBJ)GREP.MAP/FULL $(SRC_OBJS), $(EXTRA_OBJS), $(LIB)/LIBRARY

$(LIB) : $(LIB_OBJS)
	IF F$SEARCH("$(MMS$TARGET)") .EQS. "" THEN LIBRARY/CREATE/OBJECT $(MMS$TARGET)
	LIBRARY/REPLACE/OBJECT $(MMS$TARGET) $(LOBJ)*.OBJ

! Helper programs the upstream test suite builds with "make check".
CHECK_PROGRAMS : [.TESTS]get-mb-cur-max.EXE
	@ CONTINUE

[.TESTS]get-mb-cur-max.EXE : $(OBJ)get-mb-cur-max.OBJ, $(LIB)
	LINK/EXECUTABLE=$(MMS$TARGET)/NOMAP $(OBJ)get-mb-cur-max.OBJ, $(LIB)/LIBRARY

$(OBJ)get-mb-cur-max.OBJ : [.TESTS]get-mb-cur-max.c
	$(CC) $(CFLAGS) /OBJECT=$(MMS$TARGET) $(MMS$SOURCE)

CLEAN :
	IF F$SEARCH("$(LOBJ)*.*") .NES. "" THEN DELETE/NOLOG $(LOBJ)*.*;*
	IF F$SEARCH("$(OBJ)*.OBJ") .NES. "" THEN DELETE/NOLOG $(OBJ)*.OBJ;*,*.OLB;*,*.MAP;*
	IF F$SEARCH("$(BIN)*.*") .NES. "" THEN DELETE/NOLOG $(BIN)*.*;*
