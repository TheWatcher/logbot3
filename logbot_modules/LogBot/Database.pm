## @file
# This file contains the implementation of the Database model class.
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

## @class LogBot::Database
# This class contains the code required to store log events in a
# database. It should be database agnostic, but has only been tested
# with MySQL/MariaDB.
#
# Note that all time fields are stored as unsigned bigint fields, and
# time() is used to set the UTC timestamp rather than UNIX_TIMESTAMP()
# to ensure we can avoid Y2038 issues.

package LogBot::Database;

use strict;
use v5.14;
use DBI;
use LogBot::Utils qw(hash_or_hashref);


# ============================================================================
#  Connect and cleanup

## @method $ new()
# Construct a new LogBot::Database object
#
sub new {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = {
        @_,
    };

    return bless $self, $class;
}


## @method $ connect($source, $username, $password, $settings)
# Attempt to connect to the database with the specified credentials. This will
# try to establish the database connection and check that the tables needed
# are present.
#
# @param source   A DBI source string, 'DBI::mysql:logbot' for example
# @param username The username to connect with.
# @param password The password to connect with.
# @param settings A reference to a hash of arguments for DBI/DBD
# @return true on successful connection, undef otherwise
sub connect {
    my $self     = shift;
    my $source   = shift;
    my $username = shift;
    my $password = shift;
    my $settings = shift // { RaiseError => 0, AutoCommit => 1, mysql_enable_utf8mb4 => 1 }; # default for mysql

    $self -> {"dbh"} = DBI->connect($source,
                                    $username,
                                    $password,
                                    $settings)
        or return $self -> self_error("Unable to connect to database: ".$DBI::errstr);

    return $self -> _check_tables();
}


## @method void DESTROY()
# Destructor to clean up resources used by the database. Belt-and-brances
# attempt to ensure database connections are closed cleanly.
#
sub DESTROY {
    local($., $@, $!, $^E, $?);
    my $self = shift;

    # Explicitly disconnect on object destruction. This is probably redundant, as
    # it should happen implicitly anyway, but no harm in being sure.
    $self -> {"dbh"} -> disconnect()
        if($self -> {"dbh"});
}


# ============================================================================
#  Model interaction


## @method $ nick_id($nick)
# Given a nick, obtain an ID to use during logging.
#
# @param nick The nick of the user to get an ID for.
# @return The nick ID on success, undef on error.
sub nick_id {
    my $self = shift;
    my $nick = shift;

    my $id = $self -> _get_nick($nick);

    # id of 0 indicates 'not found, but no error'
    return $id
        unless(defined($id) && $id == 0);

    return $self -> _add_nick($nick);
}


## @method $ channel_id($channel)
# Given a channel, obtain an ID to use during logging.
#
# @param channel The channel to get an ID for.
# @return The channel ID on success, undef on error.
sub channel_id {
    my $self    = shift;
    my $channel = shift;

    my $id = $self -> _get_channel($channel);

    # id of 0 indicates 'not found, but no error'
    return $id
        unless(defined($id) && $id == 0);

    return $self -> _add_channel($channel);
}


## @method $ prefix_id($prefix)
# Given a prefix, obtain an ID to use during logging.
#
# @param prefix The prefix to get an ID for.
# @return The prefix ID on success, undef on error.
sub prefix_id {
    my $self    = shift;
    my $prefix = shift;

    my $id = $self -> _get_prefix($prefix);

    # id of 0 indicates 'not found, but no error'
    return $id
        unless(defined($id) && $id == 0);

    return $self -> _add_prefix($prefix);
}


