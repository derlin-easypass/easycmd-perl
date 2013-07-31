#!/usr/bin/perl

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
    
    foreach $s (@ls) {
        print $c++, ' : ', $s;
    }
    
    do{
        $i = $term->readline("\nsession [0-$c]: ");
    } while not defined $i or $i !~ /[0-9]+/ or $i > $c;
    
    chomp( $session = @ls[$i] );
}else{
    $session .= ".data_ser";
}

$session = $session_path . $session;

#~ print "\nType your password:";
#~ ReadMode('noecho'); # don't echo
#~ my $password = $term->readline();
#~ ReadMode(0);        # back to normal
#~ print "\n\n";
$password = "serieux";

my $datas = DataContainer->new();
$datas->loadFromFile( $session, $password );


my @last = $datas->keys();

while ( 1 ){

    my @in = shellwords( $term->readline("\n> ") ); #for it to work, be sure to have libterm-readline-gnu-perl package installed + export "PERL_RL= o=0"
    print "\n";
    
    # parses the arg
    my $arg = $in[1];
    
    if( scalar( @last ) > 0 and isInRange( $arg, scalar( @last ) ) ){
        $arg = $last[$arg];
    }

    switch( $in[0] ){
        
        case "list" { 
            if( not defined $arg ){
                @last = $datas->keys();
                foreach ( @last ) { print "  ", $i++, ": $_\n"; } 
                undef $i;
                
            }else{
                $_ = scalar( $datas->findAccounts( $arg ) );
                print "  --- ", $_, " match", $_ > 1 ? "es" : ""," ---" , "\n\n";
                @last = $datas->findAccounts( $arg );
                
                if( scalar( @last ) < 20 ){
                    
                    if( scalar( @last ) > 8 ){
                        foreach(@last){  print $i++, "  : ", $_, "\n"; }
                        undef $i;
                    
                    }else{
                        foreach( @last ){
                            print $i++, ": ";
                            $datas->dump( $_ );
                        }
                        undef $i;
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
                foreach ( @last ) { print "  ", $i++, ": $_\n\n"; } 
                undef $i;
            }
        }# end find
        
        
        case "pass" {
            $arg = $in[1];
            
            if( scalar( @last ) > 0 and isInRange( $arg, scalar( @last ) ) ){

                my $pass = $datas->getProp( $last[ $arg ], "password" );
                if( $pass ){
                    Clipboard->copy( $pass );
                    
                }else{
                    print "The password is empty...\n";
                } 
                
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
                            foreach(@last){  print "  ", $i++, "  : ", $_, "\n"; }
                            undef $i;
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

my %accounts = %{ &encrypted_to_hash( $session, $password ) };

&dumpAll( \%accounts );

%found = %{ findAccount( \%accounts, "essai" ) };

print Dump (\%found);
dumpAll( \%found );
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

sub findAccount{
    %arg = %{ $_[0] };
    foreach $key (keys( %arg )){
        %{ $target{$key} } = %{ $arg{$key} } unless $key !~ /$_[1]/;
    }
    return \%target;
}


=item dumbAll()
 prints the content of a 2-dimensional hash in a pretty format
 
 parameter:
 I<\%hash> a pointer to the hash
=cut
sub dumpAll{
    %hash = %{ shift() };
    foreach $i ( keys %hash ){
        print " $i \n";
        print "-" x ( 2 + length($i) ), "\n";
        
        foreach $j ( keys %{ $hash{$i} } ){
            print "  $j", " " x ( 10 - length($j) ) , "=>  $hash{ $i }{ $j }\n\n";
        }
    }
}


=item encrypted_to_hash()
 This function decrypt a json (.data_ser) file, parses it and returns a 2-dimensional
 hash containing the accounts + the details.
 
 parameters:
 I<sessionpath>
 I<password>
=cut
sub encrypted_to_hash{
    
    my $sessionpath = shift();
    my $pass = shift();
    my $decrypt = `openssl enc -d -aes-128-cbc -a -in $sessionpath -k $pass 2>&1`;
    print "exit status : $? \n";
    
    #print $decrypt;
    my $json = new JSON;

    # these are some nice json options to relax restrictions a bit:
    my $json_text = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode( $decrypt );
    my @keys = ("account", "pseudo", "email", "password", "notes");
    my %result;

    # constructs the hash
    foreach my $array ( @{ $json_text } ){
         my $account = @{ $array }[0];
         for my $i (1 .. 4){
             utf8::encode( $result{ $account }{ $keys[$i] } = @{ $array }[$i] );
         }
     }
    
    return \%result;
}



package Session;

sub new{

    my ( $class, $data ) = @_;
    @keys = sort keys %{ $data };
    
    my $self = {
        "data" => $data,
        "accounts" => @{ $data->keys() }
    };
    
    bless $self, $class;
    return $self;        
}

sub printKeys{
    print "keys : \n";
    my $self = shift();
    foreach ( @{ $self->{ "accounts" } } ){ print "--$_\n"; }
}
