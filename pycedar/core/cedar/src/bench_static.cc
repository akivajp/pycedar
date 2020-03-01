// cedar -- C++ implementation of Efficiently-updatable Double ARray trie
//  $Id: bench_static.cc 1853 2014-06-20 15:04:03Z ynaga $
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
#include <vector>
#include <string>
#include <fstream>
#ifdef USE_PREFIX_TRIE
#include <cedarpp.h>
#else
#include <cedar.h>
#endif
#include <trie.h>
#include <doar/double_array.h>
#include <darts.h>
#ifdef USE_DARTS_CLONE_OLD
#include <darts-clone-0.32e5.h> // header/macros renamed; Darts -> DartsClone
#else
#include <darts-clone-0.32g.h>  // header/macros renamed; Darts -> DartsClone
#endif
#include <dastrie.h>
#include <tx/tx.hpp>
#include <ux/ux.hpp>
#include <marisa.h>

// static const
static const size_t BUFFER_SIZE = 1 << 16;
// typedef
#if   defined (USE_CEDAR_UNORDERED)
typedef cedar::da <int, -1, -2, false>  cedar_t;
#else
typedef cedar::da <int>                 cedar_t;
#endif
typedef Trie                            Trie_t;
typedef dutil::trie                     trie_t;
typedef Darts::DoubleArray              darts_t;
typedef DartsClone::DoubleArray         dartsc_t;
typedef dastrie::trie <int>             dastrie_t;
typedef Doar::Searcher                  doar_t;
typedef tx_tool::tx                     tx_t;
typedef ux::Trie                        ux_t;
typedef marisa::Trie                    marisa_t;

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

template <typename T>
inline void destroy (T* t) { delete t; }

template <>
inline void destroy <Trie_t> (Trie_t* t) { trie_free (t); }

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

// darts/darts-clone
template <typename T>
void build (int fd, int& n, const char* index) {
  std::vector <const char*> key;
  std::vector <size_t>      len;
  std::vector <int>         val;
  char data[BUFFER_SIZE];
  char* start (data), *end (data), *tail (data + BUFFER_SIZE - 1), *tail_ (data);
  while ((tail_ = end + ::read (fd, end, tail - end)) != end) {
    for (*tail_ = KEY_SEP; (end = find_sep (end)) != tail_; start = ++end) {
      key.push_back (::strdup (start));
      len.push_back (end - start);
      val.push_back (++n);
    }
    std::memmove (data, start, tail_ - start);
    end = data + (tail_ - start); start = data;
  }
  T* t = create <T> ();
  t->build (key.size (), &key[0], &len[0], &val[0]);
  t->save (index);
  destroy (t);
  for (std::vector <const char*>::iterator it = key.begin ();
       it != key.end (); ++it)
    ::free (const_cast <char*> (*it));
}

// cedar
template <>
void build <cedar_t> (int fd, int& n, const char* index) {
  cedar_t* t = create <cedar_t> ();
  char data[BUFFER_SIZE];
  char* start (data), *end (data), *tail (data + BUFFER_SIZE - 1), *tail_ (data);
  while ((tail_ = end + ::read (fd, end, tail - end)) != end) {
    for (*tail_ = KEY_SEP; (end = find_sep (end)) != tail_; start = ++end)
      t->update (start, end - start) = ++n;
    std::memmove (data, start, tail_ - start);
    end = data + (tail_ - start); start = data;
  }
  t->save (index);
  destroy (t);
}

// libdatrie
template <>
void build <Trie_t> (int fd, int& n, const char* index) {
  Trie_t* t = create <Trie_t> ();
  char data[BUFFER_SIZE];
  char* start (data), *end (data), *tail (data + BUFFER_SIZE - 1), *tail_ (data);
  while ((tail_ = end + ::read (fd, end, tail - end)) != end) {
    for (*tail_ = KEY_SEP; (end = find_sep (end)) != tail_; start = ++end) {
      AlphaChar key_[256];
      for (size_t i (0), len (end - start); i <= len; ++i)
        key_[i] = static_cast <AlphaChar> (static_cast <unsigned char> (start[i]));
      trie_store (t, &key_[0], ++n);
    }
    std::memmove (data, start, tail_ - start);
    end = data + (tail_ - start); start = data;
  }
  trie_save (t, index);
  destroy (t);
}

