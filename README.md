Nest Programming Language
=========================

Implements a language on top of TCL. I was originally planning to use it for implementing persistence in OpenACS
(http://www.openacs.org) but the time has passed. The actual code does not exceed 500 lines including the DTD and 
the comments (less than 400 lines without the comments). Resulting spec can be validated with the DTD in the code 
and turned into C code.

You may find my templating presentation in EuroTCL 2013 relevant:
http://www.tcl.tk/community/tcl2013/EuroTcl/presentations/EuroTcl2013-Demetriou-WebTemplating.pdf

You can find the "nest" package here:
http://www.openacs.org/file/4205606/nest.tar.bz2.bz2


cd examples

tclsh read-nest.tcl message.nest



GitHub repository:

https://github.com/neophytos-sk/nest


Dependencies: 

* TCL (http://www.tcl.tk)

* tDOM (https://tdom.github.com)
