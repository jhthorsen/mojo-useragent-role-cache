package Mojo::UserAgent::Role::Cache;
use Mojo::Base -role;

use Mojo::UserAgent::Role::Cache::Driver::File;
use Mojo::Util 'term_escape';

use constant DEBUG => $ENV{MOJO_CLIENT_DEBUG} || 0;

our $VERSION = '0.01';

has cache_driver => sub { shift->cache_driver_singleton };
has cache_strategy => sub {
  my $strategy = $ENV{MOJO_USERAGENT_CACHE_STRATEGY} || 'playback_or_record';
  my @strategies = map { split /=/, $_, 2 } split '&', $strategy;
  my %strategies = @strategies == 1 ? () : @strategies;

  return !%strategies ? sub {$strategy} : sub {
    my $method = uc shift->req->method;
    return $strategies{$method} || $strategies{DEFAULT} || 'playback_or_record';
  };
};

sub cache_driver_singleton {
  my $class = shift;
  state $driver = Mojo::UserAgent::Role::Cache::Driver::File->new;
  return $driver unless @_;
  $driver = shift;
  return $class;
}

around start => sub {
  my ($orig, $self, $tx) = (shift, shift, shift);

  my $strategy = $self->cache_strategy->($tx);
  warn qq(-- Cache strategy is "$strategy" (@{[_url($tx)]})\n) if DEBUG and !$self->{cache_passthrough};
  return $self->$orig($tx, @_) if $strategy eq 'passthrough' or delete $self->{cache_passthrough};

  my $method = $self->can("_cache_start_$strategy");
  Carp::confess(qq([Mojo::UserAgent::Role::Cache] Invalid strategy "$strategy".)) unless $method;
  return $self->$method($tx, @_);
};

sub _url { shift->req->url->to_abs }

sub _cache_get_tx {
  my ($self, $tx_input) = @_;
  my $key = join '/', $tx_input->req->method, $tx_input->req->url;    # TODO - Better key

  my $buffer = $self->cache_driver->get($key);
  return undef unless defined $buffer;

  $tx_input->res->parse($buffer);
  return $tx_input;
}

sub _cache_set_tx {
  my ($self, $tx_input, $tx_output) = @_;
  my $key = join '/', $tx_input->req->method, $tx_input->req->url;    # TODO - Better key
  $self->cache_driver->set($key, $tx_output->res->to_string);
  return $self;
}

sub _cache_start_playback {
  my ($self, $tx_input, $cb) = @_;
  my $tx_output = $self->_cache_get_tx($tx_input);
  my $status = $tx_output ? '<<<' : '!!!';

  # Not in cache
  unless ($tx_output) {
    $tx_output = $tx_input;
    $tx_output->res->error({message => 'Not in cache.'});
  }

  warn term_escape "-- Client >>> Cache (@{[_url($tx_input)]})\n@{[$tx_input->req->to_string]}\n"      if DEBUG;
  warn term_escape "-- Client $status Cache (@{[_url($tx_input)]})\n@{[$tx_output->res->to_string]}\n" if DEBUG;

  # Blocking
  return $tx_output unless $cb;

  # Non-blocking
  Mojo::IOLoop->next_tick(sub { $self->$cb($tx_input) });
  return $self;
}

sub _cache_start_playback_or_record {
  my ($self, $tx_input, $cb) = @_;
  my $tx_output = $self->_cache_get_tx($tx_input);

  # Not cached
  unless ($tx_output) {
    warn term_escape "-- Client !!! Cache (@{[_url($tx_input)]}) - Start recording...\n" if DEBUG;
    return $self->_cache_start_record($tx_input, $cb ? ($cb) : ());
  }

  warn term_escape "-- Client >>> Cache (@{[_url($tx_input)]})\n@{[$tx_input->req->to_string]}\n"  if DEBUG;
  warn term_escape "-- Client <<< Cache (@{[_url($tx_input)]})\n@{[$tx_output->res->to_string]}\n" if DEBUG;

  # Blocking
  return $tx_output unless $cb;

  # Non-blocking
  Mojo::IOLoop->next_tick(sub { $self->$cb($tx_output) });
  return $self;
}

sub _cache_start_record {
  my ($self, $tx_input, $cb) = @_;

  # Make sure we perform the actual request when calling start();
  $self->{cache_passthrough} = 1;

  # Blocking
  unless ($cb) {
    my $tx_output = $self->start($tx_input);
    $self->_cache_set_tx($tx_input, $tx_output);
    return $tx_output;
  }

  # Non-blocking
  $self->start($tx_input, sub { $_[0]->_cache_set_tx($tx_input, $_[1])->$cb($_[1]) });
  return $self;
}

1;

=encoding utf8

=head1 NAME

Mojo::UserAgent::Role::Cache - Role for Mojo::UserAgent that provides caching

=head1 SYNOPSIS

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

=head1 DESCRIPTION

L<Mojo::UserAgent::Role::Cache> is a role for the full featured non-blocking
I/O HTTP and WebSocket user agent L<Mojo::UserAgent>, that provides caching.

=head1 WARNING

L<Mojo::UserAgent::Role::Cache> is still under development, so there will be
changes and there is probably bugs that needs fixing. Please report in if you
find a bug or find this role interesting.

L<https://github.com/jhthorsen/mojo-useragent-role-cache/issues>

=head1 ATTRIBUTES

=head2 cache_driver

  $obj = $self->cache_driver;
  $self = $self->cache_driver(CHI->new);

Holds an object that will get/set the HTTP messages. Default is
L<Mojo::UserAgent::Role::Cache::Driver::File>, but any backend that supports
L<get()> and L<set()> should do.

=head2 cache_strategy

  $code = $self->cache_strategy;
  $self = $self->cache_strategy(sub { my $tx = shift; return "passthrough" });

Used to set up a callback to return a cache strategy. Default value is read
from the C<MOJO_USERAGENT_CACHE_STRATEGY> environment variable or
"playback_or_record".

The return value from the C<$code> can be one of:

=over 2

=item * passthrough

Will disable any caching.

=item * playback

Will never send a request to the remote server, but only look for recorded
messages.

=item * playback_or_record

Will return a recorded message if it exists, or fetch one from the remote
server and store the response.

=item * record

Will always fetch a new response from the remote server and store the response.

=back

=head1 METHODS

=head2 cache_driver_singleton

  $obj = Mojo::UserAgent::Role::Cache->cache_driver_singleton;
  Mojo::UserAgent::Role::Cache->cache_driver_singleton($obj);

Used to retrieve or set the default L</cache_driver>. Useful for setting up
caching globally in unit tests.

=head1 AUTHOR

Jan Henning Thorsen

=head1 COPYRIGHT AND LICENSE

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 SEE ALSO

L<Mojo::UserAgent>,
L<https://metacpan.org/pod/Mojo::UserAgent::Cached> and
L<https://metacpan.org/pod/Mojo::UserAgent::Mockable>.

=cut