## @method $ log(%args)
# Log an event in the database. This does translation of nicks, channels, and
# prefixes to the corresponding IDs and stores them in the database. Supported
# arguments are:
#
# - `type`      (required) The event type: 'msg','action','join','part','quit','kick','nick','topic'
# - `channel`   (optional) The channel the event happened in
# - `nick`      (optional) The nick of the user that caused the event
# - `prefix`    (optional) The prefix set for the user (if any)
# - `secondary` (optional) The secondary nick associated with the event
# - `secondary_prefix` (optional) Prefix for the secondary user (if any)
# - `message`   (optional) The message set for the event
# - `timestamp` (optional, not for general use) The timestamp for the event,
#               if not set this defaults to the current time.
#
# @param args A hash or reference to a hash of arguments
# @return true on success, undef on error.
sub log {
    my $self = shift;
    my $args = hash_or_hashref(@_);

    $self -> clear_error();

    # Convert fields to IDs as needed
    $args -> {"channelid"} = $self -> channel_id($args -> {"channel"}) or return undef
        if($args -> {"channel"});

    $args -> {"nickid"}    = $self -> nick_id($args -> {"nick"}) or return undef
        if($args -> {"nick"});

    $args -> {"prefixid"}  = $self -> prefix_id($args -> {"prefix"}) or return undef
        if($args -> {"prefix"});

    $args -> {"snickid"}   = $self -> nick_id($args -> {"secondary"}) or return undef
        if($args -> {"secondary"});

    $args -> {"sprefixid"} = $self -> prefix_id($args -> {"secondary_prefix"}) or return undef
        if($args -> {"secondary_prefix"});

    my $logh = $self -> {"dbh"} -> prepare("INSERT
                                            INTO `log`
                                            (`timestamp`, `channel`, `type`, `nick`, `nick_prefix_id`, `secondary`, `seconday_prefix_id`, `message`)
                                            VALUES(?, ?, ?, ?, ?, ?, ?, ?)");
    my $result = $logh -> execute($args -> {"timestamp"} // time(),
                                  $args -> {"channelid"},
                                  $args -> {"type"},
                                  $args -> {"nickid"},
                                  $args -> {"prefixid"},
                                  $args -> {"snickid"},
                                  $args -> {"sprefixid"},
                                  $args -> {"message"});
    return $self -> self_error("Unable to add log entry: ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Log entry addition failed, no rows inserted") if($result eq "0E0");

    return 1;
}


# ============================================================================
#  Ghastly database internals

## @method private $ _check_tables()
# Determine whether the required tables are present in the database.
#
# @return true if the required tables are present, undef if they are not or on
#         error, in which case errstr() will give a human-readable reason.
sub _check_tables {
    my $self = shift;
    my %expect = ('channels' => 1,
                  'excerpt'  => 1,
                  'log'      => 1,
                  'nicks'    => 1,
                  'prefixes' => 1);

    $self -> clear_error();

    my $tableh = $self -> {"dbh"} -> prepare("SHOW TABLES");
    $tableh -> execute()
        or return $self -> self_error("Unable to check tables: ".$self -> {"dbh"} -> errstr());

    # Go through the table names obtained, checking wether they are expected
    my $count = 0;
    while(my $row = $tableh -> fetchrow_arrayref()) {
        if($expect{$row -> [0]}) {
            ++$count;
        }
    }

    # If the number of expected tables doesn't match the number seen, whine.
    return $self -> self_error("Missing tables in database. Check schema.")
        if($count < scalar(keys(%expect)));

    return 1;
}


## @method private $ _add_nick($nick)
# Create a nick record for the specified nick. This will attempt to create
# an entry in the nicks table for the nick, and return the ID given to it.
#
# @note This will fail with an error if the nick has been added already.
#
# @param nick The ID of the nick to add to the database.
# @return The ID for the new nick row on success, undef on error.
sub _add_nick {
    my $self = shift;
    my $nick = shift;

    $self -> clear_error();

    my $nickh = $self -> {"dbh"} -> prepare("INSERT INTO `nicks`
                                             (`nick`, `last_seen`)
                                             VALUES(?, ?)");
    my $result = $nickh -> execute($nick, time());
    return $self -> self_error("Unable to add nick '$nick': ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Nick addition failed, no rows inserted") if($result eq "0E0");

    my $id = $self -> {"dbh"} -> last_insert_id("", "", "nicks", "")
        or return $self -> self_error("Unable to get ID of inserted nick.");

    return $id;
}


## @method private $ _get_nick($nick, $notseen)
# Given a nickname, attempt to obtain the ID allocated for that nick in the
# database. If this locates the ID for the specified nick, it will update
# the last_seen timestamp for the nick, unless notseen is set to true.
#
# @param nick    The nick to get the ID for
# @param notseen If true, the nick hasn't been seen, so don't update the
#                last_seen timestamp. Defaults to false (that is, the nick
#                has been seen, so the timestamp should update)
# @return The ID for the nick on success, undef on error.
sub _get_nick {
    my $self    = shift;
    my $nick    = shift;
    my $notseen = shift;

    $self -> clear_error();

    my $nickh = $self -> {"dbh"} -> prepare("SELECT `id`
                                             FROM `nicks`
                                             WHERE `nick` LIKE ?");
    $nickh -> execute($nick)
        or return $self -> self_error("Unable to perform nick lookup: ".$self -> {"dbh"} -> errstr);

    my $data = $nickh -> fetchrow_arrayref()
        or return 0;

    # Unless the nick hasn't been seen (get was called for some other reason
    # than logging), update the last seen timestamp.
    unless($notseen) {
        my $updateh = $self -> {"dbh"} -> prepare("UPDATE `nicks`
                                                   SET `last_seen` = ?
                                                   WHERE `id` = ?");
        my $result = $updateh -> execute(time(), $data -> [0]);
        return $self -> self_error("Unable to set last seen for nick '$nick': ". $self -> {"dbh"} -> errstr) if(!$result);
        return $self -> self_error("Nick last seen update failed, no rows changed") if($result eq "0E0");
    }

    return $data -> [0];
}


## @method private $ _add_channel($channel)
# Create a channel record for the specified channel. This will attempt
# to create an entry in the channels table for the channel, and return
# the ID given to it.
#
# @note This will fail with an error if the channel has been added already.
#
# @param nick The ID of the channel to add to the database.
# @return The ID for the new channel row on success, undef on error.
sub _add_channel {
    my $self    = shift;
    my $channel = shift;

    $self -> clear_error();

    my $channelh = $self -> {"dbh"} -> prepare("INSERT INTO `channels`
                                                (`name`)
                                                VALUES(?)");
    my $result = $channelh -> execute($channel);
    return $self -> self_error("Unable to add channel '$channel': ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Channel addition failed, no rows inserted") if($result eq "0E0");

    my $id = $self -> {"dbh"} -> last_insert_id("", "", "channels", "")
        or return $self -> self_error("Unable to get ID of inserted channel.");

    return $id;
}


## @method private $ _get_channel($channel)
# Given a channel, attempt to obtain the ID allocated for that channel in the
# database.
#
# @param channel The channel to get the ID for
# @return The ID for the channel on success, undef on error.
sub _get_channel {
    my $self    = shift;
    my $channel = shift;

    $self -> clear_error();

    my $channelh = $self -> {"dbh"} -> prepare("SELECT `id`
                                                FROM `channels`
                                                WHERE `name` LIKE ?");
    $channelh -> execute($channel)
        or return $self -> self_error("Unable to perform channel lookup: ".$self -> {"dbh"} -> errstr);

    my $data = $channelh -> fetchrow_arrayref()
        or return 0;

    return $data -> [0];
}


## @method private $ _add_prefix($prefix)
# Create a prefix record for the specified prefix. This will attempt
# to create an entry in the prefixs table for the prefix, and return
# the ID given to it.
#
# @note This will fail with an error if the prefix has been added already.
#
# @param nick The ID of the prefix to add to the database.
# @return The ID for the new prefix row on success, undef on error.
sub _add_prefix {
    my $self   = shift;
    my $prefix = shift;

    $self -> clear_error();

    my $prefixh = $self -> {"dbh"} -> prepare("INSERT INTO `prefixes`
                                               (`prefix`)
                                               VALUES(?)");
    my $result = $prefixh -> execute($prefix);
    return $self -> self_error("Unable to add prefix '$prefix': ". $self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Prefix addition failed, no rows inserted") if($result eq "0E0");

    my $id = $self -> {"dbh"} -> last_insert_id("", "", "prefixes", "")
        or return $self -> self_error("Unable to get ID of inserted prefix.");

    return $id;
}


## @method private $ _get_prefix($prefix)
# Given a prefix, attempt to obtain the ID allocated for that prefix in the
# database.
#
# @param prefix The prefix to get the ID for
# @return The ID for the prefix on success, undef on error.
sub _get_prefix {
    my $self   = shift;
    my $prefix = shift;

    $self -> clear_error();

    my $prefixh = $self -> {"dbh"} -> prepare("SELECT `id`
                                               FROM `prefixes`
                                               WHERE `prefix` = ?");
    $prefixh -> execute($prefix)
        or return $self -> self_error("Unable to perform prefix lookup: ".$self -> {"dbh"} -> errstr);

    my $data = $prefixh -> fetchrow_arrayref()
        or return 0;

    return $data -> [0];
}


# ============================================================================
#  Error functions

## @method private $ self_error($errstr)
# Set the object's errstr value to an error message, and return undef. This
# function supports error reporting in various methods throughout the class.
#
# @param errstr The error message to store in the object's errstr.
# @return Always returns undef.
sub self_error {
    my $self = shift;
    $self -> {"errstr"} = shift;

    return undef;
}


## @method private void clear_error()
# Clear the object's errstr value. This is a convenience function to help
# make the code a bit cleaner.
sub clear_error {
    my $self = shift;

    $self -> self_error(undef);
}


## @method $ errstr()
# Return the current value set in the object's errstr value. This is a
# convenience function to help make code a little cleaner.
sub errstr {
    my $self = shift;

    return $self -> {"errstr"};
}

1;