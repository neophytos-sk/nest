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

Check out its [lambda] proc:

    proc lambda {params body args} {

        set {llength_params} [llength ${params}]
        set {llength_args} [llength ${args}]

        if { ${llength_params} - 1 <= ${llength_args} } {
            set {last_param} [lindex ${params} {end}]
            if { ${llength_params} == ${llength_args} || ${last_param} eq {args} } {
                unset {llength_params} {llength_args}
                return [uplevel 0 ${body} [if {${params} eq {}} {
                    # llength_params == 0 and llength_args == 0
                    unset {last_param} {params} {body} {args}
                } elseif { ${last_param} ne {args} } {
                    # llength_params == llength_args
                    lassign ${args} {*}[concat ${params} \
                        [unset {last_param} {params} {body} {args}]]
                } else {
                    # (llength_params - 1 <= llength_args) and last_param eq {args}
                    set {args} [lassign ${args} {*}[lrange [concat ${params} \
                        [unset {last_param} {params} {body} {args}]] 0 {end-1}]]
                    set {} {}
                }]]
            }
        }

        if { ${args} eq {} } {
            return [list {lambda} ${params} ${body}]
        } elseif {${llength_params} >= ${llength_args}} {
            return \
                [list {lambda} [lrange ${params} ${llength_args} {end}] \
                    [concat \
                        [list lassign ${args} \
                            {*}[lrange ${params} 0 [expr {${llength_args} - 1}]]] 
                    { ; } 
                    ${body}]]
        } else {
            error "lambda: more args than params"
        }

    } 

 
