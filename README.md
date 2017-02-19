*easypass* - Command Line interface to securely store information and
passwords about various accounts into files.

# DESCRIPTION

Having so many accounts and password that you have trouble remembering
them ? Easypasss is made for you. This program stores passwords and
account details in files encrypted using openssl encryption.You can
split data into multiple session files, each of them encrypted with its
own password.

# SYNOPSIS

    easypass [-s|--session <session name>] [-p|--path <session path>]

Command-line arguments:

    -s|--session 
         the name of the session to open (filename)

    -p|--path 
         the path of the sessions directory
 

# PROMPT COMMANDS

In the command description, the `<acc. hint>` parameter denotes an account hint. It can either a number (see "finding accounts") or a pattern matching _only one_ account.

__finding accounts__

The following commands lookup for accounts and display a list of account names. Each item of the result list is prefixed with an integer that you can use later as an account hint. Those numbers are valid until a new search command is executed.

 * `find`: find accounts:
     -  <pattern(s)>`: display all the accounts having at least one field containing the pattern
     - `<property> [is|=] <pattern(s)>` : display all the accounts whose property matches exactly the pattern(s).
     - `<property> [like|~] <pattern(s)>`: display all the accounts whose property contains the pattern(s).
     - `<property> unlike <pattern(s)>`: display all the accounts whose property does not contain the pattern(s).
 * `list [<pattern>]`: list all the account names in the current session. If pattern is specified, it behaves like `find <pattern(s)>`.

__manipulating accounts__: 

 * `add` : add a a new account. The file is then automatically updated.
 * `delete <acc>`: delete the matching account.
 * `edit|modify <account name>`: edit the properties of the matching account.
 * `details|show <acc. hint>`: display the details of the account.
 * `showpass <acc. hint>` : display the password (in clear text !!) during 2 seconds in the terminal (this supposes a readline _GNU_ support).

__copying properties__: 

 * `copy <property> <acc. hint>`: copy some property of an account to the clipboard.
 * `pass <acc. hint>`: copy the password of the account in the clipboard. This is an alias of `copy pass`.

__global commands__:

 * `help`: print this help message.
 * `h`: print the list of available commands, without details.
 * `exit|quit`: quit the program.


# REQUIRES

    Cwd
    JSON
    Clipboard
    Data::Dumper
    File::Spec::Functions
    Getopt::Long
    Term::ANSIColor
    Term::ReadKey
    Term::ReadLine::Gnu
    Text::ParseWords

# INSTALL 

TODO

# AUTHOR 

Developer: Lucy Linder, <lucy.derlin@gmail.com> | September, 2014.

