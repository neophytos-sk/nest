package require tdom

package provide nest 0.7

define_lang ::nest::lang {

    variable debug 0
    variable stack_ctx [list]
    variable stack_fwd [list]

    array set lookahead_ctx [list]
    array set alias [list]

    proc log {msg} {
        variable debug
        if {$debug} {
            puts $msg
        }
    }

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
    proc check_alias {name} {
        variable alias
        info exists alias($name)
    }

    # Wow!!!
    set name "alias"
    set cmd [list [namespace which "lambda"] {name cmd} {
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

        set ctx [list {nest} $tag $name]
        set alias_name [get_eval_path $name]
        set_lookahead_ctx $alias_name $ctx ;# needed by container_helper and type_helper
        set nest [list with_ctx $ctx {*}$nest]
        uplevel [list [namespace which "alias"] $alias_name $nest]


        set cmd [list [namespace which {node}] $tag $name -x-mode {decl} -x-type $tag {*}$args]
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

            set decls [$node selectNodes {child::*[@x-mode="decl"]}]

            $node appendFromScript {
                foreach decl $decls {

                    log "!!! nest: instantiate full slot ${name}.[$decl @x-name]"

                    inst struct.slot [$decl @x-name] [subst -nocommands -nobackslashes {
                        struct.slot.name [$decl @x-name]
                        struct.slot.type [$decl @x-type]
                        struct.slot.parent $name ;# TODO: need full path to the parent
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

    proc inst_args {inst_type argsVar} {

        upvar $argsVar args

        # rewrite args of the form
        #   varchar body = "this is a test"
        # to
        #   varchar body { t "this is a test" }

        set llength_args [llength $args]
        if { $llength_args == 2 } {
            if { [lindex $args 0] eq {=} } {
                set args [list [list ::nest::lang::t [lindex $args 1]]]
            }
        } elseif { $llength_args == 1 } {

            # we don't know which of the following two cases we are in
            # and the stack does not have the context info for this call
            #
            # message.subject "hello"
            # message.from { ... }
            #
            # so we check the lookahead_context for the upcoming command
            # we know already that inst_helper calls the given inst_type command

            # note that "unknown" types (e.g. pair<varchar,varint> do not have a lookahead context
            if { [exists_lookahead_ctx $inst_type] } {
                set lookahead_ctx [get_lookahead_ctx $inst_type]
                lassign $lookahead_ctx lookahead_ctx_type lookahead_ctx_tag lookahead_ctx_name

                log "////// (inst_args) lookahead_ctx=$lookahead_ctx inst_type=$inst_type args=[list $args]"

                if { $lookahead_ctx_tag eq {base_type} } {
                    set args [list [list ::nest::lang::t [lindex $args 0]]]
                }
            }

        }
    }

    proc declaration_mode_p {} {
        variable stack_ctx

        set first_ctx [lindex $stack_ctx end] 
        if { $first_ctx eq {nest meta struct} || $first_ctx eq {eval meta struct} } {
            log "!!! DECLARATION MODE"
            return 1
        }
        log "!!! INSTANTIATION MODE"

        return 0
    }

    proc type_helper {args} {

        set tag [top_fwd]  ;# varchar nsp -> tag=varchar name=nsp

        log "!!! tag=$tag args=[list $args] stack_ctx=$::nest::lang::stack_ctx decl_p=[declaration_mode_p]"

        if { [declaration_mode_p] } {

            # deal with args and create dom node
            set args [lassign $args name]
            if { [lindex $args 0] eq {=} } {
                set args [lreplace $args 0 0 "-x-default_value"]
            }

            set decl_name $name
            set decl_type $tag

            set cmd [list [namespace which {node}] $decl_type $decl_name -x-mode {decl} -x-type $decl_type {*}$args]
            set node [uplevel $cmd]

            # get full alias name and register the alias
            set alias_name [get_eval_path $decl_name]
            set lookahead_ctx [list {nest} $decl_type $decl_name]
            set_lookahead_ctx $alias_name $lookahead_ctx

            set dotted_nest [list {inst} $decl_type $alias_name]
            set dotted_nest [list with_ctx $lookahead_ctx {*}$dotted_nest] 
            set cmd [list [namespace which "alias"] $alias_name $dotted_nest]
            uplevel $cmd

            log "--->>> (type_helper - declaration done) decl_type=$decl_type decl_name=$decl_name alias_name=$alias_name stack_ctx=[list $::nest::lang::stack_ctx]"


            return $node

        } else {

            set inst_name $tag
            if { [exists_lookahead_ctx $inst_name] } {
                lassign [get_lookahead_ctx $inst_name] ctx_type ctx_tag ctx_name
                set inst_type $ctx_tag

                if { $inst_type eq {base_type} } {

                    # message.subject "hello" 
                    # => tag=message.subject args={{hello}} 
                    # => inst_name=message.subject inst_type=base_type
                    
                    set args [lassign $args arg0]
                    if { $args ne {} } { error "something wrong with instantiation statement" }
                    set cmd [list [namespace which {node}] $ctx_tag $tag -x-mode {inst} -x-type $ctx_tag [list ::nest::lang::t $arg0]]
                    return [uplevel $cmd]

                }
            }

            # case for composite or "unknown" types (e.g. pair<varchar,varint)
            # note that "unknown" types do not have a lookahead context
            set cmd [list [namespace which {node}] $inst_type $inst_name -x-mode {inst} -x-type $inst_type {*}$args]
            return [uplevel $cmd]

        }

    }

    proc inst_helper {inst_type inst_name args} {
        set inst_tag [top_fwd]

        inst_args $inst_type args

        log "--->>> (inst_helper) inst_type=$inst_type inst_name=$inst_name stack_ctx=[list $::nest::lang::stack_ctx]"
        
        set cmd [list [namespace which {node}] {inst} $inst_name -x-type $inst_type {*}$args]
        return [uplevel $cmd]

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
        if {[declaration_mode_p]} {
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

        log "--->>> (unknown) $field_type $field_name args=$args stack_ctx=[list $stack_ctx]"

        foreach ctx $stack_ctx {
            lassign $ctx ctx_type ctx_tag ctx_name
            set redirect_name "${ctx_name}.$field_type"
            set redirect_exists_p [[namespace which check_alias] $redirect_name]

            log "--->>> (unknown) checking context for \"${field_type}\" -> ${redirect_name} ($redirect_exists_p)"

            if { $redirect_exists_p } {

                log "+++ $field_type $field_name $args -> redirect_name=$redirect_name"

                set unknown_ctx [list "unknown" "unknown" $redirect_name]
                set cmd [list $redirect_name $field_name {*}$args]
                with_ctx $unknown_ctx uplevel $cmd
                return
            } else {
                set redirect_name "${ctx_tag}.${field_type}"
                set redirect_exists_p [[namespace which check_alias] $redirect_name]
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
        set type_re {[_a-zA-Z][_a-zA-Z0-9]*}

        set re {}
        append re "(set|list)<(${type_re})>" "|"
        append re "(pair)<(${type_re}),(${type_re})>"

        set re "^(?:${re})\$"

        if { [regexp -- $re $field_type _dummy_ sm1 sm2 sm3 sm4 sm5] } {

            log "!!! regexp success: sm1=$sm1 sm2=$sm2 sm3=$sm3 sm4=$sm4 sm5=$sm5"

            if { $sm1 ne {} && $sm2 ne {} } {
                set redirect_name [list $sm1 $sm2]
            } elseif { $sm3 ne {} && $sm4 ne {} && $sm5 ne {} } {
                set redirect_name [list $sm3 $sm4 $sm5]
            }

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

    alias "dtd" [namespace which "dtd_helper"]

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
    alias {inst} {inst_helper}
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
    ## 
    ## => alias {pair} {lambda {typefirst typesecond name} {
    ##        nest {type_helper} ${name} [subst -nocommands -nobackslashes {
    ##            ${typefirst} {first} 
    ##            ${typesecond} {second}
    ##        }]
    ##    }}
    ##

    namespace export "struct" "varchar" "bool" "varint" "byte" "int16" "int32" "int64" "double" "multiple" "dtd" "lambda"

} lang_doc

puts [$lang_doc asXML]

define_lang ::nest::data {
    namespace import ::nest::lang::*
    namespace path [list ::nest::data ::nest::lang ::]
    namespace unknown ::nest::lang::unknown



}