// libtrie
template <>
void build <trie_t> (int fd, int& n, const char* index) {
  trie_t* t = create <trie_t> ();
  char data[BUFFER_SIZE];
  char* start (data), *end (data), *tail (data + BUFFER_SIZE - 1), *tail_ (data);
  while ((tail_ = end + ::read (fd, end, tail - end)) != end) {
    for (*tail_ = KEY_SEP; (end = find_sep (end)) != tail_; start = ++end)
      t->insert (start, end - start, ++n);
    std::memmove (data, start, tail_ - start);
    end = data + (tail_ - start); start = data;
  }
  t->build (index);
  destroy (t);
}

// doar
template <>
void build <doar_t> (int fd, int& n, const char* index) {
  std::vector <const char*> key;
  char data[BUFFER_SIZE];
  char* start (data), *end (data), *tail (data + BUFFER_SIZE - 1), *tail_ (data);
  while ((tail_ = end + ::read (fd, end, tail - end)) != end) {
    for (*tail_ = KEY_SEP; (end = find_sep (end)) != tail_; start = ++end)
      key.push_back (::strdup (start)), ++n;
    std::memmove (data, start, tail_ - start);
    end = data + (tail_ - start); start = data;
  }
  Doar::Builder builder;
  builder.build (&key[0], key.size ());
  builder.save (index);
  for (std::vector <const char*>::iterator it = key.begin ();
       it != key.end (); ++it)
    ::free (const_cast <char*> (*it));
}

// dastrie
template <>
void build <dastrie_t> (int fd, int& n, const char* index) {
  typedef dastrie::builder <char*, int>::record_type record_t;
  std::vector <record_t> key_val;
  char data[BUFFER_SIZE];
  char* start (data), *end (data), *tail (data + BUFFER_SIZE - 1), *tail_ (data);
  while ((tail_ = end + ::read (fd, end, tail - end)) != end) {
    for (*tail_ = KEY_SEP; (end = find_sep (end)) != tail_; start = ++end)
      { record_t r = { ::strdup (start), ++n }; key_val.push_back (r); }
    std::memmove (data, start, tail_ - start);
    end = data + (tail_ - start); start = data;
  }
  dastrie::builder <char*, int> builder;
  builder.build (&key_val[0], &key_val[0] + key_val.size ());
  std::ofstream ofs (index, std::ios::binary); builder.write (ofs); ofs.close ();
  for (std::vector <record_t>::iterator it = key_val.begin ();
       it != key_val.end (); ++it)
    ::free (it->key);
}

// tx
template <>
void build <tx_t> (int fd, int& n, const char* index) {
  std::vector <std::string> str;
  char data[BUFFER_SIZE];
  char* start (data), *end (data), *tail (data + BUFFER_SIZE - 1), *tail_ (data);
  while ((tail_ = end + ::read (fd, end, tail - end)) != end) {
    for (*tail_ = KEY_SEP; (end = find_sep (end)) != tail_; start = ++end)
      str.push_back (start), ++n;
    std::memmove (data, start, tail_ - start);
    end = data + (tail_ - start); start = data;
  }
  tx_t* t = create <tx_t> ();
  t->build (str, index);
  destroy (t);
}

// ux
template <>
void build <ux_t> (int fd, int& n, const char* index) {
  std::vector <std::string> str;
  char data[BUFFER_SIZE];
  char* start (data), *end (data), *tail (data + BUFFER_SIZE - 1), *tail_ (data);
  while ((tail_ = end + ::read (fd, end, tail - end)) != end) {
    for (*tail_ = KEY_SEP; (end = find_sep (end)) != tail_; start = ++end)
      str.push_back (start), ++n;
    std::memmove (data, start, tail_ - start);
    end = data + (tail_ - start); start = data;
  }
  ux_t* t = create <ux_t> ();
  t->build (str);
  t->save (index);
  destroy (t);
}

