// cedar -- C++ implementation of Efficiently-updatable Double ARray trie
//  $Id: bench.cc 1853 2014-06-20 15:04:03Z ynaga $
// Copyright (c) 2013-2014 Naoki Yoshinaga <ynaga@tkl.iis.u-tokyo.ac.jp>
extern "C" {
#include <datrie/trie.h>
}
#ifdef __APPLE__
#include <mach/mach.h>
#endif
#include <unistd.h>
#include <fcntl.h>
#include <sys/time.h>
#include <cstdio>
#include <cstring>
#include <cstddef> // for ternary search tree
#include <vector>
#include <string>
#include <map>
#include <unordered_map>
#ifdef USE_PREFIX_TRIE
#include <cedarpp.h>
#else
#include <cedar.h>
#endif
#include <trie.h>
#include <doar/double_array.h>
#include <critbit.h> // need to modify critbit0_insert to take length and value
#include <btree_map.h>
#include <google/sparse_hash_map>
#include <google/dense_hash_map>
#pragma GCC diagnostic warning "-w"
#include <Judy.h>
#pragma GCC diagnostic warning "-Wall"
#include <jsw_atree.h>
#include <hat-trie/hat-trie.h>
#include <dict/skiplist.h>
#include <dict/tr_tree.h>
#include <dict/sp_tree.h>
#include <containers.h>
#include <cxxmph/mph_map.h>
#include <array-hash.hpp>
extern "C" {
#include <tst.h>
}

// static const
static const size_t BUFFER_SIZE = 1 << 16;
// typedef
#if   defined (USE_CEDAR_UNORDERED)
typedef cedar::da <int, -1, -2, false>              cedar_t;
#else
typedef cedar::da <int>                             cedar_t;
#endif
typedef Trie                                        Trie_t;
typedef dutil::trie                                 trie_t;
typedef Doar::DoubleArray                           doar_t;
typedef std::map <std::string, int>                 map_t;
typedef std::unordered_map <std::string, int>       hash_t;
typedef critbit0_tree                               cbit_t;
typedef skiplist                                    skip_t;
typedef tr_tree                                     treap_t;
typedef sp_tree                                     splay_t;
typedef jsw_atree_t                                 atree_t;
typedef TreeMap                                     scape_t;
typedef struct tnode                                tst_t;
typedef btree::btree_map <std::string, int>         gbtree_t;
typedef google::sparse_hash_map <std::string, int>  gshash_t;
typedef google::dense_hash_map <std::string, int>   gdhash_t;
typedef cxxmph::unordered_map <std::string, int>    mphash_t;
typedef ht::ArrayHash <int>                         ahash_t;
typedef Pvoid_t                                     judy_t;
typedef hattrie_t                                   hat_t;
void  cb   (void* key, void* value) { delete [] key; }
void  del  (void* key) { delete [] key; }
void* dupl (void* key) { return key; }
int   delp (void** key, void*)
{ delete [] *key; return 0; }
int   cmp  (void** key1, void** key2, void*)
{ return std::strcmp (*key1, *key2); }

template <typename T>
inline T* create () { return new T (); }

template <>
inline Trie_t* create () {
  AlphaMap* alpha_map = alpha_map_new ();
  alpha_map_add_range (alpha_map, 1, 255);
  Trie_t* t = trie_new (alpha_map);
  alpha_map_free (alpha_map);
  return t;
}

template <>
inline trie_t* create () { return dutil::trie::create_trie (); }

template <>
inline skip_t* create () { return skiplist_new (std::strcmp, cb, 28); }

template <>
inline splay_t* create () { return sp_tree_new (std::strcmp, cb); }

template <>
inline treap_t* create () { return tr_tree_new (std::strcmp, 0, cb); }

template <>
inline atree_t* create () { return jsw_anew (std::strcmp, dupl, del); }

