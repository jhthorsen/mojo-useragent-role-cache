# NAME

Mojo::UserAgent::Role::Cache - Role for Mojo::UserAgent that provides caching

# SYNOPSIS

## General

    # Apply the role
    my $ua_class_with_cache = Mojo::UserAgent->with_roles('+Cache');
    my $ua = $ua_class_with_cache->new;

    # Change the global cache driver
    use CHI;
    $ua_class_with_cache->cache_driver_singleton(CHI->new(driver => "Memory", datastore => {}));

    # Or change the driver for the instance
    $ua->cache_driver(CHI->new(driver => "Memory", datastore => {}));

    # The rest is like a normal Mojo::UserAgent
    my $tx = $ua->get($url)->error;

## Module

    package MyCoolModule;
    use Mojo::Base -base;

    has ua => sub {
      return $ENV{MOJO_USERAGENT_CACHE_STRATEGY}
        ? Mojo::UserAgent->with_roles('+Cache') : Mojo::UserAgent->new;
    };

    sub get_mojolicious_org {
      return shift->ua->get("https://mojolicious.org/");
    }

Using the `MOJO_USERAGENT_CACHE_STRATEGY` inside the module is a very
effective way to either use the global cache set up by a unit test, or run with
the default [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent) without caching.

## Test

    use Mojo::Base -strict;
    use Mojo::UserAgent::Role::Cache;
    use MyCoolModule;
    use Test::More;

    # Set up the environment and change the global cache_driver before running
    # the tests
    $ENV{MOJO_USERAGENT_CACHE_STRATEGY} ||= "playback";
    Mojo::UserAgent::Role::Cache->cache_driver_singleton->root_dir("/some/path");

    # Run the tests
    my $cool = MyCoolModule->new;
    is $cool->get_mojolicious_org->res->code, 200, "mojolicious.org works";

    done_testing;

# DESCRIPTION

[Mojo::UserAgent::Role::Cache](https://metacpan.org/pod/Mojo::UserAgent::Role::Cache) is a role for the full featured non-blocking
I/O HTTP and WebSocket user agent [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent), that provides caching.

The ["SYNOPSIS"](#synopsis) shows how to use this in with tests, but there's nothing wrong
with using it for other things as well, where you want caching.

By default, this module caches everything without any expiration. This is
because [Mojo::UserAgent::Role::Cache::Driver::File](https://metacpan.org/pod/Mojo::UserAgent::Role::Cache::Driver::File) is very basic and
actually just meant for unit testing. If you want something more complex, you
can use [CHI](https://metacpan.org/pod/CHI) or another ["cache\_driver"](#cache_driver) that implements the logic you want.

One exotic hack that is possible, is to make ["cache\_key"](#cache_key) return the whole
[$tx](https://metacpan.org/pod/$tx) object and then implement a wrapper around [CHI](https://metacpan.org/pod/CHI) that will investigate
the transaction and see if it wants to cache the request at all.

# WARNING

## Experimenntal

[Mojo::UserAgent::Role::Cache](https://metacpan.org/pod/Mojo::UserAgent::Role::Cache) is still under development, so there will be
changes and there is probably bugs that needs fixing. Please report in if you
find a bug or find this role interesting.

[https://github.com/jhthorsen/mojo-useragent-role-cache/issues](https://github.com/jhthorsen/mojo-useragent-role-cache/issues)

## Upgrading from 0.02 to 0.03

Upgrading from version 0.02 to 0.03 will cause all your cached files to be
invalid, since the ["cache\_key"](#cache_key) is changed. If you are using
[Mojo::UserAgent::Role::Cache::Driver::File](https://metacpan.org/pod/Mojo::UserAgent::Role::Cache::Driver::File), you can set the environment
variable `MOJO_UA_CACHE_RENAME=1` to on-the-fly rename the old files to the
new format.

# ATTRIBUTES

## cache\_driver

    $obj = $self->cache_driver;
    $self = $self->cache_driver(CHI->new);

Holds an object that will get/set the HTTP messages. Default is
[Mojo::UserAgent::Role::Cache::Driver::File](https://metacpan.org/pod/Mojo::UserAgent::Role::Cache::Driver::File), but any backend that supports
`get()` and `set()` should do. This means that you can use [CHI](https://metacpan.org/pod/CHI) if you
like.

## cache\_key

    $code = $self->cache_key;
    $self = $self->cache_key(sub { my $tx = shift; return $tx->req->url });

Holds a code ref that returns an array-ref of the key parts that is passed on
to `get()` or `set()` in the ["cache\_driver"](#cache_driver).

This works with [CHI](https://metacpan.org/pod/CHI) as well, since CHI will serialize the key if it is a
reference.

The default is EXPERIMENTAL, but returns this value for now:

    [
      $http_method, # get, post, ...
      $host,        # no port
      $path_query,  # /foo?x=42
      md5($body),   # but not for GET
    ]

## cache\_strategy

    $code = $self->cache_strategy;
    $self = $self->cache_strategy(sub { my $tx = shift; return "passthrough" });

Used to set up a callback to return a cache strategy. Default value is read
from the `MOJO_USERAGENT_CACHE_STRATEGY` environment variable or
"playback\_or\_record".

The return value from the `$code` can be one of:

- passthrough

    Will disable any caching.

- playback

    Will never send a request to the remote server, but only look for recorded
    messages.

- playback\_or\_record

    Will return a recorded message if it exists, or fetch one from the remote
    server and store the response.

- record

    Will always fetch a new response from the remote server and store the response.

# METHODS

## cache\_driver\_singleton

    $obj = Mojo::UserAgent::Role::Cache->cache_driver_singleton;
    Mojo::UserAgent::Role::Cache->cache_driver_singleton($obj);

Used to retrieve or set the default ["cache\_driver"](#cache_driver). Useful for setting up
caching globally in unit tests.

# AUTHOR

Jan Henning Thorsen

# COPYRIGHT AND LICENSE

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

# SEE ALSO

[Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent),
[https://metacpan.org/pod/Mojo::UserAgent::Cached](https://metacpan.org/pod/Mojo::UserAgent::Cached) and
[https://metacpan.org/pod/Mojo::UserAgent::Mockable](https://metacpan.org/pod/Mojo::UserAgent::Mockable).
