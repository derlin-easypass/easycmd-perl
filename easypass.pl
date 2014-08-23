#!/usr/bin/env perl
# This program offers a simple way to manipulate easypass session files from the command line.
# You can search for accounts, copy properties to clipboard, edit|delete|add accounts.
# Everything is saved following the easypass format : json encoded and openssl encrypted, with the .data_ser_new extension.
# COMMANDLINE OPTIONS
# ===================
# -s|--session 
#      the name of the session to open (filename)
#
# -p|--path 
#      the path of the sessions directory

$main::VERSION = 1.0;

package Easypass::CommandLine;


use warnings;
use strict;
no if $] >= 5.017011, warnings => 'experimental::smartmatch';

use utf8;

use Term::ReadKey;
use Term::ReadLine;
use Term::ANSIColor;
use Data::Dumper;
use JSON -support_by_pp;  
use Text::ParseWords;

use Clipboard;
use File::Spec::Functions;
use Getopt::Long;
use Cwd;

push @INC, ( Cwd::abs_path($0) =~ /(.*\/)[^\/]*/ and $1 );
require DataContainer;

# TODO : better structure
# variables used for completion
our @COMMANDS = qw( exit add copy delete details edit modify find list pass help h showpass show );
our @HEADERS_FOR_COMPLETION = qw( name account pseudo email );

# shared variables between packages
our $data;
our ( $term, $OUT );


# default arguments
my $session = "";
my $session_path = ""; #"/home/lucy/Dropbox/Applications/Linder\ Easypass";

# setups the terminal 
$term = Term::ReadLine->new("easypass");
$OUT = $term->OUT;

# gets the command line arguments
GetOptions( 
    "s|session=s" => sub{ 
        # adds the extension if not specified
        $session = $_[1]; # @_ = opt_name, opt_value
        $session .= ".data_ser_new" unless $session =~ /\.data_ser_new$/; 
     },
     
    "p|path=s" => sub{
        # checks that the path exists
        $session_path = $_[1]; # @_ = opt_name, opt_value
        if( not -d "$session_path" ){
            Utils::print_error( "the directory $session_path does not exist" );
            exit(1);
        }
    },
    
    "h|help" => sub{ 
        print 
"
 This program allows you to easily manipulate easypass session files from the commandline.
 The following commands are available : 
        
";
        
        Commands::help(); 
        print "\n";
        exit; 
    }
);

# prompts for the session path
if( not "$session_path" ){
    while( 1 ){
        $_ = $term->readline( "\nEnter the sessions folder path:" . color('yellow') .  " " );
        print color("reset");
        
        exit if Utils::trim( $_ ) eq "exit";
        # resolves the ~ as home folder in linux
        s/(~)/${ENV{HOME}}/g;
        # tries to get the real path if rel
        $session_path = Cwd::realpath( $_ ) unless not $_;
        # break if the dir exist
        last if ( -d $session_path ); 
        
        Utils::print_error( "'$session_path' is not a valid directory" );
    }
}

# gets the list of sessions
my @ls = Utils::list_session_dir( "$session_path" ); # list of the sessions names


# patch for clipboard copy under linux
if ('Clipboard::Xclip' eq $Clipboard::driver ) {
  no warnings 'redefine';
  *Clipboard::Xclip::all_selections = sub {  
    qw(clipboard primary buffer secondary)
  };
}

# ***************************************************** init 

my $new_session = ''; # false

