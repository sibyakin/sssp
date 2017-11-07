#!/usr/bin/env perl
#===============================================================================
#
#         FILE: socks.pl
#
#        USAGE: USER=user PASSWORD=password ./socks.pl
#
#  DESCRIPTION: simple socks5 server for home use
#
#      OPTIONS: ---
# REQUIREMENTS: ---
#         BUGS: ---
#        NOTES: heavily based on github.com/olegwtf/p5-IO-Socket-Socks/blob/master/examples/server5.pl
#       AUTHOR: Alexey Sibyakin (sibyakin@yahoo.com)
# ORGANIZATION:
#      VERSION: 1.0
#      CREATED: 2017-11-05 10:31:08 AM
#     REVISION: ---
#===============================================================================

use utf8;
use 5.022;
use warnings;

use Carp;
use IO::Select;
use IO::Socket::Socks qw(:constants $SOCKS_ERROR);

$IO::Socket::Socks::SOCKS5_RESOLVE = 1;

my $user     = $ENV{'SOCKS_USER'};
my $password = $ENV{'SOCKS_PASSWORD'};

croak "USER ENV is not specified!"     unless ($user);
croak "PASSWORD ENV is not specified!" unless ($password);

my $server = IO::Socker::Socks->new(
    ProxyAddr  => '0.0.0.0',
    ProxyPort  => 8081,
    Listen     => 1,
    UserAuth   => \&auth,
    ReqireAuth => 1
) or croak $SOCKS_ERROR;

while () {
    my $client = $server->accept();
    unless ($client) {
        say "ERR: $SOCKS_ERROR";
        next;
    }

    my $command = $client->command();
    if ( $command->[0] == CMD_CONNECT ) {
        my $socket = IO::Socket::INET->new(
            PeerHost => $command->[1],
            PeerPort => $command->[2],
            Timeout  => 10
        );

        if ($socket) {
            $client->command_reply( REPLY_SUCCESS, $socket->sockhost,
                $socket->sockport );
        }
        else {
            $client->command_reply( REPLY_HOST_UNREACHABLE, $command->[1],
                $command->[2] );
            $client->close;
            next;
        }

        my $selector = IO::Select->new( $socket, $client );

      CONNECT: while () {
            my @ready = $selector->can_read();
            for my $s (@ready) {
                my $readed = $s->sysread( my $data, 1024 );
                unless ($readed) {
                    carp 'connection closed';
                    $socket->close();
                    last CONNECT;
                }

                if ( $s == $socket ) {
                    $client->syswrite($data);
                }
                else {
                    $socket->syswrite($data);
                }
            }
        }
    }
    elsif ( $command->[0] == CMD_BIND ) {
        my $socket = IO::Socket::INET->new( Listen => 10 );

        if ($socket) {
            $client->command_reply( REPLY_SUCCESS, $socket->sockhost,
                $socket->sockport );
        }
        else {
            $client->command_reply( REPLY_HOST_UNREACHABLE, $command->[1], $command->[2] );
            $client->close();
            next;
        }

        while () {
            my $conn = $socket->accept() or next;
            $socket->close();
            if (
                $conn->peerhost ne join( '.',
                    unpack( 'C4', ( gethostbyname( $command->[1] ) )[4] ) )
              )
            {
                last;
            }

            $client->command_reply( REPLY_SUCCESS, $conn->peerhost,
                $conn->peerport );

            my $selector = IO::Select->new( $conn, $client );

          BIND: while () {
                my @ready = $selector->can_read();
                for my $s (@ready) {
                    my $readed = $s->sysread( my $data, 1024 );
                    unless ($readed) {
                        carp 'connection closed';
                        $conn->close();
                        last BIND;
                    }

                    if ( $s == $conn ) {
                        $client->syswrite($data);
                    }
                    else {
                        $conn->syswrite($data);
                    }
                }

            }

            last;
        }
    }
    elsif ( $command->[0] == CMD_UDPASSOC ) {
        carp 'UDP assoc not yet implemented';
        $client->command_reply( REPLY_GENERAL_FAILURE, $command->[1],
            $command->[2] );
    }
    else {
        carp 'Unknown command';
    }

}

sub auth {
    my $login    = shift;
    my $password = shift;

    my %allowed_users = ( root => 123 );
    return $allowed_users{$login} eq $password;
}
