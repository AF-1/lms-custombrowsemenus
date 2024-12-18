# ConfigManager::ParameterHandler
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

package Plugins::CustomBrowseMenus::ConfigManager::ParameterHandler;

use strict;

use base qw(Slim::Utils::Accessor);

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use DBI qw(:sql_types);
use HTML::Entities;

__PACKAGE__->mk_accessor( rw => qw(logHandler parameterPrefix criticalErrorCallback) );

sub new {
	my ($class, $parameters) = @_;

	my $self = $class->SUPER::new();
	$self->logHandler($parameters->{'logHandler'});
	$self->parameterPrefix($parameters->{'parameterPrefix'});
	$self->criticalErrorCallback($parameters->{'criticalErrorCallback'});

	return $self;
}

sub quoteValue {
	my $value = shift;
	$value =~ s/\'/\'\'/g;
	return $value;
}

sub addValuesToTemplateParameter {
	my ($self, $p, $currentValues) = @_;

	if ($p->{'type'} =~ '^sql.*') {
		my $listValues = $self->getSQLTemplateData($p->{'data'});
		if ($p->{'type'} =~ /.*optional.*/) {
			my %empty = (
				'id' => '',
				'name' => '',
				'value' => ''
			);
			unshift @$listValues, \%empty;
		}
		$p->{'values'} = $listValues;
	} elsif ($p->{'type'} =~ 'virtuallibraries') {
		my $listValues = Plugins::CustomBrowseMenus::Plugin->getVirtualLibraries();
		if ($p->{'type'} == 'virtuallibrariessinglelist') {
			my %empty = (
				'id' => '',
				'name' => '',
				'value' => ''
			);
			unshift @{$listValues}, \%empty;
		}
		if ($p->{'value'}) {
			for my $v (@{$listValues}) {
				$v->{'selected'} = 1;
			}
		}
		$p->{'values'} = $listValues;
	} elsif ($p->{'type'} =~ 'function.*') {
		my $listValues = $self->getFunctionTemplateData($p->{'data'});
		if ($p->{'type'} =~ /.*optional.*list$/) {
			my %empty = (
				'id' => '',
				'name' => '',
				'value' => ''
			);
			unshift @$listValues, \%empty;
		}
		if ($p->{'value'}) {
			for my $v (@$listValues) {
				$v->{'selected'} = 1;
			}
		}
		$p->{'values'} = $listValues;
	} elsif ($p->{'type'} =~ '.*list$' || $p->{'type'} =~ '.*checkboxes$') {
		my @listValues = ();
		my @values = split(/,/, $p->{'data'});
		for my $value (@values) {
			my @idName = split(/=/, $value);
			my %listValue = (
				'id' => @idName[0],
				'name' => @idName[1]
			);
			if (scalar(@idName) > 2) {
				$listValue{'value'} = @idName[2];
			} else {
				$listValue{'value'} = @idName[0];
			}
			push @listValues, \%listValue;
		}
		if ($p->{'type'} =~ /.*optional.*list$/) {
			my %empty = (
				'id' => '',
				'name' => '',
				'value' => ''
			);
			unshift @listValues, \%empty;
		}
		$p->{'values'} = \@listValues;
	}
	if (defined($currentValues)) {
		$self->setValueOfTemplateParameter($p, $currentValues);
	}
}

sub setValueOfTemplateParameter {
	my ($self, $p, $currentValues) = @_;

	if (defined($currentValues)) {
		if ($p->{'type'} =~ '^sql.*' || $p->{'type'} =~ 'function.*' || $p->{'type'} =~ '.*list$' || $p->{'type'} =~ '.*checkboxes$') {
			my $listValues = $p->{'values'};
			for my $v (@$listValues) {
				if ($currentValues->{$v->{'value'}}) {
					$v->{'selected'} = 1;
				} else {
					$v->{'selected'} = undef;
				}
			}
		} else {
			for my $v (keys %$currentValues) {
				$p->{'value'} = $v;
			}
		}
	}
}

sub parameterIsSpecified {
	my ($self, $params, $parameter) = @_;

	if ($parameter->{'type'} =~ /.*multiplelist$/ || $parameter->{'type'} =~ /.*checkboxes$/) {
		my $selectedValues = undef;
		if ($parameter->{'type'} =~ /.*multiplelist$/) {
			$selectedValues = $self->getMultipleListQueryParameter($params, $self->parameterPrefix.'_'.$parameter->{'id'});
		} else {
			$selectedValues = $self->getCheckBoxesQueryParameter($params, $self->parameterPrefix.'_'.$parameter->{'id'});
		}
		if (scalar(keys %$selectedValues) > 0) {
			return 1;
		}
	} elsif ($parameter->{'type'} =~ /.*singlelist$/) {
		my $selectedValue = $params->{$self->parameterPrefix.'_'.$parameter->{'id'}};
		if (defined($selectedValue)) {
			return 1;
		}
	} else {
		if ($params->{$self->parameterPrefix.'_'.$parameter->{'id'}}) {
			return 1;
		}
	}
	return 0;
}