template <>
inline scape_t* create () {
  scape_t* t = iTreeMap.Create (sizeof (void*));
  iTreeMap.SetCompareFunction (t, cmp);
  return t;
}

template <>
inline tst_t* create () { return tst_init (); }

template <>
inline gdhash_t* create () { gdhash_t* p = new gdhash_t; p->set_empty_key (""); return p; }

template <>
inline hat_t*  create () { return hattrie_create (); }

template <typename T>
inline void destroy (T* t) { delete t; }

template <>
inline void destroy (Trie_t* t) { trie_free (t); }

template <>
inline void destroy (cbit_t* t) { critbit0_clear (t); delete t; }

template <>
inline void destroy (skip_t* t) { skiplist_free (t); }

template <>
inline void destroy (treap_t* t) { tr_tree_free (t); }

template <>
inline void destroy (splay_t* t) { sp_tree_free (t); }

template <>
inline void destroy (atree_t* t) { jsw_adelete (t); }

template <>
inline void destroy (tst_t* t) { tst_cleanup (t); }

#ifdef USE_SCAPE
template <>
inline void destroy (scape_t* t) {
  iTreeMap.Apply (t, delp, NULL);
  iTreeMap.Finalize (t);
}
#endif

template <>
inline void destroy (judy_t* t) { Word_t bytes = 0; JSLFA (bytes, *t); delete t; }

template <>
inline void destroy (hat_t* t) { hattrie_free (t); }

size_t read_data (const char* file, char*& data) {
  int fd = ::open (file, O_RDONLY);
  if (fd < 0)
    { std::fprintf (stderr, "no such file: %s\n", file); std::exit (1); }
  size_t size = static_cast <size_t> (::lseek (fd, 0L, SEEK_END));
  data = new char[size];
  ::lseek (fd, 0L, SEEK_SET);
  ::read  (fd, data, size);
  ::close (fd);
  return size;
}

size_t get_process_size () {
#ifdef __APPLE__
  struct task_basic_info t_info;
  mach_msg_type_number_t t_info_count = TASK_BASIC_INFO_COUNT;
  task_info (current_task (), TASK_BASIC_INFO,
             reinterpret_cast <task_info_t> (&t_info), &t_info_count);
  return t_info.resident_size;
#else
  FILE* fp = std::fopen("/proc/self/statm", "r");
  size_t dummy (0), vm (0);
  std::fscanf (fp, "%ld %ld ", &dummy, &vm); // get resident (see procfs)
  std::fclose (fp);
  return vm * ::getpagesize ();
#endif
}

#ifdef USE_BINARY_DATA
#define KEY_SEP '\0'
inline char* find_sep (char* p) { while (*p != '\0') ++p; return p; }
#else
#define KEY_SEP '\n'
inline char* find_sep (char* p) { while (*p != '\n') ++p; *p = '\0'; return p; }
#endif

template <typename T> // map/unordered_map/btree
inline void insert_key (T* t, const char* key, size_t len, int n)
{ t->insert (typename T::value_type (std::string (key, len), n)); }
template <typename T>  // map/unordered_map/btree
inline bool lookup_key (T* t, const char* key, size_t len)
{ return t->find (std::string (key, len)) != t->end (); }

// array hash; it doesn't save a key;
template <>
inline void insert_key <ahash_t> (ahash_t* t, const char* key, size_t len, int n)
{ t->insert (std::string (key, len), n); }
template <>
inline bool lookup_key <ahash_t> (ahash_t* t, const char* key, size_t len)
{ return t->exists (std::string (key, len)); }

// cedar
template <>
inline void insert_key <cedar_t> (cedar_t* t, const char* key, size_t len, int n)
{ t->update (key, len) = n; }
template <>
inline bool lookup_key <cedar_t> (cedar_t* t, const char* key, size_t len)
{ return t->exactMatchSearch <int> (key, len) >= 0; }

