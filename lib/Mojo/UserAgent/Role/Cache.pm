package Mojo::UserAgent::Role::Cache;
use Mojo::Base -role;

# See also
# - https://metacpan.org/pod/Mojo::UserAgent::Cached
# - https://metacpan.org/pod/Mojo::UserAgent::Mockable

use Mojo::UserAgent::Role::Cache::Driver::File;
use Mojo::Util 'term_escape';

use constant DEBUG => $ENV{MOJO_CLIENT_DEBUG} || 0;

our $VERSION = '0.01';

has cache_driver => sub { shift->cache_driver_singleton };
has cache_mode => sub { $ENV{MOJO_USERAGENT_CACHE_MODE} || 'playback_or_record' };

sub cache_driver_singleton {
  my $class = shift;
  state $driver = Mojo::UserAgent::Role::Cache::Driver::File->new;
  return $driver unless @_;
  $driver = shift;
  return $class;
}

around start => sub {
  my ($orig, $self, $tx) = (shift, shift, shift);

  my $mode = $self->cache_mode;
  warn qq(-- Cache mode is "$mode" (@{[_url($tx)]})\n) if DEBUG and !$self->{cache_passthrough};
  return $self->$orig($tx, @_) if $mode eq 'passthrough' or delete $self->{cache_passthrough};

  my $method = $self->can("_cache_start_$mode");
  Carp::confess(qq(:Mojo::UserAgent::Role::Cache] Invalid mode "$mode".)) unless $method;
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
