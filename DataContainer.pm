#!/usr/bin/perl

package DataContainer;

use warnings;
use strict;

use utf8;
use Term::ReadKey;
use Term::ReadLine;
use Term::ANSIColor;

use Data::Dumper;
use JSON -support_by_pp;  


sub new{
    my $class = shift;
    my $self = {
        "hash" => {},
        "headers" => [ "pseudo", "email", "password", "notes" ]
    };
    bless $self, $class;
    return $self;

}


=item dumbAll()
 prints the content of this 2-dimensional hash in a pretty format
=cut
sub dumpAll{
    my $self = shift;
    foreach my $i ( keys %{ $self->{ hash } } ){
        $self->dump( $i );
    }
}

sub dump{
    
    my ( $self, $account ) = @_;
    return unless defined $account; 
    print color( "bright_blue" ), "*** $account ***", color( "reset" ), "\n";
    #print "-" x ( 2 + length($account) ), "\n", color( "reset" );
    
    while ( ( my $key, my $val ) = each %{ $self->{ hash }{ $account } } ){
        print "   ", $key, " " x ( 10 - length($key) ) , "=>  ", $val, "\n" unless ($key eq "password");
    }
}




sub findAccounts{
    my ( $self, $account ) = @_;
    return defined $account ? grep( /$account/i, $self->keys() ) : undef;
}


=item loadFromFile()
 This function decrypt a json (.data_ser) file, parses it and loads its data as a 2-dimensional
 hash containing the accounts + the details.
 
 parameters:
 I<sessionpath>
 I<password>
=cut
sub loadFromFile{
    
    my ( $self, $sessionpath, $pass ) = @_ ;
    my $decrypt = `openssl enc -d -aes-128-cbc -a -in $sessionpath -k $pass 2>&1`;
    
    die("Error, credentials or session path incorrect. Could not decrypt file.\n") unless $? == 0;
    
    #print $decrypt;
    my $json = new JSON;

    # these are some nice json options to relax restrictions a bit:
    my $json_text = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode( $decrypt );
    my @keys = @{ $self->{ headers } };
    unshift( @keys, "account" );
    
    # constructs the hash
    foreach my $array ( @{ $json_text } ){
         my $account = @{ $array }[0];
         for my $i (1 .. 4){
             utf8::encode( $self->{ hash }{ $account }{ $keys[$i] } = @{ $array }[$i] );
         }
     }
}



sub keys{
    return ( sort keys %{ shift->{ hash } } );
}

sub headers{
    return ( sort @{ shift->{ headers } } );
}

sub find{
    
    my ( $self, $find ) = @_;
    if( not defined $find ){ return $self->keys() };
    
    my @result;
    while( ( my $account, my $data ) = each %{ $self->{ hash } } ){
        
        if( $account =~ /$find/i or grep( /$find/i, values %{ $data } ) > 0 ){
            push @result, $account;
        }
    }
    
    return @result;
}


sub getProp{
    my ( $self, $account, $prop ) = @_;
    defined $account or return;
    return $self->{ hash }{ $account }{ $prop };
}

1;