// libdatrie
template <>
inline void insert_key <Trie_t> (Trie_t* t, const char* key, size_t len, int n) {
  AlphaChar key_[256];
  for (size_t i = 0; i <= len; ++i)
    key_[i] = static_cast <AlphaChar> (static_cast <unsigned char> (key[i]));
  trie_store (t, &key_[0], n);
}
template <>
inline bool lookup_key <Trie_t> (Trie_t* t, const char* key, size_t len) {
  AlphaChar key_[256];
  for (size_t i = 0; i <= len; ++i)
    key_[i] = static_cast <AlphaChar> (static_cast <unsigned char> (key[i]));
  int val = 0;
  return trie_retrieve (t, &key_[0], &val);
}

// libtrie
template <>
inline void insert_key <trie_t> (trie_t* t, const char* key, size_t len, int n)
{ t->insert (key, len, n); }
template <>
inline bool lookup_key <trie_t> (trie_t* t, const char* key, size_t len)
{ int val = 0; return t->search (key, len, &val); }

// doar
template <>
inline void insert_key <doar_t> (doar_t* t, const char* key, size_t, int n)
{ t->insert (key); n; }
template <>
inline bool lookup_key <doar_t> (doar_t* t, const char* key, size_t len)
{ return t->search (key); }

// crit-bit tree
// modified critbit0_insert so that it stores an integer value after the string
template <>
inline void insert_key <cbit_t> (cbit_t* t, const char* key, size_t len, int n)
{ critbit0_insert (t, key, len, n); }
template <>
inline bool lookup_key <cbit_t> (cbit_t* t, const char* key, size_t len)
{ return critbit0_contains (t, key, len); }

// skiplist
template <>
inline void insert_key <skip_t> (skip_t* t, const char* key, size_t len, int n)
{ bool flag = true; *skiplist_insert (t, ::strdup (key), &flag) = (void*) n; }
template <>
inline bool lookup_key <skip_t> (skip_t* t, const char* key, size_t len)
{ return skiplist_search (t, key); }

// treap
template <>
inline void insert_key <treap_t> (treap_t* t, const char* key, size_t len, int n)
{ bool flag = true; *tr_tree_insert (t, ::strdup (key), &flag) = (void*) n; }
template <>
inline bool lookup_key <treap_t> (treap_t* t, const char* key, size_t len)
{ return tr_tree_search (t, key); }

// splay_tree
template <>
inline void insert_key <splay_t> (splay_t* t, const char* key, size_t len, int n)
{ bool flag = true; *sp_tree_insert (t, ::strdup (key), &flag) = (void*) n; }
template <>
inline bool lookup_key <splay_t> (splay_t* t, const char* key, size_t len)
{ return sp_tree_search (t, key); }

// aa tree
// store an integer value after the string as in crit-bit tree
template <>
inline void insert_key <atree_t> (atree_t* t, const char* key, size_t len, int n) {
  char* data = static_cast <char*> (std::malloc (len + 1 + sizeof (int)));
  std::strcpy (data, key);
  std::memcpy (data + len + 1, &n, sizeof (int));
  jsw_ainsert (t, data);
}
template <>
inline bool lookup_key <atree_t> (atree_t* t, const char* key, size_t len)
{ return jsw_afind (t, key); }

// scapegot tree
// store an integer value after the string as in crit-bit tree
#ifdef USE_SCAPE
template <>
inline void insert_key <scape_t> (scape_t* t, const char* key, size_t len, int n) {
  char* data = reinterpret_cast <char*> (std::malloc (len + 1 + sizeof (int)));
  std::strcpy (data, key);
  std::memcpy (data + len + 1, &n, sizeof (int));
  iTreeMap.Insert (t, &data, NULL);
}
template <>
inline bool lookup_key <scape_t> (scape_t* t, const char* key, size_t len)
{ return iTreeMap.GetElement (t, &key, NULL); }
#endif

