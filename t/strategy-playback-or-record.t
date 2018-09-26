use Mojo::Base -strict;
use Test::More;
use Mojo::UserAgent;

my $url = 'https://mojolicious.org';
my $ua  = Mojo::UserAgent->with_roles('+Cache')->new;

my $error = $ua->get($url)->error;
ok !$error, 'get' or diag $error->{message};

$error = 'Not waited for';
$ua->get_p($url)->then(sub { $error = '' }, sub { $error = shift })->wait;
ok !$error, 'get_p' or diag $error;

done_testing;
