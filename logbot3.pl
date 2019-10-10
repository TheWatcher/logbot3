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
use Data::Dumper;

our $path;
BEGIN {
    $path = "~/.irssi/scripts/logbot_modules";
    $path =~ s{^~([^/]*)}{$1 ? (getpwnam($1))[7] : (getpwuid($<))[7] }e;
}

use lib "$path";
Irssi::print("path: $path");
use LogBot::Utils;
use LogBot::Database;

use constant CONFIG_PATH    => "~/.irssi/logbot.yaml";

our $VERSION = "3.0";
our %IRSSI = (
    authors     => "TheWatcher",
    contact     => "chris\@starforge.co.uk",
    name        => "LogBot3",
    description => "Logging tools",
    license     => "GPLv2",
    );


my $settings = load_settings(CONFIG_PATH);
my $database = LogBot::Database -> new();


sub load_settings {
    my $path = shift;

    my $config = LogBot::Utils::load_yaml($path);

    return $config;
}



sub nick_level {
    my $server  = shift;
    my $channel = shift;
    my $nick    = shift;

    my $chan = $server -> channel_find($channel);
    my $data = $chan -> nick_find($nick);

    return $data -> {"prefixes"};
}


sub sig_message {
    my ($server, $msg, $nick, $address, $channel) = @_;

    return unless($server -> {"tag"} eq $settings -> {"server"} -> {"name"});

    $database -> log(type    => 'msg',
                     channel => $channel,
                     nick    => $nick,
                     prefix  => nick_level($server, $channel, $nick),
                     message => $msg)
        or Irssi::print($IRSSI{"name"}." ERROR: ".$database -> errstr());
}


sub sig_own_message {
    my ($server, $msg, $channel) = @_;

    sig_message($server, $msg, $server -> {"nick"}, '', $channel);
}


my $connected = $database -> connect($settings -> {"database"} -> {"source"},
                                     $settings -> {"database"} -> {"username"},
                                     $settings -> {"database"} -> {"password"},
                                     $settings -> {"database"} -> {"settings"});

if($connected) {

    Irssi::signal_add('message public'    , 'sig_message');
    Irssi::signal_add('message own_public', 'sig_own_message');
#    Irssi::signal_add("ctcp action"       , 'sig_action');
#    Irssi::signal_add("message join"      , 'sig_join');
#    Irssi::signal_add("message part"      , 'sig_part');
#    Irssi::signal_add("message quit"      , 'sig_quit');
#    Irssi::signal_add("message kick"      , 'sig_kick');
#    Irssi::signal_add("message nick"      , 'sig_nick');
#    Irssi::signal_add("message own_nick"  , 'sig_nick');
#    Irssi::signal_add("message topic"     , 'sig_topic');

    Irssi::print($IRSSI{"name"}." $VERSION by TheWatcher loaded.");

} else {

    Irssi::print($IRSSI{"name"}." $VERSION by TheWatcher load failed: ".$database -> errstr());
}