// tst
template <>
inline void insert_key <tst_t> (tst_t* t, const char* key, size_t len, int n)
{ tst_insert (t, key, (void*) n); }
template <>
inline bool lookup_key <tst_t> (tst_t* t, const char* key, size_t len)
{ return tst_search (t, key); }

// judy array
template <>
inline void insert_key <judy_t> (judy_t* t, const char* key, size_t len, int n)
{ Word_t* PValue = 0; JSLI (PValue, *t, key); *PValue = n; }
template <>
inline bool lookup_key <judy_t> (judy_t* t, const char* key, size_t len)
{ PWord_t PValue = 0; JSLG (PValue, *t, key); return PValue; }

// hat trie
template <>
inline void insert_key <hat_t> (hat_t* t, const char* key, size_t len, int n)
{ *hattrie_get (t, key, len) = n; }
template <>
inline bool lookup_key <hat_t> (hat_t* t, const char* key, size_t len)
{ return hattrie_tryget (t, key, len); }

template <typename T>
void insert (T* t, int fd, int& n) {
  char data[BUFFER_SIZE];
  char* start (data), *end (data), *tail (data + BUFFER_SIZE - 1), *tail_ (data);
  while ((tail_ = end + ::read (fd, end, tail - end)) != end) {
    for (*tail_ = KEY_SEP; (end = find_sep (end)) != tail_; start = ++end)
      insert_key (t, start, end - start, ++n);
    std::memmove (data, start, tail_ - start);
    end = data + (tail_ - start); start = data;
  }
}

// lookup
template <typename T>
void lookup (T* t, char* data, size_t size, int& n_, int& n) {
  for (char* start (data), *end (data), *tail (data + size);
       end != tail; start = ++end) {
    end = find_sep (end);
    if (lookup_key (t, start, end - start))
      ++n_;
    ++n;
  }
}

template <typename T>
void bench (const char* keys, const char* queries, const char* label) {
  size_t rss = get_process_size ();
  std::fprintf (stderr, "---- %-25s --------------------------\n", label);
  std::fprintf (stderr, "%-20s %.2f MiB (%ld bytes)\n",
                "Init RSS:", rss / 1048576.0, rss);
  //
  T* t = create <T> ();
  struct timeval st, et;
  {
    int fd = ::open (keys, O_RDONLY);
    if (fd < 0)
      { std::fprintf (stderr, "no such file: %s\n", keys); std::exit (1); }
    // build trie
    int n = 0;
    ::gettimeofday (&st, NULL);
    insert (t, fd, n);
    ::gettimeofday (&et, NULL);
    double elapsed = (et.tv_sec - st.tv_sec) + (et.tv_usec - st.tv_usec) * 1e-6;
    std::fprintf (stderr, "%-20s %.2f sec (%.2f nsec per key)\n",
                  "Time to insert:", elapsed, elapsed * 1e9 / n);
    std::fprintf (stderr, "%-20s %d\n\n", "Words:", n);
    ::close (fd);
  }
  if (std::strcmp (queries, "-") != 0) {
    // load data
    char* data = 0;
    const size_t size = read_data (queries, data);
    // search
    int n (0), n_ (0);
    ::gettimeofday (&st, NULL);
    lookup (t, data, size, n_, n);
    ::gettimeofday (&et, NULL);
    double elapsed = (et.tv_sec - st.tv_sec) + (et.tv_usec - st.tv_usec) * 1e-6;
    std::fprintf (stderr, "%-20s %.2f sec (%.2f nsec per key)\n",
                  "Time to search:", elapsed, elapsed * 1e9 / n);
    std::fprintf (stderr, "%-20s %d\n", "Words:", n);
    std::fprintf (stderr, "%-20s %d\n", "Found:", n_);
    delete [] data;
  }
  destroy (t);
}

