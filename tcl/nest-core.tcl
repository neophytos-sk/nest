
# TODO: rename to ::nest::core (make sure namespace handling works properly)

namespace eval ::nest::lang {

    namespace import ::nest::debug::* 

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

    # interp alias:
    # * no string parsing at run time
    # * can experiment with interp:
    #   * interp create -safe -- __safe_interp__
    #   * interp eval __safe_interp__ namespace eval ::nest::lang {...}

    array set alias_compile_map {
        {::nest::lang::lambda} {::proc} 
    }

    proc interp_alias {name index args} {
        variable alias_compile_map
        set arg [lindex ${args} ${index}]
        if { [info exists alias_compile_map(${arg})] } {
            set args [lreplace $args ${index} ${index} $alias_compile_map($arg) ${name}]
            log "alias compiled to proc: ${name}"
            {*}${args}
            return
        }
        {interp} {alias} {} ${name} {} {*}${args}


    }

    proc interp_noop {args} {}
    proc interp_if {condition_expr cmd args} {
        if {[{*}${condition_expr}]} {
            {*}${cmd} {*}${args}
        }
    }
    proc interp_if_else {condition_expr if_cmd else_cmd args} {
        if {[{*}${condition_expr}]} {
            {*}${if_cmd} {*}${args}
        } else {
            {*}${if_cmd} {*}${args}
        }
    }

}


