package LogBot::Utils;

use Exporter qw(import);
use YAML::Tiny;
use experimental qw(smartmatch);
use v5.14;

our @EXPORT    = qw();
our @EXPORT_OK = qw(str_to_seconds seconds_to_str caps_counter load_yaml load_file hash_or_hashref);


## @fn $ str_to_seconds($str)
# Convert the number in the specified string to seconds, if possible. The
# string should take the form of a number (possibly including a fractional
# part) optionally followed by a modifier: m for minutes, h for hours, d
# for days. If the modifier is not recognised, it is ignored.
#
# @note This does not support negative numbers.
#
# @param str The string to convert to seconds.
# @return The number of seconds, or 0 if the number is not valid.
sub str_to_seconds {
    my $str = shift;

    my ($value, $modifier) = $str =~ /^(\d+(?:\.\d+)?)\s*([mhd])?/;

    return 0 unless($value);

    given($modifier) {
        when("m") { $value *= 60; }
        when("h") { $value *= 3600; }
        when("d") { $value *= 86400; }
    }

    return $value;
}


## @method $ seconds_to_str($seconds, $short)
# Convert a number of seconds to days/hours/minutes/seconds. This will take
# the specified number of seconds and output a string containing the number
# of days, hours, minutes, and seconds it corresponds to.
#
# @todo This function outputs English only text. Look into translating?
#
# @param seconds The number of seconds to convert.
# @param short   If set, the generates string uses short forms of 'day', 'hour' etc.
# @return A string containing the seconds in a human readable form
sub seconds_to_str {
    my $seconds = shift;
    my $short   = shift;
    my ($frac, $mins, $hours, $days);
    my $result = "";

    # Do nothing to non-digit strings.
    return $seconds
        unless(defined($seconds) && $seconds =~ /^\d+(\.\d+)?$/);

    ($frac)  = $seconds =~ /\.(\d+)$/;
    $days    = int($seconds / (24 * 60 * 60));
    $hours   = ($seconds / (60 * 60)) % 24;
    $mins    = ($seconds / 60) % 60;
    $seconds = $seconds % 60;

    if($days) {
        $result .= $days.($short ? "d" : " day").(!$short && $days  > 1 ? "s" : "");
    }

    if($hours) {
        $result .= ", " if($result);
        $result .= $hours.($short ? "h" : " hour").(!$short && $hours > 1 ? "s" : "");
    }

    if($mins) {
        $result .= ", " if($result);
        $result .= $mins.($short ? "m" : " minute").(!$short && $mins  > 1 ? "s" : "");
    }

    if($seconds || !$result) {
        $result .= ", " if($result);
        $result .= $seconds.($frac ? ".$frac" : "").($short ? "s" : " second").(!$short && $seconds > 1 ? "s" : "");
    }

    return $result;
}


## @fn $ caps_counter($msg, $minlength)
# Returns the percentage of letters in the specified message
# that are in uppercase, ignoring spaces, punctuation, and numbers.
#
# @param msg       The message to count caps letters in
# @param minlength The minimum length of strings to consider.
# @return The percentage of letters in the message that are
#         in uppercase.
sub caps_counter {
    my $msg       = shift;
    my $minlength = shift;

    # strip all non-alphabetic characters as we care not about them
    $msg =~ s/\P{IsAlpha}//g;

    # Are the remains worth counting?
    return 0
        unless(length($msg) >= $minlength);

    # Hilariously fun way of counting matches. Would use tr/// except
    # that tr and unicode is a cavern of woe
    my $count = () = $msg =~ m/[\p{IsLt}\p{IsLu}]/g;

    return int(($count * 100) / length($msg));
}


## @fn $ load_yaml($yamlpath)
# Load the data from the specified YAML file into memory.
#
# @param yamlpath The path to the YAML file to load. ~ in the path is replaced
#                 with the user's home directory.
# @return A reference to a hash (or array) containing the loaded data
sub load_yaml {
    my $yamlpath = shift;

    # Convert ~ paths to real
    $yamlpath =~ s{^~([^/]*)}{$1 ? (getpwnam($1))[7] : (getpwuid($<))[7] }e;

    # Don't bother trying to load the data if there is no file.
    die "Unable to load data from $yamlpath: file not found"
        unless(-f $yamlpath);

    my $yaml = eval { YAML::Tiny::LoadFile($yamlpath) };

    # Errors from eval generaly mean a broken YAML file.
    die "Error loading data from $yamlpath: $@"
        if($@);

    return $yaml;
}


## @fn $ load_file($name)
# Load the contents of the specified file into memory. This will attempt to
# open the specified file and read the contents into a string. This should be
# used for all file reads whenever possible to ensure there are no internal
# problems with UTF-8 encoding screwups.
#
# @param name The name of the file to load into memory.
# @return The string containing the file contents, or undef on error. If this
#         returns undef, $! should contain the reason why.
sub load_file {
    my $name = shift;

    if(open(INFILE, "<:utf8", $name)) {
        undef $/;
        my $lines = <INFILE>;
        $/ = "\n";
        close(INFILE)
            or return undef;

        return $lines;
    }
    return undef;
}


## @method $ hash_or_hashref(@args)
# Given a list of arguments, if the first argument is a hashref it is returned,
# otherwise if the list length is nonzero and even, the arguments are shoved
# into a hash and a reference to that is returned. If the argument list is
# empty or its length is odd, and empty hashref is returned.
#
# @param args A list of arguments, may either be a hashref or a list of key/value
#             pairs to place into a hash.
# @return A hashref.
sub hash_or_hashref {
    my $len = scalar(@_);
    return {} unless($len);

    # Even number of args? Shove them into a hash and get a ref
    if($len % 2 == 0) {
        return { @_ };

    # First arg is a hashref? Return it
    } elsif(ref($_[0]) eq "HASH") {
        return $_[0];
    }

    # No idea what to do, so give up.
    return {};
}

1;