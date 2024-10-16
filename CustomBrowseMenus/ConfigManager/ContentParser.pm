# ConfigManager::ContentParser
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

package Plugins::CustomBrowseMenus::ConfigManager::ContentParser;

use strict;
use base qw(Slim::Utils::Accessor);
use Plugins::CustomBrowseMenus::ConfigManager::BaseParser;
our @ISA = qw(Plugins::CustomBrowseMenus::ConfigManager::BaseParser);

use Slim::Utils::Prefs;
use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

my $prefs = preferences('plugin.custombrowsemenus');

sub new {
	my ($class, $parameters) = @_;

	$parameters->{'contentType'} = 'menu';
	my $self = $class->SUPER::new($parameters);
	return $self;
}

sub parse {
	my ($self, $client, $item, $content, $items, $globalcontext, $localcontext) = @_;

	if (!$globalcontext->{'onlylibrarysupported'}) {
		return $self->parseContent($client, $item, $content, $items, $globalcontext, $localcontext);
	} else {
		return undef;
	}
}

sub checkContent {
	my ($self, $xml, $globalcontext, $localcontext) = @_;

	my $disabled = 0;
	my $forceEnabledBrowse = undef;
	if (defined($xml->{'enabledbrowse'})) {
		if (ref($xml->{'enabledbrowse'}) ne 'HASH') {
			$forceEnabledBrowse = $xml->{'enabledbrowse'};
		} else {
			$forceEnabledBrowse = '';
		}
	} elsif (defined($localcontext->{'forceenabledbrowse'})) {
		$forceEnabledBrowse = $localcontext->{'forceenabledbrowse'};
	}

	if (defined($xml->{'menu'}) && defined($xml->{'menu'}->{'id'})) {
		my $enabled = $prefs->get('menu_'.escape($xml->{'menu'}->{'id'}).'_enabled');
		if (defined($enabled) && !$enabled) {
			$disabled = 1;
		} elsif (!defined($enabled)) {
			if (defined($xml->{'defaultdisabled'}) && $xml->{'defaultdisabled'}) {
				$disabled = 1;
			}
		}
	}
	my $disabledBrowse = 1;
	if (defined($xml->{'menu'}) && defined($xml->{'menu'}->{'id'})) {
		my $enabled = $prefs->get('menubrowse_'.escape($xml->{'menu'}->{'id'}).'_enabled');
		if (defined($enabled) && $enabled) {
			$disabledBrowse = 0;
		} elsif (!defined($enabled)) {
			if (defined($xml->{'defaultenabledbrowse'}) && $xml->{'defaultenabledbrowse'}) {
				$disabledBrowse = 0;
			}
		}
	}

	$xml->{'menu'}->{'topmenu'} = 1;
	if (defined($localcontext) && defined($localcontext->{'simple'})) {
		$xml->{'menu'}->{'simple'} = 1;
	}
	if ($localcontext->{'librarysupported'}) {
		$xml->{'menu'}->{'librarysupported'} = 1;
	}
	if (!$disabled) {
		$xml->{'menu'}->{'enabled'} = 1;
		if (!defined($forceEnabledBrowse)) {
			if ($disabledBrowse) {
				$xml->{'menu'}->{'enabledbrowse'} = 0;
			} else {
				$xml->{'menu'}->{'enabledbrowse'} = 1;
			}
		} else {
			$xml->{'menu'}->{'forcedenabledbrowse'} = 1;
			$xml->{'menu'}->{'enabledbrowse'} = $forceEnabledBrowse;
		}
		if ($globalcontext->{'source'} eq 'plugin' || $globalcontext->{'source'} eq 'builtin') {
			$xml->{'menu'}->{'defaultitem'} = 1;
		} else {
			$xml->{'menu'}->{'customitem'} = 1;
		}
	} elsif ($disabled) {
		$xml->{'menu'}->{'enabled'} = 0;
		if (!defined($forceEnabledBrowse)) {
			$xml->{'menu'}->{'enabledbrowse'} = 0;
		} else {
			$xml->{'menu'}->{'forcedenabledbrowse'} = 1;
			$xml->{'menu'}->{'enabledbrowse'}=$forceEnabledBrowse;
		}
		if ($globalcontext->{'source'} eq 'plugin' || $globalcontext->{'source'} eq 'builtin') {
			$xml->{'menu'}->{'defaultitem'} = 1;
		} else {
			$xml->{'menu'}->{'customitem'} = 1;
		}
	}
	return 1;
}

*escape = \&URI::Escape::uri_escape_utf8;

1;
