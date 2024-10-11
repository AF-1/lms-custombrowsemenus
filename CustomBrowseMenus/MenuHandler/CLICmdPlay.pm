# MenuHandler::FunctionCmdPlay
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

package Plugins::CustomBrowseMenus::MenuHandler::CLICmdPlay;

use strict;

use base qw(Slim::Utils::Accessor);
use Plugins::CustomBrowseMenus::MenuHandler::BasePlay;
our @ISA = qw(Plugins::CustomBrowseMenus::MenuHandler::BasePlay);

use File::Spec::Functions qw(:ALL);

__PACKAGE__->mk_accessor( rw => qw(itemParameterHandler requestSource) );

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = $class->SUPER::new($parameters);
	$self->itemParameterHandler($parameters->{'itemParameterHandler'});
	$self->requestSource($parameters->{'requestSource'});

	return $self;
}

sub implementsPlay {

	return 1;
}

sub play {
	my ($self, $client, $item, $items, $cmd) = @_;

	my $result = undef;
	if (defined($item->{'playdata'})) {
		my @cmds = split(/\|/, $item->{'playdata'});
		for my $cmd (@cmds) {
			my $keywords = $self->combineKeywords($item->{'keywordparameters'}, undef, $item->{'parameters'});
			$cmd = $self->itemParameterHandler->replaceParameters($client, $cmd, $keywords);
			my @cmdParts = split(/ /, $cmd);
			my $request = $client->execute(\@cmdParts);
			if (defined($request)) {
				$request->source($self->requestSource);
			} else {
				$self->errorCallback->("CustomBrowseMenus: ERROR, couldn't execute CLI command $cmd");
			}
		}
	} else {
		$self->errorCallback->("CustomBrowseMenus: ERROR, no playdata element found");
	}
	return 0;
}

1;
