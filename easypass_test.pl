#!/usr/bin/perl

use warnings;
use strict;

use utf8;
use Switch;

use Term::ReadKey;
use Term::ReadLine;
use Term::ANSIColor;
use Data::Dumper;
use JSON -support_by_pp;  
use Text::ParseWords;

use Clipboard;
use DataContainer;


my $session_path = "/home/lucy/Dropbox/projets/easypass/sessions/";
my $session = $ARGV[0];
my @ls = Utils::listSessionDir( $session_path ); 

my $term = Term::ReadLine->new("easypass");

# patch for clipboard copy under linux
if ('Clipboard::Xclip' eq $Clipboard::driver) {
  no warnings 'redefine';
  *Clipboard::Xclip::all_selections = sub {  
    qw(clipboard primary buffer secondary)
  };
}


if ( not defined $session or not grep( /^$session\.data_ser$/, @ls ) ) {
    
    print "\nExisting sessions:\n\n";
    my $i = 0;
    foreach (@ls) {
        print $i++, ' : ', $_, "\n";
    }
    $i--;
    
    my $j;
    do{
        $j = $term->readline("\nsession [0-$i]: ");
    } while not defined $j or $j !~ /[0-9]+/ or $j > $i;
    
    chomp( $session = $ls[$j] );
    
}else{
    $session .= ".data_ser";
}

$session = $session_path . $session;

#~ ReadMode('noecho'); # don't echo
#~ my $password = $term->readline( "\nType your password: " );
#~ ReadMode(0);        # back to normal
#~ print "\n\n";
my $password = "serieux";

my $datas = DataContainer->new();
$datas->loadFromFile( $session, $password );


my @last = $datas->keys();

while ( 1 ){

    my @in = shellwords( $term->readline("\n> " . color('yellow') ) ); #for it to work, be sure to have libterm-readline-gnu-perl package installed + export "PERL_RL= o=0"
    print color("reset"), "\n";
    
    # parses the arg
    my( $fun, @args ) = @in;
    
    #~ if( scalar( @last ) > 0 and Utils::isInRange( $args[0], scalar( @last ) ) ){
        #~ $args[0] = $last[$args[0]];
    #~ }
    
    #$args[0] = Utils::resolveAccount( $args[0] );

    my $result = Utils::dispatch( $fun, \@args );
    
    if( $result ){
        $_ = scalar( @last );
        print "  --- ", $_, " match", $_ > 1 ? "es" : ""," ---" , "\n\n";
        
        my $i;
        foreach( @last ){
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
    return unless defined $arg;
    
    # if this is a number from the @last list
    if( scalar( @last ) > 0 and isInRange( $arg, scalar( @last ) ) ){
        return $last[$arg];
        
    }else{
        # tries to find accounts that match
        @_ = $datas->findAccounts( $account );
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
        @last = $datas->findAccounts( $arg );
    }
    
    return 1;
}


sub find{
    my ( $package, $args ) = @_;
    
    if( scalar( @$args ) == 1 ){ # just grep in all fields
        # TODO
        Utils::printError( "usage : find <property> <operator> <keyword>" );
        return 0;
        
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
    my $arg = $args->[0];
    
    if( defined $arg ){
        
        my @matches = $datas->findAccounts( $arg );
        $_ = scalar( @matches );
        
        if( $_ == 0 ){
            Utils::printError( "0 match" );
            
        }elsif( $_ == 1 ){
           $datas->dump( @matches ); 
        
        }else{
            @last = @matches;
            return 1;
        }
        
    }else{
        Utils::printError( "no argument provided" );
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
        
        if( scalar( @last ) == 1 ){
            $account = $last[0];
            
        }else{
            Utils::printError("ambiguous account : could not copy");
            return 0;
        }
        
    }elsif( not exists $datas->{ hash }{ $account } ){
    
        @_ = $datas->findAccounts( $account );
        if( scalar( @_ ) == 1 ){
            $account = $_[0];
        }else{
           Utils::printError("ambiguous account : could not copy");
           return 0;
        }
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

