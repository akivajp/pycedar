#                                               -*- Autoconf -*-
# Process this file with autoconf to produce a configure script.

AC_PREREQ([2.69])
AC_INIT([cedar], [2014-06-24], [ynaga@tkl.iis.u-tokyo.ac.jp])
AM_INIT_AUTOMAKE([-Wall foreign])
AC_CONFIG_HEADERS([config.h])
AC_LANG([C++])

# Checks for programs.
AC_PROG_CXX
AC_PROG_CC

# Checks for libraries.

# Checks for header files.
AC_CHECK_HEADERS([stdint.h])

# Checks for typedefs, structures, and compiler characteristics.
AC_CHECK_HEADER_STDBOOL
AC_TYPE_SIZE_T
AC_TYPE_SSIZE_T
AC_TYPE_UINT16_T
AC_TYPE_UINT8_T

# Checks for library functions.
AC_CHECK_FUNCS([memset])

# exact-fit approach for memory allocation
AC_ARG_ENABLE([exact_fit],
        [AS_HELP_STRING([--enable-exact-fit],
            [exact-fit memory allcation (default=yes)])],
        [],
        [enable_exact_fit="yes"])
AS_IF([test "x$enable_exzat_fit" != "xno"],
  [AC_DEFINE([USE_EXACT_FIT], [1], [exact-fit memory allocation])])

# saving information needed to update/predict () to load a mutable trie faster
AC_ARG_ENABLE([fast_load],
        [AS_HELP_STRING([--enable-fast-load],
            [save extra data for a mutable trie (default=no)])],
        [],
        [enable_fast_load="no"])
AS_IF([test "x$enable_fast_load" != "xno"],
  [AC_DEFINE([USE_FAST_LOAD], [1], [save extra data to load a mutable trie faster])])

# reduce trie size by pruning value nodes
AC_ARG_ENABLE([reduced_trie],
        [AS_HELP_STRING([--enable-reduced-trie],
            [reduce trie size by pruning value nodes (default=no)])],
        [],
        [enable_reduced_trie="no"])
AS_IF([test "x$enable_reduced_trie" != "xno"],
  [AC_DEFINE([USE_REDUCED_TRIE], [1], [reducing trie size by pruning value nodes])])

# reduce trie size by tail
AC_ARG_ENABLE([prefix_trie],
        [AS_HELP_STRING([--enable-prefix-trie],
            [reduce trie size by introducing tail (default=no)])],
        [],
        [enable_prefix_trie="no"])
AS_IF([test "x$enable_prefix_trie" != "xno"],
  [AC_DEFINE([USE_PREFIX_TRIE], [1], [reducing trie size by introducing tail])])

AC_CONFIG_FILES([Makefile
                 src/Makefile])
AC_OUTPUT
