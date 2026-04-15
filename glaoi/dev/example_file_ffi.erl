-module(example_file_ffi).
-export([write_file/2, ensure_directory/1]).

write_file(Path, Content) ->
    case file:write_file(Path, Content) of
        ok -> {ok, nil};
        {error, Reason} -> {error, Reason}
    end.

ensure_directory(Path) ->
    case filelib:ensure_dir(Path) of
        ok -> {ok, nil};
        {error, Reason} -> {error, Reason}
    end.