// marisa
template <>
void build <marisa_t> (int fd, int& n, const char* index) {
  marisa::Keyset keyset;
  char data[BUFFER_SIZE];
  char* start (data), *end (data), *tail (data + BUFFER_SIZE - 1), *tail_ (data);
  while ((tail_ = end + ::read (fd, end, tail - end)) != end) {
    for (*tail_ = KEY_SEP; (end = find_sep (end)) != tail_; start = ++end)
      keyset.push_back (start), ++n;
    std::memmove (data, start, tail_ - start);
    end = data + (tail_ - start); start = data;
  }
  marisa_t* t = create <marisa_t> ();
  t->build (keyset);
  t->save (index);
  destroy (t);
}

// cedar/darts/darts-clone
template <typename T>
inline bool lookup_key (T* t, const char* key, size_t len)
{ return t->template exactMatchSearch <int> (key, len) >= 0; }

// libdatrie
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
inline bool lookup_key <trie_t> (trie_t* t, const char* key, size_t len)
{ int val = 0; return t->search (key, len, &val); }

// dastrie
template <>
inline bool lookup_key <dastrie_t> (dastrie_t* t, const char* key, size_t len)
{ int val = 0; return t->find (key, val); }

// doar
template <>
inline bool lookup_key <doar_t> (doar_t* t, const char* key, size_t)
{ return t->search (key); }

// tx
template <>
inline bool lookup_key <tx_t> (tx_t* t, const char* key, size_t len)
{ size_t n = 0; return t->prefixSearch (key, len, n) != tx_tool::tx::NOTFOUND && n == len; }

// ux
template <>
inline bool lookup_key <ux_t> (ux_t* t, const char* key, size_t len)
{ size_t n = 0; return t->prefixSearch (key, len, n) != ux::NOTFOUND && n == len; }

// marisa
template <>
inline bool lookup_key <marisa_t> (marisa_t* t, const char* key, size_t len)
{ static marisa::Agent agent; agent.set_query (key, len); return t->lookup (agent); }

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

// cedar/darts/darts-clone
template <typename T>
T* read_trie (const char* index)
{ T* t = create <T> (); t->open (index); return t; }

// libdatrie
template <>
Trie_t* read_trie <Trie_t> (const char* index)
{ return trie_new_from_file (index); }

// libtrie
template <>
trie_t* read_trie <trie_t> (const char* index)
{ return trie_t::create_trie (index); }

// dastrie
template <>
dastrie_t* read_trie <dastrie_t> (const char* index) {
  dastrie_t* t = create <dastrie_t> ();
  std::ifstream ifs (index, std::ios::binary); t->read (ifs); ifs.close ();
  return t;
}

// doar
template <>
doar_t* read_trie <doar_t> (const char* index)
{ return new doar_t (index); }

// tx
template <>
tx_t* read_trie <tx_t> (const char* index)
{ tx_t* t = create <tx_t> (); t->read (index); return t; }

// ux
template <>
ux_t* read_trie <ux_t> (const char* index)
{ ux_t* t = create <ux_t> (); t->load (index); return t; }

// marisa-trie
template <>
marisa_t* read_trie <marisa_t> (const char* index)
{ marisa_t* t = create <marisa_t> (); t->load (index); return t; }

size_t get_size (const char* index) {
  int fd = ::open (index, O_RDONLY);
  if (fd < 0)
    { std::fprintf (stderr, "no such file: %s\n", index); std::exit (1); }
  size_t size = static_cast <size_t> (::lseek (fd, 0L, SEEK_END));
  ::close (fd);
  return size;
}

