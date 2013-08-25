#!/usr/bin/perl

use warnings;
use strict;

use utf8;

use Term::ReadKey;
use Term::ReadLine;
use Term::ANSIColor;
use Data::Dumper;
use JSON -support_by_pp;  
use Text::ParseWords;

use Clipboard;
use File::Spec::Functions;
use DataContainer;
use Getopt::Long;

$main::VERSION = 1.0;

# default 
my $session = '';
my $session_path = "/home/lucy/Dropbox/projets/easypass/sessions/";

# gets the command line arguments
GetOptions( 
    "s|session=s" => \$session,
    "p|path=s" => \$session_path
);

my @ls = Utils::list_session_dir( $session_path ); # list of the sessions

# setups the terminal 
my $term = Term::ReadLine->new("easypass");
my $OUT = $term->OUT;

# patch for clipboard copy under linux
if ('Clipboard::Xclip' eq $Clipboard::driver ) {
  no warnings 'redefine';
  *Clipboard::Xclip::all_selections = sub {  
    qw(clipboard primary buffer secondary)
  };
}

# if the session is not defined, asks it 
if ( not $session or not grep( /^$session\.data_ser$/, @ls ) ) {
    
    # lists the existing sessions
    print "\nExisting sessions:\n\n";
    my $i = 0;
    foreach (@ls) {
        print "  ", color( "green" ), $i++, color( "reset" ),  ' : ', $_, "\n";
    }
    $i--;
    
    # asks the user for the session number to open
    my $in_session_nbr;
    do{
        $in_session_nbr = $term->readline( "\nsession [0-$i]: " . color( "yellow" ) );
        print $OUT color( "reset" );
        exit if $in_session_nbr eq "exit";
        
    }while Utils::parse_int( $in_session_nbr ) == -1 or $in_session_nbr > $i;
    
    # strips the line break
    chomp( $session = $ls[$in_session_nbr] );
    
}else{
    # adds the extension to the session passed as a param, if not already here
    $session .= ".data_ser" unless $session =~ /\.data_ser$/; 
}

# concatenates the session + path
$session = File::Spec->catfile( $session_path, $session );

# gets the password from the user

#~ ReadMode('noecho'); # don't echo
#~ my $password = $term->readline( "\nType your password: " );
#~ ReadMode(0);        # back to normal
#~ print "\n\n";
my $password = "serieux";

# loads the data
my $datas = DataContainer->new();
$datas->load_from_file( $session, $password );

# inits the last variable (storing the last results, i.e. a list of account names )
my @last = $datas->accounts();


# the actual loop
while ( 1 ){

    # for it to work, be sure to have libterm-readline-gnu-perl package installed + export "PERL_RL= o=0"
    print $OUT color( "yellow" ), "\n";
    my @in = shellwords( $term->readline( "-> " ) ); 
    print $OUT color("reset"), "\n";
    
    # parses the args from the commandline
    my( $fun, @args ) = @in;

    # dispatch: takes the first arg and tries to call the function with the same name,
    # prints the help if it is not found
    my $result = Utils::dispatch( $fun, \@args );
    
    if( $result ){ # if the function returned 1, it means that last was changed => prints it
        $_ = scalar( @last );
        # number of matches
        print "  --- ", $_, " match", $_ > 1 ? "es" : ""," ---" , "\n\n";
        
        if( $_ == 1 ){ # if only one match, prints the details
            print color( "green" ), " 0 : ", color( "reset" );
            print $datas->to_string( $last[0] );
            next;
        }
        
        # else, prints a list of account names with number
        my $i;
        foreach ( @last ){
            print color("green"), "  ", sprintf( "%-3d", $i++ ), color("reset");
            print " : $_\n";
        }
    }

}# end while



# ****************************************************** utils 

package Utils;

use Term::ANSIColor;