sub getValueOfTemplateParameter {
	my ($self, $params, $parameter) = @_;

	my $result = undef;
	my $dbh = getCurrentDBH();
	if ($parameter->{'type'} =~ /.*multiplelist$/ || $parameter->{'type'} =~ /.*checkboxes$/) {
		my $selectedValues = undef;
		if ($parameter->{'type'} =~ /.*multiplelist$/) {
			$selectedValues = $self->getMultipleListQueryParameter($params, $self->parameterPrefix.'_'.$parameter->{'id'});
		} else {
			$selectedValues = $self->getCheckBoxesQueryParameter($params, $self->parameterPrefix.'_'.$parameter->{'id'});
		}
		$self->logHandler->debug("Got ".scalar(keys %$selectedValues)." values for ".$parameter->{'id'}."");
		my $values = $parameter->{'values'};
		for my $item (@$values) {
			if (defined($selectedValues->{$item->{'id'}})) {
				if (defined($result)) {
					$result = $result.',';
				}
				my $thisvalue = $item->{'value'};
				if (!defined($parameter->{'rawvalue'}) || !$parameter->{'rawvalue'}) {
					$thisvalue = quoteValue($thisvalue);
				}
				if ($parameter->{'quotevalue'}) {
					$result .= "'".encode_entities($thisvalue,"&<>\'\"")."'";
				} else {
					$result .= encode_entities($thisvalue,"&<>\'\"");
				}
				$self->logHandler->debug("Got ".$parameter->{'id'}." = $thisvalue");
			}
		}
		if (!defined($result)) {
			$result = '';
		}
	} elsif ($parameter->{'type'} =~ /.*singlelist$/) {
		my $values = $parameter->{'values'};
		my $selectedValue = $params->{$self->parameterPrefix.'_'.$parameter->{'id'}};
		$selectedValue = Slim::Utils::Unicode::utf8decode_locale($selectedValue);
		for my $item (@$values) {
			if ($selectedValue eq $item->{'id'}) {
				my $thisvalue = $item->{'value'};
				if (!defined($parameter->{'rawvalue'}) || !$parameter->{'rawvalue'}) {
					$thisvalue = quoteValue($thisvalue);
				}
				if ($parameter->{'quotevalue'}) {
					$result = "'".encode_entities($thisvalue,"&<>\'\"")."'";
				} else {
					$result = encode_entities($thisvalue,"&<>\'\"");
				}
				$self->logHandler->debug("Got ".$parameter->{'id'}." = $thisvalue");
				last;
			}
		}
		if (!defined($result)) {
			$result = '';
		}
	} else {
		if ($params->{$self->parameterPrefix.'_'.$parameter->{'id'}}) {
			my $thisvalue = $params->{$self->parameterPrefix.'_'.$parameter->{'id'}};
			$thisvalue = Slim::Utils::Unicode::utf8decode_locale($thisvalue);
			if (!defined($parameter->{'rawvalue'}) || !$parameter->{'rawvalue'}) {
				$thisvalue = quoteValue($thisvalue);
			}
			if ($parameter->{'quotevalue'}) {
				return "'".encode_entities($thisvalue,"&<>\'\"")."'";
			} else {
				return encode_entities($thisvalue,"&<>\'\"");
			}
			$self->logHandler->debug("Got ".$parameter->{'id'}." = $thisvalue");
		} else {
			if ($parameter->{'type'} =~ /.*checkbox$/) {
				$result = '0';
			} else {
				$result = '';
			}
			$self->logHandler->debug("Got ".$parameter->{'id'}." = $result");
		}
	}
	return $result;
}


sub getXMLValueOfTemplateParameter {
	my ($self, $params, $parameter) = @_;

	my $dbh = getCurrentDBH();
	my $result = undef;
	if ($parameter->{'type'} =~ /.*multiplelist$/ || $parameter->{'type'} =~ /.*checkboxes$/) {
		my $selectedValues = undef;
		if ($parameter->{'type'} =~ /.*multiplelist$/) {
			$selectedValues = $self->getMultipleListQueryParameter($params, $self->parameterPrefix.'_'.$parameter->{'id'});
		} else {
			$selectedValues = $self->getCheckBoxesQueryParameter($params, $self->parameterPrefix.'_'.$parameter->{'id'});
		}
		$self->logHandler->debug("Got ".scalar(keys %$selectedValues)." values for ".$parameter->{'id'}." to convert to XML");
		my $values = $parameter->{'values'};
		for my $item (@$values) {
			if (defined($selectedValues->{$item->{'id'}})) {
				$result = $result.'<value>';
				$result = $result.encode_entities($item->{'value'},"&<>\'\"");
				$result = $result.'</value>';
				$self->logHandler->debug("Got ".$parameter->{'id'}." = ".$item->{'value'}."");
			}
		}
		if (!defined($result)) {
			$result = '';
		}
	} elsif ($parameter->{'type'} =~ /.*singlelist$/) {
		my $values = $parameter->{'values'};
		my $selectedValue = $params->{$self->parameterPrefix.'_'.$parameter->{'id'}};
		$selectedValue = Slim::Utils::Unicode::utf8decode_locale($selectedValue);
		for my $item (@$values) {
			if ($selectedValue eq $item->{'id'}) {
				$result = $result.'<value>';
				$result = $result.encode_entities($item->{'value'},"&<>\'\"");
				$result = $result.'</value>';
				$self->logHandler->debug("Got ".$parameter->{'id'}." = ".$item->{'value'}."");
				last;
			}
		}
		if (!defined($result)) {
			$result = '';
		}
	} else {
		if (defined($params->{$self->parameterPrefix.'_'.$parameter->{'id'}}) && $params->{$self->parameterPrefix.'_'.$parameter->{'id'}} ne '') {
			my $value = Slim::Utils::Unicode::utf8decode_locale($params->{$self->parameterPrefix.'_'.$parameter->{'id'}});
			$result = '<value>'.encode_entities($value,"&<>\'\"").'</value>';
			$self->logHandler->debug("Got ".$parameter->{'id'}." = ".$value."");
		} else {
			if ($parameter->{'type'} =~ /.*checkbox$/) {
				$result = '<value>0</value>';
			} else {
				$result = '';
			}
			$self->logHandler->debug("Got ".$parameter->{'id'}." = ".$result."");
		}
	}
	return $result;
}

