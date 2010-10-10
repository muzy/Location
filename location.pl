#!/usr/bin/env perl
#
# Location
#	A tool which can discover your location by wlan!
use strict;
use warnings;
use 5.010;
use Getopt::Long;
use Config::Tiny;
use English qw( -no_match_vars );
use Text::Trim;
use IO::Handle;
use Array::Diff;
use Data::Dumper;

STDOUT->autoflush(1);    #workaround so that one can use print without \n

my $VERSION    = '0.1';
my $configpath = "$ENV{HOME}/.locationconf";
my $config     = Config::Tiny->new;

# Code Parts related to command line option parsing
my @add;
my $delete;
my $show;
my $scans = 1;
my $delay;
my $get;
my $accuracy = '';
my $verbose;

if ( -e $configpath ) {
    $config   = Config::Tiny->read($configpath);
    $scans    = $config->{_}->{scans};
    $accuracy = $config->{_}->{accuracy};
}
else {
    $config->{_}->{version}  = $VERSION;
    $config->{_}->{accuracy} = "ok";
    $config->{_}->{scans}    = 1;
    $config->write($configpath);
}

GetOptions(
    'h|help'     => sub { exec( 'perldoc', '-F', $0 ) },
    'a|add=s{3}' => \@add,
    'd|delete=s' => \$delete,
    's|show=s'   => \$show,
    'scans=i'    => \$scans,
    'delay=i'    => \$delay,
    'g|get=s'    => \$get,
    'accuracy=s' => \$accuracy,
    'v|version' => sub { say 'Location version ' . $VERSION; exit 0; },
    'verbose' => \$verbose,
);

if ( $scans < 1 ) { $scans = 1; }

if    (@add)               { add(); }
elsif ( defined($delete) ) { delentry(); }
elsif ( defined($show) )   { show(); }
elsif ( defined($get) )    { get(); }
else {
    say
"usage: location [--help] [--add <name> <address> <station>] [--delete <name>] [--show <name>] [--scans <number>] [--delay <time in seconds>] [--get <name|address|station|all>] [--accuracy <ok|best>] [--verbose]";
}

sub add {
    my $name = $add[0];
    $config->{$name}->{mac}     = join( "|", do_scans($scans) );
    $config->{$name}->{address} = $add[1];
    $config->{$name}->{station} = $add[2];
    $config->write($configpath);
}

sub delentry {
    my $name = $delete;
    if ( $config->{$name} ) {
        delete $config->{$name};
        $config->write($configpath);
        say "Successfully deleted $name";
    }
    else {
        say "$name not found in internal database!";
    }
}

sub show {
    my $name = $show;
    if ( $config->{$name} ) {
        say "Information for $name";
        say "Address: $config->{$name}->{address}";
        say "Station: $config->{$name}->{station}";
        say "Mac-Addresses: $config->{$name}->{mac}";
    }
    else {
        say "$name not found in internal database!";
    }
}

sub get {
    my @localmacs = do_scans($scans);
    my @possiblelocations;
    while ( my ( $name, $section ) = each %{$config} ) {
        if ( $name ne "_" ) {
            foreach my $mymac (@localmacs) {
                if ( grep $_ eq $mymac, split( /\|/, $section->{mac} ) ) {
                    push( @possiblelocations, $name );
                }
            }
        }
    }
    if (@possiblelocations) {
        my %hash = map { $_, 1 } @possiblelocations;
        my @locations = keys %hash;
        foreach my $loc (@locations) {
            my @confmacs = split( /\|/, $config->{$loc}->{mac} );
            my $diff          = Array::Diff->diff( \@localmacs, \@confmacs );
            my $diffcount     = $diff->count;
            my $localmaccount = scalar(@localmacs);
            my $confmaccount  = scalar(@confmacs);
            if ( $accuracy eq "ok" ) {
                if ( $diffcount < $confmaccount ) {

                    # Then we have at least one matching mac address
                    if ( ( $get eq "name" ) xor( $get eq "all" ) ) { say $loc; }
                    if ( ( $get eq "address" ) xor( $get eq "all" ) ) {
                        say $config->{$loc}->{address};
                    }
                    if ( ( $get eq "station" ) xor( $get eq "all" ) ) {
                        say $config->{$loc}->{station};
                    }
                }
            }
            else {

     # Here we have to proove whether at least 50% of the networks are available
                if ( ( $confmaccount - $diffcount ) >= ( $confmaccount / 2 ) ) {

# confmacccount minus diffcount is the amount of matching mac addresses
# if this is greater or equal than the half of confmaccount at least 50% matches
                    if ( ( $get eq "name" ) xor( $get eq "all" ) ) { say $loc; }
                    if ( ( $get eq "address" ) xor( $get eq "all" ) ) {
                        say $config->{$loc}->{address};
                    }
                    if ( ( $get eq "station" ) xor( $get eq "all" ) ) {
                        say $config->{$loc}->{station};
                    }
                }
            }
        }
    }
    else {
        say "Error: Could not determine current location!";
        exit 1;
    }
}

