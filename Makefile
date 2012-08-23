DMD=dmd
DFLAGS=-w -wi -gc -unittest -property

all:
	$(DMD) -D $(DFLAGS) maybe.d -of"maybe"
