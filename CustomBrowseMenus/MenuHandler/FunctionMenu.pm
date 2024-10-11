# MenuHandler::FunctionMenu
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

package Plugins::CustomBrowseMenus::MenuHandler::FunctionMenu;

use strict;

use base qw(Slim::Utils::Accessor);
use Plugins::CustomBrowseMenus::MenuHandler::SQLMenu;
our @ISA = qw(Plugins::CustomBrowseMenus::MenuHandler::SQLMenu);

use File::Spec::Functions qw(:ALL);

__PACKAGE__->mk_accessor( rw => qw(sqlHandler) );

sub new {
	my ($class, $parameters) = @_;

	my $self = $class->SUPER::new($parameters);

	return $self;
}

sub getData {
	my ($self, $client, $menudata, $keywords, $context) = @_;

	my $result = undef;
	my @functions = split(/\|/, $menudata);
	if (scalar(@functions) > 0) {
		my $dataFunction = @functions[0];
		if ($dataFunction =~ /^(.+)::([^:].*)$/) {
			my $class = $1;
			my $function = $2;

			shift @functions;
			for my $item (@functions) {
				if ($item =~ /^(.+?)=(.*)$/) {
					$keywords->{$1} = $2;
				}
			}
			if (UNIVERSAL::can("$class", "$function")) {
				$self->logHandler->debug("Calling ${class}->${function}");
				no strict 'refs';
				$result = eval { $class->$function($client, $keywords, $context) };
				if ($@) {
					$self->logHandler->warn("Error calling ${class}->${function}: $@");
				}
			}
		}
	}
	return $result;
}

1;