# if the session is not defined, asks it 
unless ( $session and Utils::is_in( $session, [ @ls ] ) ) {
    
    # lists the existing sessions 
    print "\nExisting sessions:\n\n";
    my $i = 0;
    foreach (@ls) {
        print "  ", color( "green" ), $i++, color( "reset" ),  ' : ', $_, "\n";
    }
    print "  ", color( "magenta" ), $i, color( "reset" ),  ' : new...', "\n";
    
    # asks the user for the session number to open
    my $in_session_nbr;
    do{
        $in_session_nbr = Utils::readline_noh( "\nsession [0-$i]: " . color( "yellow" ) );
        print $OUT color( "reset" );
        eval{ $OUT->flush() }; # reset color !! 
        eval{ $term->remove_history( $term->where_history() ) };
        exit if $in_session_nbr eq "exit";
        
    }while Utils::parse_int( $in_session_nbr ) == -1 or $in_session_nbr > $i;
    
    if( $in_session_nbr == $i ){ # new session
        $new_session = 1;
        # gets the new session name
        do{
            $session = Utils::readline_noh( "new session name: " );
        }while( $session !~ /^[a-z0-9_-]+$/ );
        # adds the proper extension
        $session .= ".data_ser_new";
    }else{ # existing session
        # strips the line break
        chomp( $session = $ls[$in_session_nbr] );
    }
    
}else{ # sessions passed as a parameter
    # adds the extension to the session passed as a param, if not already here
    
}

# concatenates the session + path
$session = File::Spec->catfile( $session_path, $session );

# gets the password from the user
my $password = Utils::get_pass();
#my $password = "essai";

# loads the data
$data = DataContainer->new();
eval { $data->load_from_file( $session, $password ) unless $new_session };
print "$@" and exit 1 if $@;

# inits the last variable (storing the last results, i.e. a list of account names )
my @last = $data->accounts();

