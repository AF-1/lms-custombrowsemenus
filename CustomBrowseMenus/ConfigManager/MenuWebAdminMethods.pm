# ConfigManager::MenuWebAdminMethods
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

package Plugins::CustomBrowseMenus::ConfigManager::MenuWebAdminMethods;

use strict;
use Plugins::CustomBrowseMenus::ConfigManager::WebAdminMethods;
our @ISA = qw(Plugins::CustomBrowseMenus::ConfigManager::WebAdminMethods);

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

sub new {
	my ($class, $parameters) = @_;

	my $self = $class->SUPER::new($parameters);
	bless $self, $class;
	return $self;
}


sub checkSaveItem {
	my ($self, $client, $params, $item) = @_;
	return undef;
}

sub checkSaveSimpleItem {
	my ($self, $client, $params) = @_;

	my $items = $params->{'items'};
	return undef;
}

sub unescape {
	my ($in, $isParam) = @_;

	$in =~ s/\+/ /g if $isParam;
	$in =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

	return $in;
}

1;
