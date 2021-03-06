%%% -*- coding: latin-1 -*-
%%% ----------------------------------------------------------------------------
%%% Copyright (c) 2009-2013, Erlang Solutions Ltd.
%%% All rights reserved.
%%%
%%% Redistribution and use in source and binary forms, with or without
%%% modification, are permitted provided that the following conditions are met:
%%%    * Redistributions of source code must retain the above copyright
%%%      notice, this list of conditions and the following disclaimer.
%%%    * Redistributions in binary form must reproduce the above copyright
%%%      notice, this list of conditions and the following disclaimer in the
%%%      documentation and/or other materials provided with the distribution.
%%%    * Neither the name of Erlang Solutions Ltd. nor the
%%%      names of its contributors may be used to endorse or promote products
%%%      derived from this software without specific prior written permission.
%%%
%%% THIS SOFTWARE IS PROVIDED BY Erlang Solutions Ltd. ''AS IS''
%%% AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
%%% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
%%% ARE DISCLAIMED. IN NO EVENT SHALL Erlang Solutions Ltd. BE
%%% LIABLE SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
%%% BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
%%% WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
%%% OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
%%% ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
%%% ----------------------------------------------------------------------------

%%------------------------------------------------------------------------------
%%% @author Oscar Hellstr�m <oscar@hellstrom.st>
%%% @author Diana Parra Corbacho <diana.corbacho@erlang-solutions.com>
%%% @author Ramon Lastres Guerrero <ramon.lastres@erlang-solutions.com>
%%% @doc Main interface to the lightweight http client
%%% See {@link request/4}, {@link request/5} and {@link request/6} functions.
%%% @end
%%------------------------------------------------------------------------------
-module(lhttpc).
-behaviour(application).

-export([start/0, stop/0, start/2, stop/1,
         request/4, request/5, request/6, request/9,
         request_client/5, request_client/6, request_client/7,
         add_pool/1, add_pool/2, add_pool/3,
         delete_pool/1,
         connect_client/2,
         disconnect_client/1,
         send_body_part/2, send_body_part/3,
         send_trailers/2, send_trailers/3,
         get_body_part/1, get_body_part/2]).

-include("lhttpc_types.hrl").
-include("lhttpc.hrl").
%% @headerfile "lhttpc.hrl"

%%==============================================================================
%% Exported functions
%%==============================================================================

%%------------------------------------------------------------------------------
%% @hidden
%%------------------------------------------------------------------------------
-spec start(normal | {takeover, node()} | {failover, node()}, any()) -> {ok, pid()}.
start(_, _) ->
    lhttpc_sup:start_link().

%%------------------------------------------------------------------------------
%% @hidden
%%------------------------------------------------------------------------------
-spec stop(any()) -> ok.
stop(_) ->
    ok.


%%------------------------------------------------------------------------------
%% @doc Start the application.
%% This is a helper function that will call `application:start(lhttpc)' to
%% allow the library to be started using the `-s' flag.
%% For instance:
%% `$ erl -s crypto -s ssl -s lhttpc'
%%
%% For more info on possible return values the `application' module.
%% @end
%%------------------------------------------------------------------------------
-spec start() -> ok | {error, any()}.
start() ->
    application:start(lhttpc).

%%------------------------------------------------------------------------------
%% @doc Stops the application.
%% This is a helper function that will call `application:stop(lhttpc)'.
%%
%% For more info on possible return values the `application' module.
%% @end
%%------------------------------------------------------------------------------
-spec stop() -> ok | {error, any()}.
stop() ->
    application:stop(lhttpc).

%%------------------------------------------------------------------------------
%% @doc Create a new named httpc_manager pool.
%% @end
%%------------------------------------------------------------------------------
-spec add_pool(atom()) -> {ok, pid()} | {error, term()}.
add_pool(Name) when is_atom(Name) ->
    {ok, ConnTimeout} = application:get_env(lhttpc, connection_timeout),
    {ok, PoolSize} = application:get_env(lhttpc, pool_size),
    add_pool(Name, ConnTimeout, PoolSize).

%%------------------------------------------------------------------------------
%% @doc Create a new named httpc_manager pool with the specified connection
%% timeout.
%% @end
%%------------------------------------------------------------------------------
-spec add_pool(atom(), non_neg_integer()) -> {ok, pid()} | {error, term()}.
add_pool(Name, ConnTimeout) when is_atom(Name), is_integer(ConnTimeout), ConnTimeout > 0 ->
    {ok, PoolSize} = application:get_env(lhttpc, pool_size),
    add_pool(Name, ConnTimeout, PoolSize).

