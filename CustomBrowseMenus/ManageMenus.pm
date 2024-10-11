# CustomBrowseMenus::ManageMenus
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

package Plugins::CustomBrowseMenus::ManageMenus;

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
	return 'PLUGIN_CUSTOMBROWSEMENUS_SETTINGS_MANAGEMENUS';
}

sub page {
	return 'plugins/CustomBrowseMenus/webadminmethods_edititems.html';
}

sub currentPage {
	my ($class, $client, $params) = @_;
	if ($params->{'webadminmethodshandler'}) {
		return Slim::Utils::Strings::string('PLUGIN_CUSTOMBROWSEMENUS_SETTINGS_MANAGECONTEXTMENUS');
	} else {
		return Slim::Utils::Strings::string('PLUGIN_CUSTOMBROWSEMENUS_SETTINGS_MANAGEMENUS');
	}
}

sub pages {
	my %pageMenu = (
		'name' => Slim::Utils::Strings::string('PLUGIN_CUSTOMBROWSEMENUS_SETTINGS_MANAGEMENUS'),
		'page' => page(),
	);
	my %pageContextMenu = (
		'name' => Slim::Utils::Strings::string('PLUGIN_CUSTOMBROWSEMENUS_SETTINGS_MANAGECONTEXTMENUS'),
		'page' => page().'?webadminmethodshandler=context',
	);
	my @pages = (\%pageMenu, \%pageContextMenu);
	return \@pages;
}

sub prepare {
	my ($class, $client, $params) = @_;
	$params->{'nosubmit'} = 1;
	$class->SUPER::handler($client, $params);
}

sub handler {
	my ($class, $client, $params) = @_;
	if ($params->{'webadminmethodshandler'} eq 'context') {
		$params->{'pluginWebAdminMethodsHandler'} = 'context';
	}
	return Plugins::CustomBrowseMenus::Plugin::handleWebEditMenus($client, $params);
}

1;