# ******************************************************* auto-completion
# TODO : better completion
# http://search.cpan.org/~hayashi/Term-ReadLine-Gnu-1.20/Gnu.pm#Custom_Completion
# http://search.cpan.org/~hayashi/Term-ReadLine-Gnu-1.20/Gnu.pm#Term::ReadLine::Gnu_Functions
$term->Attribs->{completion_function} = sub{
    my ($text, $line, $start) = @_;
    
    if( $line =~ /^\s*$/ ){ # first word
        @_ = grep{ /^$text/ } @COMMANDS;
        return @_ if( scalar(@_) );
    }
    
    if( $line =~ /^\s*(copy|find)\s*\w*$/ ){
        return grep { /^$text/ } @HEADERS_FOR_COMPLETION if( $text );
        return @HEADERS_FOR_COMPLETION;
    }
    
    if( $line =~ /^(\w+)$/ ){
        @_ = grep{ /^$1/ } @COMMANDS;
        return @_ if( scalar(@_) );
    }
    
    
    return undef;
};
# ******************************************************* loop

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
    my $result = dispatch( $fun, \@args );
    
    if( $result ){ # if the function returned 1, it means that last was changed => prints it
        $_ = scalar( @last );
        # number of matches
        print "  --- ", $_, " match", $_ > 1 ? "es" : ""," ---" , "\n\n";
        
        if( $_ == 1 ){ # if only one match, prints the details
            print color( "green" ), " 0 : ", color( "reset" );
            print $data->to_string( $last[0] );
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


# tries to call the subroutine named after the first argument, passing to it
# the args. If the subroutine does not exist, calls the help command.
# note : the subroutines are the one in the command package.
sub dispatch{ # void ($function_name \@args)
    no strict 'refs';
    my ( $fun, $args ) = @_;
    exit if  Utils::is_in ( $fun, [ "exit", "quit" ] );
   
    my $res; # return code

    # the command is known, just execute it
    if( Commands->can( $fun ) ){
        $res = Commands->$fun( $args );

    }else{ # unknown command -> assuming find
        Utils::print_info( 'unknown command; assuming "find" (Try "h" or "help" for help).' ); 
        $res = Commands->find( [ $fun, @$args ] );
    }

    return $res;
        
}

# ****************************************************** utils 

package Utils;

# Provides simple sub utilities.

use Term::ANSIColor;
use Term::ReadKey;
use Term::ReadLine;
use List::Util qw ( first );


# tries to resolve the account pointed by the argument, returning the account name :
# 1. if the arg is a number, finds if it denotes an index of the last array var.
# 2. if the arg is undefined and the last var contains only one account, returns it
# 3. searches the account names that match the arg, and returns it if only 1 match
# if none of the above, returns undef.
#
# I<params>: the arg to resolve
sub resolve_account{ # $account_name ($arg)
    
    my $arg = shift;
    
    # if this is a number from the @last list
    if( scalar( @last ) > 0 and is_in_range( $arg, scalar( @last ) ) ){
        return $last[$arg];
     
    # if last contains only 1 item
    }elsif( scalar( @last ) == 1 ){
        return $last[0];
        
    }elsif( defined $arg ){
        # tries to find accounts that match
        @_ = $data->match_account_name( $arg );
        if( scalar( @_ ) == 1 ){ # if there is a unique match
            return $_[0];
        }
    }
       
    return undef; 
}

# returns true if the first argument is a positive number and is less than
# the number passed as a second parameter.
#
# I<params>: the potential number, the max (exclusive) 
sub is_in_range{ # $bool ( $int, $max_range )
    my ( $n, $max_range ) = @_;
    return unless defined $n and defined $max_range;
    $n = parse_int( $n );
    return $n == -1 ? 0 : ( $n >= 0 and $n < $max_range );
}

# parses a string and returns its integer counterpart, or -1 if it is not a number
#
# I<params>: the string to parse
sub parse_int{ # $int ( $arg )
    my $n = shift;
    return $n  =~ /^[0-9]+$/ ? int( $n ) : -1;
}

# simple trim function
# I<params>: the string to trim 
sub trim { # $ ($)
   return $_[0] =~ s/^\s+|\s+$//rg;
}

# removes the duplicates from the given array
# I<params>: the array
sub distinct{ # \@ ( \@ )
    # the idea is to convert the array into a hash, since hash keys must be
    # unique, and then get the keys back
    my %h;
    return grep { !$h{$_}++ } @_
}

# prompts for a password and returns it.
sub get_pass{ # $pass (void)
    my $msg = shift;
    $msg = "Type your password : " unless defined $msg;

    print $msg; # don't know why, but it does not work with $term->...
    ReadMode('noecho'); # don't echo
    my $password = ReadLine 0; 
    chomp $password;
    eval{ $term->remove_history( $term->where_history() ) }; # remove pass from history
    ReadMode( 0 );        # back to normal

    print "\n";
    return $password;
}

# returns an array containing the names of the files with the .data_ser_new extension
# contained in the specified directory
# I<params>: the absolute path to the directory
sub list_session_dir{ # \@session_files ( $path )
    my $dirname = shift;
    opendir my($dh), $dirname or die "Couldn't open dir '$dirname': $!";
    @_ = readdir $dh;
    closedir $dh;
    @_ = grep( /\.data_ser_new$/, @_);
    return @_;

}

# prints an error message (in red) to stdout
# I<params>: the message to print
sub print_error{ # void ( $message )
    my $msg = shift;
    print "  --- ", color( 'red' ), $msg, color( "reset" ), " ---" , "\n" 
        unless not defined $msg;
}

# prints an info message to stdout
# I<params>: the message to print
sub print_info{ # void ( $message )
    my $msg = shift;
    print "  --- ", color( 'magenta' ), $msg, color( "reset" ), " ---" , "\n" 
        unless not defined $msg;
}
 
sub readline_noh {
    my @args = @_;
    for (@args){ utf8::decode($_); }
    my $answer = $term->readline( @args );
    chomp $answer;
    eval{ $term->remove_history( $term->where_history() ) }; # remove from history
    return $answer;
}
# checks if $val is in $list
#
#   Utils::is_in( $val, [.., ..] ) 
# is equivalent to:
#   $val ~~ [ .., .. ]
#
# I<params>: the value, the reference to a list
sub is_in { # bool ($val, \@list )
    my ($val, $list) = @_;
    first { $_ eq "$val" } @$list; # use first from List::Util
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
use Term::ReadLine;



# list the accounts 
# stores in the last variable all the account names, or only the ones with at least one 
# field containing the pattern passed as a parameter.
# 
# I<params>: the pattern ( optional )
sub list{ # ( void|\$pattern )
    my ( $package, $args ) = @_;
    my $arg = $args->[0];
    
   if( not defined $arg ){
        @last = $data->accounts();
        return 1;

    }else{
        @_ = $data->match_account_name( $arg );
        
        if( scalar( @_ ) == 0 ){  # nothing found
            Utils::print_error( "0 match" );
            return 0;
        }
        @last = @_;        
        return 1;
    }
}

# search method. Stores the matches in the @last variable.
# find <global pattern>
#       stores all the accounts having at least one field containing the
#       pattern.
#
#    find <property> [is|=] <pattern(s)>
#       stores all the accounts whose property matches exactly the
#       pattern(s).
#
#    find <property> [like|~] <pattern(s)>
#       stores all the accounts whose property contains the pattern(s).
#
#    find <property> unlike <pattern(s)>
#       stores all the accounts whose property does not contain the pattern(s).

sub find{ # void ( \@args )
    my ( $package, $args ) = @_;
    
    if( scalar( @$args ) == 1 ){ # just grep in all fields
        @_ = $data->match_any( $args->[0] );
        if( scalar( @_ ) > 0 ){
            @last = @_;
            return 1;
        }else{
            Utils::print_error( "0 match" );
            return 0;
        } 
        
        
    }elsif( scalar( @$args ) > 2 ){
        
        my $header = $args->[0];
        my $operator = $args->[1];
        my @keywords = splice( $args, 2 ); # the remaining args
        my $regex;
        
        # -- checks the operator part        
        if( Utils::is_in( $operator, ['=', 'is'] ) ){
            $regex = "^" . join( '$|^', @keywords ) . '$';
            
        }elsif( Utils::is_in( $operator, ['like', '~'] ) ){ 
            $regex = join( '|', @keywords );
        
        }elsif( Utils::is_in( $operator, ['unlike', '!~'] ) ){
            $regex = "^(?:(?!(" . join( '|', @keywords ) . ')).)*$';
            
        }else{ # invalid operator
            Utils::print_error( "allowed operators : like, ~, is, =, unlike" );
            return;
        }
        
        print " regex $regex\n";
        my @matches;
        
        # -- checks the keyword part
        if( Utils::is_in( $header, ['account', 'name'] ) ){ # search in account names
            foreach ( $data->accounts() ){
                push @matches, $_ if /$regex/i; 
            }
            
        }elsif( Utils::is_in( $header, [ $data->headers() ] ) and not $header eq 'password' ){   # search in one field   
            foreach my $key ( $data->accounts() ){
                push @matches, $key if $data->get_prop( $key, $header ) =~ /$regex/i;
            }
            
        }elsif( Utils::is_in( $header, ['*', 'any'] ) ){ # search everywhere
            foreach ( @keywords ){
                push ( \@matches, $data->match_any( $_ ) );
            }
            
        }else{ # the header is not correct
            my $str;
            foreach( $data->headers() ){ $str .= "$_ " unless $_ eq 'password' ; }
            Utils::print_error( "possible headers : name|account $str");
            return;
        }
        
        # removes the duplicates from @match
        @matches = Utils::distinct( @matches );
        
        
        if( scalar( @matches ) == 0){ # if no match
            Utils::print_error( "0 match" ); 
            return; 
            
        }else{ # if matches, stores them into last and asks for output
            @last = @matches;
            return 1;
        }
        
    }else{ # there is only two arguments...
        Utils::print_error( "invalid number of arguments" );
        return 0;
    }
}

# simply returns 1, so tells the main routine to print the content of last
sub last{ 
    return 1;
}

# prints the details of the account
sub show{ details( @_ ); }
sub details{ # ( $account )
    my ($package, $args) = @_;
    my $account = Utils::resolve_account( $args->[0] );
    
    if( defined $account ){
        
        print $data->to_string( $account );
        return 0;
        
    }else{
        Utils::print_error( defined $args->[0] ? "0 match"  : "no argument provided" );
        return 0;
    }
}
    
# Copies the password of the account in the clipboard
#
# I<params>: the account name
sub pass{ # ( $account )
    my ( $package, $args ) = @_;
    my $arg = Utils::resolve_account( $args->[0] );
    
    if( not defined $arg ){
        Utils::print_error( "could not copy : ambiguous account" );
        return;
    }
            
    my $pass = $data->get_prop( $arg, "password" );
            
    if( $pass ){
        Clipboard->copy( $pass );
        print " Copied password from \"$arg\" to clipboard.\n"; 
        
    }else{
        Utils::print_error( "could not copy : ambiguous account" );
    } 
    
    return 0;
}


# copy <property> <account name>
#    Copies some property of an account to the clipboard.
# 
# # I<params>: the account name
sub copy{ # ( $account )
    my ( $package, $args ) = @_;
    my $prop = $args->[0];
    my $account = Utils::resolve_account( $args->[1] );
    
    if( not defined $prop or not Utils::is_in( $prop, [ ('name', 'account'), $data->headers() ] ) ){
        print " syntax : copy <", join( "|", $data->headers() ), "> <?account?>\n";
        return 0;
    }
    
    if( not $account ){
        Utils::print_error("ambiguous account : could not copy");
        return 0;
        
    }
    
    # gets either the name of the account or the specified property
    $_ = Utils::is_in( $prop, [ 'name', 'account'] ) ? $account : $data->get_prop( $account, $prop );
    
    if( $_ ){
        Clipboard->copy( $_ );
        print " Copied property \"$prop\" of \"$account\" to clipboard\n"; 
        
    }else{
        Utils::print_info("empty property : did not copy");
    }
    
    return 0;
}

# adds a new account
sub add{
    my ( $package, $args ) = @_;
    
    my %new_values;
    my $account = Utils::readline_noh( "\n  new account name : " );
    eval{ $term->remove_history( $term->where_history() ) }; # remove pass from history
    $account = Utils::trim( $account );
    Utils::print_error( "this account already exist. Use the edit command instead" ) and return 
        unless not Utils::is_in( $account, [ $data->accounts() ] );
        
    foreach my $prop ( @{ $data->{ headers } } ){ # headers unsorted
        if( $prop eq 'password' ){
            $new_values{ $prop } = Utils::get_pass( "  $prop : " );
        }else{
            $new_values{ $prop } = Utils::readline_noh( "  $prop : " );
            eval{ $term->remove_history( $term->where_history() ) }; # remove pass from history
        }
    }
    

    while( 1 ){
        my $confirm = Utils::readline_noh( "\nsaving ? [y/n] " );
        if( $confirm =~ /^[\s]*(y|yes|no|n)[\s]*$/i ){
            if( $confirm =~ /y/i ){
                $data->add( $account, \%new_values );
                $data->save_to_file( $session, $password );
                print $OUT "\n";
                Utils::print_info("New entry saved");
            } 
            
           return 0;
        }
    }

}

# edits an account
#
# I<params>: the account name
sub modify{ # ( $account )
    edit( @_ );
}

# show the pass in plain text --> dangerous !!
sub showpass{
  my ( $package, $args ) = @_;
  my $account = Utils::resolve_account( $args->[0] );
  my $pass = $data->get_prop( $account, "password" );

  if( $pass ){
      chomp( $pass ); # remove trailing newline, if any
      print "$pass\r"; flush STDOUT; # print pass for x seconds
      sleep 2;
      print " " x length($pass); flush STDOUT;#, "\n"; # write spaces over password

  }else{
      Utils::print_error( "ambiguous account or no pass defined..." );
  } 

    return 0;
}

# edits an account
sub edit{  # ( $account )
#
# I<params>: the account name
    my ( $package, $args ) = @_;
    my $account = Utils::resolve_account( $args->[0] );
    Utils::print_error("No account provided") and return unless defined $account;
    
    my %new_values;
    my $new_account = Utils::trim( Utils::readline_noh( "\n  account name : ", $account ) );
    
    foreach my $prop ( @{ $data->{ headers } } ){ # headers unsorted
        if( $prop eq 'password' ){
            my $newpass = Utils::get_pass( "  $prop : " );

            if( Utils::trim( $newpass ) ){
                $new_values{ $prop } = $newpass;
            }else{ # no new pass, just copy the old one
                $new_values{ $prop } = $data->get_prop( $account, $prop );
            }
        }else{
            $new_values{ $prop } = Utils::readline_noh( "  $prop : ", 
                $data->get_prop( $account, $prop ) );
            chomp $new_values{ $prop };
        }
    }
    
    my $confirm;
    
    while( 1 ){
        $confirm = Utils::readline_noh( "\n  Saving ? [y/n] " );
        if( $confirm =~ /^[\s]*(y|yes|no|n)[\s]*$/i ){
           last;
        }
    }
    
    if( $confirm =~ /y/i ){
        # if the account name was changed, deletes the old key
        $data->delete( $account ) unless $account eq $new_account;
        $data->add( $new_account, \%new_values );
        $data->save_to_file( $session, $password );
        print "\n";
        Utils::print_info("New entry saved");
    } 
    
    return 0;
}

# deletes an account
sub delete{ # ( $account )
    my ( $package, $args ) = @_;
    my $account = Utils::resolve_account( $args->[0] );
    Utils::print_error("No account provided") and return unless defined $account;
    
    while( 1 ){
        my $confirm = Utils::readline_noh( "\n  Deleting \"$account\" ? [y/n] " );
        if( $confirm =~ /^[\s]*(y|yes|no|n)[\s]*$/i ){
           if( $confirm =~ /y/i ){
                print "calling delete ";
                $data->delete( $account );
           }
           return 0;
        }
    }
    
}

# prints the available commands, with details
sub help{

    my $color = color("bold");
    my $reset = color("reset");
    print
    
"   $color add $reset
       add a a new account. The file is then automatically updated.

   $color copy$reset <property> <account name>
       copy some property of an account to the clipboard.

   $color delete$reset <account name> 
       delete the matching account

   $color details|show$reset <account name>
       display the details of the account

   $color edit|modify$reset <account name>
       edit the properties of the matching account.

   $color find$reset <global pattern>
       display sall the accounts having at least one field containing the
       pattern.

   $color find$reset <property> [is|=] <pattern(s)>
       display all the accounts whose property matches exactly the
       pattern(s).

   $color find$reset <property> [like|~] <pattern(s)>
       display all the accounts whose property contains the pattern(s).

   $color find$reset <property> unlike <pattern(s)>
       display all the accounts whose property does not contain the
       pattern(s).

   $color list$reset
       list all the account names in the current session.

   $color list$reset <pattern>
       list all the account names with at least one property containing the
       pattern.  Same as \"find <pattern\".

   $color pass$reset <account name>
       copy the password of the account in the clipboard

   $color showpass$reset <account>
          display the password (in clear text !!) during 2 seconds in the terminal

   $color help$reset
       print this help message

   $color h$reset
       print the list of available commands, without details.

   $color exit|quit$reset
          quit the program
";

    return 0;
}

# prints the available commands, without details
sub h{
    my $color = color("bold");
    my $reset = color("reset");
    
    print 
"   $color add $reset
   $color copy$reset <property> <account name>
   $color delete$reset <account name> 
   $color details$reset <account name>
   $color edit|modify$reset <account name>
   $color find$reset <global pattern>
   $color find$reset <property> [is|=] <pattern(s)>
   $color find$reset <property> [like|~] <pattern(s)>
   $color find$reset <property> unlike <pattern(s)>
   $color list$reset
   $color list$reset <pattern>
   $color pass$reset <account name>
   $color help$reset
   $color h$reset
";
    return 0;
}
