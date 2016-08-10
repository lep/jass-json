library Json initializer init

globals
    private string array state_help
endglobals


interface JsonValue
    method encode takes nothing returns string
endinterface

private keyword JsonNull

globals
    private hashtable ht
    public JsonValue Null
endglobals


private function jsondestroy takes JsonValue v returns nothing
    if v.getType() != JsonNull.typeid then
        call v.destroy()
    endif
endfunction



private struct JsonNull extends JsonValue
    method encode takes nothing returns string
        return "null"
    endmethod

    method onDestroy takes nothing returns nothing
        call BJDebugMsg("You are destroying Json_Null. Don't do that.")
    endmethod
endstruct

struct JsonBool extends JsonValue
    boolean value
    static method create takes boolean b returns thistype
        local thistype this = allocate()
        set .value = b
        return this
    endmethod

    method encode takes nothing returns string
        if value then
            return "true"
        else
            return "false"
        endif
    endmethod
endstruct

struct JsonString extends JsonValue
    string value

    static method create takes string s returns thistype
        local thistype this = allocate()
        set .value = s
        return this
    endmethod

    method encode takes nothing returns string
        local integer idx = 0
        local integer length = StringLength(.value)
        local string accum = "\""
        local string c
        loop
        exitwhen idx == length
            set c = SubString(.value, idx, idx+1)
            
            if c == "\"" then
                set accum = accum + "\\\""
            elseif c == "\\" then
                set accum = accum + "\\\\"
            else
                set accum = accum + c
            endif
            set idx = idx +1
        endloop
        return accum + "\""
    endmethod
endstruct

struct JsonInt extends JsonValue
    integer value

    static method create takes integer i returns thistype
        local thistype this = allocate()
        set .value = i
        return this
    endmethod

    method encode takes nothing returns string
        return I2S(.value)
    endmethod
endstruct

struct JsonReal extends JsonValue
    real value

    static method create takes real r returns thistype
        local thistype this = allocate()
        set .value = r
        return this
    endmethod

    method encode takes nothing returns string
        return R2S(.value)
    endmethod
endstruct

struct JsonArray extends JsonValue
    readonly integer length = 0

    method operator []= takes integer k, JsonValue v returns nothing
        if k >= .length then
            set .length = k+1
        endif
        call SaveInteger(ht, integer(this), k, integer(v))
    endmethod

    method operator [] takes integer k returns JsonValue
        local JsonValue ret = JsonValue(LoadInteger(ht, integer(this), k))
        if integer(ret) == 0 then
            return Null
        else
            return ret
        endif
    endmethod

    method onDestroy takes nothing returns nothing
        local integer i = 0
        loop
        exitwhen i == .length
            call jsondestroy(this[i])
            set i = i+1
        endloop
        call FlushChildHashtable(ht, integer(this))
    endmethod

    method encode takes nothing returns string
        local integer i = 0
        local string accum = "["
        loop
        exitwhen i == .length
            if i != 0 then
                set accum = accum + ","
            endif
            set accum = accum + this[i].encode()
            set i = i+1
        endloop
        return accum + "]"
    endmethod
endstruct

private struct List
    string key
    JsonValue value
    List tail
    
    static method create takes string k, JsonValue v, List tail returns thistype
        local thistype this = allocate()
        set .tail = tail
        set .key = k
        set .value = v
        return this
    endmethod
    
    method onDestroy takes nothing returns nothing
        call jsondestroy(.value)
        if .tail != 0 then
            call .tail.destroy()
        endif
	endmethod
endstruct

struct JsonHash extends JsonValue
    List head = 0

    method operator []= takes string k, JsonValue v returns nothing
        local List l = LoadInteger(ht, integer(this), StringHash(k))
        if integer(l) == 0 then
            set .head = List.create(k, v, head)
        else
            loop
            exitwhen l == 0
                if l.key == k then
                    set l.value = v
                    return
                endif
                set l = l.tail
            endloop
            set .head = List.create(k, v, .head)
        endif
        call SaveInteger(ht, integer(this), StringHash(k), .head)
    endmethod

    method operator [] takes string k returns JsonValue
        local List l = LoadInteger(ht, integer(this), StringHash(k))
        if integer(l) == 0 then
            return Null
        else
            loop
            exitwhen l == 0
                if l.key == k then
                    return l.value
                endif
                set l = l.tail
            endloop
            return Null
        endif
    endmethod

    method onDestroy takes nothing returns nothing
        call head.destroy()
        call FlushChildHashtable(ht, integer(this))
    endmethod


    method encode takes nothing returns string
        local List it = head
        local boolean after_first = false
        local string accum = "{"
        local JsonString tmp = JsonString.create("")
        loop
        exitwhen it == 0
            if not after_first then
                set after_first = true
            else
                set accum = accum + ","
            endif
            set tmp.value = it.key
            set accum = accum + tmp.encode() +":"+ it.value.encode()
            
            set it = it.tail
        endloop
        call tmp.destroy()
        return accum + "}"
    endmethod
    
