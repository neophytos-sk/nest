package require tdom

package provide nest 1.2

define_lang ::nest::lang {

    namespace import ::nest::debug::* 

    # =========
    # stack_ctx
    # =========
    #
    # each context is a list that consists of ctx_type, ctx_tag, and ctx_name
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
    # stack_ctx = {nest base_type bool} {nest meta struct}
    #
    # EXAMPLE 2:
    # 
    # struct email {
    #   varchar name
    #   -> varchar address
    # }
    #
    # stack_ctx = {nest base_type varchar} {nest meta struct}

    variable stack_ctx [list]
    variable stack_fwd [list]
    variable stack_mode [list {inst}]  ;# default mode is {inst}
    variable stack_eval [list]

    variable eval_path ""

    array set alias [list]
    array set forward [list]
    array set dispatcher [list]
    array set lookahead_ctx [list]


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
        set result [{*}${args}] ;# uplevel ${args}
        stack_pop ${varname}
        return ${result}
    }

    proc {with_eval} {name args} {
        variable eval_path
        set old_eval_path ${eval_path}
        set eval_path [join [concat ${eval_path} ${name}] {.}]
        push_eval ${name}
        set result [{*}${args}] ;# uplevel ${args}
        pop_eval
        set eval_path ${old_eval_path}
        return ${result}
    }

    proc {gen_eval_path} {name} {
        variable {eval_path}
        join [concat ${eval_path} ${name}] {.}
    }


    # Wow!!!
    set {nspAliasCmd} {lambda {name arg0 args} {
        set nsp [uplevel {namespace current}]
        set compile_arg_index "0"
        interp_alias ${nsp}::${name} ${compile_arg_index} ${nsp}::${arg0} {*}${args}
        set_alias ${name} ${args}
    }}
    {*}${nspAliasCmd} {set_alias} array_setter alias
    {*}${nspAliasCmd} {nsp_alias} {*}${nspAliasCmd}
        
    nsp_alias {alias} {lambda} {name args} {
        interp alias {} ${name} {} {*}${args}
        set_alias ${name} ${args}
    }

    foreach {name cmd} {

        {get_alias} {array_getter alias}
        {exists_alias} {array_exister alias}

        {set_forward} {array_setter forward}
        {get_forward} {array_getter forward}
        {exists_forward} {array_exister forward}

        {set_dispatcher} {array_setter dispatcher}
        {get_dispatcher} {array_getter dispatcher}
        {exists_dispatcher} {array_exister dispatcher}

        {set_lookahead_ctx} {array_setter lookahead_ctx}
        {get_lookahead_ctx} {array_getter lookahead_ctx}
        {exists_lookahead_ctx} {array_exister lookahead_ctx}

        {push_fwd} {stack_push stack_fwd}
        {pop_fwd} {stack_pop stack_fwd}
        {top_fwd} {stack_top stack_fwd}
        {with_fwd} {stack_with stack_fwd}

        {push_mode} {stack_push stack_mode}
        {pop_mode} {stack_pop stack_mode}
        {top_mode} {stack_top stack_mode}
        {with_mode} {stack_with stack_mode}

        {push_ctx} {stack_push stack_ctx}
        {pop_ctx} {stack_pop stack_ctx}
        {top_ctx} {stack_top stack_ctx}
        {with_ctx} {stack_with stack_ctx}
        
        {push_eval} {stack_push stack_eval}
        {pop_eval} {stack_pop stack_eval}
        {top_eval} {stack_top stack_eval}

    } {
        nsp_alias ${name} {*}[join ${cmd} { }]
    }

    # forward is an alias that pushes its name to stack_fwd
    nsp_alias {forward} {lambda} {name cmd} {
        {set_forward} ${name} ${cmd}
        {alias} ${name} {::nest::lang::with_fwd} ${name} {*}${cmd}
    }

    forward {meta} {lambda {metaCmd args} {{*}$metaCmd {*}$args}}
    forward {keyword} {::dom::createNodeCmd elementNode}

    keyword {decl}
    keyword {inst}

    dom createNodeCmd textNode t

    proc nt {text} { t -disableOutputEscaping ${text} }

    nsp_alias {interp_t} interp_if dom_p t

    nsp_alias {interp_execNodeCmd} {lambda} {tag name args} {
        if { [dom_p] } {
            ::dom::execNodeCmd elementNode ${tag} -x-name ${name} {*}${args}
        } else {
            # TODO: remove -x-attributes from args, one way or another
            if { [llength $args] % 2 == 1 } {
                eval [lindex ${args} end]
            } else {
                # do nothing, dom node attributes only in args
            }
            return {::nest::lang::interp_noop}
        }
    }

    nsp_alias {node} {lambda} {tag name args} \
        {with_eval ${name} interp_execNodeCmd ${tag} ${name} {*}${args}}





    # nest argument holds nested calls in the procs below
    proc nest {nest name args} {
        set tag [top_fwd]

        log "!!! nest: $name -> $nest"

        set id [gen_eval_path $name]

        #if { [exists_alias $id] } {
        #    error "alias for $id already exists"
        #}

        if { [top_mode] eq {decl} || $tag eq {base_type} } {

            set ctx [list {nest} $tag $id]
            set_lookahead_ctx $id $ctx ;# needed by container_helper and type_helper
            set nest [list with_ctx $ctx {*}$nest]
            {forward} ${id} ${nest}

        } else {

            # creates dispatcher alias for object/instance methods
            #
            # @${id}
            # => @ ${id}
            # => with_eval ${id}

            {dispatcher} ${id}

        }

        set node [{node} [top_mode] $name -x-id ${id} -x-type $tag {*}$args]

        ###

        if { ![debug_p] } {
            return $node
        }

        set nsp [uplevel {namespace current}]

        if {  $tag ne {base_type} } {

            # $node appendFromScript {
            #     struct.type [$node @x-type] ;# $tag
            #     struct.name [$node @x-name] ;# $name
            #     struct.nsp  [$node @x-nsp]  ;# $nsp
            # }
            ${node} appendFromScript {
                init_slots $node {struct}
            }

            set decls [$node selectNodes {child::decl}]
            foreach decl $decls {
                $decl appendFromScript {
                    # $decl appendFromScript {
                    #     struct.slot.cons          [$decl @x-type]
                    #     struct.slot.name          [$decl @x-name]
                    #     struct.slot.default_value [$decl @x-default_value] (opt) 
                    #     struct.slot.optional_p    [$decl @x-optional_p]    (opt)
                    #     struct.slot.container     [$decl @x-container]     (opt)
                    # }
                    init_slots $decl {struct.slot}
                }
                #$decl setAttribute x-meta {struct.slot}
            }

            #$node setAttribute x-meta ${name}

        }

        return $node

    }

    proc init_slots {node struct} {
        foreach attname [$node attributes] {
            set identifier [string range [set attname] 2 end]
            ${struct}.[set identifier] [$node @[set attname]]
        }
    }


    proc typedecl {args} {
        
        set tag [top_fwd]  ;# varchar nsp -> tag=varchar name=nsp

        # deal with args and create dom node
        set args [lassign $args arg0]
        if { [lindex $args 0] eq {=} } {
            set args [lreplace $args 0 0 "-x-default_value"]
        }

        set decl_type $tag
        set decl_name $arg0

        set cmd [list with_mode {decl} {node} {decl} $decl_name -x-type $decl_type {*}$args]
        set node [{*}${cmd}]  ;# uplevel $cmd

        # get full forward name and register the forward
        set forward_name [gen_eval_path $decl_name]
        set lookahead_ctx [list {nest} $decl_type $decl_name]
        set_lookahead_ctx $forward_name $lookahead_ctx

        set dotted_nest [list with_mode {inst} $decl_type $forward_name]
        set dotted_nest [list with_ctx $lookahead_ctx {*}$dotted_nest] 
        set cmd [list {forward} $forward_name $dotted_nest]
        {*}${cmd} ;# uplevel $cmd

        log "(declaration done) decl_type=$decl_type decl_name=$decl_name forward_name=$forward_name stack_ctx=[list $::nest::lang::stack_ctx]"

        return $node

    }

    proc typeinst {args} {

        set tag [top_fwd]  ;# varchar nsp -> tag=varchar name=nsp
        lassign [top_ctx] ctx_type ctx_tag ctx_name

        if { $ctx_tag eq {base_type} } {

            # message.subject "hello" 
            # => inst_name=message.subject args={{hello}} 
            # => inst_name=message.subject inst_type=base_type
            
            set inst_type $tag
            set args [lassign $args inst_name inst_arg0]

            if { $args ne {} } { 
                error "something wrong with instantiation statement args=[list $args]"
            }

            set inst_arg0 [list ::nest::lang::interp_t $inst_arg0]
            set cmd [list with_mode {inst} {node} {inst} $inst_name -x-type $inst_type $inst_arg0]

            return [{*}${cmd}]  ;# uplevel ${cmd}

        } else {

            # case for composite or "unknown" types (e.g. pair<varchar,varint)
            # note that "unknown" types do not have a lookahead context

            set inst_type $ctx_tag
            set inst_name $tag   ;# for inst_type=struct.slot => tag=struct.name => arg0=name
            set cmd [list with_mode {inst} {node} {inst} $inst_name -x-type $inst_type {*}$args]
            return [{*}${cmd}]  ;# uplevel $cmd

        }

    }

    proc {type_helper} {args} {::nest::lang::type[top_mode] {*}${args}}


    # container_helper
    #
    # INSTANTIATION EXAMPLE 1:
    # 
    #   multiple wordcount {{ 
    #       word "the"
    #       count "123"
    #   } {
    #   } { 
    #       word "and" 
    #       count "54" 
    #   }}
    #
    #
    # DECLARATION EXAMPLE 1 ( llength_args==1 && arg0 ne {struct} ):
    #   struct message {
    #     ...
    #     multiple word_count_pair wordcount
    #     ...
    #   }
    #
    # DECLARATION EXAMPLE 2 ( llength_args==2 && arg0 eq {struct} ):
    #   struct message {
    #     ...
    #     multiple struct wordcount { 
    #       varchar word
    #       varint count
    #     }
    #     ...
    #   }
    #
    #
    # DECLARATION EXAMPLE 3 ( llength_args==3 && arg0 ne {struct} ):
    #   struct message {
    #     ...
    #     multiple word_count_pair wordcount = {}
    #     ...
    #   }
    #
    # DECLARATION EXAMPLE 4 ( llength_args==4 && arg0 eq {struct} ):
    #   struct message {
    #     ...
    #     multiple struct wordcount = {} { 
    #       varchar word
    #       varint count
    #     }
    #     ...
    #   }
    #


    proc containerdecl {arg0 args} {
        set tag [top_fwd]

        log "!!! container DECLARATION"

        set args [lassign $args name]
        if { [lindex $args 0] eq {=} } {
            set args [lreplace $args 0 0 "-x-default_value"]
        }

        set node [$arg0 $name {*}$args]
        ${node} setAttribute x-container $tag
        return ${node}
    }

    proc containerinst {arg0 args} {
        set tag [top_fwd]

        log "!!! container INSTANTIATION"

        set args [lassign $args argvals]
        set arg0 [which $arg0]

        set nodes [list]
        lassign [get_lookahead_ctx $arg0] ctx_type ctx_tag ctx_name
        foreach argval $argvals {
            if {$ctx_type eq {nest}} {
                log "!!! container INSTANTIATION (ctx_type=nest) arg0=${arg0} argval=[list ${argval}]"
                set node [with_fwd $arg0 $arg0 $argval]
                ${node} setAttribute x-container $tag
            } else {
                log "!!! container INSTANTIATION (ctx_type=other i.e. not nest) arg0=${arg0} argval=[list ${argval}]"
                set node [with_fwd $arg0 type_helper {*}$argval]
                ${node} setAttribute x-container $tag
            }
            lappend nodes ${node}
        }
        return ${nodes}
    }

    proc {container_helper} {args} {::nest::lang::container[top_mode] {*}${args}}

    proc which {name} {

        set redirect_name [gen_eval_path ${name}]
        set redirect_exists_p [exists_alias $redirect_name]

        log "checking eval path for \"${name}\" -> ${redirect_name} ($redirect_exists_p)"

        if { $redirect_exists_p } {
            return $redirect_name
        } else {
            variable stack_ctx
            foreach ctx $stack_ctx {
                lassign $ctx ctx_type ctx_tag ctx_name
                set redirect_name "${ctx_name}.${name}"
                set redirect_exists_p [exists_alias $redirect_name]

                log "checking nest context name for \"${name}\" -> ${redirect_name} ($redirect_exists_p)"

                if { $redirect_exists_p } {
                    return $redirect_name
                } else {
                    set redirect_name "${ctx_tag}.${name}"
                    set redirect_exists_p [exists_alias $redirect_name]

                    log "checking nest context tag for \"${name}\" -> ${redirect_name} ($redirect_exists_p)"

                    if { $redirect_exists_p } {
                        return $redirect_name
                    }
                }

            }
        }

        return

    }

    proc unknown {arg0 args} {

        set redirect_name [which ${arg0}]

        if { $redirect_name ne {} } {

            log "+++ $arg0 $args -> redirect_name=${redirect_name}"

            if { ![exists_forward ${redirect_name}] } {
                log "redirect (=${redirect_name}) is an alias, i.e. no forward info"
            }

            return [${redirect_name} {*}${args}]  ;# uplevel
        }

        # check for types of the form pair<varchar,varint>
        # forced to do this to keep multiple ignorant of the
        # type it is given

        set last_char [string index ${arg0} end]
        if { $last_char eq {>} } {
            set index [string first {<} ${arg0}]
            set type [string range ${arg0} 0 [expr { ${index} - 1 }]]
            set rest [string range ${arg0} [expr { ${index} + 1 }] end-1]
            set redirect_name [concat ${type} [split ${rest} {,}]]

            # be blind about it
            set node [{*}${redirect_name} {*}${args}]  ;# uplevel
            return $node
        }


        error "no redirect found for [list $arg0] args=[list $args])"


    }

    namespace unknown unknown


    # basis of class/object methods

    nsp_alias {@} with_eval

    nsp_alias {dispatcher} {lambda} {id} {
        set_dispatcher ${id} "@${id}"
        alias "@${id}" {::nest::lang::@} ${id}
    }

    # class/object aliases, used in def of base_type and struct
    nsp_alias object nest {type_helper}
    nsp_alias class with_mode {decl} nest

    forward {base_type} {with_mode {inst} nest {type_helper}}

    forward {multiple} {container_helper}

    # a varying-length text string encoded using UTF-8 encoding
    base_type "varchar"

    # a boolean value (true or false)
    base_type "bool"

    # a varying-bit signed integer
    base_type "varint"

    # an 8-bit signed integer
    base_type "byte"

    # a 16-bit signed integer
    base_type "int16"

    # a 32-bit signed integer
    base_type "int32"

    # a 64-bit signed integer
    base_type "int64"

    # a 64-bit floating point number
    base_type "double"

    # timestamp/date
    # base_type "date"

    forward {generic_type} {lambda {forward_name params body nest} {
        forward ${forward_name} \
                [list {lambda} [lappend {params} {name}] \
                    [concat {nest} [list ${nest}] "\${name}" \
                        "\[subst -nocommands -nobackslashes [list ${body}]\]"]]
    }}

    # pair construct, equivalent to:
    #
    # => forward {pair} {lambda {typefirst typesecond name} {
    #        nest {type_helper} ${name} [subst -nocommands -nobackslashes {
    #            ${typefirst} {first} 
    #            ${typesecond} {second}
    #        }]
    #    }}

    generic_type {pair} {typefirst typesecond} {
        ${typefirst} {first}
        ${typesecond} {second}
    } {type_helper}

    meta {class} {class {nest type_helper}} {struct} {
        varchar id
        varchar name
        varchar type
        varchar nsp
        varchar default_value = ""

        multiple struct slot = {} {
            varchar id
            varchar name
            varchar type
            varchar default_value = ""
            bool optional_p = false
            varchar container = ""
        }

        varchar pk
        bool is_final_if_no_scope

    }

    struct {method} {
        varchar name
        multiple varchar param = {}
        varchar body
    }

    nsp_alias {fun} {lambda} {name params body} { 

        # overwrites the alias created by method
        alias [gen_eval_path ${name}] {::nest::lang::lambda} ${params} ${body}

        method ${name} \
            [concat name ${name} { ; } multiple param [list ${params}] { ; } body [list $body]]


    }



    namespace export "struct" "varchar" "bool" "varint" "byte" "int16" "int32" "int64" "double" "multiple"

} lang_doc

if { [::nest::debug::dom_p] } {
    puts [$lang_doc asXML]
}


define_lang ::nest::data {

    upvar ::nest::lang::dispatcher {}

    namespace import ::nest::lang::*
    namespace path [list ::nest::data ::nest::lang]
    namespace unknown ::nest::lang::unknown

}




