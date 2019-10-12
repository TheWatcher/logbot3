## @file
#
# @author  Chris Page &lt;chris@starforge.co.uk&gt;

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see http://www.gnu.org/licenses/.

use strict;
use v5.14;
use experimental qw(smartmatch);

use Irssi qw(command);
use Irssi::Irc;
use IRC::Formatting::HTML qw(irc_to_html);
use Data::Dumper;

our $path;
BEGIN {
    $path = "~/.irssi/scripts/logbot_modules";
    $path =~ s{^~([^/]*)}{$1 ? (getpwnam($1))[7] : (getpwuid($<))[7] }e;
}

use lib "$path";
use LogBot::Utils;
use LogBot::Database;


# =============================================================================
#  Global stuff

use constant CONFIG_PATH    => "~/.irssi/logbot.yaml";

our $VERSION = "3.0";
our %IRSSI = (
    authors     => "TheWatcher",
    contact     => "chris\@starforge.co.uk",
    name        => "LogBot3",
    description => "Logging tools",
    license     => "GPLv2",
    );

# These must, alas, be global as there's no other clean
# way to pass them into the signal handlers.
my $settings = load_settings(CONFIG_PATH);
my $database = LogBot::Database -> new();


# =============================================================================
#  Support functions

## @fn $ load_settings($path)
# Load the configuration for logbot.
#
# @return A reference to an object containing the logbot configuration.
sub load_settings {
    my $path = shift;

    # Note that this does not use standard Irssi configuration
    # options. In part because working with them is a pain, and
    # in part because they don't support sections to divide the
    # configuration up sensibly. But mainly the first bit.
    my $config = LogBot::Utils::load_yaml($path);

    return $config;
}


## @fn $ convert_formatting($msg)
# Given a message that may contain IRC-style formatting codes, generate a
# string containing HTML formatting to represent the formatting.
#
# @param msg A string containing IRC-style formatting codes.
# @return A string containing HTML
sub convert_formatting {
    my $msg = shift;

    my $html = irc_to_html($msg, invert => "italic");

    # Remove the redundant empty style wrappers added by irc_to_html()
    $html =~ s{<span style="">(.*?)</span>}{$1}g;

    return $html;
}


## @fn $ nick_prefix($server, $channel, $nick)
# Determine the prefix for the given nick in the specified channel on the
# provided server.
#
# @param server  A reference to a server object.
# @param channel The name of the channel the user is in.
# @param nick    The nick to fetch the prefix for.
# @return The prefix for the nick, or undef if the user has no prefix.
sub nick_prefix {
    my $server  = shift;
    my $channel = shift;
    my $nick    = shift;

    my $chan = $server -> channel_find($channel);
    my $data = $chan -> nick_find($nick);

    return $data -> {"prefixes"};
}


# =============================================================================
#  IRC signal handler functions

sub sig_message {
    my ($server, $msg, $nick, $address, $channel) = @_;

    return unless($server -> {"tag"} eq $settings -> {"server"} -> {"name"});

    $database -> log(type    => 'msg',
                     channel => $channel,
                     nick    => $nick,
                     prefix  => nick_prefix($server, $channel, $nick),
                     message => convert_formatting($msg))
        or Irssi::print($IRSSI{"name"}." ERROR: ".$database -> errstr());
}


sub sig_own_message {
    my ($server, $msg, $channel) = @_;

    sig_message($server, $msg, $server -> {"nick"}, '', $channel);
}


sub sig_action {
    my ($server, $msg, $nick, $address, $channel) = @_;

    return unless($server -> {"tag"} eq $settings -> {"server"} -> {"name"});

    $database -> log(type    => 'action',
                     channel => $channel,
                     nick    => $nick,
                     prefix  => nick_prefix($server, $channel, $nick),
                     message => convert_formatting($msg))
        or Irssi::print($IRSSI{"name"}." ERROR: ".$database -> errstr());
}


sub sig_own_action {
    my ($server, $msg, $channel) = @_;

    sig_action($server, $msg, $server -> {"nick"}, '', $channel);
}


