# MenuHandler::FunctionPlay
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

package Plugins::CustomBrowseMenus::MenuHandler::FunctionPlay;

use strict;

use base qw(Slim::Utils::Accessor);
use Plugins::CustomBrowseMenus::MenuHandler::BasePlay;
our @ISA = qw(Plugins::CustomBrowseMenus::MenuHandler::BasePlay);

use File::Spec::Functions qw(:ALL);

__PACKAGE__->mk_accessor( rw => qw(itemParameterHandler) );

sub new {
	my ($class, $parameters) = @_;
	my $self = $class->SUPER::new($parameters);
	$self->itemParameterHandler($parameters->{'itemParameterHandler'});
	return $self;
}

sub getItems {
	my ($self, $client, $item, $items) = @_;

	my $result = undef;
	if (defined($item->{'playdata'})) {
		my @functions = split(/\|/, $item->{'playdata'});
		if (scalar(@functions) > 0) {
			my $dataFunction = @functions[0];
			if ($dataFunction =~ /^(.+)::([^:].*)$/) {
				my $class = $1;
				my $function = $2;

				shift @functions;
				my $keywords = $self->combineKeywords($item->{'keywordparameters'}, undef, $item->{'parameters'});
				my %parameters = ();
				for my $item (@functions) {
					if ($item =~ /^(.+?)=(.*)$/) {
						$parameters{$1} = $self->itemParameterHandler->replaceParameters($client, $2, $keywords);
					}
				}
				if (UNIVERSAL::can("$class", "$function")) {
					$self->logHandler->debug("Calling ${class}->${function}");
					no strict 'refs';
					$result = eval { &{"${class}::${function}"}($client, \%parameters) };
					if ($@) {
						$self->logHandler->warn("Error calling ${class}->${function}: $@");
					}
				} else {
					$self->logHandler->warn("Error calling ${class}->${function}: function does not exist");
				}
			}
		}
	} else {
		$self->logHandler->warn("CustomBrowseMenus: ERROR, no playdata element found");
	}
	return $result;
}

1;