# tries to call the subroutine named after the first argument, passing to it
# the rest of the args. If the subroutine does not exist, calls the help command.
# note : the subroutines are the one in the command package.
# @params : the subroutine name, a list of args to pass to the sub
sub dispatch{
    no strict 'refs';
    my ( $fun, $args ) = @_;
    exit if $fun eq "exit";
    $fun = "help" unless Commands->can( $fun );
    Commands->$fun( $args );
}

# tries to resolve the account pointed by the argument, returning the account name :
# 1. if the arg is a number, finds if it denotes an index of the last array var.
# 2. if the arg is undefined and the last var contains only one account, returns it
# 3. searches the account names that match the arg, and returns it if only 1 match
# if none of the above, returns undef.
sub resolve_account{
    
    my $arg = shift;
    
    # if this is a number from the @last list
    if( scalar( @last ) > 0 and is_in_range( $arg, scalar( @last ) ) ){
        return $last[$arg];
     
    # if last contains only 1 item
    }elsif( scalar( @last ) == 1 ){
        return $last[0];
        
    }elsif( defined $arg ){
        # tries to find accounts that match
        @_ = $datas->match_account_name( $arg );
        if( scalar( @_ ) == 1 ){ # if there is a unique match
            return $_[0];
        }
    }
       
    return undef; 
}

# returns true if the first argument is a positive number and is less than
# the number passed as a second parameter.
# @params : the potential number, the max (exclusive) 
sub is_in_range{
    my ( $n, $max_range ) = @_;
    return unless defined $n and defined $max_range;
    $n = parse_int( $n );
    return ( $n >= 0 and $n < $max_range );
}

# parses a string and returns its integer counterpart, or -1 if it is not a number
# @params : the string to parse
sub parse_int{
    my $n = shift;
    return defined $n and $n  =~ /^[0-9]+$/ ? int( $n ) : -1;
}

# returns an array containing the names of the files with the .data_ser extension
# contained in the specified directory
# @params : the absolute path to the directory
sub list_session_dir{
    my $dirname = shift;
    opendir my($dh), $dirname or die "Couldn't open dir '$dirname': $!";
    @_ = readdir $dh;
    closedir $dh;
    @_ = grep( /\.data_ser$/, @_);
    return @_;

}

# prints an error message (in red) to stdout
# @params : the message to print
sub print_error{
    my $msg = shift;
    print "  --- ", color( 'red' ), $msg, color( "reset" ), " ---" , "\n" 
        unless not defined $msg;
}

# prints an info message to stdout
# @params : the message to print
sub print_info{
    my $msg = shift;
    print "  --- ", color( 'magenta' ), $msg, color( "reset" ), " ---" , "\n" 
        unless not defined $msg;
}


# ************************************************* Commands
package Commands;
# all the sub in this package represent commands that can be used by the user
# in interactive mode. They all receive a pointer to an array of arguments,
# which can be empty.
# They must return 1 if they modified the last var (and want the main sub to
# print its content), 0 otherwise.

use Data::Dumper;
use Term::ANSIColor;

# list the accounts 
# if no arguments, lists all the accounts names and stores them in last
# if 1 argument, uses it as a regex and stores in last only the account names that match
sub list{
    my ( $package, $args ) = @_;
    my $arg = $args->[0];
    
   if( not defined $arg ){
        @last = $datas->accounts();
        return 1;

    }else{
        @_ = $datas->match_account_name( $arg );
        
        if( scalar( @_ ) == 0 ){  # nothing found
            Utils::print_error( "0 match" );
            return 0;
        }
        @last = @_;        
        return 1;
    }
}

