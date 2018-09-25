package Mojo::UserAgent::Role::Cache;
use Mojo::Base -role;

use Mojo::UserAgent::Role::Cache::Driver::File;

our $VERSION = '0.01';

has cache_driver => sub { shift->cache_driver_singleton };

sub cache_driver_singleton {
  my $class = shift;
  state $driver = Mojo::UserAgent::Role::Cache::Driver::File->new;
  return $driver unless @_;
  $driver = shift;
  return $class;
}

1;