sub getMultipleListQueryParameter {
	my ($self, $params, $parameter) = @_;

	my $query = $params->{url_query};
	my %result = ();
	if ($query) {
		foreach my $param (split /\&/, $query) {
			if ($param =~ /^([^=]+)=(.*)$/) {
				my $name = unescape($1);
				my $value = unescape($2);
				if ($name eq $parameter) {
					# We need to turn perl's internal
					# representation of the unescaped
					# UTF-8 string into a "real" UTF-8
					# string with the appropriate magic set.
					if ($value ne '*' && $value ne '') {
						$value = Slim::Utils::Unicode::utf8on($value);
						$value = Slim::Utils::Unicode::utf8encode_locale($value);
					}
					$result{$value} = 1;
				}
			}
		}
	}
	return \%result;
}

sub getCheckBoxesQueryParameter {
	my ($self, $params, $parameter) = @_;

	my %result = ();
	foreach my $key (keys %$params) {
		my $pattern = '^'.$parameter.'_(.*)';
		if ($key =~ /$pattern/) {
			my $id = unescape($1);
			if ($id ne '*' && $id ne '') {
				$id = Slim::Utils::Unicode::utf8on($id);
				$id = Slim::Utils::Unicode::utf8encode_locale($id);
			}
			$result{$id} = 1;
		}
	}
	return \%result;
}

sub getSQLTemplateData {
	my ($self, $sqlstatements) = @_;
	my @result =();
	my $dbh = getCurrentDBH();
	my $trackno = 0;
		for my $sql (split(/[;]/, $sqlstatements)) {
		eval {
			$sql =~ s/^\s+//g;
			$sql =~ s/\s+$//g;
			my $sth = $dbh->prepare( $sql );
			$self->logHandler->debug("Executing: $sql");
			$sth->execute() or do {
				$self->logHandler->warn("Error executing: $sql");
				$sql = undef;
			};

			if ($sql =~ /^SELECT+/oi) {
				$self->logHandler->debug("Executing and collecting: $sql");
				my $id;
				my $name;
				my $value;
				$sth->bind_col( 1, \$id);
				$sth->bind_col( 2, \$name);
				$sth->bind_col( 3, \$value);
				while( $sth->fetch() ) {
					my %item = (
						'id' => Slim::Utils::Unicode::utf8decode($id,'utf8'),
						'name' => Slim::Utils::Unicode::utf8decode($name,'utf8'),
						'value' => Slim::Utils::Unicode::utf8decode($value,'utf8')
					);
					push @result, \%item;
				}
			}
			$sth->finish();
		};
		if ( $@ ) {
			warn "Database error: $DBI::errstr\n";
			$self->criticalErrorCallback->("Running: $sql got error: <br>".$DBI::errstr);
		}
	}
	return \@result;
}

sub getFunctionTemplateData {
	my ($self, $data) = @_;
	my @params = split(/\,/, $data);
	my @result =();
	if (scalar(@params) == 2) {
		my $object = @params[0];
		my $function = @params[1];
		if (UNIVERSAL::can($object, $function)) {
			$self->logHandler->debug("Getting values for: $function");
			no strict 'refs';
			my $items = eval { &{$object.'::'.$function}() };
			if ( $@ ) {
				warn "Function call error: $@\n";
			}
			use strict 'refs';
			if (defined($items)) {
				@result = @$items;
			}
		}
	} else {
		$self->logHandler->warn("Error getting values for: $data, incorrect number of parameters ".scalar(@params)."");
	}
	return \@result;
}

sub getCurrentDBH {
	return Slim::Schema->storage->dbh();
}

*escape = \&URI::Escape::uri_escape_utf8;

sub unescape {
	my ($in) = @_;
	my ($isParam) = @_;

	$in =~ s/\+/ /g if $isParam;
	$in =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

	return $in;
}

1;