# search method.
# if only one arg, stores in last all the account names with at least one
# field that match the arg.
# Else, the format is <1 field name> <2 operator> <3 regex>
#   field names : *, name|account, email, pseudo, notes
#   operators : is|=, like|~
sub find{
    my ( $package, $args ) = @_;
    
    if( scalar( @$args ) == 1 ){ # just grep in all fields
        @_ = $datas->match_any( $args->[0] );
        if( scalar( @_ ) > 0 ){
            @last = @_;
            return 1;
        }else{
            Utils::print_error( "0 match" );
            return 0;
        } 
        
        
    }elsif( scalar( @$args ) == 3 ){
        my ($header, $operator, $keyword ) = @$args;
        
        # checks the operator part        
        if( $operator ~~ ['=', 'is'] ){
            $keyword = "^[\\s]*" . $keyword . '[\\s]*$';
            
        }elsif( not $operator ~~ ['like', '~'] ){ # invalid operator
            Utils::print_error( "allowed operators : like, ~, is, =" );
            return;
        }
        
        my @matches;
        
        #checks the keyword part and gets the matches
        if( $header ~~ ['account', 'name'] ){
            foreach ( $datas->accounts() ){
                push @matches, $_ if /$keyword/i; 
            }
            
        }elsif( $header ~~ [ $datas->headers() ] and not $header eq 'password' ){        
            foreach my $key ( $datas->accounts() ){
                push @matches, $key unless $datas->get_prop( $key, $header ) !~ /$keyword/i;
            }
            
        }elsif( $header ~~ ['*', 'any'] ){
            @matches = $datas->find( $keyword );
            
        }else{
            # the header is not correct
            my $str;
            foreach( $datas->headers() ){ $str .= "$_ " unless $_ eq 'password' ; }
            Utils::print_error( "possible headers : name|account $str");
            return;
        }
        
        if( scalar( @matches ) == 0){ 
            Utils::print_error( "0 match" ); 
            return; 
        }

        if( scalar( @matches ) == 0 ){
            Utils::print_error( "0 match" );
            return 0;
        }else{
            @last = @matches;
            return 1;
        }
        
    }else{
        Utils::print_error( "invalid number of arguments" );
        return 0;
    }
}

# returns 1, so tells the main routine to print the content of last
sub last{
    return 1;
}


# prints the details of the account
sub details{
    my ($package, $args) = @_;
    my $account = Utils::resolve_account( $args->[0] );
    
    if( defined $account ){
        
        print $datas->to_string( $account );
        return 0;
        
    }else{
        Utils::print_error( defined $args->[0] ? "0 match"  : "no argument provided" );
        return 0;
    }
}
    
# copies the password of the account in the clipboard
sub pass{
    my ( $package, $args ) = @_;
    my $arg = Utils::resolve_account( $args->[0] );
    
    if( not defined $arg ){
        Utils::print_error( "could not copy : ambiguous account" );
        return;
    }
            
    my $pass = $datas->get_prop( $arg, "password" );
            
    if( $pass ){
        Clipboard->copy( $pass );
        print " Copied password from \"$arg\" to clipboard.\n"; 
        
    }else{
        Utils::print_error( "could not copy : ambiguous account" );
    } 
    
    return 0;
}


# format : copy <name|account|field name> <account>
sub copy{
    my ( $package, $args ) = @_;
    my $prop = $args->[0];
    my $account = Utils::resolve_account( $args->[1] );
    
    if( not defined $prop or not $prop ~~ [ ('name', 'account'), $datas->headers() ] ){
        print " syntax : copy <", join( "|", $datas->headers() ), "> <?account?>\n";
        return 0;
    }
    
    if( not $account ){
        Utils::print_error("ambiguous account : could not copy");
        return 0;
        
    }
    
    # gets either the name of the account or the specified property
    $_ = $prop ~~ [ 'name', 'account'] ? $account : $datas->get_prop( $account, $prop );
    
    if( $_ ){
        Clipboard->copy( $_ );
        print " Copied property \"$prop\" of \"$account\" to clipboard\n"; 
        
    }else{
        Utils::print_info("empty property : did not copy");
    }
    
    return 0;
}


sub help{
    print " Possible commands : find, copy, list, pass\n";
    return 0;
}