endstruct



private function error takes string s, integer idx returns nothing
    local integer i
    call BJDebugMsg("JsonError: "+ s +" at offset "+ I2S(idx))
    set i = 1/0
endfunction

//! textmacro json__advance takes errmsg
    if not (idx+1 < length) then
        call error("$errmsg$", idx)
    endif
    set idx=idx+1
    set c = SubString(s, idx, idx+1)
//! endtextmacro


//! textmacro json__slurpWhitespace
    loop
    exitwhen idx >= length
    exitwhen c != " " and c != "\t" and c != "\n"

    set idx=idx+1
    set c = SubString(s, idx, idx+1)
	endloop
//! endtextmacro

//! textmacro json_insertSimpleValue
    if state_stack[state_idx] == ARRAY_START or state_stack[state_idx] == ARRAY_COMMA_ENCOUNTERED then
        set JsonArray(json_stack[json_idx])[JsonArray(json_stack[json_idx]).length] = json_stack[json_idx+1]
        set state_stack[state_idx] = ARRAY_VALUE_ENCOUNTERED
        
    elseif state_stack[state_idx] == HASH_COLON_ENCOUNTERED then
        set JsonHash(json_stack[json_idx])[hashkey] = json_stack[json_idx+1]
        set state_stack[state_idx] = HASH_VALUE_ENCOUNTERED
        
    endif
//! endtextmacro

globals
    private key HASH_START
    private key HASH_KEY_ENCOUNTERED
    private key HASH_VALUE_ENCOUNTERED
    private key HASH_COLON_ENCOUNTERED
    private key HASH_COMMA_ENCOUNTERED

    private key ARRAY_START
    private key ARRAY_COMMA_ENCOUNTERED
    private key ARRAY_VALUE_ENCOUNTERED
endglobals

