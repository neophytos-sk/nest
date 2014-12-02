Nest Programming Language
=========================

Nest is a language on top of TCL. It was originally meant to be used for a persistence package for OpenACS
(http://www.openacs.org) but the time has passed. The actual code does not exceed 500 lines. Its output can be compiled
into C code (or any other target language). In other words, nest provides a language to write other languages.

You may find my templating presentation in EuroTCL 2013 relevant:
http://www.tcl.tk/community/tcl2013/EuroTcl/presentations/EuroTcl2013-Demetriou-WebTemplating.pdf

You can find the "nest" package here:
http://www.openacs.org/file/4205606/nest-latest.tar.bz2


cd examples

tclsh read-nest.tcl message.nest



GitHub repository:

https://github.com/neophytos-sk/nest


Dependencies: 

* TCL (http://www.tcl.tk)

* tDOM (https://tdom.github.com)

History:

* nest-1.5 (2014-12-02) - simpler examples, added tests dir
* nest-1.1 (2014-12-01) - dispatcher construct, object methods e.g. "$(msg4) sayhi world"
* nest-1.0 (2014-11-30) - alias/forward, inst/decl mode, class/object aliases, struct/slot, template/pair

Notes:

Check out the definition of the struct construct in nest, I think it's cool:

    alias {object} nest {object_helper}

    alias {class} with_mode {decl} nest

    meta {class} {class {object}} {struct} {
        varchar name
        varchar type
        varchar nsp
        varchar default_value = ""

        multiple struct slot = {} {
            varchar name
            varchar type
            varchar meta
            varchar default_value = ""
            bool optional_p = false
            varchar container = ""
        }

        varchar pk
        bool is_final_if_no_scope

    }

Before the chicken and the egg, it was the nest --- pairs, nest-style:

    generic_type {pair} {typefirst typesecond} {
        ${typefirst} {first}
        ${typesecond} {second}
    } {object_helper}

