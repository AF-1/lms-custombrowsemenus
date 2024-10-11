# MenuHandler::ParameterHandler
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

package Plugins::CustomBrowseMenus::MenuHandler::ParameterHandler;

use strict;

use base qw(Slim::Utils::Accessor);

use File::Spec::Functions qw(:ALL);
use Slim::Utils::Prefs;

__PACKAGE__->mk_accessor( rw => qw(logHandler pluginId pluginVersion propertyHandler) );

my %prefs = ();

sub new {
	my ($class, $parameters) = @_;

	my $self = $class->SUPER::new();
	$self->logHandler($parameters->{'logHandler'});
	$self->pluginId($parameters->{'pluginId'});
	$self->pluginVersion($parameters->{'pluginVersion'});
	$self->propertyHandler($parameters->{'propertyHandler'});

	return $self;
}

sub quoteValue {
	my $value = shift;
	$value =~ s/\'/\'\'/g;
	return $value;
}

sub replaceParameters {
	my ($self, $client, $originalValue, $parameters, $context, $quote) = @_;

	$self->logHandler->debug('originalValue/sql = '.Data::Dump::dump($originalValue));

	if (defined($parameters)) {
		for my $param (keys %$parameters) {
			my $propertyValue = $parameters->{$param};
			if ($quote) {
				$propertyValue = quoteValue($propertyValue);
			}
			$originalValue =~ s/\{$param\}/$propertyValue/g;
		}
	}

	while ($originalValue =~ m/\{custombrowsemenus\.(.*?)\}/) {
		my $propertyValue = $self->propertyHandler->getProperty($1);
		if (defined($propertyValue)) {
			if ($quote) {
				$propertyValue = quoteValue($propertyValue);
			}
			$originalValue =~ s/\{custombrowsemenus\.$1\}/$propertyValue/g;
		} else {
			$originalValue =~ s/\{custombrowsemenus\..*?\}//g;
		}
	}

	while ($originalValue =~ m/\{property:(.*?):(.*?)\}/) {
		my $propContext = $1;
		my $propName = $2;
		if (!defined($prefs{$propContext})) {
			$prefs{$propContext} = preferences($propContext);
		}
		my $propertyValue = $prefs{$propContext}->get($propName);
		if (defined($propertyValue)) {
			if ($quote) {
				$propertyValue = quoteValue($propertyValue);
			}
			$originalValue =~ s/\{property:$propContext:$propName\}/$propertyValue/g;
		} else {
			$originalValue =~ s/\{property:$propContext:$propName\}//g;
		}
	}

	while ($originalValue =~ m/\{activeclientvirtuallibrary}/) {
		my $activeClientVL = Slim::Music::VirtualLibraries->getLibraryIdForClient($client) || -1;
		$self->logHandler->debug('activeClientVL = '.Data::Dump::dump($activeClientVL));
		$originalValue =~ s/\{activeclientvirtuallibrary\}/'$activeClientVL'/g if $activeClientVL;
	}

	while ($originalValue =~ m/\{selectedvirtuallibrary:(.*?)\}/) {
		my $persistentVLID = $1;
		$self->logHandler->debug('persistentVLID = '.Data::Dump::dump($persistentVLID));
		if (defined($persistentVLID)) {
			my $VLrealID = Slim::Music::VirtualLibraries->getRealId($persistentVLID);
			$self->logHandler->debug('VLrealID = '.Data::Dump::dump($VLrealID));
			$originalValue =~ s/\{selectedvirtuallibrary:$persistentVLID\}/'$VLrealID'/g;
		}
	}

	while ($originalValue =~ m/\{clientproperty:(.*?):(.*?)\}/) {
		my $propContext = $1;
		my $propName = $2;
		if (!defined($prefs{$propContext})) {
			$prefs{$propContext} = preferences($propContext);
		}
		my $propertyValue = undef;
		if (defined($client)) {
			$propertyValue = $prefs{$propContext}->client($client)->get($propName);
		}
		if (defined($propertyValue)) {
			if ($quote) {
				$propertyValue = quoteValue($propertyValue);
			}
			$originalValue =~ s/\{clientproperty:$propContext:$propName\}/$propertyValue/g;
		} else {
			$originalValue =~ s/\{clientproperty:$propContext:$propName\}//g;
		}
	}
	while ($originalValue =~ m/\{context\.(.*?)\}/) {
		my $propertyValue = undef;
		my $contextHash = $context;
		if (!defined($contextHash)) {
			$contextHash = $client->modeParam($self->pluginId.".context");
		}
		if (defined($contextHash)) {
			$propertyValue = $contextHash->{$1};
		}
		if (defined($propertyValue)) {
			if ($quote) {
				$propertyValue = quoteValue($propertyValue);
			}
			$originalValue =~ s/\{context\.$1\}/$propertyValue/g;
		} else {
			$originalValue =~ s/\{context\..*?\}//g;
		}
	}

	return $originalValue;
}

1;
