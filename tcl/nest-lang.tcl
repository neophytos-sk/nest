package require tdom

package provide nest 0.1

define_lang ::nest::lang {

    variable debug 1
    variable stack_ctx [list]
    variable stack_fwd [list]

    proc log {msg} {
        variable debug
        if {$debug} {
            puts $msg
        }
    }

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


    # =========
    # stack_ctx
    # =========
    #
    # EXAMPLE 1:
    #
    # struct typedecl {
    #     varchar name
    #     varchar type
    #     varchar default
    #     -> bool optional_p = false
    #     varchar container_type
    #     varchar subtype
    # }
    # 
    # stack_ctx = {proc base_type bool} {eval struct typedecl} {proc struct struct}
    #
    # EXAMPLE 2:
    # 
    # struct email {
    #   varchar name
    #   -> varchar address
    # }
    #
    # stack_ctx = {proc base_type varchar} {eval struct email} {proc struct struct}

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

    proc top_context_of_type {context_type} {
        variable stack_ctx
        set indexList 0 ;# match first element of nested list
        set index [lsearch -exact -index $indexList $stack_ctx $context_type]
        return [lindex $stack_ctx $index]
    }

    proc get_context_path_of_type {context_type} {
        variable stack_ctx
        set indexList 0 ;# match first element of nested list
        set contextList [lsearch -all -inline -exact -index $indexList $stack_ctx $context_type]
        set context_path ""
        foreach context [lreverse $contextList] {
            lassign $context context_type context_tag context_name
            append context_path $context_name "."
        }
        return [string trimright $context_path "."]
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


        set cmd [list [namespace which {node}] $tag $name -x-type $tag {*}$args]
        set node [uplevel $cmd]

        log "!!! nest: $name -> $nest"

        set decl_ctx [list {typedecl} $tag $name]
        set_lookahead_ctx $name $decl_ctx
        set nest [list with_ctx $decl_ctx {*}$nest]

        uplevel [list [namespace which "alias"] $name $nest]

        set nsp [uplevel {namespace current}]

        if { $tag ni {object base_type} } {

            $node appendFromScript {
                foreach typedecl [$node selectNodes {child::typedecl}] {
                    log "!!! nest: instantiate empty slot ${name}.[$typedecl @x-name]"
                    typeinst slot [$typedecl @x-name]
                }
                type $tag
                name $name
                nsp $nsp
            }

            foreach typeinst [$node selectNodes {child::typeinst[@x-type="slot"]}] {
                $typeinst delete
            }

            $node appendFromScript {
                foreach typedecl [$node selectNodes {child::typedecl}] {

                    log "!!! nest: instantiate full slot ${name}.[$typedecl @x-name]"

                    typeinst slot [$typedecl @x-name] [subst -nocommands -nobackslashes {
                        struct.slot.name [$typedecl @x-name]
                        struct.slot.type [$typedecl @x-type]
                        struct.slot.parent ${name}
                        if { [$typedecl hasAttribute "x-default_value"] } {
                            struct.slot.default_value [$typedecl @x-default_value ""]
                        }
                        if { [$typedecl hasAttribute "x-optional_p"] } {
                            struct.slot.optional_p [$typedecl @x-optional_p ""]
                        }
                        if { [$typedecl hasAttribute "x-container"] } {
                            struct.slot.container [$typedecl @x-container ""]
                        }
                    }]
                }

            }
        }
        return $node
    }


    #alias "shiftl" {lambda {_ args} {return $args}}
    #alias "chain" {lambda {args} {foreach arg $args {set args [{*}$arg {*}$args]}}}

    alias {object} {lambda {name nest args} {nest $nest $name {*}$args}}


    proc container_helper {arg0 args} {

        # remove {proc meta map} from the top of the context stack
        # and at the bottom, put it back so that it will be removed 
        # from whatever put it there
        set top_ctx [top_ctx]
        pop_ctx

        set container_type [top_fwd]

        set nodes [list]
        set llength_args [llength $args]


        if { $llength_args == 1 && $arg0 ne {struct} } {
            # we need to decide whether it is a declaration
            # or an instantiation
            #HERE
            if { ![is_declaration_mode_p] } {
                # (map | multiple) slot_name instantiation_script
                set instantiation_p 1
            } else {
                # (map | multiple) type slot_name
                set instantiation_p 0
            }
        } else {
            # all other acceptable cases are declarations
            if { $llength_args in {1 2 3 4} } {
                set instantiation_p 0
            } else {
                set usage_info ""
                append usage_info "\n\t * DECL: (map|multiple) type slot_name = default_value ?decl_script?"
                append usage_info "\n\t * DECL: (map|multiple) type slot_name"
                append usage_info "\n\t * INST: (map|multiple) slot_name inst_script"
                error "must be any of the following cases:${usage_info}"
            }
        }

        log "@@@@ (container_helper) llength_args=$llength_args instantiation_p=$instantiation_p"


        if { $instantiation_p } {

            # EXAMPLE:
            # 
            #   map wordcount {{ 
            #       word "the"
            #       count "123"
            #   } {
            #   } { 
            #       word "and" 
            #       count "54" 
            #   }}

            set name $arg0

            log "----- (container instantiation) name=[list $name] args=$args"

            set type $arg0
            set tag $type

            # does not play well with embedded structures
            set cmd [list $name]

            lassign $args argv
            foreach arg $argv {
                set node [uplevel $cmd [list $arg]]
                #log [$node asXML]
                lappend nodes $node
            }

        } else {

            # EXAMPLE 1 ( llength_args==1 && arg0 ne {struct} ):
            #   struct message {
            #     ...
            #     map word_count_pair wordcount
            #     ...
            #   }
            #
            # EXAMPLE 2 ( llength_args==2 && arg0 eq {struct} ):
            #   struct message {
            #     ...
            #     map struct wordcount { 
            #       varchar word
            #       varint count
            #     }
            #     ...
            #   }
            #
            #
            # EXAMPLE 3 ( llength_args==3 && arg0 ne {struct} ):
            #   struct message {
            #     ...
            #     map word_count_pair wordcount = {}
            #     ...
            #   }
            #
            # EXAMPLE 4 ( llength_args==4 && arg0 eq {struct} ):
            #   struct message {
            #     ...
            #     map struct wordcount = {} { 
            #       varchar word
            #       varint count
            #     }
            #     ...
            #   }
            #
            # EXAMPLE 5 (TODO):
            #   struct message {
            #     ...
            #     map pair "from_type to_type" wordcount = {}
            #     ...
            #   }
            #


            set type $arg0
            set tag $type
            set args [lassign $args name]

            set context [top_context_of_type "eval"]
            lassign $context context_type context_tag context_name

            log "++++++ (container declaration) tag=type=$type name=$name args=$args stack_ctx=$::nest::lang::stack_ctx context=$context"

            # arg0 = type
            if { [exists_lookahead_ctx $arg0] } {

                typedecl_args args
                set args [concat -x-container $container_type $args] 

                set cmd [list $arg0 $name {*}$args]
                set node [uplevel $cmd]
                lappend nodes $node

                if { $llength_args in {2 4} && $arg0 eq {struct} } {

                    # EXAMPLE 4:
                    # struct message {
                    #   map struct wordcount_X {
                    #     varchar word
                    #     varint count
                    #   }
                    # }
                    #
                    # DECL ABOVE WAS: struct wordcount_X_type {...}
                    # INST AGAIN NOW: wordcount_X_type wordcount_X 

                    # WE DO NOT KNOW HOW TO DEAL WITH THIS CASE WELL
                    # COME BACK LATER

                    #error "not handled properly yet"

                    #if { $name in {slot wordcount_X message.wordcount_X}} exit

                }

                log "llength_args=$llength_args args=$args cmd=$cmd"
                #log [[lindex $nodes end] asXML]


            } else {

                # context = {eval struct message}
                # lookahead_context of message = {proc struct message}
                # push a temporary context so that typedecl_helper gets it right
                set lookahead_ctx [get_lookahead_ctx $context_name]
                push_ctx $lookahead_ctx
                set cmd [list {typedecl} $type $name {*}$args]
                lappend nodes [with_fwd $tag uplevel $cmd]
                pop_ctx

            }

            if {0} {
                log "----- (container_helper) cmd=$type ${name} {*}$args"
                log [[lindex $nodes end] asXML]
            }
            

        }

        # push the {proc meta map} context back to the top of the context stack
        # as it were before we removed it in the beginning of this proc
        push_ctx $top_ctx

        return $nodes


    }

    object  "multiple" [namespace which "container_helper"]
    object  "map" [namespace which "container_helper"]

    proc typedecl_args {argsVar} {

        upvar $argsVar args

        # rewrite args of the form
        #   varchar device = "sms"
        # to
        #   varchar device -x-default_value "sms"

        if { [llength $args] && [lindex $args 0] eq {=} } {
            # we don't make any claims about the field being optional or not
            set args [concat -x-default_value [lrange $args 1 end]]
        }
    }

    proc typedecl_helper {decl_type decl_name args} {
        set decl_tag [top_fwd]

        typedecl_args args
        set cmd [list with_ctx [list {typedecl} $decl_type $decl_name] [namespace which {node}] {typedecl} $decl_name -x-type $decl_type {*}$args]
        set node [uplevel $cmd]

        set context_path [get_context_path_of_type "eval"]

        log "--->>> (typedecl_helper) context_path=[list $context_path] stack_ctx=[list $::nest::lang::stack_ctx]"

        if { ${context_path} ne {} } {
            set dotted_name "${context_path}.$decl_name"
        } else {
            set dotted_name ${decl_name}
        }

        # EXPERIMENTAL
        set_lookahead_ctx $dotted_name [list proc $decl_type $decl_name]

        set dotted_nest [list {typeinst} $decl_type $dotted_name]
        set dotted_nest [list with_ctx [list {typedecl} $decl_type $dotted_name] {*}$dotted_nest] 
        set cmd [list [namespace which "alias"] $dotted_name $dotted_nest]
        uplevel $cmd

        return $node

    }
    
    object {typedecl} [namespace which "typedecl_helper"]

    dom createNodeCmd textNode t

    proc nt {text} { t -disableOutputEscaping ${text} }

    proc typeinst_args {inst_type argsVar} {

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
            # i.e. the stack is {proc meta typeinst}
            #
            # message.subject "hello"
            # message.from { ... }
            #
            # so we check the lookahead_context for the upcoming command
            # we know already that typeinst_helper calls the given inst_type command

            set lookahead_ctx [get_lookahead_ctx $inst_type]
            lassign $lookahead_ctx lookahead_ctx_type lookahead_ctx_tag lookahead_ctx_name

            log "////// (typeinst_args) lookahead_ctx=$lookahead_ctx inst_type=$inst_type args=[list $args]"

            if { $lookahead_ctx_tag eq {base_type} } {
                set args [list [list ::nest::lang::t [lindex $args 0]]]
            }
        }
    }

    proc typeinst_helper {inst_type inst_name args} {
        set inst_tag [top_fwd]

        typeinst_args $inst_type args

        set context [top_context_of_type {typedecl}]
        set context_tag [lindex $context 1]
        set context_name [lindex $context 2]

        log "--->>> (typeinst_helper) inst_type=$inst_type inst_name=$inst_name context=[list $context] stack_ctx=[list $::nest::lang::stack_ctx]"
        
        set cmd [list with_ctx [list {typeinst} $inst_type $inst_name] [namespace which {node}] {typeinst} $inst_name -x-type $inst_type {*}$args]
        return [uplevel $cmd]

    }

    object  "typeinst" [namespace which "typeinst_helper"]

    proc is_dotted_p {name} {
        return [expr { [llength [split ${name} {.}]] > 1 }]
    }

    proc top_mode_ctx {} {
        variable stack_ctx
        set ctx [lsearch -inline -index 0 -not $stack_ctx "eval"]
    }

    proc is_declaration_mode_p {} {

        #log "--- check mode ctx: stack_ctx=$stack_ctx"

        set ctx [top_mode_ctx]
        lassign $ctx ctx_type ctx_tag ctx_name
        if { $ctx_tag eq {typedecl} } {
            return 1
        }

        return 0
    }

    proc type_helper {name args} {

        set tag [top_fwd]  ;# varchar nsp -> tag=varchar name=nsp

        log "--->>> (type_helper) $tag $name {*}$args"
        
        # ctx_type = (typedecl | typeinst)
        # tag = (varchar | bool | varint | ... | message)

        # TEMPORARY HACK, WE NEED TO INSPECT THE STATE
        # TO DECIDE WHETHER WE ARE DEALING WITH A
        # typeinst OR typedecl.
        #
        # FOR THE TIME BEING, IF IT HAS A SCRIPT/BODY
        # IT IS TREATED AS typeinst
        #
        set llength_args [llength $args]
        if { $llength_args % 2 == 1 } {
            set ctx_type {typeinst}
        } else {
            set ctx_type {typedecl}
        }
        set cmd [list $ctx_type $tag $name {*}$args]
        set node [uplevel $cmd]
        return $node
    }

    object  "base_type" {nest {type_helper}}

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

    object  "struct" {nest {nest {type_helper}}}

    proc unknown {field_type field_name args} {

        set stack_ctx $::nest::lang::stack_ctx
        set stack_ctx [lsearch -all -inline -index 0 $stack_ctx {typedecl}]

        log "--->>> (unknown) $field_type $field_name args=$args stack_ctx=[list $stack_ctx]"

        foreach ctx $stack_ctx {
            lassign $ctx ctx_type ctx_tag ctx_name
            set redirect_name "${ctx_name}.$field_type"
            set redirect_exists_p [[namespace which check_alias] $redirect_name]

            log "--->>> (unknown) checking each context for \"${field_type}\" -> ${redirect_name} ($redirect_exists_p)"

            if { 0 } {
                log "+++ stack_ctx=[list $::nest::lang::stack_ctx]"
                log "+++ info proc=[uplevel [list info proc $redirect_name]]"
                log "+++ alias=[array get ::nest::lang::alias]"
                log "+++ alias_exists_p=[[namespace which check_alias] $redirect_name]"
            }


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

        error "no redirect found for [list $field_type $field_name $args]"


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

            <!ELEMENT nest (struct | typedecl | typeinst)*>
            <!ELEMENT struct (struct | struct.slot | typedecl | typeinst)*>
            <!ATTLIST struct x-name CDATA #IMPLIED
                           x-type CDATA #REQUIRED
                           x-default_value CDATA #IMPLIED
                           x-container CDATA #IMPLIED>

            <!ELEMENT struct.slot (typedecl | typeinst)*>
            <!ATTLIST struct.slot x-name CDATA #IMPLIED
                           x-type CDATA #REQUIRED>

            <!ELEMENT typedecl (typedecl)*>
            <!ATTLIST typedecl x-name CDATA #REQUIRED
                           x-type CDATA #REQUIRED
                           x-default_value CDATA #IMPLIED
                           x-container CDATA #IMPLIED
                           name CDATA #IMPLIED
                           type CDATA #IMPLIED
                           nsp CDATA #IMPLIED
                           default_value CDATA #IMPLIED
                           optional_p CDATA #IMPLIED
                           container_type CDATA #IMPLIED>

            <!ELEMENT typeinst ANY>
            <!ATTLIST typeinst x-name CDATA #REQUIRED
                               x-type CDATA #REQUIRED
                               x-container CDATA #IMPLIED
                               x-map_p CDATA #IMPLIED
                               name CDATA #IMPLIED
                               type CDATA #IMPLIED>

        ]>
    }

    namespace export "struct" "varchar" "bool" "varint" "byte" "int16" "int32" "int64" "double" "multiple" "dtd" "lambda"

}

define_lang ::nest::data {
    namespace import ::nest::lang::*
    namespace path [list ::nest::data ::nest::lang ::]
    namespace unknown ::nest::lang::unknown
}



