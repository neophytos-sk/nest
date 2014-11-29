package require tdom

package provide nest 0.8

define_lang ::nest::lang {

    namespace import ::nest::debug::* 

    variable stack_ctx [list]
    variable stack_fwd [list]
    variable stack_mode [list]

    array set lookahead_ctx [list]
    array set alias [list]

    proc push_fwd {name} {
        variable stack_fwd
        set stack_fwd [linsert $stack_fwd 0 $name]
    }
    proc pop_fwd {} {
        variable stack_fwd
        set stack_fwd [lreplace $stack_fwd 0 0]
    }
    proc top_fwd {} {
        variable stack_fwd
        lindex $stack_fwd 0
    }
    proc with_fwd {name args} {
        push_fwd $name
        set result [uplevel $args]
        pop_fwd
        return $result
    }

    proc push_mode {name} {
        variable stack_mode
        set stack_mode [linsert $stack_mode 0 $name]
    }
    proc pop_mode {} {
        variable stack_mode
        set stack_mode [lreplace $stack_mode 0 0]
    }
    proc top_mode {} {
        variable stack_mode
        lindex $stack_mode 0
    }
    proc with_mode {name args} {
        push_mode $name
        set result [uplevel $args]
        pop_mode
        return $result
    }



    # =========
    # stack_ctx
    # =========
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
    # stack_ctx = {nest base_type bool} {eval struct slot} {nest meta struct} {eval meta struct}
    #
    # EXAMPLE 2:
    # 
    # struct email {
    #   varchar name
    #   -> varchar address
    # }
    #
    # stack_ctx = {nest base_type varchar} {eval struct email} {nest meta struct}

    proc push_ctx {ctx} {
        variable stack_ctx
        set stack_ctx [linsert $stack_ctx 0 $ctx]
    }
    proc pop_ctx {} {
        variable stack_ctx
        set stack_ctx [lreplace $stack_ctx 0 0]
    }
    proc top_ctx {} { 
        variable stack_ctx
        lindex $stack_ctx 0
    }
    proc with_ctx {context args} {
        push_ctx $context
        set result [uplevel $args]
        pop_ctx
        return $result
    }

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

    # used to get the full alias name
    proc get_eval_path {name} {
        join [concat [get_context_path_of_type {eval} {context_name}] ${name}] {.}
    }

    # context := {context_type context_tag context_name}
    proc set_lookahead_ctx {name context} {
        variable lookahead_ctx
        set lookahead_ctx($name) $context
    }

    proc get_lookahead_ctx {name} {
        variable lookahead_ctx
        set lookahead_ctx($name)
    }

    proc exists_lookahead_ctx {name} {
        variable lookahead_ctx
        info exists lookahead_ctx($name)
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

    proc set_alias {name cmd} {
        variable alias
        set alias($name) "" ;# set alias($name) $cmd
    }
    proc get_alias {name} {
        variable alias
        set alias($name)
    }
    proc exists_alias {name} {
        variable alias
        info exists alias($name)
    }

    # Wow!!!
    set name "alias"
    set cmd [list {lambda} {name cmd} {
        set_alias $name $cmd
        interp alias {} [namespace current]::${name} {} [namespace which "with_fwd"] ${name} {*}${cmd}
        keyword ${name}
    }]
    {*}${cmd} "keyword" {::dom::createNodeCmd elementNode}
    {*}${cmd} ${name} ${cmd}
    # with_fwd alias lambda {name cmd} {
    #   set_alias $name $cmd
    #   interp alias {} [namespace current]::${name} {} [namespace which "with_fwd"] ${name} {*}${cmd}
    #   keyword ${name}
    # }


    alias {node} {lambda {tag name args} {with_ctx [list "eval" $tag $name] ::dom::execNodeCmd elementNode $tag -x-name $name {*}$args}}

    # nest argument holds nested calls in the procs below
    proc nest {nest name args} {
        set tag [top_fwd]
        keyword $name

        log "!!! nest: $name -> $nest"

        set alias_name [get_eval_path $name]
        if { [exists_alias $alias_name] } {
            error "alias $alias_name already exists"
        }

        set ctx [list {nest} $tag $name]
        set_lookahead_ctx $alias_name $ctx ;# needed by container_helper and type_helper
        set nest [list with_ctx $ctx {*}$nest]
        uplevel [list {alias} $alias_name $nest]

        set mode [lsearch -not -inline [list [top_mode] {decl}] {}]
        set cmd [list {node} $mode $name -x-type $tag {*}$args]
        set node [uplevel $cmd]

        #####
         
        # log [$node asXML]
        set nsp [uplevel {namespace current}]

        if { $tag ni {base_type} } {

            $node appendFromScript {
                struct.type $tag
                struct.name $name
                struct.nsp $nsp
            }

            set decls [$node selectNodes {child::decl}]
            $node appendFromScript {
                foreach decl $decls {

                    log "!!! nest: instantiate full slot ${name}.[$decl @x-name]"

                    with_mode {inst} struct.slot ${name}.__[$decl @x-name]__ [subst -nocommands -nobackslashes {
                        struct.slot.name [$decl @x-name]
                        struct.slot.type [$decl @x-type]
                        #struct.slot.parent [get_eval_path ""]
                        if { [$decl hasAttribute "x-default_value"] } {
                            struct.slot.default_value [$decl @x-default_value ""]
                        }
                        if { [$decl hasAttribute "x-optional_p"] } {
                            struct.slot.optional_p [$decl @x-optional_p ""]
                        }
                        if { [$decl hasAttribute "x-container"] } {
                            struct.slot.container [$decl @x-container ""]
                        }
                    }]
                }

            }
        }

        return $node

    }

    dom createNodeCmd textNode t

    proc nt {text} { t -disableOutputEscaping ${text} }

    proc decl_mode_p {} {
        variable stack_mode
        variable stack_ctx
        log "top_mode=[top_mode] stack_mode=[list $stack_mode] stack_ctx=[list $stack_ctx]"

        set mode [top_mode]
        return [expr { ${mode} ne {inst} }]
    }

    keyword {decl}
    keyword {inst}

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

            set cmd [list with_mode {decl} {node} {decl} $decl_name -x-type $decl_type -x-meta $ctx_tag {*}$args]
            set node [uplevel $cmd]

            # get full alias name and register the alias
            set alias_name [get_eval_path $decl_name]
            set lookahead_ctx [list {nest} $decl_type $decl_name]
            set_lookahead_ctx $alias_name $lookahead_ctx

            set dotted_nest [list with_mode {inst} $decl_type $alias_name]
            set dotted_nest [list with_ctx $lookahead_ctx {*}$dotted_nest] 
            set cmd [list {alias} $alias_name $dotted_nest]
            uplevel $cmd

            log "(declaration done) decl_type=$decl_type decl_name=$decl_name alias_name=$alias_name stack_ctx=[list $::nest::lang::stack_ctx]"


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
                set cmd [list with_mode {inst} {node} {inst} $inst_name -x-type $inst_type -x-meta $ctx_tag $inst_arg0]

                return [uplevel $cmd]

            } else {

                # case for composite or "unknown" types (e.g. pair<varchar,varint)
                # note that "unknown" types do not have a lookahead context

                set inst_type $ctx_tag
                set inst_name $tag   ;# for inst_type=struct.slot => tag=struct.name => arg0=name
                set cmd [list with_mode {inst} {node} {inst} $inst_name -x-type $inst_type -x-meta $ctx_tag {*}$args]
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
        if {[decl_mode_p]} {
            log "!!! container DECLARATION"
            set args [lassign $args name]
            if { [lindex $args 0] eq {=} } {
                set args [lreplace $args 0 0 "-default_value"]
            }
            [$arg0 $name {*}$args] setAttribute x-container [top_fwd]
        } else {
            log "!!! container INSTANTIATION"
            set args [lassign $args argvals]
            foreach argval $argvals {
                set lookahead_ctx [get_lookahead_ctx $arg0]
                lassign $lookahead_ctx ctx_type ctx_tag ctx_name
                if {$ctx_type eq {nest}} {
                    log "!!! container INSTANTIATION lookahead_ctx=[list $lookahead_ctx] arg0=${arg0} argval=[list ${argval}]"
                    [with_fwd $arg0 $arg0 $argval] setAttribute x-container [top_fwd]
                } else {
                    log "!!! container INSTANTIATION lookahead_ctx_type={other} (not nest) arg0=${arg0} argval=[list ${argval}]"
                    [with_fwd $arg0 type_helper {*}$argval] setAttribute x-container [top_fwd]
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
            set redirect_exists_p [exists_alias $redirect_name]

            log "checking context for \"${field_type}\" -> ${redirect_name} ($redirect_exists_p)"

            if { $redirect_exists_p } {

                log "+++ $field_type $field_name $args -> redirect_name=$redirect_name"

                set unknown_ctx [list "unknown" "unknown" $redirect_name]
                set cmd [list $redirect_name $field_name {*}$args]
                with_ctx $unknown_ctx uplevel $cmd
                return
            } else {
                set redirect_name "${ctx_tag}.${field_type}"
                set redirect_exists_p [exists_alias $redirect_name]
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

    alias {dtd} {dtd_helper}

    dtd {
        <!DOCTYPE nest [

            <!ELEMENT nest (struct | inst)*>
            <!ELEMENT struct (struct | struct.slot | inst)*>
            <!ATTLIST struct x-name CDATA #IMPLIED
                           x-type CDATA #REQUIRED
                           x-default_value CDATA #IMPLIED
                           x-container CDATA #IMPLIED>

            <!ELEMENT struct.slot (inst)*>
            <!ATTLIST struct.slot x-name CDATA #IMPLIED
                           x-type CDATA #REQUIRED>

            <!ELEMENT inst ANY>
            <!ATTLIST inst x-name CDATA #REQUIRED
                               x-type CDATA #REQUIRED
                               x-container CDATA #IMPLIED
                               x-map_p CDATA #IMPLIED
                               name CDATA #IMPLIED
                               type CDATA #IMPLIED>

        ]>
    }

    alias {base_type} {nest {type_helper}}
    alias {multiple} {container_helper}
    alias {meta} {lambda {metaCmd args} {{*}$metaCmd {*}$args}}

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

    alias {template} {lambda {alias_name params body nest} {
        alias ${alias_name} \
                [list {lambda} [lappend {params} {name}] \
                    [concat {nest} [list ${nest}] "\${name}" \
                        "\[subst -nocommands -nobackslashes [list ${body}]\]"]]
    }}

    template {pair} {typefirst typesecond} {
        ${typefirst} {first}
        ${typesecond} {second}
    } {type_helper}

    # => alias {pair} {lambda {typefirst typesecond name} {
    #        nest {type_helper} ${name} [subst -nocommands -nobackslashes {
    #            ${typefirst} {first} 
    #            ${typesecond} {second}
    #        }]
    #    }}


    meta {nest} {nest {with_mode {inst} nest {type_helper}}} {struct} {
        varchar name
        varchar type
        varchar nsp

        multiple struct slot = {} {
            varchar name
            varchar type
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




