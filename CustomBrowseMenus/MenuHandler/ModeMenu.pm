# MenuHandler::ModeMenu
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

package Plugins::CustomBrowseMenus::MenuHandler::ModeMenu;

use strict;

use base qw(Slim::Utils::Accessor);
use Plugins::CustomBrowseMenus::MenuHandler::BaseMenu;
our @ISA = qw(Plugins::CustomBrowseMenus::MenuHandler::BaseMenu);

use File::Spec::Functions qw(:ALL);

__PACKAGE__->mk_accessor( rw => qw(itemParameterHandler) );

sub new {
	my ($class, $parameters) = @_;

	my $self = $class->SUPER::new($parameters);
	$self->itemParameterHandler($parameters->{'itemParameterHandler'});

	return $self;
}

sub prepareMenu {
	my ($self, $client, $menu, $item, $option, $result, $context) = @_;

	my $keywords = $self->combineKeywords($menu->{'keywordparameters'}, undef, $item->{'parameters'});
	my @params = split(/\|/, $menu->{'menudata'});
	my $mode = shift(@params);
	my %modeParameters = ();
	foreach my $keyvalue (@params) {
		if ($keyvalue =~ /^([^=].*?)=(.*)/) {
			my $name = $1;
			my $value = $2;
			if ($name =~ /^([^\.].*?)\.(.*)/) {
				if (!defined($modeParameters{$1})) {
					my %hash = ();
					$modeParameters{$1}=\%hash;
				}
				$modeParameters{$1}->{$2} = $self->itemParameterHandler->replaceParameters($client, $value, $keywords, $context);
			} else {
				$modeParameters{$name} = $self->itemParameterHandler->replaceParameters($client, $value, $keywords, $context);
			}
		}
	}
	my %params = (
		'useMode' => $mode,
		'parameters' => \%modeParameters
	);
	return \%params;
}

sub hasCustomUrl {
	return 1;
}

sub getCustomUrl {
	my ($self, $client, $item, $params, $parent, $context) = @_;

	if (defined($item->{'menu'}->{'menuurl'})) {
		my $url = $item->{'menu'}->{'menuurl'};
		my $keywords = $self->combineKeywords($item->{'menu'}->{'keywordparameters'}, undef, $params);
		$url = $self->itemParameterHandler->replaceParameters($client, $url, $keywords, $context);
		return $url;
	}
	return undef;
}

1;
