# CustomBrowseMenus::Settings
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

package Plugins::CustomBrowseMenus::Settings;

use strict;
use base qw(Plugins::CustomBrowseMenus::BaseSettings);

use File::Basename;
use File::Next;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Strings;

my $prefs = preferences('plugin.custombrowsemenus');
my $log = logger('plugin.custombrowsemenus');

my $plugin; # reference to main plugin

sub new {
	my $class = shift;
	$plugin = shift;

	$class->SUPER::new($plugin,1);
}

sub name {
	return 'PLUGIN_CUSTOMBROWSEMENUS';
}

sub page {
	return 'plugins/CustomBrowseMenus/settings/basic.html';
}

sub currentPage {
	return Slim::Utils::Strings::string('PLUGIN_CUSTOMBROWSEMENUS_SETTINGS');
}

sub pages {
	my %page = (
		'name' => Slim::Utils::Strings::string('PLUGIN_CUSTOMBROWSEMENUS_SETTINGS'),
		'page' => page(),
	);
	my @pages = (\%page);
	return \@pages;
}

sub prefs {
	return ($prefs, qw(cbmparentfolderpath menuname toplevelmenuinextras override_trackinfo header_value_separator touchtoplay));
}

sub handler {
	my ($class, $client, $paramRef) = @_;
	# TODO: Handle properties attribute
	if ($paramRef->{'saveSettings'}) {
		my $properties = $prefs->get('properties');

		for my $key (keys %$properties) {
			if ($paramRef->{'property_value_'.$key} eq '') {
				delete $properties->{$key};
			} else {
				$properties->{$key} = $paramRef->{'property_value_'.$key};
			}
		}
		if ($paramRef->{'property_name_new'} ne '' && $paramRef->{'property_value_new'} ne '') {
			my $name = $paramRef->{'property_name_new'};
			if (exists $paramRef->{'property_value_new'}) {
				$properties->{$name} = $paramRef->{'property_value_new'};
			}
		}
		$paramRef->{'prefs'}->{'properties'} = $properties;
	} else {
		$paramRef->{'prefs'}->{'properties'} = $prefs->get('properties');
	}
	my $result = $class->SUPER::handler($client, $paramRef);
	if ($paramRef->{'saveSettings'}) {
		Plugins::CustomBrowseMenus::Plugin::getConfigManager()->initWebAdminMethods();
		Plugins::CustomBrowseMenus::Plugin::getContextConfigManager()->initWebAdminMethods();
		if ($prefs->get('override_trackinfo')) {
			Slim::Buttons::Common::addMode('trackinfo', Plugins::CustomBrowseMenus::Plugin::getFunctions(),\&Plugins::CustomBrowseMenus::Plugin::setModeContext);
		} else {
			if (UNIVERSAL::can("Slim::Buttons::TrackInfo", "getFunctions")) {
				Slim::Buttons::Common::addMode('trackinfo', Slim::Buttons::TrackInfo::getFunctions(),\&Slim::Buttons::TrackInfo::setMode);
			} else {
				Slim::Buttons::Common::addMode('trackinfo', undef, \&Slim::Buttons::TrackInfo::setMode);
			}
		}
	}
	return $result;
}

1;
