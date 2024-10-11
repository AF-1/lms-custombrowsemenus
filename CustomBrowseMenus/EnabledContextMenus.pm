# CustomBrowseMenus::EnabledContextMenus
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

package Plugins::CustomBrowseMenus::EnabledContextMenus;

use strict;
use base qw(Plugins::CustomBrowseMenus::BaseSettings);

use File::Basename;
use File::Next;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;

my $prefs = preferences('plugin.custombrowsemenus');
my $log = logger('plugin.custombrowsemenus');

my $plugin;

sub new {
	my $class = shift;
	$plugin = shift;

	$class->SUPER::new($plugin);
}

sub name {
	return 'PLUGIN_CUSTOMBROWSEMENUS_SETTINGS_ENABLEDCONTEXTMENUS';
}

sub page {
	return 'plugins/CustomBrowseMenus/settings/enabledcontextmenus.html';
}

sub currentPage {
	return name();
}

sub pages {
	my %page = (
		'name' => name(),
		'page' => page(),
	);
	my @pages = (\%page);
	return \@pages;
}

sub initMenus {
	my $contextBrowseMenusFlat = shift;
	my @contextMenus = ();
	for my $key (keys %$contextBrowseMenusFlat) {
		my %webmenu = ();
		my $menu = $contextBrowseMenusFlat->{$key};
		for my $key (keys %$menu) {
			$webmenu{$key} = $menu->{$key};
		}
		if (defined($webmenu{'menuname'}) && defined($webmenu{'menugroup'})) {
			$webmenu{'menuname'} = $webmenu{'menugroup'}.'/'.$webmenu{'menuname'};
		}
		push @contextMenus, \%webmenu;
	}
	@contextMenus = sort { $a->{'menuname'} cmp $b->{'menuname'} } @contextMenus;
	return @contextMenus;
}
sub handler {
	my ($class, $client, $paramRef) = @_;

	my $contextBrowseMenusFlat = Plugins::CustomBrowseMenus::Plugin::readContextBrowseConfiguration($client);

	my @contextMenus = initMenus($contextBrowseMenusFlat);
	$paramRef->{'pluginCustomBrowseMenusContextMenus'} = \@contextMenus;

	if ($paramRef->{'saveSettings'}) {
		foreach my $menu (keys %$contextBrowseMenusFlat) {
			my $menuid = "context_menu_".escape($contextBrowseMenusFlat->{$menu}->{'id'});
			if ($paramRef->{$menuid}) {
				$prefs->set($menuid.'_enabled',1);
				$contextBrowseMenusFlat->{$menu}->{'enabled'} = 1;
			} else {
				$prefs->set($menuid.'_enabled', 0);
				$contextBrowseMenusFlat->{$menu}->{'enabled'} = 0;
			}
		}
		my @contextMenus = initMenus($contextBrowseMenusFlat);
		$paramRef->{'pluginCustomBrowseMenusContextMenus'} = \@contextMenus;
	}

	return $class->SUPER::handler($client, $paramRef);
}

*escape = \&URI::Escape::uri_escape_utf8;

1;
