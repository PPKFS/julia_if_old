macro do_while(condition, block)
    quote
        let
            $block
            while $condition
                $block
            end
        end
    end |> esc
end

function _reg(s, quoted_attr, attr_name)
    @eval begin
        #$get_attr_name(x)      = getattr( x, $quoted_attr)
        #$set_attr_name(x, val) = setattr!(x, $quoted_attr, val)
        #export $get_attr_name
        #export $set_attr_name
        $attr_name(o::Object) = get_attr(o, $quoted_attr)
        $attr_name(w::World, id::Symbol) = get_attr(w, id, $quoted_attr)
        $attr_name(o::Object, v::Any) = set_attr!(o, $quoted_attr, v)
        $attr_name(w::World, id::Symbol, v::Any) = set_attr!(w, id, $quoted_attr, v)
        $attr_name(w::World, o::Object) = $attr_name(o)
        $attr_name(w::World, o::Object, v::Any) = $attr_name(o, v)
        export $attr_name
    end
end

macro register_attribute(attr)
    #get_attr_name = Symbol("get_", attr)
    #set_attr_name = Symbol("set_", attr)
    attr_name = Symbol(attr)
    quoted_attr  = QuoteNode(attr)
    s = string(attr)
    _reg(s, quoted_attr, attr_name)
end
