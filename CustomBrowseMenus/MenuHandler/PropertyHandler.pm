# MenuHandler::PropertyHandler
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

package Plugins::CustomBrowseMenus::MenuHandler::PropertyHandler;

use strict;

use base qw(Slim::Utils::Accessor);

use File::Spec::Functions qw(:ALL);
use Slim::Utils::Prefs;

__PACKAGE__->mk_accessor( rw => qw(logHandler pluginId pluginVersion) );

my $prefs = preferences('plugin.custombrowsemenus');

sub new {
	my ($class, $parameters) = @_;

	my $self = $class->SUPER::new();
	$self->logHandler($parameters->{'logHandler'});
	$self->pluginId($parameters->{'pluginId'});
	$self->pluginVersion($parameters->{'pluginVersion'});

	return $self;
}

sub getProperty {
	my ($self, $name) = @_;
	my $properties = $self->getProperties();
	return $properties->{$name};
}

sub getProperties {
	my $self = shift;
	my $result = $prefs->get('properties');
	return $result;
}

1;
