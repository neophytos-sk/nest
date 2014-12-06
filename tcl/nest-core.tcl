package require tdom

namespace eval ::nest::core {
    namespace export *
    namespace import ::nest::conf::*
    namespace import ::nest::debug::*

    # =========
    # stack_nest
    # =========
    #
    # each context is a pair of ctx_tag, and ctx_name
    #
    # EXAMPLE 1:
    #
    # struct slot {
    #     varchar name
    #     varchar type
    #     varchar default
    #     -> bool optional_p = false
    #     varchar container_type
    #     varchar subtype
    # }
    # 
    # stack_nest = {base_type bool} {meta struct}
    #
    # EXAMPLE 2:
    # 
    # struct email {
    #   varchar name
    #   -> varchar address
    # }
    #
    # stack_nest = {base_type varchar} {meta struct}

    variable stack_nest [list]
    variable stack_fwd [list]
    variable stack_mode [list {inst}]  ;# default mode is {inst}
    variable stack_eval [list]
    variable stack_proxy [list]

    variable eval_path ""

    array set alias [list]
    array set forward [list]
    array set dispatcher [list]
    array set typeof [list]

    proc lambda {params body args} {
        set nsp [uplevel {namespace current}]
        set cmd [list apply [list ${params} ${body} ${nsp}] {*}${args}]
        uplevel ${cmd}
    }

    proc array_setter {arrayname name value} {
        variable ${arrayname}
        set ${arrayname}(${name}) ${value}
    }
    proc array_getter {arrayname name} {
        variable ${arrayname}
        set ${arrayname}(${name})
    }
    proc array_exister {arrayname name} {
        variable ${arrayname}
        info exists ${arrayname}(${name})
    }

    proc stack_push {varname value} {
        variable ${varname}
        set ${varname} [linsert [set ${varname}] 0 ${value}]
    }
    proc stack_pop {varname} {
        variable ${varname}
        set ${varname} [lreplace [set ${varname}] 0 0]
    }
    proc stack_top {varname} { 
        variable ${varname}
        lindex [set ${varname}] 0
    }
    proc stack_with {varname value args} {
        stack_push ${varname} ${value}
        set result [uplevel ${args}]
        stack_pop ${varname}
        return ${result}
    }

    proc {with_eval} {name args} {
        variable eval_path
        set old_eval_path ${eval_path}
        set eval_path [join [concat ${eval_path} ${name}] {.}]
        push_eval ${name}
        set result [uplevel ${args}]
        pop_eval
        set eval_path ${old_eval_path}
        return ${result}
    }

    proc {eval_path} {} {
        variable {eval_path}
        return ${eval_path}
    }

    proc {gen_eval_name} {name} {
        variable {eval_path}
        join [concat ${eval_path} ${name}] {.}
    }

    # interp alias:
    # * no string parsing at run time
    # * can experiment with interp:
    #   * interp create -safe -- __safe_interp__
    #   * interp eval __safe_interp__ namespace eval ::nest::lang {...}

    array set alias_compile_map {
        {::nest::lang::lambda} {::proc} 
    }

