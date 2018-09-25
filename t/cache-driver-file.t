use Mojo::Base -strict;
use Test::More;
use Mojo::UserAgent;

my $url
  = 'https://supergirl:for-testing@www.google.com/search?source=hp&ei=yXXXXXXzXXX00yXXz5XXXX&btnG=X%C3%B8y&q=mojolicious&gs_l=xyz-xy.3..0x000y0l0j0i00x00x0y0.000000.000000.0.000000.00.00.0.0.0.0.000.0000.0.0x0y0.0.0....0...0z.1.00.xyz-xy..00.0.0000.0..0.0.0xYZz00yZ0z';

my $ua     = Mojo::UserAgent->with_roles('+Cache')->new;
my $driver = $ua->cache_driver;
is $driver, $ua->cache_driver_singleton, 'using cache_driver_singleton';

is $driver->get($url), undef, 'get';

is $driver->set($url, {x => 42}), $driver, 'set';
is_deeply $driver->get($url), {x => 42}, 'get after set';

is $driver->remove($url), $driver, 'remove';
is $driver->get($url), undef, 'get after remove';

done_testing;
