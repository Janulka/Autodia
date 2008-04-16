################################################################
# AutoDIA - Automatic Dia XML.   (C)Copyright 2001 A Trevena   #
#                                                              #
# AutoDIA comes with ABSOLUTELY NO WARRANTY; see COPYING file  #
# This is free software, and you are welcome to redistribute   #
# it under certain conditions; see COPYING file for details    #
################################################################
package Autodia::Handler::DBI;

require Exporter;

use strict;

use warnings;
use warnings::register;

use vars qw($VERSION @ISA @EXPORT);
use Autodia::Handler;

@ISA = qw(Autodia::Handler Exporter);

use Autodia::Diagram;
use Data::Dumper;
use DBI;

#---------------------------------------------------------------

#####################
# Constructor Methods

# new inherited from Autodia::Handler

#------------------------------------------------------------------------
# Access Methods

# parse_file inherited from Autodia::Handler

#-----------------------------------------------------------------------------
# Internal Methods

# _initialise inherited from Autodia::Handler

sub _parse_file { # parses dbi-connection string
  my $self     = shift();
  my $filename = shift();
  my %config   = %{$self->{Config}};

  # new dbi connection
  my $dbh = DBI->connect("DBI:$filename", $config{username}, $config{password});

  my $escape_tablenames = 0;
  my $unescape_tablenames=0;
  my $database_type =  $dbh->get_info( 17 );
  warn "DBI - processing database type : $database_type\n";

  my $schema = '' ;
  # only keep tables in schema public for PostgreSQL
  # could be given as a parameter... (+ a list of tables...)
  $schema = 'public' if (lc($database_type) =~ m/(oracle|postgres)/);

  print "database type : $database_type $schema\n";

  # Manage database tablenames that need to be escaped before calling DBI
  # and those that need to be unescaped before calling DBI 
  $escape_tablenames = 1 if (lc($database_type) =~ m/(oracle|postgres)/);
  $unescape_tablenames = 1 if (lc($database_type) =~ m/(mysql)/);
  print "esc : $escape_tablenames unescape $unescape_tablenames\n";

  # pre-process tables
  foreach my $table ($dbh->tables(undef, $schema, '%', '')) {
      $table =~ s/['`"]//g;
      my $esc_table = $table;
      $esc_table = qq{"$esc_table"} if ($escape_tablenames);
      my $sth = $dbh->prepare("select * from $esc_table where 1 = 0");
      $sth->execute;
      $self->{tables}{$table}{fields} = $sth->{NAME};
#      $self->{tables}{$table}{fields_hash} = map { $_ => 1 } $sth->{NAME};
      $sth->finish;
  }


  # got to about here applying dbi datatypes patch
  foreach my $table (keys %{$self->{tables}}) {
    # create new 'class' representing table
    my $Class = Autodia::Diagram::Class->new($table);
    # add 'class' to diagram
    $self->{Diagram}->add_class($Class);

    # get fields
    my $esc_table = $table;
    $esc_table = qq{"$esc_table"} if ($escape_tablenames);

#    warn "table : $esc_table\n";

    for my $field (@{$self->{tables}{$table}{fields}}) {
      $Class->add_attribute({
			     name => $field,
			     visibility => 0,
			     type => '',
			    });

      if (my $dep = $self->_is_foreign_key($table, $field)) {
	$self->{foreign_tables}{$dep} = {field => $field, table => $table, class => $Class }
      }
    }
  }

  foreach my $fk_table (keys %{$self->{foreign_tables}} ) {
    $self->_add_foreign_keytable($self->{foreign_tables}{$fk_table}{table},
				 $self->{foreign_tables}{$fk_table}{field},
				 $self->{foreign_tables}{$fk_table}{class},
				 $fk_table);
  }

  $dbh->disconnect;
}


sub _add_foreign_keytable {
  my ($self,$table,$field,$Class,$dep) = @_;

  my $Superclass = Autodia::Diagram::Superclass->new($dep);
  my $exists_already = $self->{Diagram}->add_superclass($Superclass);
  if (ref $exists_already) {
    $Superclass = $exists_already;
    # create new relationship
    my $Relationship = Autodia::Diagram::Inheritance->new($Class, $Superclass);
    # add Relationship to superclass
    $Superclass->add_inheritance($Relationship);
    # add Relationship to class
    $Class->add_inheritance($Relationship);
    # add Relationship to diagram
    $self->{Diagram}->add_inheritance($Relationship);
  } else {
    warn "misguessed foreign key : $field\n";
  }
  return;
}

sub _is_foreign_key {
  my ($self, $table, $field) = @_;
  my $is_fk = undef;
  $field =~ s/'"`//g;
  if (($field !~ m/$table.u?id/i) && ($field =~ m/^(.*)_u?id$/i)) {
      $is_fk = ($self->{tables}{$1}) ? $1 : undef;
  } elsif (($field ne $table ) && ($self->{tables}{$field})) {
      $is_fk = $field;
  }
  return $is_fk;
}

sub _discard_line
{
  warn "not implemented\n";
  return 0;
}

1;

###############################################################################

=head1 NAME

Autodia::Handler::DBI.pm - AutoDia handler for DBI connections

=head1 INTRODUCTION

This module parses the contents of a database through a dbi connection and builds a diagram

%language_handlers = { .. , dbi => "Autodia::Handler::DBI", .. };

=head1 CONSTRUCTION METHOD

use Autodia::Handler::DBI;

my $handler = Autodia::Handler::DBI->New(\%Config);
This creates a new handler using the Configuration hash to provide rules selected at the command line.

=head1 ACCESS METHODS

$handler->Parse($connection); # where connection includes full or dbi connection string

$handler->output(); # any arguments are ignored.

=cut





