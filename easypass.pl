#!/usr/bin/perl

use warnings;
use strict;

use utf8;
use Switch;

use Term::ReadKey;
use Term::ReadLine;
use Data::Dumper;
use JSON -support_by_pp;  
use Text::ParseWords;

use Clipboard;
use DataContainer;

my $session_path = "/home/lucy/Dropbox/projets/easypass/sessions/";
my $session = $ARGV[0];
my @ls = `ls $session_path | grep .data_ser`;
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
    
    my $i;
    foreach (@ls) {
        print $i++, ' : ', $_;
    }
    
    my $j;
    do{
        $j = $term->readline("\nsession [0-$i]: ");
    } while not defined $j or $j !~ /[0-9]+/ or $j > $i;
    
    chomp( $session = $ls[$j] );
    
}else{
    $session .= ".data_ser";
}

$session = $session_path . $session;

ReadMode('noecho'); # don't echo
my $password = $term->readline( "\nType your password:" );
ReadMode(0);        # back to normal
print "\n\n";
#~ my $password = "serieux";

my $datas = DataContainer->new();
$datas->loadFromFile( $session, $password );


my @last = $datas->keys();

while ( 1 ){

    my @in = shellwords( $term->readline("\n> ") ); #for it to work, be sure to have libterm-readline-gnu-perl package installed + export "PERL_RL= o=0"
    print "\n";
    
    # parses the arg
    my $arg = $in[1];
    my $arg2 = $in[2];
    
    if( defined $arg and scalar( @last ) > 0 and isInRange( $arg, scalar( @last ) ) ){
        $arg = $last[$arg];
    }
    
    switch( $in[0] ){
        
        case "list" { 
            if( not defined $arg ){
                @last = $datas->keys();
                my $i;
                foreach ( @last ) { print "  ", $i++, ": $_\n"; } 
                
            }else{
                $_ = scalar( $datas->findAccounts( $arg ) );
                print "  --- ", $_, " match", $_ > 1 ? "es" : ""," ---" , "\n\n";
                @last = $datas->findAccounts( $arg );
                
                if( scalar( @last ) < 20 ){
                    
                    if( scalar( @last ) > 8 ){
                        my $i;
                        foreach(@last){  print $i++, "  : ", $_, "\n"; }
                    
                    }else{
                        foreach( @last ){
                            my $i;
                            print $i++, ": ";
                            $datas->dump( $_ );
                        }
                    }
                    
                }
            }
        }# end list
        
        case "exit" { 
            exit; 
        }# end exit
        
        case "find" { 
            if( not defined $arg ){ 
                print "  The find option requires a regex to search for...\n\n"; 
                
            }else { 
                @last = $datas->find( $arg ); 
                print "  --- ", $_, " match", $_ > 1 ? "es" : ""," ---" , "\n\n";
                my $i;
                foreach ( @last ) { print "  ", $i++, ": $_\n\n"; } 
            }
        }# end find
        
        
        case "pass" {
            
            if( not defined $arg and scalar( @last ) == 1 ){
                $arg = $last[0];
            }
            
            my $pass = $datas->getProp( $arg, "password" );
            
            if( $pass ){
                print "  Password from \"$arg\" copied to clipboard.\n"; 
                Clipboard->copy( $pass );
                
            }else{
                print "  Could not determine which password to copy...\n";
            } 

        }# end pass
        
        case "copy" {
            if( scalar( grep( /^$arg$/, $datas->headers() ) ) ){
                my $account;
                
                if( defined $in[2] ){
                    
                    if( scalar( @last ) > 0 and isInRange( $in[2], scalar( @last ) ) ){
                        $account = $last[ $in[2] ];
                        
                    }elsif( scalar( $datas->findAccounts( $in[2] ) ) > 0 ){
                       @_ = $datas->findAccounts( $in[2] );
                       if( scalar( @_ ) > 1 ){
                            @last = @_;
                            print "  --- Multiple accounts match --- \n";
                            my $i;
                            foreach(@last){  print "  ", $i++, "  : ", $_, "\n"; }
                            undef $account;
                       }else{
                            $account = $_[0];
                       }
                    }
                    
                }elsif( scalar( @last ) == 1 ){
                    $account = $last[0];
                }
                
                $_ = $datas->getProp( $account, $arg );
                if( $_ ){
                    Clipboard->copy( $_ );
                    print " Copied property \"$arg\" of \"$account\" to clipboard\n"; 
                }else{
                    print "  Account ambiguous...\n" unless not defined $account;
                }
                 
            }else{
                print "  syntax : copy <", join( "|", $datas->headers() ), "> <?account?>\n";
            } 
        }#end copy
        
        else {
            print " Possible commands : find, copy, list, pass\n";
        }
     
    }# end switch 

}# end while


exit;


sub isInRange{
    my $n = parseInt( shift );
    $_ = ( $n >= 0 and $n < shift );
    return $_;
}


sub parseInt{
    my $n = shift;
    return $n  =~ /^[0-9]+$/ ? int( $n ) : -1;
}




