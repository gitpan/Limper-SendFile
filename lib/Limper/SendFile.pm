package Limper::SendFile;
$Limper::SendFile::VERSION = '0.001';
use base 'Limper';
use 5.10.0;
use strict;
use warnings;

package Limper;
$Limper::VERSION = '0.001';
use File::Slurp;
use Time::Local 'timegm';

push @Limper::EXPORT, qw/public send_file/;
push @Limper::EXPORT_OK, qw/parse_date/;

my $public = './public/';

sub public {
    if (defined wantarray) { $public } else { ($public) = @_ }
}

# parse whatever crappy date a client might give
my @months = qw/Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec/;
sub parse_date {
    my ($d, $m, $y, $h, $n, $s) = $_[0] =~ qr/^(?:\w+), (\d\d)[ -](\w+)[ -](\d\d(?:\d\d)?) (\d\d):(\d\d):(\d\d) GMT$/;
    ($m, $d, $h, $n, $s, $y) = $_[0] =~ qr/^(?:\w+) (\w+) ([ \d]\d) (\d\d):(\d\d):(\d\d) (\d{4})$/ unless defined $d;
    return 0 unless defined $d;
    timegm( $s, $n, $h, $d, (grep { $months[$_] eq $m } 0..$#months)[0], $y + (length $y == 2 ? 1900 : 0) );
}

# support If-Modified-Since and If-Unmodified-Since
hook after => sub {
    my ($request, $response) = @_;
    if ($request->{method} // '' eq 'GET' and substr($response->{status} // 200, 0, 1) == 2 and
            my ($lm) = grep { lc $_ eq 'last-modified' } @{$response->{headers}}) {
        for my $since (grep { /if-(?:un)?modified-since/ } keys %{$request->{hheaders}}) {
            next if $since eq 'if-modified-since' and ($response->{status} // 200) != 200;
            if (parse_date($request->{hheaders}{$since}) >= parse_date({@{$response->{headers}}}->{$lm})) {
                $response->{body} = '';
                $response->{status} = $since eq 'if-modified-since' ? 304 : 412;
            }
        }
    }
};

use JSON();
sub send_file {
    my ($file) = @_ || request->{uri};

    $file =~ s{^/}{$public/};
    if ($file =~ qr{/\.\./}) {
        status 403;
        return 'Forbidden';
    }
    if (-e $file and -r $file) {
        if (-f $file) {
            $file =~ /\.html$/ and headers 'Content-Type' => 'text/html';
            open my $fh, '<', $file;
            headers 'Last-Modified' => rfc1123date((stat($fh))[9]);
            scalar read_file $file;
        } elsif (-d $file) {
            opendir my($dh), $file;
            my @files = sort grep { !/^\./ } readdir $dh;
            @files = map { "<a href=\"$_\">$_</a><br>" } @files;
            headers 'Content-Type' => 'text/html';
            join "\n", '<html><head><title>Directory listing of ' . request->{uri} . '</title></head><body>', @files, '</body></html>';
        } else {
            status 500;
            $Limper::reasons->{500};
        }
    } else {
        status 404;
        'This is the void';
    }
};

1;

__END__

=for Pod::Coverage

=head1 NAME

Limper::SendFile - add static content support to Limper

=head1 VERSION

version 0.001

=head1 SYNOPSIS

  # order is important:
  use Limper::SendFile;
  use Limper;

  # some other routes

  get qr{^/} => sub {
      send_file;        # sends request->{uri} by default
  };

  limp;

=head1 DESCRIPTION

C<Limper::SendFile> extends C<Limper> to also return actual files. Because sometimes that's needed.

=head1 EXPORTS

The following are all additionally exported by default:

  public send_file

=head1 FUNCTIONS

=head2 send_file

Sends either the file name given, or the value of C<< request->{uri} >> if no file name given.

The following as the last defined route will have C<Limper> look for the file as a last resort:

  get qr{^/} => sub { send_file }

Note: currently this only changes content-type for files ending in B<.html>, otherwise content-type is set to B<text/plain>.

=head2 public

Get or set the public root directory. Default is C<./public/>.

  my $public = public;

  public '/var/www/langlang.us/public_html';

=head1 ADDITIONAL FUNCTIONS

=head2 parse_date

Liberally parses whatever date a client might give, returning a Unix timestamp.

  # these all return 784111777
  my $date = parse_date("Sun, 06 Nov 1994 08:49:37 GMT");
  my $date = parse_date("Sunday, 06-Nov-94 08:49:37 GMT");
  my $date = parse_date("Sun Nov  6 08:49:37 1994");

=head1 HOOKS

=head2 after

An B<after> hook is created to support B<If-Modified-Since> and B<If-Unmodified-Since>, comparing to B<Last-Modified>.
This runs for all defined routes, not just those using C<send_file>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014 by Ashley Willis E<lt>ashley+perl@gitable.orgE<gt>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.12.4 or,
at your option, any later version of Perl 5 you may have available.

=head1 SEE ALSO

L<Limper>
