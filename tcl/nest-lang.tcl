package require tdom

package provide nest 0.9

define_lang ::nest::lang {

    namespace import ::nest::debug::* 

    variable stack_ctx [list]
    variable stack_fwd [list]
    variable stack_mode [list]

    array set alias [list]
    array set forward [list]
    array set lookahead_ctx [list]

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
    # stack_ctx = {nest base_type bool} {eval decl slot} {nest meta struct} {eval decl struct}
    #
    # EXAMPLE 2:
    # 
    # struct email {
    #   varchar name
    #   -> varchar address
    # }
    #
    # stack_ctx = {nest base_type varchar} {eval decl email} {nest meta struct}

    proc get_context_path_of_type {context_type varname} {
        variable stack_ctx
        set indexList 0 ;# match first element of nested list
        set contextList [lsearch -all -inline -exact -index $indexList $stack_ctx $context_type]
        set context_path ""
        foreach context [lreverse $contextList] {
            lassign $context context_type context_tag context_name
            append context_path [set $varname] "."
        }
        return [string trimright $context_path "."]
    }

    # used to get the full forward name
    proc get_eval_path {name} {
        join [concat [get_context_path_of_type {eval} {context_name}] ${name}] {.}
    }

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


    # Wow!!!
    set {name} {::nest::lang::alias}
    set {cmd} [list {::nest::lang::lambda} {name args} {
        {interp} {alias} {} ${name} {} {*}${args}
        {set_alias} ${name} ${args}
    }]
    {*}${cmd} {set_alias} ::nest::lang::array_setter alias
    {*}${cmd} ${name} {*}${cmd}

    foreach {name cmd} {
        {get_alias} {getter alias}
        {exists_alias} {array_exister alias}

        {set_forward} {array_setter forward}
        {get_forward} {array_getter forward}
        {exists_forward} {array_exister forward}

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
    } {
        set name "[namespace current]::${name}"
        set cmd "::nest::lang::${cmd}"
        alias ${name} {*}[join ${cmd} { }]
    }

    # forward is an alias that pushes its name to stack_fwd
    {alias} {forward} {::nest::lang::lambda} {name cmd} {
        {set_forward} ${name} ${cmd}
        {alias} ${name} {::nest::lang::with_fwd} ${name} {*}${cmd}
    }

    forward {keyword} {::dom::createNodeCmd elementNode}

    keyword {decl}
    keyword {inst}

    forward {node} {lambda {tag name args} {with_ctx [list "eval" $tag $name] ::dom::execNodeCmd elementNode $tag -x-name $name {*}$args}}

    # nest argument holds nested calls in the procs below
    proc nest {nest name args} {
        set tag [top_fwd]

        log "!!! nest: $name -> $nest"

        if { $name ne {} } {
            set forward_name [get_eval_path $name]
            if { [exists_forward $forward_name] } {
                error "forward $forward_name already exists"
            }

            set ctx [list {nest} $tag $name]
            set_lookahead_ctx $forward_name $ctx ;# needed by container_helper and type_helper
            set nest [list with_ctx $ctx {*}$nest]
            uplevel [list {forward} $forward_name $nest]
        }

        set cmd [list {node} [top_mode] $name -x-type $tag {*}$args]
        set node [uplevel $cmd]

        #####
         
        # log [$node asXML]
        set nsp [uplevel {namespace current}]

        if { $tag ni {base_type} } {

            # $node appendFromScript {
            #     struct.type [$node @x-type] ;# $tag
            #     struct.name [$node @x-name] ;# $name
            #     struct.nsp  [$node @x-nsp]  ;# $nsp
            # }
            init_slots $node {struct}

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
                $decl setAttribute x-meta {struct.slot}
            }

            $node setAttribute x-meta {struct}

        }

        return $node

    }

    proc init_slots {node struct} {
        foreach attname [$node attributes] {
            set identifier [string range [set attname] 2 end]
            ${struct}.[set identifier] [$node @[set attname]]
        }
    }


    dom createNodeCmd textNode t

    proc nt {text} { t -disableOutputEscaping ${text} }

    proc decl_mode_p {} {
        variable stack_mode
        variable stack_ctx
        log "top_mode=[top_mode] stack_mode=[list $stack_mode] stack_ctx=[list $stack_ctx]"

        return [expr { [top_mode] ne {inst} }]
    }

    proc type_helper {args} {

        set tag [top_fwd]  ;# varchar nsp -> tag=varchar name=nsp
        lassign [top_ctx] ctx_type ctx_tag ctx_name

        if { [decl_mode_p] } {

            # deal with args and create dom node
            set args [lassign $args arg0]
            if { [lindex $args 0] eq {=} } {
                set args [lreplace $args 0 0 "-x-default_value"]
            }

            set decl_type $tag
            set decl_name $arg0

            set cmd [list with_mode {decl} {node} {decl} $decl_name -x-type $decl_type {*}$args]
            set node [uplevel $cmd]

            # get full forward name and register the forward
            set forward_name [get_eval_path $decl_name]
            set lookahead_ctx [list {nest} $decl_type $decl_name]
            set_lookahead_ctx $forward_name $lookahead_ctx

            set dotted_nest [list with_mode {inst} $decl_type $forward_name]
            set dotted_nest [list with_ctx $lookahead_ctx {*}$dotted_nest] 
            set cmd [list {forward} $forward_name $dotted_nest]
            uplevel $cmd

            log "(declaration done) decl_type=$decl_type decl_name=$decl_name forward_name=$forward_name stack_ctx=[list $::nest::lang::stack_ctx]"


            return $node

        } else {

            if { $ctx_tag eq {base_type} } {

                # message.subject "hello" 
                # => inst_name=message.subject args={{hello}} 
                # => inst_name=message.subject inst_type=base_type
                
                set inst_type $tag
                set args [lassign $args inst_name inst_arg0]

                if { $args ne {} } { 
                    error "something wrong with instantiation statement args=[list $args]"
                }

                set inst_arg0 [list ::nest::lang::t $inst_arg0]
                set cmd [list with_mode {inst} {node} {inst} $inst_name -x-type $inst_type $inst_arg0]

                return [uplevel $cmd]

            } else {

                # case for composite or "unknown" types (e.g. pair<varchar,varint)
                # note that "unknown" types do not have a lookahead context

                set inst_type $ctx_tag
                set inst_name $tag   ;# for inst_type=struct.slot => tag=struct.name => arg0=name
                set cmd [list with_mode {inst} {node} {inst} $inst_name -x-type $inst_type {*}$args]
                return [uplevel $cmd]

            }

        }

    }

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

    proc container_helper {arg0 args} {
        set tag [top_fwd]
        if {[decl_mode_p]} {
            log "!!! container DECLARATION"
            set args [lassign $args name]
            if { [lindex $args 0] eq {=} } {
                set args [lreplace $args 0 0 "-x-default_value"]
            }
            [$arg0 $name {*}$args] setAttribute x-container $tag
        } else {
            log "!!! container INSTANTIATION"
            set args [lassign $args argvals]
            foreach argval $argvals {
                set lookahead_ctx [get_lookahead_ctx $arg0]
                lassign $lookahead_ctx ctx_type ctx_tag ctx_name
                if {$ctx_type eq {nest}} {
                    log "!!! container INSTANTIATION lookahead_ctx=[list $lookahead_ctx] arg0=${arg0} argval=[list ${argval}]"
                    [with_fwd $arg0 $arg0 $argval] setAttribute x-container $tag
                } else {
                    log "!!! container INSTANTIATION lookahead_ctx_type={other} (not nest) arg0=${arg0} argval=[list ${argval}]"
                    [with_fwd $arg0 type_helper {*}$argval] setAttribute x-container $tag
                }
            }
        }
    }

    proc unknown {field_type field_name args} {

        variable stack_ctx
        set stack_ctx [lsearch -all -inline -index 0 $stack_ctx {nest}]

        log "$field_type $field_name args=$args stack_ctx=[list $stack_ctx]"

        foreach ctx $stack_ctx {
            lassign $ctx ctx_type ctx_tag ctx_name
            set redirect_name "${ctx_name}.$field_type"
            set redirect_exists_p [exists_forward $redirect_name]

            log "checking context for \"${field_type}\" -> ${redirect_name} ($redirect_exists_p)"

            if { $redirect_exists_p } {

                log "+++ $field_type $field_name $args -> redirect_name=$redirect_name"

                set unknown_ctx [list "unknown" "unknown" $redirect_name]
                set cmd [list $redirect_name $field_name {*}$args]
                with_ctx $unknown_ctx uplevel $cmd
                return
            } else {
                set redirect_name "${ctx_tag}.${field_type}"
                set redirect_exists_p [exists_forward $redirect_name]
                if { $redirect_exists_p } {
                    log "+++ $field_type $field_name $args -> redirect_name=$redirect_name"
                    set cmd [list $redirect_name $field_name {*}$args]
                    with_ctx [list "unknown" "unknown" $redirect_name] uplevel $cmd
                    return
                }
            }
        }

        # check for types of the form pair<varchar,varint>
        # forced to do this to keep multiple ignorant of the
        # type it is given

        set last_char [string index $field_type end]
        if { $last_char eq {>} } {
            set index [string first {<} $field_type]
            set type [string range $field_type 0 [expr { ${index} - 1 }]]
            set rest [string range $field_type [expr { ${index} + 1 }] end-1]
            set redirect_name [concat $type [split $rest {,}]]

            # be blind about it
            set cmd [list {*}$redirect_name $field_name {*}$args]
            set node [with_ctx [list "unknown" "unknown" $redirect_name] uplevel $cmd]
            return $node
        }


        error "no redirect found for [list $field_type] (field_name=$field_name args=[list $args])"


    }

    namespace unknown unknown

    variable dtd
    proc dtd_helper {args} {
        variable dtd
        if { $args eq {} } {
            return $dtd
        } else {
            set dtd [lindex $args 0]
        }
    }

    forward {dtd} {dtd_helper}

    dtd {
        <!DOCTYPE nest [

            <!ELEMENT nest (struct | inst)*>
            <!ELEMENT struct (struct | struct.slot | inst)*>
            <!ATTLIST struct x-name CDATA #IMPLIED
                           x-type CDATA #REQUIRED
                           x-meta CDATA #REQUIRED
                           x-default_value CDATA #IMPLIED
                           x-container CDATA #IMPLIED>

            <!ELEMENT struct.slot (inst)*>
            <!ATTLIST struct.slot x-name CDATA #IMPLIED
                           x-type CDATA #REQUIRED
                           x-meta CDATA #REQUIRED>

            <!ELEMENT inst ANY>
            <!ATTLIST inst x-name CDATA #REQUIRED
                               x-type CDATA #REQUIRED
                               x-container CDATA #IMPLIED
                               x-map_p CDATA #IMPLIED
                               name CDATA #IMPLIED
                               type CDATA #IMPLIED>

        ]>
    }

    alias ::nest::lang::object ::nest::lang::with_mode {inst} nest {type_helper}
    alias ::nest::lang::class ::nest::lang::with_mode {decl} nest

    forward {base_type} {object}
    forward {multiple} {container_helper}
    forward {meta} {lambda {metaCmd args} {{*}$metaCmd {*}$args}}

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

    forward {template} {lambda {forward_name params body nest} {
        forward ${forward_name} \
                [list {lambda} [lappend {params} {name}] \
                    [concat {nest} [list ${nest}] "\${name}" \
                        "\[subst -nocommands -nobackslashes [list ${body}]\]"]]
    }}

    template {pair} {typefirst typesecond} {
        ${typefirst} {first}
        ${typesecond} {second}
    } {type_helper}

    # => forward {pair} {lambda {typefirst typesecond name} {
    #        nest {type_helper} ${name} [subst -nocommands -nobackslashes {
    #            ${typefirst} {first} 
    #            ${typesecond} {second}
    #        }]
    #    }}


    # meta {with_mode {decl} nest} {with_mode {decl} nest {type}} {struct}
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


    namespace export "struct" "varchar" "bool" "varint" "byte" "int16" "int32" "int64" "double" "multiple" "dtd" "lambda"

} lang_doc

puts [$lang_doc asXML]

define_lang ::nest::data {
    namespace import ::nest::lang::*
    namespace path [list ::nest::data ::nest::lang ::]
    namespace unknown ::nest::lang::unknown



}




