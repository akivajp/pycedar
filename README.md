# pycedar

![version](https://img.shields.io/pypi/v/pycedar.svg)
![python](https://img.shields.io/pypi/pyversions/pycedar.svg)
![license](https://img.shields.io/pypi/l/pycedar.svg)

Python binding of ``cedar`` (implementation of efficiently-updatable double-array trie) using Cython

Official URL of ``cedar``: http://www.tkl.iis.u-tokyo.ac.jp/~ynaga/cedar/

## Installation

### install from PyPi release

```shell
$ pip install --user pycedar
```

### install from GitHub master

```shell
$ pip install --user https://github.com/akivajp/pycedar/archive/master.zip
```

## Usage

### using python-like dict class based on double array trie

```python
>>> import pycedar

>>> d = pycedar.dict()
>>> print( len(d) )
0
>>> print( bool(d) )
False
>>> print( list(d) )
[]

>>> d['nineteen'] = 19
>>> d.set('twenty', 20)
>>> d['twenty one'] = 21
>>> d['twenty two'] = 22
>>> d['twenty three'] = 23
>>> d['twenty four'] = 24

>>> print( len(d) )
6
>>> print( bool(d) )
True
>>> print( list(d) )
['nineteen', 'twenty', 'twenty four', 'twenty one', 'twenty three', 'twenty two']
>>> print( list(d.keys()) )
['nineteen', 'twenty', 'twenty four', 'twenty one', 'twenty three', 'twenty two']
>>> print( list(d.values()) )
[19, 20, 24, 21, 23, 22]
>>> print( list(d.items()) )
[('nineteen', 19), ('twenty', 20), ('twenty four', 24), ('twenty one', 21), ('twenty three', 23), ('twenty two', 22)]
>>> print( d['twenty four'] )
24
>>> print( 'twenty four' in d )
True
>>> del d['twenty four']
>>> print( 'twenty four' in d )
False
>>> try:
>>>     print( d['twenty four'] )
>>> except Exception as e:
>>>     print( repr(e) )
KeyError('twenty four',)
>>> print( d.get('twenty three') )
23
>>> print( d.get('twenty four') )
-1
>>> print( d.get('twenty four', None) )
None

>>> print( list(d.find('')) )
[('nineteen', 19), ('twenty', 20), ('twenty one', 21), ('twenty three', 23), ('twenty two', 22)]
>>> print( list(d.find('tw')) )
[('twenty', 20), ('twenty one', 21), ('twenty three', 23), ('twenty two', 22)]
>>> print( list(d.find('twenty t')) )
[('twenty three', 23), ('twenty two', 22)]
>>> print( list(d.find_keys('twenty')) )
['twenty', 'twenty one', 'twenty three', 'twenty two']
>>> print( list(d.find_values('twenty')) )
[20, 21, 23, 22]

>>> n = d.get_node('twenty')
>>> print( n )
'twenty'
>>> print( repr(n) )
pycedar.node(trie=<pycedar.str_trie object at 0x7fffe2394b80>, id=260, length=6, root=0)
>>> print( n.key() )
twenty
>>> print( n.value() )
20
>>> print( [n.key() for n in n.find_nodes(' t')] )
[' three', ' two']

>>> n = d.get_node('twenty ')
>>> print( n )
None

>>> d.save('test.dat')
>>> d2 = pycedar.dict()
>>> print( d2.setdefault('eighteen', 18) )
18
>>> print( list(d2.items()) )
[('eighteen', 18)]
>>> d2.load('test.dat')
>>> print( list(d2.items()) )
[('nineteen', 19), ('twenty', 20), ('twenty one', 21), ('twenty three', 23), ('twenty two', 22)]
>>> print( d2.setdefault('eighteen', 18) )
18
>>> print( list(d2.items()) )
[('eighteen', 18), ('nineteen', 19), ('twenty', 20), ('twenty one', 21), ('twenty three', 23), ('twenty two', 22)]
```

### using more primitive data structures

(TBA)

### todo

* documentation of classes:
    * base_trie
    * str_trie
    * bytes_trie
    * unicode_trie
    * node