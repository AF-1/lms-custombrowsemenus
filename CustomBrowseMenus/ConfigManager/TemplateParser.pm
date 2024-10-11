# ConfigManager::TemplateParser
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

package Plugins::CustomBrowseMenus::ConfigManager::TemplateParser;

use strict;
use Plugins::CustomBrowseMenus::ConfigManager::BaseParser;
our @ISA = qw(Plugins::CustomBrowseMenus::ConfigManager::BaseParser);

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

sub new {
	my ($class, $parameters) = @_;

	$parameters->{'contentType'} = 'template';
	my $self = $class->SUPER::new($parameters);

	return $self;
}

sub parse {
	my ($self, $client, $item, $content, $items, $globalcontext, $localcontext) = @_;

	if ($globalcontext->{'source'} ne 'plugin') {
		return $self->parseContent($client, $item, $content, $items, $globalcontext, $localcontext);
	} else {
		$items->{lc($item)} = $content;
		return undef;
	}
}

sub checkContent {
	my ($self, $xml, $globalcontext, $localcontext) = @_;

	if ($globalcontext->{'source'} ne 'plugin' && $globalcontext->{'source'} ne 'builtin') {
		$xml->{'template'}->{'customtemplate'} = 1;
	}
	return 1;
}

1;