%%------------------------------------------------------------------------------
%% @doc Create a new named httpc_manager pool with the specified connection
%% timeout and size.
%% @end
%%------------------------------------------------------------------------------
-spec add_pool(atom(), non_neg_integer(), poolsize()) -> {ok, pid()} | {error, term()}.
add_pool(Name, ConnTimeout, PoolSize) ->
    lhttpc_manager:new_pool(Name, ConnTimeout, PoolSize).

%%------------------------------------------------------------------------------
%% @doc Delete an existing pool
%% @end
%%------------------------------------------------------------------------------
-spec delete_pool(atom() | pid()) -> ok.
delete_pool(PoolPid) when is_pid(PoolPid) ->
    {registered_name, Name} = erlang:process_info(PoolPid, registered_name),
    delete_pool(Name);
delete_pool(PoolName) when is_atom(PoolName) ->
    case supervisor:terminate_child(lhttpc_sup, PoolName) of
        ok -> case supervisor:delete_child(lhttpc_sup, PoolName) of
                ok -> ok;
                {error, not_found} -> ok
            end;
        {error, Reason} -> {error, Reason}
    end.

%%------------------------------------------------------------------------------
%% @doc Starts a Client process and connects it to a Destination, which can be
%% either an URL or a tuple
%% `{Host, Port, Ssl}'
%% If the pool is provided whithin the options, it uses the pool to get an
%% existing connection or creates a new one managed by it.
%% This is intended to be able to create a client process that will generate many
%% requests to a given destination, keeping the process alive, using
%% {@link request_client/5}, {@link request_client/5} or {@link request_client/7}.
%%
%% The only relevant options to be included here (other options will be ignored) are:
%%
%% `{connect_timeout, Milliseconds}' specifies how many milliseconds the
%% client can spend trying to establish a connection to the server. This
%% doesn't affect the overall request timeout. However, if it's longer than
%% the overall timeout it will be ignored. Also note that the TCP layer my
%% choose to give up earlier than the connect timeout, in which case the
%% client will also give up. The default value is infinity, which means that
%% it will either give up when the TCP stack gives up, or when the overall
%% request timeout is reached.
%%
%% `{connect_options, Options}' specifies options to pass to the socket at
%% connect time. This makes it possible to specify both SSL options and
%% regular socket options, such as which IP/Port to connect from etc.
%% Some options must not be included here, namely the mode, `binary'
%% or `list', `{active, boolean()}', `{active, once}' or `{packet, Packet}'.
%% These options would confuse the client if they are included.
%% Please note that these options will only have an effect on *new*
%% connections, and it isn't possible for different requests
%% to the same host uses different options unless the connection is closed
%% between the requests. Using HTTP/1.0 or including the "Connection: close"
%% header would make the client close the connection after the first
%% response is received.
%%
%% `{use_cookies, UseCookies}' If set to true, the client will automatically
%% handle the cookies for the user. Considering that the Cookies get stored
%% in the client process state, the usage of this option only has effect when
%% using the request_client() functions, NOT when using standalone requests,
%% since in such case a new process is spawned each time.
%%
%% `{pool_options, PoolOptions}' This are the configuration options regarding the
%% pool of connections usage. If the `pool_ensure' option is true, the pool with
%% the given name in the `pool' option will be created and then used if it
%% does not exist.
%% The `pool_connection_timeout' specifies the time that the pool keeps a
%% connection open before it gets closed, `pool_max_size' specifies the number of
%% connections the pool can handle.
%%
%% `{proxy, ProxyUrl}' if this option is specified, a proxy server is used as
%% an intermediary for all communication with the destination server. The link
%% to the proxy server is established with the HTTP CONNECT method (RFC2817).
%% Example value: {proxy, "http://john:doe@myproxy.com:3128"}
%%
%% `{proxy_ssl_options, SslOptions}' this is a list of SSL options to use for
%% the SSL session created after the proxy connection is established. For a
%% list of all available options, please check OTP's ssl module manpage.
%% @end
%%------------------------------------------------------------------------------
-spec connect_client(destination(), options()) -> {ok, pid()} | ignore | {error, term()}.
connect_client(Destination, Options) ->
    lhttpc_client:start({Destination, Options}, []).

%%------------------------------------------------------------------------------
%% @doc Stops a Client process and closes the connection (if no pool is used) or
%% it returns the connection to the pool (if pool is used).
%% @end
%%------------------------------------------------------------------------------
-spec disconnect_client(pid()) -> ok.
disconnect_client(Client) ->
    lhttpc_client:stop(Client).

%REQUESTS USING THE CLIENT

%%------------------------------------------------------------------------------
%% @doc Makes a request using a client already connected.
%% It can receive either a URL or a path.
%% Would be the same as calling {@link request_client/6} with an empty body.
%% @end
%%------------------------------------------------------------------------------
-spec request_client(pid(), string(), method(), headers(), pos_timeout()) -> result().
request_client(Client, PathOrUrl, Method, Hdrs, Timeout) ->
    request_client(Client, PathOrUrl, Method, Hdrs, [], Timeout, []).

%%------------------------------------------------------------------------------
%% @doc Makes a request using a client already connected.
%% It can receive either a URL or a path.
%% %% Would be the same as calling {@link request_client/7} with no options.
%% @end
%%------------------------------------------------------------------------------
-spec request_client(pid(), string(), method(), headers(), iodata(), pos_timeout()) -> result().
request_client(Client, PathOrUrl, Method, Hdrs, Body, Timeout) ->
    request_client(Client, PathOrUrl, Method, Hdrs, Body, Timeout, []).

%%------------------------------------------------------------------------------
%% @doc Makes a request using a client already connected.
%% It can receive either a URL or a path. It allows to add the body and specify
%% options. The only relevant options here are:
%%
%% `{send_retry, N}' specifies how many times the client should retry
%% sending a request if the connection is closed after the data has been
%% sent. The default value is `1'. If `{partial_upload, WindowSize}'
%% (see below) is specified, the client cannot retry after the first part
%% of the body has been sent since it doesn't keep the whole entitity body
%% in memory.
%%
%% `{partial_upload, WindowSize}' means that the request entity body will be
%% supplied in parts to the client by the calling process. The `WindowSize'
%% specifies how many parts can be sent to the process controlling the socket
%% before waiting for an acknowledgement. This is to create a kind of
%% internal flow control if the network is slow and the client process is
%% blocked by the TCP stack. Flow control is disabled if `WindowSize' is
%% `infinity'. If `WindowSize' is an integer, it must be >= 0. If partial
%% upload is specified and no `Content-Length' is specified in `Hdrs' the
%% client will use chunked transfer encoding to send the entity body.
%% If a content length is specified, this must be the total size of the entity
%% body.
%% The call to {@link request/6} will return `{ok, UploadState}'. The
%% `UploadState' is supposed to be used as the first argument to the {@link
%% send_body_part/2} or {@link send_body_part/3} functions to send body parts.
%% Partial upload is intended to avoid keeping large request bodies in
%% memory but can also be used when the complete size of the body isn't known
%% when the request is started.
%%
%% `{partial_download, PartialDownloadOptions}' means that the response body
%% will be supplied in parts by the client to the calling process. The partial
%% download option `{window_size, WindowSize}' specifies how many part will be
%% sent to the calling process before waiting for an acknowledgement. This is
%% to create a kind of internal flow control if the calling process is slow to
%% process the body part and the network and server are considerably faster.
%% Flow control is disabled if `WindowSize' is `infinity'. If `WindowSize'
%% is an integer it must be >=0. The partial download option `{part_size,
%% PartSize}' specifies the size the body parts should come in. Note however
%% that if the body size is not determinable (e.g entity body is termintated
%% by closing the socket) it will be delivered in pieces as it is read from
%% the wire. There is no caching of the body parts until the amount reaches
%% body size. If the body size is bounded (e.g `Content-Length' specified or
%% `Transfer-Encoding: chunked' specified) it will be delivered in `PartSize'
%% pieces. Note however that the last piece might be smaller than `PartSize'.
%% Size bounded entity bodies are handled the same way as unbounded ones if
%% `PartSize' is `infinity'. If `PartSize' is integer it must be >= 0.
%% If `{partial_download, PartialDownloadOptions}' is specified the
%% `ResponseBody' will be a `pid()' unless the response has no body
%% (for example in case of `HEAD' requests). In that case it will be be
%% `undefined'. The functions {@link get_body_part/1} and
%% {@link get_body_part/2} can be used to read body parts in the calling
%% process.
%%
%% @end
%%------------------------------------------------------------------------------
-spec request_client(pid(), string(), method(), headers(), iodata(),
                     pos_timeout(), options()) -> result().
request_client(Client, PathOrUrl, Method, Hdrs, Body, Timeout, Options) ->
    verify_options(Options),
    try
        Reply = lhttpc_client:request(Client, PathOrUrl, Method, Hdrs, Body, Options, Timeout),
        Reply
    catch
        exit:{timeout, _} ->
            {error, timeout}
    end.

%%------------------------------------------------------------------------------
%% @doc Sends a request without a body.
%% Would be the same as calling {@link request/5} with an empty body,
%% `request(URL, Method, Hdrs, [], Timeout)' or
%% `request(URL, Method, Hdrs, <<>>, Timeout)'.
%% @see request/9
%% @end
%%------------------------------------------------------------------------------
-spec request(string(), method(), headers(), pos_timeout()) -> result().
request(URL, Method, Hdrs, Timeout) ->
    request(URL, Method, Hdrs, [], Timeout, []).

%%------------------------------------------------------------------------------
%% @doc Sends a request with a body.
%% Would be the same as calling {@link request/6} with no options,
%% `request(URL, Method, Hdrs, Body, Timeout, [])'.
%% @see request/9
%% @end
%%------------------------------------------------------------------------------
-spec request(string(), method(), headers(), iodata(), pos_timeout()) -> result().
request(URL, Method, Hdrs, Body, Timeout) ->
    request(URL, Method, Hdrs, Body, Timeout, []).

%%------------------------------------------------------------------------------
%% @doc Sends a request with a body.
%% Would be the same as calling <pre>
%% #lhttpc_url{host = Host, port = Port, path = Path, is_ssl = Ssl} = lhttpc_lib:parse_url(URL),
%% request(Host, Port, Path, Ssl, Method, Hdrs, Body, Timeout, Options).
%% </pre>
%%
%% `URL' is expected to be a valid URL:
%% `scheme://host[:port][/path]'.
%% @see request/9
%% @end
%%------------------------------------------------------------------------------
-spec request(string(), method(), headers(), iodata(), pos_timeout(), options()) -> result().
request(URL, Method, Hdrs, Body, Timeout, Options) ->
    #lhttpc_url{host = Host, port = Port, path = Path, is_ssl = Ssl,
                user = User,password = Passwd} = lhttpc_lib:parse_url(URL),
    Headers = case User of
        [] ->
            Hdrs;
        _ ->
            Auth = "Basic " ++ binary_to_list(base64:encode(User ++ ":" ++ Passwd)),
            lists:keystore("Authorization", 1, Hdrs, {"Authorization", Auth})
    end,
    request(Host, Port, Ssl, Path, Method, Headers, Body, Timeout, Options).

%%------------------------------------------------------------------------------
%% @doc Sends a request with a body. For this, a new client process is created,
%% it creates a connection or takes it from a pool (depends of the options) and
%% uses that client process to send the request. Then it stops the process.
%%
%% Instead of building and parsing URLs the target server is specified with
%% a host, port, weither SSL should be used or not and a path on the server.
%% For instance, if you want to request http://example.com/foobar you would
%% use the following:<br/>
%% `Host' = `"example.com"'<br/>
%% `Port' = `80'<br/>
%% `Ssl' = `false'<br/>
%% `Path' = `"/foobar"'<br/>
%% `Path' must begin with a forward slash `/'.
%%
%% `Method' is either a string, stating the HTTP method exactly as in the
%% protocol, i.e: `"POST"' or `"GET"'. It could also be an atom, which is
%% then coverted to an uppercase (if it isn't already) string.
%%
%% `Hdrs' is a list of headers to send. Mandatory headers such as
%% `Host', `Content-Length' or `Transfer-Encoding' (for some requests)
%% are added automatically.
%%
%% `Body' is the entity to send in the request. Please don't include entity
%% bodies where there shouldn't be any (such as for `GET').
%%
%% `Timeout' is the timeout for the request in milliseconds.
%%
%% `Options' is a list of options.
%%
%% Options:
%%
%% `{connect_timeout, Milliseconds}' specifies how many milliseconds the
%% client can spend trying to establish a connection to the server. This
%% doesn't affect the overall request timeout. However, if it's longer than
%% the overall timeout it will be ignored. Also note that the TCP layer my
%% choose to give up earlier than the connect timeout, in which case the
%% client will also give up. The default value is infinity, which means that
%% it will either give up when the TCP stack gives up, or when the overall
%% request timeout is reached.
%%
%% `{connect_options, Options}' specifies options to pass to the socket at
%% connect time. This makes it possible to specify both SSL options and
%% regular socket options, such as which IP/Port to connect from etc.
%% Some options must not be included here, namely the mode, `binary'
%% or `list', `{active, boolean()}', `{active, once}' or `{packet, Packet}'.
%% These options would confuse the client if they are included.
%% Please note that these options will only have an effect on *new*
%% connections, and it isn't possible for different requests
%% to the same host uses different options unless the connection is closed
%% between the requests. Using HTTP/1.0 or including the "Connection: close"
%% header would make the client close the connection after the first
%% response is received.
%%
%% `{send_retry, N}' specifies how many times the client should retry
%% sending a request if the connection is closed after the data has been
%% sent. The default value is `1'. If `{partial_upload, WindowSize}'
%% (see below) is specified, the client cannot retry after the first part
%% of the body has been sent since it doesn't keep the whole entitity body
%% in memory.
%%
%% `{partial_upload, WindowSize}' means that the request entity body will be
%% supplied in parts to the client by the calling process. The `WindowSize'
%% specifies how many parts can be sent to the process controlling the socket
%% before waiting for an acknowledgement. This is to create a kind of
%% internal flow control if the network is slow and the client process is
%% blocked by the TCP stack. Flow control is disabled if `WindowSize' is
%% `infinity'. If `WindowSize' is an integer, it must be >= 0. If partial
%% upload is specified and no `Content-Length' is specified in `Hdrs' the
%% client will use chunked transfer encoding to send the entity body.
%% If a content length is specified, this must be the total size of the entity
%% body.
%% The call to {@link request/6} will return `{ok, UploadState}'. The
%% `UploadState' is supposed to be used as the first argument to the {@link
%% send_body_part/2} or {@link send_body_part/3} functions to send body parts.
%% Partial upload is intended to avoid keeping large request bodies in
%% memory but can also be used when the complete size of the body isn't known
%% when the request is started.
%%
%% `{partial_download, PartialDownloadOptions}' means that the response body
%% will be supplied in parts by the client to the calling process. The partial
%% download option `{window_size, WindowSize}' specifies how many part will be
%% sent to the calling process before waiting for an acknowledgement. This is
%% to create a kind of internal flow control if the calling process is slow to
%% process the body part and the network and server are considerably faster.
%% Flow control is disabled if `WindowSize' is `infinity'. If `WindowSize'
%% is an integer it must be >=0. The partial download option `{part_size,
%% PartSize}' specifies the size the body parts should come in. Note however
%% that if the body size is not determinable (e.g entity body is termintated
%% by closing the socket) it will be delivered in pieces as it is read from
%% the wire. There is no caching of the body parts until the amount reaches
%% body size. If the body size is bounded (e.g `Content-Length' specified or
%% `Transfer-Encoding: chunked' specified) it will be delivered in `PartSize'
%% pieces. Note however that the last piece might be smaller than `PartSize'.
%% Size bounded entity bodies are handled the same way as unbounded ones if
%% `PartSize' is `infinity'. If `PartSize' is integer it must be >= 0.
%% If `{partial_download, PartialDownloadOptions}' is specified the
%% `ResponseBody' will be a `pid()' unless the response has no body
%% (for example in case of `HEAD' requests). In that case it will be be
%% `undefined'. The functions {@link get_body_part/1} and
%% {@link get_body_part/2} can be used to read body parts in the calling
%% process.
%%
%% `{use_cookies, UseCookies}' If set to true, the client will automatically
%% handle the cookies for the user. Considering that the Cookies get stored
%% in the client process state, the usage of this option only has effect when
%% using the request_client() functions, NOT when using standalone requests,
%% since in such case a new process is spawned each time.
%%
%% `{proxy, ProxyUrl}' if this option is specified, a proxy server is used as
%% an intermediary for all communication with the destination server. The link
%% to the proxy server is established with the HTTP CONNECT method (RFC2817).
%% Example value: {proxy, "http://john:doe@myproxy.com:3128"}
%%
%% `{proxy_ssl_options, SslOptions}' this is a list of SSL options to use for
%% the SSL session created after the proxy connection is established. For a
%% list of all available options, please check OTP's ssl module manpage.
%%
%% `{pool_options, PoolOptions}' This are the configuration options regarding the
%% pool of connections usage. If the `pool_ensure' option is true, the pool with
%% the given name in the `pool' option will be created and then used if it
%% does not exist.
%% The `pool_connection_timeout' specifies the time that the pool keeps a
%% connection open before it gets closed, `pool_max_size' specifies the number of
%% connections the pool can handle.
%% @end
%%------------------------------------------------------------------------------
-spec request(host(), port_num(), boolean(), string(), method(),
              headers(), iodata(), pos_timeout(), options()) -> result().
request(Host, Port, Ssl, Path, Method, Hdrs, Body, Timeout, Options) ->
    verify_options(Options),
    case connect_client({Host, Port, Ssl}, Options) of
        {ok, Client} ->
            try
                Reply = lhttpc_client:request(Client, Path, Method, Hdrs, Body, Options, Timeout),
                disconnect_client(Client),
                Reply
            catch
                exit:{timeout, _} ->
                    disconnect_client(Client),
                    {error, timeout}
            end;
        {error, {timeout, _Reason}} ->
            {error, connection_timeout};
        {error, _Reason} = Error ->
            Error
    end.

%%------------------------------------------------------------------------------
%% @doc Sends a body part to an ongoing request when
%% `{partial_upload, true}' is used. The default timeout, `infinity'
%% will be used. Would be the same as calling
%% `send_body_part(Client, BodyPart, infinity)'.
%% @end
%%------------------------------------------------------------------------------
-spec send_body_part(pid(), bodypart()) -> result().
send_body_part(Client, BodyPart) ->
    send_body_part(Client, BodyPart, infinity).

%%------------------------------------------------------------------------------
%% @doc Sends a body part to an ongoing request when
%% `{partial_upload, true}' is used.
%% `Timeout' is the timeout for the request in milliseconds.
%%
%% The `BodyPart' `http_eob' signals an end of the entity body, the request
%% is considered sent and the response will be read from the socket. If
%% there is no response within `Timeout' milliseconds, the request is
%% canceled and `{error, timeout}' is returned.
%% @end
%%------------------------------------------------------------------------------
-spec send_body_part(pid(), bodypart(), timeout()) -> result().
send_body_part(Client, BodyPart, Timeout)  ->
    lhttpc_client:send_body_part(Client, BodyPart, Timeout).

%%------------------------------------------------------------------------------
%% @doc Sends trailers to an ongoing request when `{partial_upload,
%% true}' is used and no `Content-Length' was specified. The default
%% timout `infinity' will be used. Plase note that after this the request is
%% considered complete and the response will be read from the socket.
%% Would be the same as calling
%% `send_trailers(Client, BodyPart, infinity)'.
%% @end
%%------------------------------------------------------------------------------
-spec send_trailers(pid(), headers()) -> result().
send_trailers(Client, Trailers) ->
    lhttpc_client:send_trailers(Client, Trailers, infinity).

%%------------------------------------------------------------------------------
%% @doc Sends trailers to an ongoing request when
%% `{partial_upload, true}' is used and no `Content-Length' was
%% specified.
%% `Timeout' is the timeout for sending the trailers and reading the
%% response in milliseconds.
%%
%% Sending trailers also signals the end of the entity body, which means
%% that no more body parts, or trailers can be sent and the response to the
%% request will be read from the socket. If no response is received within
%% `Timeout' milliseconds the request is canceled and `{error, timeout}' is
%% returned.
%% @end
%%------------------------------------------------------------------------------
-spec send_trailers(pid(), headers(), timeout()) -> result().
send_trailers(Client, Trailers, Timeout) when is_list(Trailers), is_pid(Client) ->
    lhttpc_client:send_trailers(Client, Trailers, Timeout).

%%------------------------------------------------------------------------------
%% @doc Reads a body part from an ongoing response when
%% `{partial_download, PartialDownloadOptions}' is used. The default timeout,
%% `infinity' will be used.
%% Would be the same as calling
%% `get_body_part(HTTPClient, infinity)'.
%% @end
%%------------------------------------------------------------------------------
-spec get_body_part(pid()) -> {ok, binary()} | {ok, {http_eob, headers()}} | {error, term()}.
get_body_part(Pid) ->
    get_body_part(Pid, infinity).

%%------------------------------------------------------------------------------
%% @doc Reads a body part from an ongoing response when
%% `{partial_download, PartialDownloadOptions}' is used.
%% `Timeout' is the timeout for reading the next body part in milliseconds.
%% `http_eob' marks the end of the body. If there were Trailers in the
%% response those are returned with `http_eob' as well.
%% If it evers returns an error, no further calls to this function should
%% be done.
%% @end
%%------------------------------------------------------------------------------
-spec get_body_part(pid(), timeout()) -> {ok, binary()} |
                                         {ok, {http_eob, headers()}} | {error, term()}.
get_body_part(Client, Timeout) ->
    lhttpc_client:get_body_part(Client, Timeout).

%%==============================================================================
%% Internal functions
%%==============================================================================

%%------------------------------------------------------------------------------
%% @private
%%------------------------------------------------------------------------------
-spec verify_options(options()) -> ok | any().
verify_options([{send_retry, N} | Options]) when is_integer(N), N >= 0 ->
    verify_options(Options);
verify_options([{connect_timeout, infinity} | Options]) ->
    verify_options(Options);
verify_options([{connect_timeout, MS} | Options])
        when is_integer(MS), MS >= 0 ->
    verify_options(Options);
verify_options([{partial_upload, Bool} | Options])
        when is_boolean(Bool) ->
    verify_options(Options);
verify_options([{partial_upload, infinity} | Options])  ->
    verify_options(Options);
verify_options([{partial_download, DownloadOptions} | Options])
        when is_list(DownloadOptions) ->
    verify_partial_download(DownloadOptions),
    verify_options(Options);
verify_options([{connect_options, List} | Options]) when is_list(List) ->
    verify_options(Options);
verify_options([{proxy, List} | Options]) when is_list(List) ->
    verify_options(Options);
verify_options([{proxy_ssl_options, List} | Options]) when is_list(List) ->
    verify_options(Options);
verify_options([{pool_options, PoolOptions} | Options]) ->
    ok = verify_pool_options(PoolOptions),
    verify_options(Options);
verify_options([Option | _Rest]) ->
    erlang:error({bad_option, Option});
verify_options([]) ->
    ok.

%%------------------------------------------------------------------------------
%% @private
%%------------------------------------------------------------------------------
-spec verify_pool_options(pool_options()) -> ok | no_return().
verify_pool_options([{pool, PidOrName} | Options])
        when is_pid(PidOrName); is_atom(PidOrName) ->
    verify_pool_options(Options);
verify_pool_options([{pool_ensure, Bool} | Options])
        when is_boolean(Bool) ->
    verify_pool_options(Options);
verify_pool_options([{pool_connection_timeout, Size} | Options])
        when is_integer(Size) ->
    verify_pool_options(Options);
verify_pool_options([{pool_max_size, Size} | Options])
        when is_integer(Size) orelse
        Size =:= infinity->
    verify_pool_options(Options);
verify_pool_options([Option | _Rest]) ->
    erlang:error({bad_option, Option});
verify_pool_options([]) ->
    ok.

%%------------------------------------------------------------------------------
%% @private
%%------------------------------------------------------------------------------
-spec verify_partial_download(options()) -> ok.
verify_partial_download([{window_size, infinity} | Options])->
    verify_partial_download(Options);
verify_partial_download([{window_size, Size} | Options]) when
        is_integer(Size), Size >= 0 ->
    verify_partial_download(Options);
verify_partial_download([{part_size, Size} | Options]) when
        is_integer(Size), Size >= 0 ->
    verify_partial_download(Options);
verify_partial_download([{part_size, infinity} | Options]) ->
    verify_partial_download(Options);
verify_partial_download([{recv_proc, Pid} | Options]) when
      is_pid(Pid) ->
    case is_process_alive(Pid) of
      true ->
	 verify_partial_download(Options);
      _ ->
	erlang:error({bad_option, {partial_download, recv_proc}})
    end;
verify_partial_download([Option | _Options]) ->
    erlang:error({bad_option, {partial_download, Option}});
verify_partial_download([]) ->
    ok.
