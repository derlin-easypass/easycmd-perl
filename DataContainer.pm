#!/usr/bin/perl

package DataContainer;

use utf8;
use Term::ReadKey;
use Term::ReadLine;
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
    foreach $i ( keys %{ $self->{ hash } } ){
        $self->dump( $i );
        #~ print " $i \n";
        #~ print "-" x ( 2 + length($i) ), "\n";
        #~ 
        #~ foreach $j ( keys %{ $self->{ hash }{ $i } } ){
            #~ print "  $j", " " x ( 10 - length($j) ) , "=>  ", $self->{"hash"}{ $i }{ $j }, "\n\n";
        #~ }
    }
}

sub dump{
    
    my ( $self, $account ) = @_;
    
    print "$account \n";
    print "-" x ( 2 + length($account) ), "\n";
    
    while ( ($key, $val ) = each %{ $self->{ hash }{ $account } } ){
        print ("\t", $key, " " x ( 10 - length($key) ) , "=>  ", $val, "\n") unless ($key eq "password");
    }
    
    #~ foreach $j ( keys %{ $self->{ hash }{ $key } } ){
        #~ print "  $j", " " x ( 10 - length($j) ) , "=>  ", $self->{"hash"}{ $key }{ $j }, "\n\n";
    #~ }
}



sub findAccounts{
    my ( $self, $account ) = @_;
    return grep( /$account/i, $self->keys() );
}

#~ sub dumpAll{
    #~ %self = %{ shift() };
    #~ foreach $i ( keys %self ){
        #~ print " $i \n";
        #~ print "-" x ( 2 + length($i) ), "\n";
        #~ 
        #~ foreach $j ( keys %{ $self{$i} } ){
            #~ print "  $j", " " x ( 10 - length($j) ) , "=>  $self{ $i }{ $j }\n\n";
        #~ }
    #~ }
#~ }



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

    $self->dump("essai");
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
    while( ($account, $data ) = each %{ $self->{ hash } } ){
        
        if( $account =~ /$find/i or grep( /$find/i, values %{ $data } ) > 0 ){
            push @result, $account;
        }
    }
    
    #my @result = map {  grep( /$find/, values %{ $self->{ hash } } ) ?  }
    
    return @result;
}


sub getProp{
    my ( $self, $account, $prop ) = @_;
    return $self->{ hash }{ $account }{ $prop };
}

1;
