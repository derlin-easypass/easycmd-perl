#!/usr/bin/perl

=head1 NAME

DataContainer - a module to read and manipulate easypass session files from the commandline

=head1 SYNOPSIS 
 
 use DataContainer;
 use Term::ReadKey;

 # gets the session full path from the arguments
 my $session = $ARGV[0];
 
 # gets the password from the user
 print "\nType your password: ";
 ReadMode('noecho'); # don't echo
 my $password = <>;
 ReadMode(0);        # back to normal
 print "\n";
 
 my $datas = DataContainer->new();
 $datas->load_from_file( $session, $password );

=head1 DESCRIPTION

This module loads the account datas from a .data_ser (easypass) file and stores
everything in a hash. 
It then offers different methods to manipulate and search in the datas. 

=head2 METHODS

=over 4

=item C<new>

Returns a new empty container. Only the headers are available.


=item C<load_from_file>

Used to load datas from a file into the object (initialisation).

I<params> : full session path (i.e. the file to load from), password

=item C<save_to_file>

The data contained in this object are saved to a file.
The saving is easypass compatible, i.e. json encoded and aes-cbc-128 encrypted (openssl compatible) 

I<params> : full session path (i.e. the file to save to), password


=item C<match_account_name>

Returns an array containing the account names matching a specified regex. 

I<params> : the regex


=item C<match_any>

Returns an array containing the account names of all the records with one or more fields matching a specified regex.

I<params> : the regex


=item C<accounts>
    
Returns an array containing all the account names, on ascending order.

I<params> :  - 


=item C<headers>
    
Returns an array containing the headers, i.e. the fields of an account (email, pseudo, password, notes).

I<params> :  - 


=item C<get_prop>

Returns the value of the specified field from the specified session.  
  
I<params> :  the account name, the header name 


=item C<to_string>

Returns a string containing the details of a specific account, 
or nothing if the account is not defined.     

I<params> : full account name


=item C<add>

Adds a new item (the changes are not serialized, you need to call save_to_file to make it permanent).
  
I<params> :  the new account name, a pointer to a hash containing the new values (pseudo, email, password, notes)


=item C<delete>

Removes and entry from the session and saves the file.  
  
I<params> :  the account name, to be deleted


=back


=head1 DEPENDENCIES

Term::ANSIColor, for the to_string method


=head1 AUTHOR

Lucy Linder, august 2013

=cut
    
package DataContainer;

#use warnings;
use strict;

use utf8;
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


sub dump_all{
    my $self = shift;
    foreach my $i ( keys %{ $self->{ hash } } ){
        print $self->to_string( $i );
    }
}




sub match_account_name{
    my ( $self, $account ) = @_;
    return defined $account ? grep( /$account/i, $self->accounts() ) : undef;
}

sub match_any{
    
    my ( $self, $regex ) = @_;
    if( not defined $regex ){ return $self->accounts() };
    
    my @result;
    my @search_headers = grep { not $_ eq "password" } $self->headers;

    while( ( my $account, my $data ) = each %{ $self->{ hash } } ){
        
        if( $account =~ /$regex/i or grep { $data->{$_} =~ /$regex/i } @search_headers ){
            push @result, $account;
        }
    }
    
    return @result;
}


sub load_from_file{
    
    my ( $self, $sessionpath, $pass ) = @_ ;
    my $decrypt = `openssl enc -d -aes-128-cbc -a -in '$sessionpath' -k $pass 2>/dev/null`;
    die "Error, credentials or session path incorrect. Could not decrypt file.\n" 
        unless $decrypt =~ /^\s*\[/;
    

    # these are some nice json options to relax restrictions a bit:
    my $json = new JSON;
    
    my $json_text;
    eval { $json_text = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode( $decrypt ) };
    
    die "Unable to decrypt file (json corrupted?)... Check your credentials and try again\n"
     unless $json_text and $json_text =~ 'ARRAY';

    my @keys = @{ $self->{ headers } };
    unshift( @keys, "account" );
    
    
    # constructs the hash
    foreach my $array ( @{ $json_text } ){
         my $account = $array->[0] =~ s/^\s+|\s+$//rg; # trims the account name
         utf8::encode( $account );
         for (1 .. 4){
              #$self->{ hash }{ $account }{ $keys[$_] } = $array->[$_];
              utf8::encode( $self->{ hash }{ $account }{ $keys[$_] } = $array->[$_] );
         }
     }
}

sub save_to_file{
    my ( $self, $sessionpath, $pass ) = @_ ;
    my $json = new JSON;

    my @encrypt;
    
    # reconstructs the ArrayList<Object[5]> java structure
    foreach my $account ( keys %{ $self->{hash} } ){
        my @entry = ( $account );
        utf8::decode( @entry ); # in scalar context, the array returns its last element
        foreach my $field ( @{ $self->{headers} } ){
            utf8::decode( $_ = $self->get_prop( $account, $field ) );
            push @entry, $_;
        }
        push @encrypt, \@entry;
    }
    
    # converts to json
    #my $json_text = $json->new->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->encode( \@encrypt );
    my $json_text = $json->encode( \@encrypt );
    utf8::decode( $json_text =~ s/\"/\\\"/g ); # decodes in utf8 and escapes the double quotes since we use echo "..." for openssl command
    
    # encrypts the json
    my $encrypt = `echo "$json_text" | openssl enc -aes-128-cbc -a -k $pass 2>&1`;
    return unless $? == 0;
    
    # prints the encrypted result to file
    open my $FILE, ">$sessionpath";
    print $FILE $encrypt;
    close $FILE;

    return 1;
    
}

sub to_string{
    
    my ( $self, $account ) = @_;
    return unless defined $account; 
    my $str = color( "bright_blue" ) . "*** $account ***" . color( "reset" ) . "\n";
    #print "-" x ( 2 + length($account) ), "\n", color( "reset" );
    
    while ( ( my $key, my $val ) = each %{ $self->{ hash }{ $account } } ){
        $str .= "   $key" . " " x ( 10 - length($key) ) . "=>  $val \n" unless ($key eq "password");
    }
    
    return $str;
}


sub accounts{
    return ( sort keys %{ shift->{ hash } } );
}

sub headers{
    return ( sort @{ shift->{ headers } } );
}

sub get_prop{
    my ( $self, $account, $prop ) = @_;
    defined $account or return;
    return $self->{ hash }{ $account }{ $prop };
}


sub delete{
    my ( $self, $account ) = @_;
    defined $account or return;
    delete $self->{ hash }{ $account };    
}


sub add{
    my ( $self, $account, $values ) = @_;
    defined $account or return;
    $self->{ hash }{ $account } = $values;    
}

1;
