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

* libxml2 (http://www.xmlsoft.org) [xmllint needed for the read-nest.tcl example]


History:

* nest-0.2 released (2014-11-28) - 367 non-blank, non-comment, non-debugging lines

Notes:

Check out the definition of the struct construct in nest, I think it's very cool:

    meta {nest} {nest {nest {type_helper}}} {struct} {
        varchar name
        varchar type
        varchar nsp

        multiple struct slot = {} {
            varchar parent
            varchar name
            varchar type
            varchar default_value = ""
            bool optional_p = false
            varchar container = ""
        }

        varchar pk
        bool is_final_if_no_scope

    }

