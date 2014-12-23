package provide nest 1.5

define_lang ::nest::lang {

    namespace import ::nest::core::* 

    set nsp [namespace current]

    # forward is an alias that pushes its name to stack_fwd
    nsp_alias ${nsp} forward lambda {name args} {
        set_forward ${name} ${args}
        nsp_alias [namespace current] ${name} {::nest::core::with_fwd} ${name} {*}${args}
    }

    nsp_alias ${nsp} meta lambda {metaCmd args} {{*}$metaCmd {*}$args}
    forward keyword ::dom::createNodeCmd elementNode

    keyword node
    keyword decl
    keyword inst

    nsp_alias ${nsp} node lambda {mode name tag nest_p args} {
        set cmd [list with_eval ${name} interp_execNodeCmd_[get_option output_format] ${mode} ${name} ${tag} $nest_p [top_eval] {*}${args}]
        set node [uplevel ${cmd}]

        # if { $mode eq {decl} } {
        # init_node $node
        # }

        return $node
    }

    proc init_node {node} {
        $node appendFromScript {
            foreach attname [$node attributes] {
                set value [$node @$attname]
                set slotname [string range $attname 2 end]
                #struct.attribute.$attname $value
                #interp_execNodeCmd_[get_option output_format] inst $slotname "struct.attribute" nest_p [top_eval] { t $value }
            }
        }
    }

    # nest argument holds nested calls in the procs below
    proc nest {nest name args} {
        set tag [top_fwd]
        set id [gen_eval_name $name]
        set_typeof ${id} ${tag}

        # TODO: unify to use just one dispatcher for everything
        # forward ${id} [list @ ${id} ${nest}]
        if { [top_mode] eq {decl} } {

            set ctx [list ${tag} ${id}]
            set nest [list with_ctx ${ctx} {*}${nest}]
            {forward} ${id} {*}${nest}

        }

        # creates dispatcher alias for object/instance methods
        #
        # @${id}
        # => @ ${id}
        # => with_eval ${id}

        {dispatcher} ${id}

        set cmd [list {node} [top_mode] $name $tag true -x-id ${id} {*}$args]
        set node [uplevel ${cmd}]
        return $node

    }

    proc which {name} {

        # check self
        set redirect_name [gen_eval_name ${name}]
        set redirect_exists_p [exists_alias ${redirect_name}] 
        log "checking whether ${name} is $redirect_name (${redirect_exists_p})"
        if { ${redirect_exists_p} } {

            # CASE 1 (self)
            #
            # message msg1 {
            #     ...
            #     fun self(sayhi) {what} { ... }
            #     ...
            # }
            #
            # -> @ msg1 sayhi "world"

            return ${redirect_name}
        }

        # check type/tag of top eval
        if { [exists_typeof [eval_path]] } {
            set eval_ctx_name [eval_path]
            set eval_ctx_tag [get_typeof [eval_path]]
            set redirect_name ${eval_ctx_tag}.${name}
            set redirect_exists_p [exists_alias ${redirect_name}] 
            log "checking in ctx tag (=${eval_ctx_tag}) of top eval (=${eval_ctx_name})... $redirect_name (${redirect_exists_p})"
            if { ${redirect_exists_p} } {

                # CASE 2 (context of top eval)
                #
                # struct message {
                #     varchar subject
                #     ...
                # }
                #
                # message msg1 {
                # --> subject "hello world"
                #     ...
                # }
                #
                # => redirects to message.subject (see log notices below)
                #
                # (case 1) checking whether subject is msg1.subject (0)
                # (case 2) checking in ctx tag (=message) of top eval (=msg1)... message.subject (1)

                return ${redirect_name}
            }
        } else {
            log "did not check top eval (=[eval_path]) - no context info"
        }

        # check nest context
        lassign [top_ctx] ctx_tag ctx_name
        set redirect_name "${ctx_tag}.${name}"
        set redirect_exists_p [exists_alias ${redirect_name}] 
        log "checking in ctx tag (=${ctx_tag}) of parent nest (=${ctx_name})... $redirect_name (${redirect_exists_p})"
        if { [exists_alias ${redirect_name}] } {

            # CASE 3 (context of top nest)
            #
            # struct message {
            #     ...
            #     email from
            #     ...
            # }
            #
            # message msg1 {
            #     ...
            #     from {
            #        name "zena wow"
            #     -> address "zena@example.com"
            #     }
            #     ...
            # }
            #
            # => redirects to email.address (see log notices below)
            #
            # (case 1) checking whether address is msg1.message.from.address (0)
            # (case 2) did not check top eval (=msg1.message.from) - no context info
            # (case 3) checking in ctx tag (=email) of parent nest (=message.from)... email.address (1)

            return ${redirect_name}

        }

        # check for an embedded structure in parent nest, like the one that generic types produce
        set redirect_name ${ctx_name}.${name}
        set redirect_exists_p [exists_alias ${redirect_name}] 
        log "checking in parent nest (=${ctx_name})... $redirect_name (${redirect_exists_p})"
        if { ${redirect_exists_p} } {

            # CASE 4 (unknown types like pair<varchar,varint> embed a dom structure in ctx_name):
            #
            # struct message {
            #     ...
            #     multiple pair<varchar,varint> wordcount
            #     ...
            # }
            #
            # message msg1 {
            #     ...
            #     multiple wordcount {{
            #       first "hello"
            # ----> second "123"
            #     } { ... }}
            #     ...
            # }
            #
            # => redirects to message.wordcount.second (see log notices below)
            #
            # (case 1) checking whether second is msg1.message.wordcount.second (0)
            # (case 2) did not check top eval (=msg1.message.wordcount) - no context info
            # (case 3) checking in ctx tag (=pair) of parent nest (=message.wordcount)... pair.second (0)
            # (case 4) checking in parent nest (=message.wordcount)... message.wordcount.second (1)

            return ${redirect_name}
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

    ### HELPERS
 
    proc base_typedecl {args} {
        
        set tag [top_fwd]  ;# varchar nsp -> tag=varchar name=nsp

        # deal with args and create dom node
        set args [lassign $args arg0]
        if { [lindex $args 0] eq {=} } {
            set args [lreplace $args 0 0 "-x-default_value"]
        }

        set decl_type $tag
        set decl_name $arg0

        set cmd [list ::nest::core::with_mode {decl} {node} {decl} $decl_name $decl_type false {*}$args]
        set node [{*}${cmd}]  ;# uplevel $cmd

        # get full forward name and register the forward
        set forward_name [gen_eval_name $decl_name]
        set ctx [list $decl_type $decl_name]
        set dotted_nest [list ::nest::core::with_mode {inst} $decl_type $forward_name]
        set dotted_nest [list with_proxy [top_proxy] with_ctx $ctx {*}$dotted_nest] 
        {forward} $forward_name {*}$dotted_nest
        return $node
    }

    proc base_typeinst {args} {
        set tag [top_fwd]  ;# varchar nsp -> tag=varchar name=nsp

        # message.subject "hello" 
        # => inst_name=message.subject args={{hello}} 
        # => inst_name=message.subject inst_type=base_type
        
        set inst_type $tag
        set args [lassign $args inst_name inst_arg0]
        if { $args ne {} } { 
            error "something wrong with instantiation statement args=[list $args]"
        }
        set inst_arg0 [list ::nest::lang::interp_t $inst_arg0]
        set cmd [list ::nest::core::with_mode {inst} {node} {inst} ${inst_name} ${inst_type} false ${inst_arg0}]
        set node [uplevel ${cmd}]
        $node setAttribute x-id $inst_name
        return $node
    }

    # case for composite or "unknown" types (e.g. pair<varchar,varint)
    proc {object_typeinst} {args} {
        set tag [top_fwd]
        lassign [top_ctx] ctx_tag ctx_name
        set inst_type $ctx_tag
        set inst_name $tag   ;# for inst_type=struct.slot => tag=struct.name => arg0=name
        set cmd [list ::nest::core::with_mode {inst} {node} {inst} ${inst_name} ${inst_type} false {*}$args]
        set node [uplevel ${cmd}]
        $node setAttribute x-id $inst_name
        return $node
    }


    # DEPRECATED
    # nsp_alias ${nsp} {object_typedecl} {base_typedecl}

    # nsp_route {type} eval top_mode
    # nsp_route {object} eval top_mode
    proc {base_type} {args} {::nest::lang::base_type[top_mode] {*}${args}}
    proc {object_type} {args} {::nest::lang::object_type[top_mode] {*}${args}}



    # qualifier_helper
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


    proc qualifierdecl {attname attvalue arg0 args} {
        set args [lassign $args name]
        if { [lindex $args 0] eq {=} } {
            set args [lreplace $args 0 0 "-x-default_value"]
        }

        set node [$arg0 $name {*}$args]
        ${node} setAttribute x-$attname $attvalue
        return ${node}
    }

    proc qualifierinst {attname attvalue args} {
        set node [uplevel $args]
        ${node} setAttribute x-$attname $attvalue
        return ${node}
    }

    proc {qualifier_helper} {args} {::nest::lang::qualifier[top_mode] {*}${args}}


    # Containers
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

    proc {containerinst} {attname attvalue arg0 args} {
        set argvals [lindex $args end]
        set attributes [lrange $args 0 end-1]
        set arg0 [which $arg0]

        set nodes [list]
        foreach argval $argvals {
            set node [uplevel \
                [list {qualifierinst} ${attname} ${attvalue} ${arg0} {*}${attributes} ${argval}]]
            lappend nodes ${node}
        }
        return ${nodes}
    }

    nsp_alias ${nsp} {containerdecl} {qualifierdecl}

    proc {container_helper} {args} {::nest::lang::container[top_mode] {*}${args}}

    proc gen_shadow_name {name} { return _${name} }

    nsp_alias ${nsp} shadow_alias lambda {name args} {
        rename ${name} [gen_shadow_name ${name}]
        set cmd [list nsp_alias [namespace current] ${name} {*}${args}]
        uplevel ${cmd}
    }

    nsp_alias ${nsp} {shadow} {lambda} {name args} {
        set cmd [list [gen_shadow_name ${name}] {*}${args}]
        uplevel ${cmd}
    }

    ### THE LANGUAGE

    ## basis of class/object methods

    nsp_alias ${nsp} @ ::nest::core::with_eval

    nsp_alias ${nsp} dispatcher lambda {id} {
        set_dispatcher ${id} "@${id}"
        nsp_alias [namespace current] "@${id}" {@} ${id}
    }

    ## class/object aliases, used in def of base_type and struct
    nsp_alias ${nsp} object nest {object_type}
    nsp_alias ${nsp} class ::nest::core::with_mode {decl} {nest}

    ## qualifiers
    nsp_alias ${nsp} {multiple} container_helper container multiple
    nsp_alias ${nsp} {optional} qualifier_helper optional_p true
    nsp_alias ${nsp} {required} qualifier_helper optional_p false
    nsp_alias ${nsp} {xor} qualifier_helper xor
    nsp_alias ${nsp} {private} qualifier_helper access private

    ## Generic Types

    forward {generic_type} {lambda} {forward_name params body nest} {
        forward ${forward_name} {lambda} \
            [lappend {params} {name}] \
                [concat {nest} [list ${nest}] "\${name}" [list ${body}]]
    }

    # pair construct, equivalent to:
    #
    # => forward {pair} {lambda {typefirst typesecond name} {
    #        nest {base_type} ${name} {
    #            ${typefirst} {first} 
    #            ${typesecond} {second}
    #        }
    #    }}

    generic_type {pair} {typefirst typesecond} {
        ${typefirst} {first}
        ${typesecond} {second}
    } {object_type}


    keyword code
    forward {code} {lambda} {script} {
        ::dom::execNodeCmd elementNode code { ::nest::lang::t $script }
        uplevel $script
    }

    meta {class} {class {object}} {struct} {
    

        multiple nest base_type attribute {

            required struct.attribute x-id
            required struct.attribute x-tag
            required struct.attribute x-name
            optional struct.attribute x-proxy

            optional struct.attribute x-default_value = {}
            optional struct.attribute x-optional_p
            optional struct.attribute x-container

        }

        multiple struct proxy {
            attribute target
            attribute name
        }

        code {
            rename struct.proxy struct._proxy

            nsp_alias [namespace current] {struct.proxy} {lambda} {name target} {
                with_fwd proxy nest [list with_proxy [gen_eval_name ${name}] ${target}] ${name} {
                    struct.proxy.name $name
                    struct.proxy.target $target
                }
            }
        }

        # a varying-length text string encoded using UTF-8 encoding
        proxy "varchar" struct.attribute

        # a boolean value (true or false)
        proxy "bool" struct.attribute

        # a varying-bit signed integer
        proxy "varint" struct.attribute

        # date timestamp
        proxy "date" struct.attribute

        # an 8-bit signed integer
        proxy "byte" struct.attribute

        # a 16-bit signed integer
        proxy "int16" struct.attribute

        # a 32-bit signed integer
        proxy "int32" struct.attribute

        # a 64-bit signed integer
        proxy "int64" struct.attribute

        # a 64-bit floating point number
        proxy "double" struct.attribute

        # Without a quantifier, the name does not exist
        # as far as "which" is concerned (TODO), except
        # within the scope of the block it was defined.

        required varchar x-id
        required varchar x-name
        required varchar x-tag
        optional varchar x-proxy

        optional varchar pk
        optional varchar is_final_if_no_scope

    }

    struct {fun} {
        varchar name
        multiple varchar param = {}
        varchar body
    }

    shadow_alias {fun} {lambda} {fun_name fun_params fun_body} {

        nsp_alias [namespace current] [gen_eval_name ${fun_name}] {lambda} ${fun_params} ${fun_body}

        # must be last so that it returns the dom node
        # otherwise, we would have to keep the resulting 
        # node in a variable and return it at the end

        ::nest::core::with_mode {inst} shadow fun ${fun_name} {
            name ${fun_name}
            multiple param ${fun_params}
            body ${fun_body}
        }

    }

    namespace export "struct"

} lang_doc

if { [::nest::debug::dom_p] } {
    puts [$lang_doc asXML]
}

define_lang ::nest::data {

    upvar ::nest::core::dispatcher {}

    namespace import ::nest::lang::*
    namespace path [list ::nest::data ::nest::lang]
    namespace unknown ::nest::lang::unknown

}




