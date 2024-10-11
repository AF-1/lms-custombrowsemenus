# ConfigManager::PluginLoader
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

package Plugins::CustomBrowseMenus::ConfigManager::PluginLoader;

use strict;

use base qw(Slim::Utils::Accessor);

use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

__PACKAGE__->mk_accessor( rw => qw(logHandler listMethod dataMethod pluginId pluginVersion contentType templateContentParser contentParser) );

sub new {
	my ($class, $parameters) = @_;

	my $self = $class->SUPER::new();
	$self->logHandler($parameters->{'logHandler'});
	$self->listMethod($parameters->{'listMethod'});
	$self->dataMethod($parameters->{'dataMethod'});
	$self->pluginId($parameters->{'pluginId'});
	$self->pluginVersion($parameters->{'pluginVersion'});
	$self->contentType($parameters->{'contentType'});
	$self->contentParser($parameters->{'contentParser'});
	$self->templateContentParser($parameters->{'templateContentParser'});

	return $self;
}

sub readFromPlugins {
	my ($self, $client, $items, $excludePlugins, $globalcontext) = @_;

	no strict 'refs';
	my @enabledplugins = Slim::Utils::PluginManager->enabledPlugins();

	my %excludePluginsHash = ();
	if ($excludePlugins) {
		my @items = split(/\,/, $excludePlugins);
		for my $item (@items) {
			$excludePluginsHash{$item} = 1;
		}
	}
	if (defined($self->templateContentParser)) {
		$self->templateContentParser->readFromCache();
	}
	if (defined($self->contentParser)) {
		$self->contentParser->readFromCache();
	}
	for my $plugin (@enabledplugins) {
		if ($excludePluginsHash{$plugin}) {
			next;
		}
		if (UNIVERSAL::can("$plugin", $self->listMethod)) {
			$self->logHandler->debug("Calling ".$self->listMethod." for: $plugin");
			my $pluginItems = eval { &{"${plugin}::".$self->listMethod}($client, $self->pluginVersion) };
			if ($@) {
				$self->logHandler->warn("Error calling ".$self->listMethod." from $plugin: $@");
			}
			$self->logHandler->debug("Got ".scalar(@$pluginItems)." items from $plugin");
			for my $item (@$pluginItems) {
				my $itemData = $item->{$self->contentType};
				my $itemId = $item->{'id'};
				$itemData->{'id'} = $item->{'id'};
				if ($plugin =~ /^.*::([^:]+)::([^:]*?)$/) {
					$itemId = lc($1)."_".$item->{'id'};
				}
				my %localcontext = ();
				if (defined($item->{'timestamp'})) {
					$localcontext{'timestamp'} = $item->{'timestamp'};
				}
				if ($item->{'type'} eq 'simple') {
					if (defined($self->templateContentParser)) {
						if (ref($itemData) ne 'HASH') {
							my $encoding = Slim::Utils::Unicode::encodingFromString($itemData);
							if ($encoding ne 'utf8') {
								$itemData = Slim::Utils::Unicode::latin1toUTF8($itemData);
								$itemData = Slim::Utils::Unicode::utf8on($itemData);
								$self->logHandler->debug("Loading $itemId configuration from $plugin and converting from latin1");
							} else {
								$itemData = Slim::Utils::Unicode::utf8decode($itemData, 'utf8');
								$self->logHandler->debug("Loading $itemId configuration from $plugin without conversion with encoding ".$encoding."");
							}
						}
						my $errorMsg = $self->templateContentParser->parse($client, $itemId, $itemData, $items, $globalcontext, \%localcontext);
						if ($errorMsg) {
							$self->logHandler->warn("Unable to open plugin ".$self->contentType." configuration: $plugin(".$item->{'id'}.")\n$errorMsg");
						} elsif (defined($items->{$itemId})) {
							$items->{$itemId}->{'id'} = $itemId;
							$items->{$itemId}->{lc($self->pluginId).'_plugin_'.$self->contentType} = $item;
							$items->{$itemId}->{lc($self->pluginId).'_plugin'} = "${plugin}";
						}
					}
				} else {
					my $errorMsg = undef;
					if (defined($self->contentParser)) {
						if (ref($itemData) ne 'HASH') {
							my $encoding = Slim::Utils::Unicode::encodingFromString($itemData);
							if ($encoding ne 'utf8') {
								$itemData = Slim::Utils::Unicode::latin1toUTF8($itemData);
								$itemData = Slim::Utils::Unicode::utf8on($itemData);
								$self->logHandler->debug("Loading $itemId configuration from $plugin and converting from latin1");
							} else {
								$itemData = Slim::Utils::Unicode::utf8decode($itemData, 'utf8');
								$self->logHandler->debug("Loading $itemId configuration from $plugin without conversion with encoding ".$encoding."");
							}
						}
						$errorMsg = $self->contentParser->parse($client, $itemId, $itemData, $items, $globalcontext, \%localcontext);
					}
					if (defined($errorMsg)) {
						$self->logHandler->warn("Unable to open plugin ".$self->contentType." configuration: $plugin(".$item->{'id'}.")\n$errorMsg");
					} else {
						$items->{$itemId}->{'id'} = $itemId;
						$items->{$itemId}->{lc($self->pluginId).'_plugin_'.$self->contentType} = $item;
						$items->{$itemId}->{lc($self->pluginId).'_plugin'} = "${plugin}";
					}
				}
			}
		}
	}
	if (defined($self->templateContentParser)) {
		$self->templateContentParser->writeToCache();
	}
	if (defined($self->contentParser)) {
		$self->contentParser->writeToCache();
	}

	use strict 'refs';
}

sub readDataFromPlugin {
	my ($self, $client, $itemData, $parameters) = @_;

	if (defined($itemData->{lc($self->pluginId).'_plugin'})) {
		my $content = $self->_getPluginContentData($client, $itemData);
		if (defined($content) && ref($content) ne 'HASH') {
			my $encoding = Slim::Utils::Unicode::encodingFromString($content);
			if ($encoding ne 'utf8') {
				$content = Slim::Utils::Unicode::latin1toUTF8($content);
				$content = Slim::Utils::Unicode::utf8on($content);
				$self->logHandler->debug("Loading ".($itemData->{'id'}." data from ".$itemData->{lc($self->pluginId).'_plugin'})." and converting from latin1");
			} else {
				$content = Slim::Utils::Unicode::utf8decode($content, 'utf8');
				$self->logHandler->debug("Loading ".($itemData->{'id'}." data from ".$itemData->{lc($self->pluginId).'_plugin'})." without conversion with encoding ".$encoding."");
			}
		}
		return $content;
	}
	return undef;
}

sub _getPluginContentData {
	my ($self, $client, $itemData, $parameters) = @_;

	my $plugin = $itemData->{lc($self->pluginId).'_plugin'};
	my $pluginItem = $itemData->{lc($self->pluginId).'_plugin_'.$self->contentType};
	my $itemFileData = undef;
	no strict 'refs';
	if (UNIVERSAL::can("$plugin", $self->dataMethod)) {
		$self->logHandler->debug("Calling: $plugin :: ".$self->dataMethod."");
		$itemFileData = eval { &{"${plugin}::".$self->dataMethod}($client, $pluginItem) };
		if ($@) {
			$self->logHandler->warn("Error retreiving item data from $plugin: $@");
		}
	}
	use strict 'refs';
	return $itemFileData;
}

1;
