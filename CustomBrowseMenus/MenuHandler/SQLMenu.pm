# MenuHandler::SQLMenu
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

package Plugins::CustomBrowseMenus::MenuHandler::SQLMenu;

use strict;

use base qw(Slim::Utils::Accessor);
use Plugins::CustomBrowseMenus::MenuHandler::BaseMenu;
our @ISA = qw(Plugins::CustomBrowseMenus::MenuHandler::BaseMenu);

use File::Spec::Functions qw(:ALL);

__PACKAGE__->mk_accessor( rw => qw(sqlHandler) );

sub new {
	my $class = shift;
	my $parameters = shift;

	my $self = $class->SUPER::new($parameters);
	$self->sqlHandler($parameters->{'sqlHandler'});

	return $self;
}

sub prepareMenu {
	my ($self, $client, $menu, $item, $option, $result, $context, $params) = @_;

	my ($menudata, $itemformat, $itemformatdata, $optionKeywords) = undef;
	if (defined($menu->{'option'})) {
		if (ref($menu->{'option'}) eq 'ARRAY') {
			my $foundOption = 0;
			if (!defined($option) && defined($menu->{'defaultoption'})) {
				$option = $menu->{'defaultoption'};
				if (defined($params)) {
					$params->{'option'} = $option;
				}
			}
			if (defined($option)) {
				my $options = $menu->{'option'};
				foreach my $op (@$options) {
					if (defined($op->{'id'}) && $op->{'id'} eq $option) {
						$menudata = $op->{'menudata'};
						$itemformat = $op->{'itemformat'} if (defined($op->{'itemformat'}));
						$itemformatdata = $op->{'itemformatdata'} if (defined($op->{'itemformatdata'}));
						$optionKeywords = $self->getKeywords($op);
						$foundOption = 1;
						last;
					}
				}
			}
			if (!defined($menudata)) {
				my $options = $menu->{'option'};
				if (!$foundOption && defined($options->[0]->{'menudata'})) {
					$menudata = $options->[0]->{'menudata'};
					$itemformat = $options->[0]->{'itemformat'} if (defined($options->[0]->{'itemformat'}));
					$itemformatdata = $options->[0]->{'itemformatdata'} if (defined($options->[0]->{'itemformatdata'}));
				} else {
					$menudata = $menu->{'menudata'};
					$itemformat = $menu->{'itemformat'} if (defined($menu->{'itemformat'}));
					$itemformatdata = $menu->{'itemformatdata'} if (defined($menu->{'itemformatdata'}));
				}
				if (!$foundOption && defined($options->[0]->{'keyword'})) {
					$optionKeywords = $self->getKeywords($options->[0]);
				}
			}
		} else {
			if (defined($menu->{'option'}->{'menudata'})) {
				$menudata = $menu->{'option'}->{'menudata'};
				$itemformat = $menu->{'option'}->{'itemformat'} if (defined($menu->{'option'}->{'itemformat'}));
				$itemformatdata = $menu->{'option'}->{'itemformatdata'} if (defined($menu->{'option'}->{'itemformatdata'}));
				$optionKeywords = $self->getKeywords($menu->{'option'});
			} else {
				$menudata = $menu->{'menudata'};
				$itemformat = $menu->{'itemformat'} if (defined($menu->{'itemformat'}));
				$itemformatdata = $menu->{'itemformatdata'} if (defined($menu->{'itemformatdata'}));
			}
		}
	} else {
		$menudata = $menu->{'menudata'};
		$itemformat = $menu->{'itemformat'} if (defined($menu->{'itemformat'}));
		$itemformatdata = $menu->{'itemformatdata'} if (defined($menu->{'itemformatdata'}));
	}
	my $keywords = $self->combineKeywords($menu->{'keywordparameters'}, $optionKeywords, $item->{'parameters'});
	my $menuData = $self->getData($client, $menudata, $keywords, $context);
	for my $dataItem (@$menuData) {
		my %menuItem = (
			'itemid' => $dataItem->{'id'},
			'itemname' => $dataItem->{'name'}
		);
		if (defined($dataItem->{'link'})) {
			$menuItem{'itemlink'} = uc($dataItem->{'link'});
		}
		if (defined($item->{'value'})) {
			$menuItem{'value'} = $item->{'value'}."_".$dataItem->{'name'};
		} else {
			$menuItem{'value'} = $dataItem->{'name'};
		}

		for my $menuKey (keys %{$menu}) {
			$menuItem{$menuKey} = $menu->{$menuKey};
		}
		if (defined($dataItem->{'type'}) && defined($menu->{'itemtype'}) && $menu->{'itemtype'} eq 'sql') {
			$menuItem{'itemtype'} = $dataItem->{'type'};
		}elsif (defined($dataItem->{'type'}) && defined($menu->{'itemtype'}) && $menu->{'itemtype'} ne $dataItem->{'type'}) {
			$menuItem{'itemsubtype'} = $dataItem->{'type'};
		}
		if (defined($dataItem->{'format'}) && defined($menu->{'itemformat'}) && $menu->{'itemformat'} eq 'sql') {
			$menuItem{'itemformat'} = $dataItem->{'format'};
		}
		my %parameters = ();
		$menuItem{'parameters'} = \%parameters;
		if (defined($item->{'parameters'})) {
			for my $param (keys %{$item->{'parameters'}}) {
				$menuItem{'parameters'}->{$param} = $item->{'parameters'}->{$param};
			}
		}
		if (defined($menu->{'contextid'})) {
			$menuItem{'parameters'}->{$menu->{'contextid'}} = $dataItem->{'id'};
		}elsif (defined($menu->{'id'})) {
			$menuItem{'parameters'}->{$menu->{'id'}} = $dataItem->{'id'};
		}
		if (defined($itemformat) && $itemformat ne 'sql') {
			$menuItem{'itemformat'} = $itemformat;
		}
		if (defined($itemformatdata) && $itemformat ne 'sql') {
			$menuItem{'itemformatdata'} = $itemformatdata;
		}
		push @$result, \%menuItem;
	}
	return undef;
}

sub getData {
	my ($self, $client, $menudata, $keywords, $context) = @_;
	return $self->sqlHandler->getData($client, $menudata, $keywords, $context);
}

1;
