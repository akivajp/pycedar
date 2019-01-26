#!/usr/bin/env python
# -*- coding: utf-8 -*-

import pycedar

d = pycedar.dict()

print( len(d) )
print( bool(d) )
print( list(d) )

d['nineteen'] = 19
d.set('twenty', 20)
d['twenty one'] = 21
d['twenty two'] = 22
d['twenty three'] = 23
d['twenty four'] = 24

print( len(d) )
print( bool(d) )
print( list(d) )
print( list(d.keys()) )
print( list(d.values()) )
print( list(d.items()) )
print( d['twenty four'] )
print( 'twenty four' in d )
del d['twenty four']
print( 'twenty four' in d )
try:
    print( d['twenty four'] )
except Exception as e:
    print( repr(e) )
print( d.get('twenty three') )
print( d.get('twenty four') )
print( d.get('twenty four', None) )

print( list(d.find('')) )
print( list(d.find('tw')) )
print( list(d.find('twenty t')) )
print( list(d.find_keys('twenty')) )
print( list(d.find_values('twenty')) )

n = d.get_node('twenty')
print( n )
print( repr(n) )
print( n.key() )
print( n.value() )
print( [n.key() for n in n.find_nodes(' t')] )

n = d.get_node('twenty ')
print( n )

d.save('test.dat')
d2 = pycedar.dict()
print( d2.setdefault('eighteen', 18) )
print( list(d2.items()) )
d2.load('test.dat')
print( list(d2.items()) )
print( d2.setdefault('eighteen', 18) )
print( list(d2.items()) )

