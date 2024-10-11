# MenuHandler::SQLHandler
#
# (c) 2021 AF
#
# Based on the CustomBrowse plugin by (c) 2006 Erland Isaksson
#
# GPLv3 license
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
#

package Plugins::CustomBrowseMenus::MenuHandler::SQLHandler;

use strict;

use base qw(Slim::Utils::Accessor);

use File::Spec::Functions qw(:ALL);

__PACKAGE__->mk_accessor( rw => qw(logHandler pluginId pluginVersion itemParameterHandler addSqlErrorCallback) );

sub new {
	my ($class, $parameters) = @_;

	my $self = $class->SUPER::new();
	$self->logHandler($parameters->{'logHandler'});
	$self->pluginId($parameters->{'pluginId'});
	$self->pluginVersion($parameters->{'pluginVersion'});
	$self->itemParameterHandler($parameters->{'itemParameterHandler'});
	$self->addSqlErrorCallback($parameters->{'addSqlErrorCallback'});

	return $self;
}

sub getData {
	my ($self, $client, $sql, $parameters, $context) = @_;

	$self->logHandler->debug("Preparing SQL: $sql");
	$sql = $self->itemParameterHandler->replaceParameters($client, $sql, $parameters, $context, 1);
	return $self->_execute($sql);
}

sub _execute {
	my ($self, $sqlstatements) = @_;
	my @result =();
	my $dbh = getCurrentDBH();
	my $trackno = 0;
	$sqlstatements =~ s/\r\n/\n/g;
	my $newUnicodeHandling = 0;
	if (UNIVERSAL::can("Slim::Utils::Unicode", "hasEDD")) {
		$newUnicodeHandling = 1;
	}

	for my $sql (split(/;\s*\n/, $sqlstatements)) {
		eval {
			$sql =~ s/^\s+//g;
			$sql =~ s/\s+$//g;
			my $sth = $dbh->prepare( $sql );
			$self->logHandler->debug("Executing: $sql");
			$sth->execute() or do {
				$self->logHandler->warn("Error executing: $sql");
				$sql = undef;
			};

			if ($sql =~ /^\(*SELECT+/oi) {
				$self->logHandler->debug("Executing and collecting: $sql");
				my $id;
				my $name;
				my $link;
				my $valuetype;
				my $valueformat;
				$sth->bind_col( 1, \$id);
				$sth->bind_col( 2, \$name);
				# bind optional column
				eval {
					$sth->bind_col( 3, \$link);
				};
				# bind optional column
				eval {
					$sth->bind_col( 4, \$valuetype);
				};
				# bind optional column
				eval {
					$sth->bind_col( 5, \$valueformat);
				};
				while( $sth->fetch() ) {
					if ($newUnicodeHandling) {
						my %item = (
							'id' => $id?Slim::Utils::Unicode::utf8on($id):$id
						);
						if (defined($name)) {
							$item{'name'} = Slim::Utils::Unicode::utf8on($name);
						} else {
							$item{'name'} = '';
						}
						if (defined($link)) {
							$item{'link'} = Slim::Utils::Unicode::utf8on($link);
						}
						if (defined($valuetype)) {
							$item{'type'} = Slim::Utils::Unicode::utf8on($valuetype);
						}
						if (defined($valueformat)) {
							$item{'format'} = Slim::Utils::Unicode::utf8on($valueformat);
						}
						push @result, \%item;
					} else {
						my %item = (
							'id' => $id ? Slim::Utils::Unicode::utf8on(Slim::Utils::Unicode::utf8decode($id, 'utf8')) : $id
						);
						if (defined($name)) {
							$item{'name'} = Slim::Utils::Unicode::utf8on(Slim::Utils::Unicode::utf8decode($name, 'utf8'));
						} else {
							$item{'name'} = '';
						}
						if (defined($link)) {
							$item{'link'} = Slim::Utils::Unicode::utf8on(Slim::Utils::Unicode::utf8decode($link, 'utf8'));
						}
						if (defined($valuetype)) {
							$item{'type'} = Slim::Utils::Unicode::utf8on(Slim::Utils::Unicode::utf8decode($valuetype, 'utf8'));
						}
						if (defined($valueformat)) {
							$item{'format'} = Slim::Utils::Unicode::utf8on(Slim::Utils::Unicode::utf8decode($valueformat, 'utf8'));
						}
						push @result, \%item;
					}
				}
			}
			$sth->finish();
		};
		if ( $@ ) {
			warn "Database error: $DBI::errstr\n$@\n";
			$self->addSqlErrorCallback->("Running: $sql got error: <br>".$DBI::errstr);
		}
	}
	return \@result;
}

sub getCurrentDBH {
	return Slim::Schema->storage->dbh();
}

1;
