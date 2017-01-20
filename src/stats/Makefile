TOP = ../..

include $(TOP)/configure/CONFIG
#----------------------------------------
#  ADD MACRO DEFINITIONS AFTER THIS LINE

#  Device support declarations
DBD += devSeqCar.dbd
DB += devSeqCar.db

USR_CFLAGS += -I$(TOP)/src/seq

LIBRARY = seqCar
seqDev_LIBS += seq pv 
seqDev_LIBS += $(EPICS_BASE_IOC_LIBS)
seq_DIR=$(INSTALL_LIB)

LIBSRCS += devSeqCar.c

include $(TOP)/configure/RULES
#----------------------------------------
#  ADD RULES AFTER THIS LINE

# $(INSTALL_DBD)/seq.dbd needed by test/demo depends
depends: $(INSTALL_DBDS)
