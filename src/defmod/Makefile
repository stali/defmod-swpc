# Makefile for Defmod

FFLAGS = -Wno-maybe-uninitialized 
FPPFLAGS =
LDLIBS =

-include ${PETSC_DIR}/conf/variables
-include ${PETSC_DIR}/conf/rules
-include ${PETSC_DIR}/lib/petsc/conf/variables
-include ${PETSC_DIR}/lib/petsc/conf/rules

OBJS = main.o m_FD2FE.o m_global.o m_local.o m_elems.o m_utils.o

m_utils.o  : m_utils.F90
m_elems.o  : m_elems.F90 m_utils.o
m_local.o  : m_local.F90 m_elems.o
m_global.o : m_global.F90 m_local.o 
m_FD2FE.o  : m_FD2FE.F90 m_global.o
main.o     : main.F90 m_global.o m_FD2FE.o

all: ${OBJS}
	-${FLINKER} ${OBJS} -o ../../bin/defmod ${PETSC_LIB} ${LDLIBS}
