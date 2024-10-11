# CustomBrowseMenus::EnabledMenus
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

package Plugins::CustomBrowseMenus::EnabledMenus;

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
	return 'PLUGIN_CUSTOMBROWSEMENUS_SETTINGS_ENABLEDMENUS';
}

sub page {
	return 'plugins/CustomBrowseMenus/settings/enabledmenus.html';
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
	my $browseMenusFlat = shift;
	my @menus = ();
	for my $key (keys %$browseMenusFlat) {
		my %webmenu = ();
		my $menu = $browseMenusFlat->{$key};
		for my $key (keys %$menu) {
			$webmenu{$key} = $menu->{$key};
		}
		if (defined($webmenu{'menuname'}) && defined($webmenu{'menugroup'})) {
			$webmenu{'menuname'} = $webmenu{'menugroup'}.'/'.$webmenu{'menuname'};
		}
		push @menus, \%webmenu;
	}
	@menus = sort { $a->{'menuname'} cmp $b->{'menuname'} } @menus;
	return @menus;
}
sub handler {
	my ($class, $client, $paramRef) = @_;

	my $browseMenusFlat = Plugins::CustomBrowseMenus::Plugin::readBrowseConfiguration($client);

	# Pass on the current pref values and now playing info

	my @menus = initMenus($browseMenusFlat);
	$paramRef->{'pluginCustomBrowseMenus'} = \@menus;

	if ($paramRef->{'saveSettings'}) {
		foreach my $menu (keys %$browseMenusFlat) {
			my $menuid = "menu_".escape($browseMenusFlat->{$menu}->{'id'});
			my $menubrowseid = "menubrowse_".escape($browseMenusFlat->{$menu}->{'id'});
			if ($paramRef->{$menuid}) {
				$prefs->set($menuid.'_enabled', 1);
				$browseMenusFlat->{$menu}->{'enabled'} = 1;
				if (!defined($browseMenusFlat->{$menu}->{'forceenabledbrowse'})) {
					if ($paramRef->{$menubrowseid}) {
						$prefs->set($menubrowseid.'_enabled', 1);
						$browseMenusFlat->{$menu}->{'enabledbrowse'} = 1;
					} else {
						$prefs->set($menubrowseid.'_enabled', 0);
						$browseMenusFlat->{$menu}->{'enabledbrowse'} = 0;
					}
				}
			} else {
				$prefs->set($menuid.'_enabled', 0);
				$browseMenusFlat->{$menu}->{'enabled'} = 0;
				if (!defined($browseMenusFlat->{$menu}->{'forceenabledbrowse'})) {
					$browseMenusFlat->{$menu}->{'enabledbrowse'} = 0;
				}
			}
		}
		@menus = initMenus($browseMenusFlat);
			$paramRef->{'pluginCustomBrowseMenus'} = \@menus;
		}

		return $class->SUPER::handler($client, $paramRef);
}

*escape = \&URI::Escape::uri_escape_utf8;

1;