int main (int argc, char** argv) {
  if (argc < 3)
    { std::fprintf (stderr, "Usage: %s keys queries\n", argv[0]); std::exit (1); }
  //
#ifdef USE_CEDAR
#if   defined (USE_PREFIX_TRIE)
  bench <cedar_t>   (argv[1], argv[2], "cedar (prefix)");
#elif defined (USE_REDUCED_TRIE)
  bench <cedar_t>   (argv[1], argv[2], "cedar (reduced)");
#else
  bench <cedar_t>   (argv[1], argv[2], "cedar");
#endif
#endif
#ifdef USE_CEDAR_UNORDERED
#if   defined (USE_PREFIX_TRIE)
  bench <cedar_t>   (argv[1], argv[2], "cedar unordered (prefix)");
#elif defined (USE_REDUCED_TRIE)
  bench <cedar_t>   (argv[1], argv[2], "cedar unordered (reduced)");
#else
  bench <cedar_t>   (argv[1], argv[2], "cedar unordered");
#endif
#endif
#ifdef USE_LIBDATRIE
  bench <Trie_t>    (argv[1], argv[2], "libdatrie");
#endif
#ifdef USE_LIBTRIE
  bench <trie_t>    (argv[1], argv[2], "libtrie");
#endif
#ifdef USE_DOAR
  bench <doar_t>    (argv[1], argv[2], "doar");
#endif
#ifdef USE_MAP
  bench <map_t>     (argv[1], argv[2], "map");
#endif
#ifdef USE_HASH
  bench <hash_t>    (argv[1], argv[2], "hash");
#endif
#ifdef USE_CBIT
  bench <cbit_t>    (argv[1], argv[2], "cbit");
#endif
#ifdef USE_SKIP
  bench <skip_t>    (argv[1], argv[2], "skip");
#endif
#ifdef USE_TREAP
  bench <treap_t>   (argv[1], argv[2], "treap");
#endif
#ifdef USE_SPLAY
  bench <splay_t>   (argv[1], argv[2], "splay");
#endif
#ifdef USE_AA
  bench <atree_t>   (argv[1], argv[2], "atree");
#endif
#ifdef USE_SCAPE
  bench <scape_t>   (argv[1], argv[2], "scape");
#endif
#ifdef USE_TST
  bench <tst_t>     (argv[1], argv[2], "tst");
#endif
#ifdef USE_GOOGLE_BTREE
  bench <gbtree_t>  (argv[1], argv[2], "gbtree");
#endif
#ifdef USE_GOOGLE_SHASH
  bench <gshash_t>  (argv[1], argv[2], "gshash");
#endif
#ifdef USE_GOOGLE_DHASH
  bench <gdhash_t>  (argv[1], argv[2], "gdhash");
#endif
#ifdef USE_MPHASH
  bench <mphash_t>  (argv[1], argv[2], "mphash");
#endif
#ifdef USE_JUDY
  bench <judy_t>    (argv[1], argv[2], "judy");
#endif
#ifdef USE_HAT
  bench <hat_t>     (argv[1], argv[2], "hat");
#endif
#ifdef USE_AHASH
  bench <ahash_t>   (argv[1], argv[2], "ahash");
#endif
}
/*
  gcc -Wall -O2 -g -c jsw_atree.c
  gcc -Wall -O2 -g -c tst.c
  gcc -WALL -O2 -g -std=c99 -c critbit.c
  g++ -DUSE_CEDAR -DHAVE_CONFIG_H -fpermissive -std=c++11 -I. -I.. -I$HOME/local/include -O2 -g critbit.o bench.cc -o bench -L$HOME/local/lib -lhat-trie -lJudy -ltrie -ldict
  g++ -DUSE_CEDAR -DHAVE_CONFIG_H -DUSE_BINARY_DATA -fpermissive -std=c++11 -I. -I$HOME/local/include -O2 -g critbit.o bench.cc -o bench_bin -L$HOME/local/lib -lhat-trie -lJudy -ltrie -ldict
*/
