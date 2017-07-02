SUBDIRS = src
EXTRA_DIST = GPL LGPL BSD swig

dist-hook:
	cp $(srcdir)/src/bench.cc $(srcdir)/src/bench_static.cc $(distdir)/src
