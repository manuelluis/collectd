#!/usr/bin/perl
# $Id: Collectd.pm 4 2006-12-02 15:18:14Z formorer $

=head1 NAME

Collectd - plugin for filling collectd with stats 

=head1 INSTALLATION

Just copy Collectd.pm into your SpamAssassin Plugin path 
(e.g /usr/share/perl5/Mail/SpamAssassin/Plugin/) and
add a loadplugin call into your init.pre file. 

=head1 SYNOPSIS

  loadplugin    Mail::SpamAssassin::Plugin::Collectd

=head1 USER SETTINGS

=over 4

=item collectd_socket [ socket path ]	    (default: /tmp/.collectd-email)

Where the collectd socket is

=cut 

=item collectd_buffersize [ size ] (default: 256) 

the email plugin uses a fixed buffer, if a line exceeds this size
it has to be continued in another line. (This is of course handled internally)
If you have changed this setting please get it in sync with the SA Plugin
config. 

=cut 
=head1 DESCRIPTION

This modules uses the email plugin of collectd from Sebastian Harl to
collect statistical informations in rrd files to create some nice looking
graphs with rrdtool. They communicate over a unix socket that the collectd
plugin creates. The generated graphs will be placed in /var/lib/collectd/email

=head1 AUTHOR

Alexander Wirt <formorer@formorer.de>

=head1 COPYRIGHT

 Copyright 2006 Alexander Wirt <formorer@formorer.de> 
 
 Licensed under the Apache License,  Version 2.0 (the "License"); 
 you may not use this file except in compliance
 with the License. You may obtain a copy of the License at
 http://www.apache.org/licenses/LICENSE-2.0 Unless required 
 by applicable law or agreed to in writing, software distributed 
 under the License is distributed on an "AS IS" BASIS, WITHOUT 
 WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
 See the License for the specific language governing permissions 
 and limitations under the License.

=cut

package Mail::SpamAssassin::Plugin::Collectd;

use Mail::SpamAssassin::Plugin;
use Mail::SpamAssassin::Logger;
use strict;
use bytes; 
use warnings;
use IO::Socket;

use vars qw(@ISA);
@ISA = qw(Mail::SpamAssassin::Plugin);

sub new {
    my ($class, $mailsa) = @_;

    # the usual perlobj boilerplate to create a subclass object
    $class = ref($class) || $class;
    my $self = $class->SUPER::new($mailsa);
    bless ($self, $class);

    # register our config options
    $self->set_config($mailsa->{conf});

    # and return the new plugin object
    return $self;
}

sub set_config {
    my ($self, $conf) = @_;
    my @cmds = ();

    push (@cmds, {
	    setting => 'collectd_buffersize',
	    default => 256,
	    type =>
	    $Mail::SpamAssassin::Conf::CONF_TYPE_NUMERIC,
	});

    push (@cmds, {
	    setting => 'collectd_socket', 
	    default => '/tmp/.collectd-email',
	    type => $Mail::SpamAssassin::Conf::CONF_TYPE_STRING,
    });

    $conf->{parser}->register_commands(\@cmds);
}

sub check_end {
    my ($self, $params) = @_;
    my $message_status = $params->{permsgstatus};
	#create  new connection to our socket
	my $sock = new IO::Socket::UNIX ( $self->{main}->{conf}->{collectd_socket});
	# debug some informations if collectd is not running or anything else went
	# wrong
	if ( ! $sock ) {
		dbg("collect: could not connect to " .
			$self->{main}->{conf}->{collectd_socket} . ": $! - collectd plugin
			disabled"); 
		return 0; 
	}
	$sock->autoflush(1);

	my $score = $message_status->{score};
	#get the size of the message 
	my $body = $message_status->{msg}->{pristine_body};

	my $len = length($body);

	if ($message_status->{score} >= $self->{main}->{conf}->{required_score} ) {
		#hey we have spam
		print $sock "e:spam:$len\n";
	} else {
		print $sock "e:ham:$len\n";
	}
	print $sock "s:$score\n";
	my @tmp_array; 
	my @tests = @{$message_status->{test_names_hit}};

	my $buffersize = $self->{main}->{conf}->{collectd_buffersize}; 
	dbg("collectd: buffersize: $buffersize"); 

	while  (scalar(@tests) > 0) {
	 push (@tmp_array, pop(@tests)); 
		if (length(join(',', @tmp_array) . '\n') > $buffersize) {
			push (@tests, pop(@tmp_array)); 
				if (length(join(',', @tmp_array) . '\n') > $buffersize or scalar(@tmp_array) == 0) {
					dbg("collectd: this shouldn't happen. Do you have tests"
						." with names that have more than ~ $buffersize Bytes?");
					return 1; 
				} else {
					dbg ( "collectd: c:" . join(',', @tmp_array) . "\n" ); 
					print $sock "c:" . join(',', @tmp_array) . "\n"; 
					#clean the array
					@tmp_array = ();
				} 
		} elsif ( scalar(@tests) == 0 ) {
			dbg ( "collectd: c:" . join(',', @tmp_array) . '\n' );
			print $sock "c:" . join(',', @tmp_array) . "\n";
		}
	}
	close($sock); 
}

1;

# vim: syntax=perl sw=4 ts=4 noet shiftround
