-module(glaoi_webhook_ffi).
-export([hmac_sha256/2, base64_encode/1, base64_decode/1]).

%% Compute an HMAC-SHA256 of `Data` keyed by `Key`. Both inputs are
%% bitstrings/binaries; output is the raw 32-byte MAC.
hmac_sha256(Key, Data) ->
    crypto:mac(hmac, sha256, Key, Data).

%% Standard base64 encode of a binary into a binary.
base64_encode(Bin) ->
    base64:encode(Bin).

%% Standard base64 decode of a binary into `{ok, Binary}` or `{error, nil}`.
base64_decode(Bin) ->
    try
        {ok, base64:decode(Bin)}
    catch
        _:_ -> {error, nil}
    end.
