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
BIN = [.BIN_$(ARCH)]

.INCLUDE [.VMS]SOURCES.MMS

CC = CC
CFLAGS = $(CC_QUAL)/NOLIST/INCLUDE_DIRECTORY=("./","./lib","./src")/DEFINE=($(CC_DEFS),HAVE_CONFIG_H)

LIB = $(OBJ)GREPUTILS.OLB
EXE = $(BIN)GREP.EXE

ALL : $(EXE)
	@ CONTINUE

$(EXE) : $(SRC_OBJS), $(EXTRA_OBJS), $(LIB)
	LINK/EXECUTABLE=$(MMS$TARGET)/MAP=$(OBJ)GREP.MAP/FULL $(SRC_OBJS), $(EXTRA_OBJS), $(LIB)/LIBRARY

$(LIB) : $(LIB_OBJS)
	IF F$SEARCH("$(MMS$TARGET)") .EQS. "" THEN LIBRARY/CREATE/OBJECT $(MMS$TARGET)
	LIBRARY/REPLACE/OBJECT $(MMS$TARGET) $(MMS$CHANGED_LIST)

CLEAN :
	IF F$SEARCH("$(OBJ)*.*") .NES. "" THEN DELETE/NOLOG $(OBJ)*.*;*
	IF F$SEARCH("$(BIN)*.*") .NES. "" THEN DELETE/NOLOG $(BIN)*.*;*