sub sig_join {
    my ($server, $channel, $nick, $address) = @_;

    return unless($server -> {"tag"} eq $settings -> {"server"} -> {"name"});

    $database -> log(type    => 'join',
                     channel => $channel,
                     nick    => $nick,
                     prefix  => nick_prefix($server, $channel, $nick))
        or Irssi::print($IRSSI{"name"}." ERROR: ".$database -> errstr());
}


sub sig_part {
    my ($server, $channel, $nick, $address, $msg) = @_;

    return unless($server -> {"tag"} eq $settings -> {"server"} -> {"name"});

    $database -> log(type    => 'part',
                     channel => $channel,
                     nick    => $nick,
                     prefix  => nick_prefix($server, $channel, $nick),
                     message => convert_formatting($msg))
        or Irssi::print($IRSSI{"name"}." ERROR: ".$database -> errstr());
}


sub sig_quit {
    my ($server, $nick, $address, $msg) = @_;

    return unless($server -> {"tag"} eq $settings -> {"server"} -> {"name"});

    $database -> log(type    => 'quit',
                     nick    => $nick,
                     message => convert_formatting($msg))
        or Irssi::print($IRSSI{"name"}." ERROR: ".$database -> errstr());
}


sub sig_kick {
    my ($server, $channel, $nick, $kicker, $address, $msg) = @_;

    return unless($server -> {"tag"} eq $settings -> {"server"} -> {"name"});

    $database -> log(type      => 'kick',
                     channel   => $channel,
                     nick      => $nick,
                     prefix    => nick_prefix($server, $channel, $nick),
                     secondary => $kicker,
                     secondary_prefix => nick_prefix($server, $channel, $kicker),
                     message   => convert_formatting($msg))
        or Irssi::print($IRSSI{"name"}." ERROR: ".$database -> errstr());
}


sub sig_nick {
    my ($server, $newnick, $oldnick, $address) = @_;

    return unless($server -> {"tag"} eq $settings -> {"server"} -> {"name"});

    $database -> log(type      => 'nick',
                     nick      => $newnick,
                     secondary => $oldnick)
        or Irssi::print($IRSSI{"name"}." ERROR: ".$database -> errstr());
}


sub sig_topic {
    my ($server, $channel, $msg, $nick, $address) = @_;

    return unless($server -> {"tag"} eq $settings -> {"server"} -> {"name"});

    $database -> log(type    => 'topic',
                     channel => $channel,
                     nick    => $nick,
                     prefix  => nick_prefix($server, $channel, $nick),
                     message => convert_formatting($msg))
        or Irssi::print($IRSSI{"name"}." ERROR: ".$database -> errstr());
}


# =============================================================================
#  Setup code

# Attempt to get somewhere to log to!
my $connected = $database -> connect($settings -> {"database"} -> {"source"},
                                     $settings -> {"database"} -> {"username"},
                                     $settings -> {"database"} -> {"password"},
                                     $settings -> {"database"} -> {"settings"});

# Connection was successful - set up the signal handlers
if($connected) {
    Irssi::signal_add('message public'        , 'sig_message');
    Irssi::signal_add('message own_public'    , 'sig_own_message');
    Irssi::signal_add("message irc action"    , 'sig_action');
    Irssi::signal_add("message irc own_action", 'sig_own_action');
    Irssi::signal_add("message join"          , 'sig_join');
    Irssi::signal_add("message part"          , 'sig_part');
    Irssi::signal_add("message quit"          , 'sig_quit');
    Irssi::signal_add("message kick"          , 'sig_kick');
    Irssi::signal_add("message nick"          , 'sig_nick');
    Irssi::signal_add("message own_nick"      , 'sig_nick');
    Irssi::signal_add("message topic"         , 'sig_topic');

    Irssi::print($IRSSI{"name"}." $VERSION by TheWatcher loaded.");

# Connection failed - whine about it.
} else {
    Irssi::print($IRSSI{"name"}." $VERSION by TheWatcher load failed: ".$database -> errstr());
}