function decodeJson takes string s returns JsonValue
    local integer length = StringLength(s)
    local integer idx = 0

    local integer stringStart

    local string c
    local string buffer
    local string hashkey

    local JsonValue array json_stack
    local integer json_idx = -1

    local integer array state_stack
    local integer state_idx = -1

    loop
    exitwhen idx >= length
    set c = SubString(s, idx, idx+1)
    //! runtextmacro json__slurpWhitespace()
    exitwhen idx >= length
        
        if c == "\"" then
            //! runtextmacro json__advance("quote at the end of input")
            set stringStart = idx
            
            if not (state_stack[state_idx] == ARRAY_START or state_stack[state_idx] == ARRAY_COMMA_ENCOUNTERED /*
                */ or state_stack[state_idx] == HASH_START or state_stack[state_idx] == HASH_COMMA_ENCOUNTERED /*
                */ or state_stack[state_idx] == HASH_COLON_ENCOUNTERED) then
                call error("Unexpected string", idx)
            endif
            
            set buffer = ""
            loop
            exitwhen idx >= length
            exitwhen c == "\""
            
                if c == "\\" then
                    set buffer = buffer + SubString(s, stringStart, idx)
                    //! runtextmacro json__advance("\\ at the end of input")
                    set stringStart = idx

                    if c=="\\" then
                        set buffer = buffer +"\\"
                    elseif c=="b" then
                        set buffer = buffer +"\b"
                    elseif c=="t" then
                        set buffer = buffer +"\t"
                    elseif c=="r" then
                        set buffer = buffer +"\r"
                    elseif c=="n" then
                        set buffer = buffer +"\n"
                    elseif c=="\"" then
                        set buffer = buffer +"\""
                    else
                        call error("Unknown escape sequence '\\"+ c +"'.", idx)
                    endif
                endif
                
            set idx=idx+1
            set c = SubString(s, idx, idx+1)
            endloop
            
            set buffer = buffer + SubString(s, stringStart, idx)
            
            if state_stack[state_idx] == HASH_START or state_stack[state_idx] == HASH_COMMA_ENCOUNTERED then
                set hashkey = buffer
                set state_stack[state_idx] = HASH_KEY_ENCOUNTERED
            else
                set json_stack[json_idx+1] = JsonString.create(buffer)
                //! runtextmacro json_insertSimpleValue()
            endif
            
            set idx=idx+1
        elseif c == "[" then
            //! runtextmacro json__advance("[ at the end of input")

            set json_stack[json_idx+1] = JsonArray.create()
            
            if state_stack[state_idx] == ARRAY_START or state_stack[state_idx] == ARRAY_COMMA_ENCOUNTERED then
                set JsonArray(json_stack[json_idx])[JsonArray(json_stack[json_idx]).length] = json_stack[json_idx+1]
            endif
            
            
            set json_idx = json_idx +1
            
            set state_idx = state_idx +1
            set state_stack[state_idx] = ARRAY_START

        elseif c == "{" then
            //! runtextmacro json__advance("{ at the end of input")
            
            set json_stack[json_idx+1] = JsonHash.create()
            
            if state_stack[state_idx] == ARRAY_START or state_stack[state_idx] == ARRAY_COMMA_ENCOUNTERED then
                set JsonArray(json_stack[json_idx])[JsonArray(json_stack[json_idx]).length] = json_stack[json_idx+1]
            endif
            
            set json_idx = json_idx +1
            
            set state_idx = state_idx +1
            set state_stack[state_idx] = HASH_START
        
        elseif c == "," then
            //! runtextmacro json__advance(", at the end of input")
            
            if state_stack[state_idx] == ARRAY_VALUE_ENCOUNTERED then
                set state_stack[state_idx] = ARRAY_COMMA_ENCOUNTERED
                
            elseif state_stack[state_idx] == HASH_VALUE_ENCOUNTERED then
                set state_stack[state_idx] = HASH_COMMA_ENCOUNTERED
                
            else
                call error("Unexpected ','.", idx)
            endif

        elseif c == ":" then
            //! runtextmacro json__advance(": at the end of input")
            
            if state_stack[state_idx] == HASH_KEY_ENCOUNTERED then
                set state_stack[state_idx] = HASH_COLON_ENCOUNTERED
            else
                call error("Unexpected ':'.", idx)
            endif
            
        elseif c == "]" then
            set idx = idx+1
            
            if state_stack[state_idx] == ARRAY_START or state_stack[state_idx] == ARRAY_VALUE_ENCOUNTERED then
                set json_idx = json_idx -1
                set state_idx = state_idx -1
                
                if state_stack[state_idx] == ARRAY_START or state_stack[state_idx] == ARRAY_COMMA_ENCOUNTERED then
                    set state_stack[state_idx] = ARRAY_VALUE_ENCOUNTERED
                    
                elseif state_stack[state_idx] == HASH_COLON_ENCOUNTERED then
                    set state_stack[state_idx] = HASH_VALUE_ENCOUNTERED
                    set JsonHash(json_stack[json_idx])[hashkey] = json_stack[json_idx+1]
                elseif state_idx == -1 then
                else
                    call error("[3]Unexpected ']'.", idx)
                endif
            else
                call error("[2]Unexpected ']'.", idx)
            endif
            
        
        elseif c == "}" then
            set idx = idx+1

            if state_stack[state_idx] == HASH_START or state_stack[state_idx] == HASH_VALUE_ENCOUNTERED then
                set json_idx = json_idx -1
                set state_idx = state_idx -1
                
                if state_stack[state_idx] == ARRAY_START or state_stack[state_idx] == ARRAY_COMMA_ENCOUNTERED then
                    set state_stack[state_idx] = ARRAY_VALUE_ENCOUNTERED
                    
                elseif state_stack[state_idx] == HASH_START or state_stack[state_idx] == HASH_COLON_ENCOUNTERED then
                    set state_stack[state_idx] = HASH_VALUE_ENCOUNTERED
                    set JsonHash(json_stack[json_idx])[hashkey] = json_stack[json_idx+1]
                elseif state_idx == -1 then
                else
                    call error("[3]Unexpected '}'.", idx)
                endif
            else
                call error("[2]Unexpected '}'.", idx)
            endif
            
        elseif c == "0" or c == "1" or c == "2" or c == "3" or c == "4" or c == "5" /*
            */ or c == "6" or c == "7" or c == "8" or c == "9" then
            
            if not (state_stack[state_idx] == ARRAY_START or state_stack[state_idx] == ARRAY_COMMA_ENCOUNTERED /*
                */ or state_stack[state_idx] == HASH_COLON_ENCOUNTERED) then
                call error("Unexpected number", idx)
            endif

            set buffer = ""
            loop
            exitwhen idx >= length
            exitwhen c == "."
            exitwhen c != "0" and c != "1" and c != "2" and c != "3" and c != "4" and /*
                    */ c != "5" and c != "6" and c != "7" and c != "8" and c != "9"
            
                set buffer = buffer + c
                
            set idx=idx+1
            set c = SubString(s, idx, idx+1)
            endloop
            
            if c == "." then
                //! runtextmacro json__advance(". at the end of input")
                
                set buffer = buffer + "."
                loop
                exitwhen idx >= length
                exitwhen c != "0" and c != "1" and c != "2" and c != "3" and c != "4" /*
                        */ and c != "5" and c != "6" and c != "7" and c != "8" and c != "9"
                
                    set buffer = buffer + c
                    
                set idx=idx+1
                set c = SubString(s, idx, idx+1)
                endloop
                
                set json_stack[json_idx+1] = JsonReal.create(S2R(buffer))
            else
                set json_stack[json_idx+1] = JsonInt.create(S2I(buffer))
            endif
            
            //! runtextmacro json_insertSimpleValue()
            
        elseif SubString(s, idx, idx+4) == "true" then
            if not (state_stack[state_idx] == ARRAY_START or state_stack[state_idx] == ARRAY_COMMA_ENCOUNTERED /*
                */ or state_stack[state_idx] == HASH_COLON_ENCOUNTERED) then
                call error("Unexpected true", idx)
            endif
            set json_stack[json_idx+1] = JsonBool.create(true)
            set idx = idx +4
            
            //! runtextmacro json_insertSimpleValue()
            
        elseif SubString(s, idx, idx+4) == "null" then
            if not (state_stack[state_idx] == ARRAY_START or state_stack[state_idx] == ARRAY_COMMA_ENCOUNTERED /*
                */ or state_stack[state_idx] == HASH_COLON_ENCOUNTERED) then
                call error("Unexpected null", idx)
            endif
            set json_stack[json_idx+1] = Null
            set idx = idx +4
            
            //! runtextmacro json_insertSimpleValue()
            
        elseif SubString(s, idx, idx+5) == "false" then
            if not (state_stack[state_idx] == ARRAY_START or state_stack[state_idx] == ARRAY_COMMA_ENCOUNTERED /*
                */ or state_stack[state_idx] == HASH_COLON_ENCOUNTERED) then
                call error("Unexpected false", idx)
            endif
            set json_stack[json_idx+1] = JsonBool.create(false)
            set idx = idx +5
            
            //! runtextmacro json_insertSimpleValue()	
        else
            call error("[1]Unexpected '"+ c +"'.", idx)
        endif

    endloop

    if state_idx != -1 then
        call error(state_help[state_stack[state_idx]], idx)
    endif
    return json_stack[0]
endfunction

private function init takes nothing returns nothing
    set state_help[HASH_START]="No closing '}'."
    set state_help[HASH_KEY_ENCOUNTERED]="Hash key without ':'."
    set state_help[HASH_VALUE_ENCOUNTERED]="No closing '}'"
    set state_help[HASH_COLON_ENCOUNTERED]="Missing hash value."
    set state_help[HASH_COMMA_ENCOUNTERED]="No key/value-pair after ','."

    set state_help[ARRAY_START]="No closing ']'."
    set state_help[ARRAY_COMMA_ENCOUNTERED]="No array value after ','."
    set state_help[ARRAY_VALUE_ENCOUNTERED]="No closing ']'."

    set Null = JsonNull.create()

    set ht = InitHashtable()
endfunction

endlibrary

