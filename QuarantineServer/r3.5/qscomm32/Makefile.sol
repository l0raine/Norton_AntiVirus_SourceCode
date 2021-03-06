# Makefile for QsComm (Quarantine Server Communications)

ifdef PURIFY
     PURIFYCMD= purify
     DEBUG= 1
endif

# CC= $(PURIFYCMD) gcc-2.95.2
CC= $(PURIFYCMD) gcc

INCDIRS = \
	-I../shared/include \
	-I../Include

SYMBOLS = \
	-DUNIX \
	-DSYM_UNIX \
	-DSOLARIS \
	-DSYM_SOLARIS \
	-DBIG_ENDIAN \
	-D_PTHREADS \
	-D_REENTRANT \
	-D_POSIX_PTHREAD_SEMANTICS

CCFLAGS = $(INCDIRS) $(SYMBOLS) -funsigned-char -fPIC

OBJS = \
	sockets.o 


.SUFFIXES: .cpp .in

ifdef DEBUG
    SYMBOLS += -D_DEBUG
    CCFLAGS += -g
else
    CCFLAGS += -O2
endif



all: 
	$(MAKE) release
	@DEBUG=1 $(MAKE) debug


.cpp.o: $<
	$(CC) $(CCFLAGS) -c $< -o $@

libqscomm.a: $(OBJS)
	ar $(ARFLAGS) $@ $(OBJS)



mv-release-up:
	mkdir -p release
	touch release/ph.o release/ph.a
	mv -f release/*.o .
	mv -f release/*.a .

mv-debug-up:
	mkdir -p debug
	touch debug/ph.o debug/ph.a
	mv -f debug/*.o .
	mv -f debug/*.a .


release: mv-release-up libqscomm.a 
	mkdir -p release
	mv libqscomm.a release

debug: mv-debug-up libqscomm.a 
	mkdir -p debug
	mv libqscomm.a debug


release-clean:
	rm -rf release

debug-clean:
	rm -rf debug

clean: release-clean debug-clean
	rm -f *.o libqscomm.a

