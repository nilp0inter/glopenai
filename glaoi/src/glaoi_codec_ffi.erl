-module(glaoi_codec_ffi).
-export([dynamic_to_json/1]).

%% Re-encode a native Erlang term (from json:decode) back into iodata
%% that gleam_json can embed in its Json type.
dynamic_to_json(Value) ->
    json:encode(Value).