sub do_scans {
    my $times = shift(@_);
    my @macs  = ();
    for ( my $i = 1 ; $i <= $times ; $i++ ) {
        if ( defined($verbose) ) { say "Scan $i of $times."; }
        push( @macs, scan_environment() );
        if ( defined($delay) and ( $i != $times ) ) {
            if ( defined($verbose) ) { print "Delay until next scan: "; }
            for ( my $j = $delay ; $j >= 1 ; $j-- ) {
                if ( defined($verbose) ) { print "$j "; }
                sleep 1;
            }
            if ( defined($verbose) ) { print "\n"; }
        }
    }
    my %hash = map { $_, 1 } @macs;
    return keys %hash;
}

sub scan_environment {
    my @output
      = qx(sudo iwlist scan 2> /dev/null | grep -i 'Address' | cut -d ":" -f2-);
    trim @output;
    return @output;
}

__END__

=head1 NAME

Location - A tool which can discover your location with wlan!

=head1 SYNOPSIS

B<location> [--help] [--add I<name> I<address> I<station>] [--delete I<name>] 
[--show I<name>] [--scans I<number>] [--delay I<time in seconds>] 
[--get I<name|address|station|all>] [--accuracy I<ok|best>] [--verbose]

=head1 DESCRIPTION

Location can determine your location. To provide the service it scans available wlan networks
and compares the mac adresses of networks. 

=head1 OPTIONS

=over

=item B<--help>

Shows information on howto access this manpage

=item B<--add> I<name> I<address> I<station>

With this option a scan for available wireless networks is performed. This 
action should be combined with the B<--scans> and/or B<--delay> option.
If you want to cover a bigger area walk around a bit to get better results.
If you do not want to add a name or the address then run it like this:
location --add "" "" "foostation" --scans 4
To update an entry just run location --add with the same "name" argument. It will 
update everything accordingly.

=item B<--delete> I<name>

Deletes a previously scanned location from the internal database when I<name>
is found in the internal database.

=item B<--show> I<name>

Show all information about the given I<name> even if you are not at this
location.

=item B<--scans> I<number>

Use I<number> to increase the number of scans (must be greater than 0). This 
option can only be used in combination with the I<--add> or I<--get> parameter.

=item B<--delay> I<time in seconds>

This option is only applied when I<--scans> is used. It adds a delay between
the scans. 

=item B<--get> I<name|address|station|all>

Gets the current location. The parameter is used to determine the output.
I<name> returns the name of the location, I<address> the address of the location,
and I<station> the saved train station. I<all> returns all values seperated by
newlines.

=item B<--accuracy> I<ok|best>

Sets the accuracy. This option is only applied when the I<--get> action is used.
In the I<ok> level just one wlan router is enough to determine the current location.
In the I<best> level at least 50% of the networks must be present. It is recommend
that one uses the I<ok> level (since this level is the default).

=item B<--verbose>

Force verbose output. 

=back

=head1 CONFIGURATION

See the .locationconf in your home-directory. It will be added after first start.

=head1 AUTHOR

Copyright (C) 2010 by Sebastian Muszytowski E<lt>muzy@muzybot.deE<gt>