template <typename T>
void bench (const char* keys, const char* index, const char* queries, const char* label) {
  size_t rss = get_process_size ();
  std::fprintf (stderr, "---- %-25s --------------------------\n", label);
  std::fprintf (stderr, "%-20s %.2f MiB (%ld bytes)\n",
                "Init RSS:", rss / 1048576.0, rss);
  //
  struct timeval st, et;
  if (std::strcmp (keys, "-") != 0) {
    int fd = ::open (keys, O_RDONLY);
    if (fd < 0)
      { std::fprintf (stderr, "no such file: %s\n", keys); std::exit (1); }
    // build trie
    int n = 0;
    ::gettimeofday (&st, NULL);
    build <T> (fd, n, index);
    ::gettimeofday (&et, NULL);
    double elapsed = (et.tv_sec - st.tv_sec) + (et.tv_usec - st.tv_usec) * 1e-6;
    std::fprintf (stderr, "%-20s %.2f sec (%.2f nsec per key)\n",
                  "Time to insert:", elapsed, elapsed * 1e9 / n);
    std::fprintf (stderr, "%-20s %d\n\n", "Words:", n);
    ::close (fd);
  }
  // trie size
  rss = get_size (index);
  std::fprintf (stderr, "%-20s %.2f MiB (%ld bytes)\n",
                "Trie size:", rss / 1048576.0, rss);
  if (std::strcmp (queries, "-") != 0) {
    // load data
    char* data = 0;
    const size_t size = read_data (queries, data);
    // search
    T* t = read_trie <T> (index);
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
    destroy (t);
  }
}

int main (int argc, char** argv) {
  if (argc < 4)
    { std::fprintf (stderr, "Usage: %s keys index queries\n", argv[0]); std::exit (1); }
  //
#ifdef USE_CEDAR
#if   defined (USE_PREFIX_TRIE)
  bench <cedar_t>   (argv[1], argv[2], argv[3], "cedar (prefix)");
#elif defined (USE_REDUCED_TRIE)
  bench <cedar_t>   (argv[1], argv[2], argv[3], "cedar (reduced)");
#else
  bench <cedar_t>   (argv[1], argv[2], argv[3], "cedar");
#endif
#endif
#ifdef USE_CEDAR_UNORDERED
#if   defined (USE_PREFIX_TRIE)
  bench <cedar_t>   (argv[1], argv[2], argv[3], "cedar unordered (prefix)");
#elif defined (USE_REDUCED_TRIE)
  bench <cedar_t>   (argv[1], argv[2], argv[3], "cedar unordered (reduced)");
#else
  bench <cedar_t>   (argv[1], argv[2], argv[3], "cedar unordered");
#endif
#endif
#ifdef USE_LIBDATRIE
  bench <Trie_t>    (argv[1], argv[2], argv[3], "libdatrie");
#endif
#ifdef USE_LIBTRIE
  bench <trie_t>    (argv[1], argv[2], argv[3], "libtrie");
#endif
#ifdef USE_DOAR
  bench <doar_t>    (argv[1], argv[2], argv[3], "doar");
#endif
#ifdef USE_DARTS
  bench <darts_t>   (argv[1], argv[2], argv[3], "darts");
#endif
#ifdef USE_DARTS_CLONE
  bench <dartsc_t>  (argv[1], argv[2], argv[3], "darts-clone");
#endif
#ifdef USE_DARTS_CLONE_OLD
  bench <dartsc_t>  (argv[1], argv[2], argv[3], "darts-clone_old");
#endif
#ifdef USE_DASTRIE
  bench <dastrie_t> (argv[1], argv[2], argv[3], "dastrie");
#endif
#ifdef USE_TX
  bench <tx_t>      (argv[1], argv[2], argv[3], "tx");
#endif
#ifdef USE_UX
  bench <ux_t>      (argv[1], argv[2], argv[3], "ux");
#endif
#ifdef USE_MARISA
  bench <marisa_t>  (argv[1], argv[2], argv[3], "marisa-trie");
#endif
}
/*
  g++ -DUSE_CEDAR -DHAVE_CONFIG_H -I. -I.. -I$HOME/local/include -O2 -g bench_static.cc -o bench_static_marisa -L$HOME/local/lib -ltx -lux -lmarisa -ltrie
  g++ -DUSE_CEDAR -DHAVE_CONFIG_H -DUSE_BINARY_DATA -I. -I.. -I$HOME/local/include -O2 -g bench_static.cc -o bench_static_marisa_bin -L$HOME/local/lib -ltx -lux -lmarisa -ltrie
*/
