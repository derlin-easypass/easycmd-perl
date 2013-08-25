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
use Getopt::Std;

# gets the commandline options 
my %opts;
getopts('p:s:', \%opts );
my $session_path = ( defined $opts{p} and -r $opts{p} ) ? 
        $opts{p} : "/home/lucy/Dropbox/projets/easypass/sessions/";
        
my $session = ( defined $opts{s} ) ? $opts{ s } : undef;
my @ls = Utils::listSessionDir( $session_path ); # list of the sessions

# setups the terminal 
my $term = Term::ReadLine->new("easypass");
my $OUT = $term->OUT;

# patch for clipboard copy under linux
if ('Clipboard::Xclip' eq $Clipboard::driver) {
  no warnings 'redefine';
  *Clipboard::Xclip::all_selections = sub {  
    qw(clipboard primary buffer secondary)
  };
}

# if the session is not defined, asks it 
if ( not defined $session or not grep( /^$session\.data_ser$/, @ls ) ) {
    
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
        $in_session_nbr = $term->readline( color( "reset" ) . "\nsession [0-$i]: " . color( "yellow" ) );
    } while not defined $in_session_nbr or $in_session_nbr !~ /[0-9]+/ or $in_session_nbr > $i;
    
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
$datas->loadFromFile( $session, $password );

# inits the last variable (storing the last results, i.e. a list of account names )
my @last = $datas->keys();


# the actual loop
while ( 1 ){

    # for it to work, be sure to have libterm-readline-gnu-perl package installed + export "PERL_RL= o=0"
    print $OUT color( "yellow" );
    my @in = shellwords( $term->readline( "\n> ") ); 
    print $OUT color("reset"), "\n";
    # my $color = color("yellow");
    # my @test = map { s#\Q$color\E##i } @in;
    # $term->addhistory( join( " ", @test ) );
    # next;
    
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
            $datas->dump( $last[0] );
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


package Utils;

use Term::ANSIColor;
use Data::Dumper;

sub dispatch{
    no strict 'refs';
    my ( $fun, $args ) = @_;
    $fun = "help" unless defined Commands->can( $fun );
    Commands->$fun( $args );
}

sub resolveAccount{
    
    my $arg = shift;
    
    # if this is a number from the @last list
    if( scalar( @last ) > 0 and isInRange( $arg, scalar( @last ) ) ){
        return $last[$arg];
        
    }elsif( scalar( @last ) == 1 ){
        return $last[0];
        
    }elsif( defined $arg ){
        # tries to find accounts that match
        @_ = $datas->findAccounts( $arg );
        if( scalar( @_ ) == 1 ){ # if there is a unique match
            return $_[0];
        }
    }
       
    return undef; 
}


sub isInRange{
    my ( $n, $maxRange ) = @_;
    return 0 unless defined $n;
    $n = parseInt( $n );
    return ( $n >= 0 and $n < $maxRange );
}


sub parseInt{
    my $n = shift;
    return $n  =~ /^[0-9]+$/ ? int( $n ) : -1;
}

sub listSessionDir{
    my $dirname = shift;
    opendir my($dh), $dirname or die "Couldn't open dir '$dirname': $!";
    @_ = readdir $dh;
    closedir $dh;
    @_ = grep( /\.data_ser$/, @_);
    return @_;

}

sub printError{
    my $msg = shift;
    print "  --- ", color( 'red' ), $msg, color( "reset" ), " ---" , "\n\n" 
        unless not defined $msg;
}



package Commands;

use Data::Dumper;
use Term::ANSIColor;

sub list{
    my ( $package, $args ) = @_;
    my $arg = $args->[0];
    
   if( not defined $arg ){
        @last = $datas->keys();

    }else{
        @last = ( Utils::resolveAccount( $arg ) ) and defined $_ or $datas->findAccounts( $arg );
        
    }

    return 1;
}


sub find{
    my ( $package, $args ) = @_;
    
    if( scalar( @$args ) == 1 ){ # just grep in all fields
        @_ = $datas->find( $args->[0] );
        if( $_ > 0 ){
            @last = @_;
            return 1;
        }else{
            Utils::printError( "0 match" );
            return 0;
        } 
        
        
    }elsif( scalar( @$args ) == 3 ){
        my ($header, $operator, $keyword ) = @$args;
        
        # checks the operator part        
        if( $operator ~~ ['=', 'is'] ){
            $keyword = "^[\\s]*" . $keyword . '[\\s]*$';
            
        }elsif( not $operator ~~ ['like', '~'] ){ # invalid operator
            Utils::printError( "allowed operators : like, ~, is, =" );
            return;
        }
        
        my @matches;
        
        #checks the keyword part and gets the matches
        if( $header ~~ ['account', 'name'] ){
            foreach ( $datas->keys() ){
                push @matches, $_ if /$keyword/i; 
            }
            
        }elsif( $header ~~ @{ $datas->{ headers } } and not $header eq 'password' ){        
            foreach my $key ( $datas->keys() ){
                push @matches, $key unless $datas->{ hash }{ $key }{ $header } !~ /$keyword/i;
            }
        }else{
            # the header is not correct
            my $str;
            foreach(@{ $datas->{headers} } ){ $str += "$_ " unless $_ eq 'password' ; }
            Utils::printError( "possible headers : name|account $str");
            return;
        }
        
        if( scalar( @matches ) == 0){ 
            Utils::printError( "0 match" ); 
            return; 
        }

        if( scalar( @matches ) == 0 ){
            Utils::printError( "0 match" );
            return 0;
        }else{
            @last = @matches;
            return 1;
        }
        
    }else{
        Utils::printError( "invalid number of arguments" );
        return 0;
    }
}

sub details{
    my ($package, $args) = @_;
    my $account = Utils::resolveAccount( $args->[0] );
    
    if( defined $account ){
        
        $datas->dump( $account );
        return 0;
        
    }else{
        Utils::printError( defined $args->[0] ? "0 match"  : "no argument provided" );
        return 0;
    }
}
    
sub pass{
    my ( $package, $args ) = @_;
    my $arg = Utils::resolveAccount( $args->[0] );
    
    if( not defined $arg ){
        Utils::printError( "could not copy : ambiguous account" );
        return;
    }
            
    my $pass = $datas->getProp( $arg, "password" );
            
    if( $pass ){
        Clipboard->copy( $pass );
        print "Copied password from \"$arg\" to clipboard.\n"; 
        
    }else{
        Utils::printError( "could not copy : ambiguous account" );
    } 
    
    return 0;
}



sub copy{
    my ( $package, $args ) = @_;
    my $prop = $args->[0];
    my $account = Utils::resolveAccount( $args->[1] );
    
    
    if( not $prop ~~ @{ $datas->{ headers } } ){
        Utils::printError( "syntax : copy <" . join( "|", $datas->headers() ) . "> <?account?>" );
        return 0;
    }
    
    if( not defined $account ){
        Utils::printError("ambiguous account : could not copy");
        return 0;
        
    }
        
    $_ = $datas->getProp( $account, $prop );
    
    if( $_ ){
        Clipboard->copy( $_ );
        print " Copied property \"$prop\" of \"$account\" to clipboard\n"; 
        
    }else{
        Utils::printError("ambiguous account : could not copy");
    }
    
    return 0;
}


sub help{
    print " Possible commands : find, copy, list, pass\n";
    return 0;
}

sub exit{
    exit;
}

