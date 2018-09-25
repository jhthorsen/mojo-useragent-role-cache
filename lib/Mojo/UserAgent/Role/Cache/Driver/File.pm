package Mojo::UserAgent::Role::Cache::Driver::File;
use Mojo::Base -base;

use Mojo::File;
use Mojo::Util;

has root_dir => sub { $ENV{MOJO_USERAGENT_CACHE_DIR} || Mojo::File::tempdir('mojo-useragent-cache-XXXXX') };

sub get {
  my $self = shift;
  my $file = $self->_file($self->root_dir, shift);
  return -e $file ? $file->slurp : undef;
}

sub remove {
  my $self = shift;
  my $file = $self->_file($self->root_dir, shift);
  unlink $file or die "unlink $file: $!" if -e $file;
  return $self;
}

sub set {
  my $self = shift;
  my $file = $self->_file($self->root_dir, shift);
  my $dir  = Mojo::File->new($file->dirname);
  $dir->make_path({mode => 0755}) unless -d $dir;
  $file->spurt(shift);
  return $self;
}

sub _file {
  my $self = shift;
  local $_ = Mojo::Util::url_escape(shift, '^A-Za-z0-9_/.-');
  s#//#/#g;
  s#%#+#g;
  return Mojo::File->new($self->root_dir, $_);
}

1;
