# jass-json
A vJass JSON-library.

# Doc

````
function decodeJson takes string s returns JsonValue
````

Returns a `JsonValue` or crashes the thread on error.
Only ever destroy `JsonValue`s created via `decodeJson`

````
interface JsonValue
	method encode takes nothing returns string
endinterface
````

The basic type to work with. Every JsonValue knows how to encode itself.
All json types are based on this.

````
struct JsonBool extends JsonValue
	boolean value
endstruct

struct JsonString extends JsonValue
	string value
endstruct

struct JsonInt extends JsonValue
	integer value
endstruct

struct JsonReal extends JsonValue
	real value
endstruct

struct JsonArray extends JsonValue
	readonly integer length
	method operator []= takes integer k, JsonValue v returns nothing
	method operator []  takes integer k returns JsonValue
endstruct

struct JsonHash extends JsonValue
  method operator []= takes string k, JsonValue v returns nothing
  method operator []  takes string k returns JsonValue
endstruct
````

For the Json `null`-value there is the global `Json_Null`.
