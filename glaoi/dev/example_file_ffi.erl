-module(example_file_ffi).
-export([write_file/2, read_file/1, ensure_directory/1, sleep_ms/1]).

write_file(Path, Content) ->
    case file:write_file(Path, Content) of
        ok -> {ok, nil};
        {error, Reason} -> {error, Reason}
    end.

read_file(Path) ->
    case file:read_file(Path) of
        {ok, Content} -> {ok, Content};
        {error, Reason} -> {error, Reason}
    end.

ensure_directory(Path) ->
    case filelib:ensure_dir(Path) of
        ok -> {ok, nil};
        {error, Reason} -> {error, Reason}
    end.

sleep_ms(Millis) ->
    timer:sleep(Millis).