    proc interp_alias {name args} {
        variable alias_compile_map
        set index 0  ;# compile_arg_index
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

    # Wow!!!
    set nsp [namespace current]
    set {nspAliasCmd} {::nest::core::lambda {nsp name arg0 args} {
        set cmd [concat \
            [list interp_alias ${nsp}::${name} [namespace which ${arg0}] {*}${args}] \
            { ; } \
            [list set_alias ${name} ${args}]]
        uplevel ${cmd}
    }}
    {*}${nspAliasCmd} ${nsp} set_alias array_setter alias
    {*}${nspAliasCmd} ${nsp} nsp_alias {*}${nspAliasCmd}

    foreach {name cmd} {

        {get_alias}         {array_getter alias}
        {exists_alias}      {array_exister alias}

        {set_typeof}        {array_setter typeof}
        {get_typeof}        {array_getter typeof}
        {exists_typeof}     {array_exister typeof}

        {set_forward}       {array_setter forward}
        {get_forward}       {array_getter forward}
        {exists_forward}    {array_exister forward}

        {set_dispatcher}    {array_setter dispatcher}
        {get_dispatcher}    {array_getter dispatcher}
        {exists_dispatcher} {array_exister dispatcher}

        {push_fwd}          {stack_push stack_fwd}
        {pop_fwd}           {stack_pop stack_fwd}
        {top_fwd}           {stack_top stack_fwd}
        {with_fwd}          {stack_with stack_fwd}

        {push_mode}         {stack_push stack_mode}
        {pop_mode}          {stack_pop stack_mode}
        {top_mode}          {stack_top stack_mode}
        {with_mode}         {stack_with stack_mode}

        {push_ctx}          {stack_push stack_nest}
        {pop_ctx}           {stack_pop stack_nest}
        {top_ctx}           {stack_top stack_nest}
        {with_ctx}          {stack_with stack_nest}

        {with_proxy}         {stack_with stack_proxy}
        {top_proxy}          {stack_top stack_proxy}
        
        {push_eval}         {stack_push stack_eval}
        {pop_eval}          {stack_pop stack_eval}
        {top_eval}          {stack_top stack_eval}

    } {
        lassign $cmd cmd_name cmd_arg0
        nsp_alias ${nsp} ${name} ${nsp}::${cmd_name} ${cmd_arg0}
    }

    dom createNodeCmd textNode t

    proc nt {text} { t -disableOutputEscaping ${text} }


    nsp_alias ${nsp} {interp_t} interp_if dom_p t

    nsp_alias ${nsp} {interp_execNodeCmd_5} {lambda} {mode name tag proxy args} {
        set node_tag [lsearch -not -inline [list ${proxy} ${tag}] {}]

        if { [exists_typeof $tag] } {
            set metatag [get_typeof $tag]
        } else {
            set metatag "generic_type"
        }

        set node_tag [lsearch -not -inline [list $metatag [lindex [split $tag {.}] end]] {}]

        ::dom::createNodeCmd elementNode ${mode}:${node_tag}
        set cmd \
            [list ::dom::execNodeCmd elementNode ${mode}:${node_tag} \
                -x-name ${name} -x-tag ${tag} -x-mode ${mode} -x-metatag $metatag {*}${args}]
        set node [uplevel ${cmd}]
        if { $proxy ne {} } {
            $node setAttribute x-proxy $proxy
        }
        return $node
    }

    nsp_alias ${nsp} {interp_execNodeCmd_4} {lambda} {mode name tag proxy args} {
        set node_tag [lsearch -not -inline [list ${proxy} ${tag}] {}]

        if { [exists_typeof $tag] } {
            set metatag [get_typeof $tag]
        } else {
            set metatag "generic_type"
        }

        ::dom::createNodeCmd elementNode ${mode}:${node_tag}
        set cmd \
            [list ::dom::execNodeCmd elementNode ${mode}:${node_tag} \
                -x-name ${name} -x-tag ${tag} -x-mode ${mode} -x-metatag $metatag {*}${args}]
        set node [uplevel ${cmd}]
        if { $proxy ne {} } {
            $node setAttribute x-proxy $proxy
        }
        return $node
    }

    nsp_alias ${nsp} {interp_execNodeCmd_3} {lambda} {mode name tag proxy args} {
        set node_tag [lindex [split [lsearch -not -inline [list ${proxy} ${tag}] {}] {.}] end]
        ::dom::createNodeCmd elementNode ${mode}:${node_tag}
        set cmd \
            [list ::dom::execNodeCmd elementNode ${mode}:${node_tag} \
                -x-name ${name} -x-tag ${tag} -x-mode ${mode} {*}${args}]
        set node [uplevel ${cmd}]
        if { $proxy ne {} } {
            $node setAttribute x-proxy $proxy
        }
        return $node
    }


    nsp_alias ${nsp} {interp_execNodeCmd_2} {lambda} {mode name tag proxy args} {
        set node_tag [lindex [split ${tag} {.}] end]
        ::dom::createNodeCmd elementNode ${mode}:${node_tag}
        set cmd \
            [list ::dom::execNodeCmd elementNode ${mode}:${node_tag} \
                -x-name ${name} -x-tag ${tag} -x-mode ${mode} {*}${args}]
        set node [uplevel ${cmd}]
        if { $proxy ne {} } {
            $node setAttribute x-proxy $proxy
        }
        return $node
    }

    nsp_alias ${nsp} {interp_execNodeCmd_1} {lambda} {mode name tag proxy args} {
        set node_tag $tag

        ::dom::createNodeCmd elementNode ${mode}:${node_tag}
        set cmd \
            [list ::dom::execNodeCmd elementNode ${mode}:${node_tag} \
                -x-name ${name} -x-tag ${tag} -x-mode ${mode} {*}${args}]
        set node [uplevel ${cmd}]
        if { $proxy ne {} } {
            $node setAttribute x-proxy $proxy
        }
        return $node
    }

    # default output format (inst/decl) - output_format==0
    nsp_alias ${nsp} {interp_execNodeCmd_0} {lambda} {mode name tag proxy args} {
        set cmd [list ::dom::execNodeCmd elementNode ${mode} -x-name ${name} -x-tag ${tag} {*}${args}]
        set node [uplevel ${cmd}]
        if { $proxy ne {} } {
            $node setAttribute x-proxy $proxy
        }
        return $node
    }

    nsp_alias ${nsp} {interp_execNodeCmd_none} {lambda} {mode name tag proxy args} {
        # TODO: remove -x-attributes from args, one way or another
        if { [llength $args] % 2 == 1 } {
            uplevel [lindex ${args} end]
        } else {
            # do nothing, dom node attributes only in args
        }
        return {::nest::lang::interp_noop}
    }
        
}

# TODO: rename to ::nest::core (make sure namespace handling works properly)

namespace eval ::nest::OLD_lang {

    namespace import ::nest::debug::* 

    # slightly slower than pure tcl version below

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

}
