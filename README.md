# LHTTPC - [![Build Status](https://travis-ci.org/lastres/lhttpc.svg?branch=v1.2.7)](https://travis-ci.org/lastres/lhttpc)

Copyright (c) 2009-2013 Erlang Solutions Ltd.

## Features

Some of the basic features provided by Lhttpc:

- HTTP basic auth
- SSL support
- Keepalive connections
- Pools for managing connections
- Support for IPv6
- Optional automatic cookie handling
- Chunked encoding
- Connection through proxy (only to HTTPS servers).

## Starting

Download the sources or clone the git repository. Then you can build with:

```
make all
```

which will generate .beam files and documentation. To start the lhttpc OTP application, you first need to start the applications it depends on:

```
$ erl -pa ebin
1> application:start(crypto),
1> application:start(public_key),
1> application:start(ssl),
1> lhttpc:start().
ok
```

## Usage
Lhttpc allows the user to send requests by always spawning a process for each of them, or reusing a single client process for several requests. It also allows the usage of pools of connections in order to keep connections alive and reuse them.

### Send a simple request
A single request without using a client process, will just spawn a process, do the request, and then stop the process.

```erlang
Method = get,
URL = "http://www.erlang-solutions.com",
Headers = [],
Timeout = 100,
{ok,{{StatusCode, Status}, Headers, Body}} = lhttpc:request(URL, Method, Headers, Timeout).
```
Using the function `request/9` it is also possible to specify the target server using `Host`, `Port` and `Ssl` and a relative `Path`. All the available options are listed in the documentation.

### Reuse a client process

It is possible to first connect a client process to the target server, and then do a requests specifing just the relative Path:

```erlang
{ok, Client} = lhttpc:connect_client("http://erlang-solutions.com", []),
{ok,{{StatusCode, Status}, Headers, Body}} = lhttpc:request_client(Client, "/", get, [], 100).
```

And then reuse the same client to do more requests to the same server.

### Use connection pools

Lhttpc supports pools of connections. They keep the connections to the different servers independently of the client processes. Therefore, if we do a requests specifing a pool, the client process will try to retrieve the connection from the pool if there is one, use it, and then return it to the pool before stopping. This makes it possible to share connections between different client processes and keep connections alive.

```erlang
lhttpc:add_pool(my_pool),
lhttpc:request("http://www.erlang-solutions.com", get, [], [], 100, [{pool_options, [{pool, my_pool}]}]).
```

The `lhttpc_manager` module provides functions to retrive information about the pools:

```erlang
1>lhttpc_manager:connection_count(my_pool).
0
2>lhttpc:request("http://www.erlang-solutions.com", get, [], [], 100, [{pool_options, [{pool, my_pool}]}]).
3>lhttpc_manager:connection_count(my_pool).
1
4>lhttpc_manager:list_pools().
[{my_pool,[{max_pool_size,50},{timeout,300000}]}]
5>lhttpc_manager:update_connection_timeout(my_pool, 1000).
ok
6>lhttpc_manager:list_pools().
[{my_pool,[{max_pool_size,50},{timeout,1000}]}]
```

### Automatic cookie handling
Lhttpc supports basic cookie handling. If you want the client process to automatically handle the cookies, use the option `{use_cookies, true}`.

### Transfering the body by chunks

To be able to send the body divided in different parts, it is necessary to first start the client and then use the `request_client` functions, since it is necessary to reuse the client for the calls to `send_body_part` functions. You need to specify the `{partial_upload, true}` option. Then use the `send_body_part/2` and `send_body_part/3` functions to send the body parts. `http_eob` signals the end of the body. As an example:

```erlang
{ok, Client} = lhttpc:connect_client("http://erlang-solutions.com", []),
lhttpc:request_client(Client, "/", get, [], [], 100, [{partial_upload, true}]),
lhttpc:send_body_part(Client, <<"some part of the body">>),
lhttpc:send_body_part(Client, <<"more body">>),
lhttpc:send_body_part(Client, http_eob).
```

### Partial download of the response body

It is also possible to download the body of the response by chunks. For this it is also necessary to connect the client first. The response body will be sent asynchronously to the specified process:

```erlang
1> {ok, Client} = lhttpc:connect_client("http://www.google.com", []).
{ok,<0.40.0>}
2> lhttpc:request_client(Client, "/", get, [], [], 100, [{partial_download, [{window_size, infinity},{recv_proc, self()}]}]).
{ok,{{302,"Found"},
     [{"Alternate-Protocol","80:quic"},
      {"Server","GFE/2.0"},
      {"Date","Wed, 30 Apr 2014 11:22:09 GMT"},
      {"Content-Length","258"},
      {"Location",
       "http://www.google.co.uk/?gfe_rd=cr&ei=4dxgU_jHA8SK8QfWhQE"},
      {"Content-Type","text/html; charset=UTF-8"},
      {"Cache-Control","private"}],
     partial_download}}
3> flush().
Shell got {body_part,<<"<HTML><HEAD><meta http-equiv=\"content-type\" content=\"text/html;charset=utf-8\">\n<TITLE>302 Moved</TITLE></HEAD><BODY>\n<H1>302 Moved</H1>\nThe document has moved\n<A HREF=\"http://www.google.co.uk/?gfe_rd=cr&amp;ei=4dxgU_jHA8SK8QfWhQE\">here</A>.\r\n</BODY></HTML>\r\n">>}
Shell got {http_eob,[]}
ok
```

You can control the flow by using the `window_size` and the `part_size` options:

```erlang
4> lhttpc:request_client(Client, "/", get, [], [], 100, [{partial_download, [{window_size, 2}, {part_size, 100}, {recv_proc, self()}]}]).
{ok,{{302,"Found"},
     [{"Alternate-Protocol","80:quic"},
      {"Server","GFE/2.0"},
      {"Date","Wed, 30 Apr 2014 11:23:51 GMT"},
      {"Content-Length","258"},
      {"Location",
       "http://www.google.co.uk/?gfe_rd=cr&ei=R91gU4nwFcSK8QfWhQE"},
      {"Content-Type","text/html; charset=UTF-8"},
      {"Cache-Control","private"}],
     partial_download}}
5> flush().
Shell got {body_part,<<"<HTML><HEAD><meta http-equiv=\"content-type\" content=\"text/html;charset=utf-8\">\n<TITLE>302 Moved</TIT">>}
Shell got {body_part,<<"LE></HEAD><BODY>\n<H1>302 Moved</H1>\nThe document has moved\n<A HREF=\"http://www.google.co.uk/?gfe_rd=">>}
Shell got {body_part,window_finished}
ok
6> lhttpc:get_body_part(Client).
ok
7> flush().
Shell got {body_part,<<"cr&amp;ei=R91gU4nwFcSK8QfWhQE\">here</A>.\r\n</BODY></HTML>\r\n">>}
Shell got {http_eob,[]}
ok
```
