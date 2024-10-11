# MenuHandler::AllPlay
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

package Plugins::CustomBrowseMenus::MenuHandler::AllPlay;

use strict;

use base qw(Slim::Utils::Accessor);
use Plugins::CustomBrowseMenus::MenuHandler::BasePlay;
our @ISA = qw(Plugins::CustomBrowseMenus::MenuHandler::BasePlay);

use File::Spec::Functions qw(:ALL);

sub new {
	my ($class, $parameters) = @_;
	my $self = $class->SUPER::new($parameters);
	return $self;
}

sub getItems {
	my ($self, $client, $item, $items) = @_;

	my @result = ();
	if (defined($items)) {
		@result = @$items;
	} else {
		push @result, $item;
	}
	return \@result;
}

1;
