# ConfigManager::ContextMain
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

package Plugins::CustomBrowseMenus::ConfigManager::ContextMain;

use strict;

use base qw(Slim::Utils::Accessor);

use Slim::Utils::Prefs;
use Plugins::CustomBrowseMenus::ConfigManager::TemplateParser;
use Plugins::CustomBrowseMenus::ConfigManager::ContextContentParser;
use Plugins::CustomBrowseMenus::ConfigManager::ContextTemplateContentParser;
use Plugins::CustomBrowseMenus::ConfigManager::PluginLoader;
use Plugins::CustomBrowseMenus::ConfigManager::DirectoryLoader;
use Plugins::CustomBrowseMenus::ConfigManager::ParameterHandler;
use Plugins::CustomBrowseMenus::ConfigManager::MenuWebAdminMethods;
use FindBin qw($Bin);
use File::Spec::Functions qw(:ALL);
use Slim::Control::Request;

__PACKAGE__->mk_accessor( rw => qw(logHandler pluginPrefs pluginId pluginVersion contentDirectoryHandler templateContentDirectoryHandler templateDirectoryHandler templateDataDirectoryHandler contentPluginHandler templatePluginHandler parameterHandler templateParser contentParser templateContentParser webAdminMethods addSqlErrorCallback templates items) );

my $prefs = preferences('plugin.custombrowsemenus');

sub new {
	my ($class, $parameters) = @_;

	my $self = $class->SUPER::new();

	$self->logHandler($parameters->{'logHandler'});
	$self->pluginId($parameters->{'pluginId'});
	$self->pluginVersion($parameters->{'pluginVersion'});
	$self->addSqlErrorCallback($parameters->{'addSqlErrorCallback'});

	$self->init();
	return $self;
}

sub init {
	my $self = shift;
	my %parserParameters = (
		'pluginId' => $self->pluginId,
		'pluginVersion' => $self->pluginVersion,
		'logHandler' => $self->logHandler,
		'cacheName' => "PluginCache/CustomBrowseMenus",
	);
	$parserParameters{'cachePrefix'} = "PluginCache/CustomBrowseMenus/ContextTemplates";
	$self->templateParser(Plugins::CustomBrowseMenus::ConfigManager::TemplateParser->new(\%parserParameters));
	$parserParameters{'cachePrefix'} = "PluginCache/CustomBrowseMenus/ContextMenus";
	$self->contentParser(Plugins::CustomBrowseMenus::ConfigManager::ContextContentParser->new(\%parserParameters));

	my %parameters = (
		'logHandler' => $self->logHandler,
		'criticalErrorCallback' => $self->addSqlErrorCallback,
		'parameterPrefix' => 'itemparameter'
	);
	$self->parameterHandler(Plugins::CustomBrowseMenus::ConfigManager::ParameterHandler->new(\%parameters));

	my %directoryHandlerParameters = (
		'logHandler' => $self->logHandler,
		'pluginVersion' => $self->pluginVersion,
		'cacheName' => "PluginCache/CustomBrowseMenus",
		'cachePrefix' => "PluginCache/CustomBrowseMenus/Files",
	);
	$directoryHandlerParameters{'extension'} = "cbm.context.xml";
	$directoryHandlerParameters{'parser'} = $self->contentParser;
	$directoryHandlerParameters{'includeExtensionInIdentifier'} = undef;
	$self->contentDirectoryHandler(Plugins::CustomBrowseMenus::ConfigManager::DirectoryLoader->new(\%directoryHandlerParameters));

	$directoryHandlerParameters{'extension'} = "xml";
	$directoryHandlerParameters{'identifierExtension'} = "xml";
	$directoryHandlerParameters{'parser'} = $self->templateParser;
	$directoryHandlerParameters{'includeExtensionInIdentifier'} = 1;
	$self->templateDirectoryHandler(Plugins::CustomBrowseMenus::ConfigManager::DirectoryLoader->new(\%directoryHandlerParameters));

	$directoryHandlerParameters{'extension'} = "template";
	$directoryHandlerParameters{'identifierExtension'} = "xml";
	$directoryHandlerParameters{'parser'} = $self->contentParser;
	$directoryHandlerParameters{'includeExtensionInIdentifier'} = 1;
	$self->templateDataDirectoryHandler(Plugins::CustomBrowseMenus::ConfigManager::DirectoryLoader->new(\%directoryHandlerParameters));

	my %pluginHandlerParameters = (
		'logHandler' => $self->logHandler,
		'pluginId' => $self->pluginId,
		'pluginVersion' => $self->pluginVersion,
	);

	$pluginHandlerParameters{'listMethod'} = "getCustomBrowseMenusContextTemplates";
	$pluginHandlerParameters{'dataMethod'} = "getCustomBrowseMenusContextTemplateData";
	$pluginHandlerParameters{'contentType'} = "template";
	$pluginHandlerParameters{'contentParser'} = $self->templateParser;
	$pluginHandlerParameters{'templateContentParser'} = undef;
	$self->templatePluginHandler(Plugins::CustomBrowseMenus::ConfigManager::PluginLoader->new(\%pluginHandlerParameters));

	$parserParameters{'templatePluginHandler'} = $self->templatePluginHandler;
	$parserParameters{'cachePrefix'} = "PluginCache/CustomBrowseMenus/ContextMenus";
	$self->templateContentParser(Plugins::CustomBrowseMenus::ConfigManager::ContextTemplateContentParser->new(\%parserParameters));

	$directoryHandlerParameters{'extension'} = "cbm.context.values.xml";
	$directoryHandlerParameters{'parser'} = $self->templateContentParser;
	$directoryHandlerParameters{'includeExtensionInIdentifier'} = undef;
	$self->templateContentDirectoryHandler(Plugins::CustomBrowseMenus::ConfigManager::DirectoryLoader->new(\%directoryHandlerParameters));

	$pluginHandlerParameters{'listMethod'} = "getCustomBrowseMenusContextMenus";
	$pluginHandlerParameters{'dataMethod'} = "getCustomBrowseMenusContextMenuData";
	$pluginHandlerParameters{'contentType'} = "menu";
	$pluginHandlerParameters{'contentParser'} = $self->contentParser;
	$pluginHandlerParameters{'templateContentParser'} = $self->templateContentParser;
	$self->contentPluginHandler(Plugins::CustomBrowseMenus::ConfigManager::PluginLoader->new(\%pluginHandlerParameters));

	$self->initWebAdminMethods();
}

sub initWebAdminMethods {
	my $self = shift;

	my %webTemplates = (
		'webEditItems' => 'plugins/CustomBrowseMenus/webadminmethods_edititems.html',
		'webEditItem' => 'plugins/CustomBrowseMenus/webadminmethods_edititem.html',
		'webEditSimpleItem' => 'plugins/CustomBrowseMenus/webadminmethods_editsimpleitem.html',
		'webNewItem' => 'plugins/CustomBrowseMenus/webadminmethods_newitem.html',
		'webNewSimpleItem' => 'plugins/CustomBrowseMenus/webadminmethods_newsimpleitem.html',
		'webNewItemParameters' => 'plugins/CustomBrowseMenus/webadminmethods_newitemparameters.html',
		'webNewItemTypes' => 'plugins/CustomBrowseMenus/webadminmethods_newitemtypes.html',
	);

	my @itemDirectories = ();
	my @templateDirectories = ();
	my $dir = $prefs->get("folder_browsemenus");
	if (defined $dir && -d $dir) {
		push @itemDirectories, $dir
	}
	$dir = $prefs->get("folder_contexttemplates");
	if (defined $dir && -d $dir) {
		push @templateDirectories, $dir
	}

	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	for my $plugindir (@pluginDirs) {
		if ( -d catdir($plugindir, "CustomBrowseMenus", "ContextMenus")) {
			push @itemDirectories, catdir($plugindir, "CustomBrowseMenus", "ContextMenus")
		}
		if ( -d catdir($plugindir, "CustomBrowseMenus", "ContextTemplates")) {
			push @templateDirectories, catdir($plugindir, "CustomBrowseMenus", "ContextTemplates")
		}
	}
	my %webAdminMethodsParameters = (
		'pluginPrefs' => $self->pluginPrefs,
		'pluginId' => $self->pluginId,
		'pluginVersion' => $self->pluginVersion,
		'extension' => 'cbm.context.xml',
		'simpleExtension' => 'cbm.context.values.xml',
		'logHandler' => $self->logHandler,
		'contentPluginHandler' => $self->contentPluginHandler,
		'templatePluginHandler' => $self->templatePluginHandler,
		'contentDirectoryHandler' => $self->contentDirectoryHandler,
		'contentTemplateDirectoryHandler' => $self->templateContentDirectoryHandler,
		'templateDirectoryHandler' => $self->templateDirectoryHandler,
		'templateDataDirectoryHandler' => $self->templateDataDirectoryHandler,
		'parameterHandler' => $self->parameterHandler,
		'contentParser' => $self->contentParser,
		'templateDirectories' => \@templateDirectories,
		'itemDirectories' => \@itemDirectories,
		'customTemplateDirectory' => $prefs->get("folder_contexttemplates"),
		'customItemDirectory' => $prefs->get("folder_browsemenus"),
		'webCallbacks' => $self,
		'webTemplates' => \%webTemplates,
	);
	$self->webAdminMethods(Plugins::CustomBrowseMenus::ConfigManager::MenuWebAdminMethods->new(\%webAdminMethodsParameters));
}
sub readTemplateConfiguration {
	my ($self, $client) = @_;

	my %templates = ();
	my %globalcontext = ();
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	for my $plugindir (@pluginDirs) {
		$self->logHandler->debug("Checking for dir: ".catdir($plugindir, "CustomBrowseMenus", "ContextTemplates")."");
		next unless -d catdir($plugindir, "CustomBrowseMenus", "ContextTemplates");
		$globalcontext{'source'} = 'builtin';
		$self->templateDirectoryHandler()->readFromDir($client,catdir($plugindir, "CustomBrowseMenus", "ContextTemplates"), \%templates, \%globalcontext);
	}

	$globalcontext{'source'} = 'plugin';
	$self->templatePluginHandler()->readFromPlugins($client, \%templates, undef, \%globalcontext);

	my $templateDir = $prefs->get('folder_contexttemplates');
	$self->logHandler->debug("Checking for dir: $templateDir");
	if ($templateDir && -d $templateDir) {
		$globalcontext{'source'} = 'custom';
		$self->templateDirectoryHandler()->readFromDir($client, $templateDir, \%templates, \%globalcontext);
	}
	return \%templates;
}

sub readItemConfiguration {
	my ($self, $client, $onlyWithLibrarySupport, $excludedPlugins, $storeInCache, $forceRefreshTemplates) = @_;

	my $dir = $prefs->get("folder_browsemenus");
	$self->logHandler->debug("Searching for item configuration in: $dir");

	my %localItems = ();

	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');

	my %globalcontext = ();
	if (!defined($self->templates) || $forceRefreshTemplates) {
		$self->templates($self->readTemplateConfiguration());
	}
	$globalcontext{'source'} = 'plugin';
	$globalcontext{'templates'} = $self->templates;
	if ($onlyWithLibrarySupport) {
		$globalcontext{'onlylibrarysupported'} = 1;
	}

	$self->contentPluginHandler->readFromPlugins($client, \%localItems, $excludedPlugins, \%globalcontext);
	for my $plugindir (@pluginDirs) {
		$globalcontext{'source'} = 'builtin';
		$self->logHandler->debug("Checking for dir: ".catdir($plugindir, "CustomBrowseMenus", "ContextMenus")."");
		if ( -d catdir($plugindir, "CustomBrowseMenus", "ContextMenus")) {
			if (!$onlyWithLibrarySupport) {
				$self->contentDirectoryHandler()->readFromDir($client, catdir($plugindir, "CustomBrowseMenus", "ContextMenus"), \%localItems, \%globalcontext);
			}
			$self->templateContentDirectoryHandler()->readFromDir($client, catdir($plugindir, "CustomBrowseMenus", "ContextMenus"), \%localItems, \%globalcontext);
		}
	}
	$self->logHandler->debug("Checking for dir: $dir");
	if (!defined $dir || !-d $dir) {
		$self->logHandler->debug("Skipping custom browse configuration scan - directory is undefined");
	} else {
		$globalcontext{'source'} = 'custom';
		if (!$onlyWithLibrarySupport) {
			$self->contentDirectoryHandler()->readFromDir($client, $dir, \%localItems, \%globalcontext);
		}
		$self->templateContentDirectoryHandler()->readFromDir($client, $dir, \%localItems, \%globalcontext);
	}

	for my $key (keys %localItems) {
		postProcessItem($localItems{$key});
	}

	if ($storeInCache) {
		$self->items(\%localItems);
	}

	my %result = (
		'menus' => \%localItems,
		'templates' => $self->templates
	);
	return \%result;
}

sub postProcessItem {
	my $item = shift;

	if (defined($item->{'menuname'})) {
		$item->{'menuname'} =~ s/\'\'/\'/g;
	}
	if (defined($item->{'menugroup'})) {
		$item->{'menugroup'} =~ s/\'\'/\'/g;
	}
}

sub changedItemConfiguration {
	my ($self, $client, $params) = @_;
	Slim::Control::Request::notifyFromArray(undef, ['custombrowsemenus', 'changedconfiguration']);
}

sub changedTemplateConfiguration {
	my ($self, $client, $params) = @_;
	Slim::Control::Request::notifyFromArray(undef, ['custombrowsemenus', 'changedconfiguration']);
}

sub webEditItems {
	my ($self, $client, $params) = @_;

	Plugins::CustomBrowseMenus::Plugin::prepareManagingContextMenus($client, $params);
	my $items = $self->items;

	my @webitems = ();
	for my $key (keys %$items) {
		my %webitem = ();
		my $item = $items->{$key};
		for my $key (keys %$item) {
			$webitem{$key} = $item->{$key};
		}
		if (defined($webitem{'menuname'}) && defined($webitem{'menugroup'})) {
			$webitem{'menuname'} = $webitem{'menugroup'}.'/'.$webitem{'menuname'};
		}
		push @webitems, \%webitem;
	}
	@webitems = sort { $a->{'menuname'} cmp $b->{'menuname'} } @webitems;
	return $self->webAdminMethods->webEditItems($client, $params, \@webitems);
}

sub webEditItem {
	my ($self, $client, $params) = @_;

	if (!defined($self->items)) {
		my $itemConfiguration = $self->readItemConfiguration($client);
		$self->items($itemConfiguration->{'menus'});
	}
	if (!defined($self->templates)) {
		$self->templates($self->readTemplateConfiguration($client));
	}

	return $self->webAdminMethods->webEditItem($client, $params, $params->{'item'}, $self->items, $self->templates);
}


sub webDeleteItemType {
	my ($self, $client, $params) = @_;
	return $self->webAdminMethods->webDeleteItemType($client, $params, $params->{'itemtemplate'});
}


sub webNewItemTypes {
	my ($self, $client, $params) = @_;
	$self->templates($self->readTemplateConfiguration($client));
	return $self->webAdminMethods->webNewItemTypes($client, $params, $self->templates);
}

sub webNewItemParameters {
	my ($self, $client, $params) = @_;

	if (!defined($self->templates) || !defined($self->templates->{$params->{'itemtemplate'}})) {
		$self->templates($self->readTemplateConfiguration($client));
	}
	return $self->webAdminMethods->webNewItemParameters($client, $params, $params->{'itemtemplate'}, $self->templates);
}

sub webNewItem {
	my ($self, $client, $params) = @_;

	if (!defined($self->templates)) {
		$self->templates($self->readTemplateConfiguration($client));
	}

	return $self->webAdminMethods->webNewItem($client, $params, $params->{'itemtemplate'}, $self->templates);
}

sub webSaveSimpleItem {
	my ($self, $client, $params) = @_;

	if (!defined($self->templates)) {
		$self->templates($self->readTemplateConfiguration($client));
	}
	$params->{'items'} = $self->items;

	return $self->webAdminMethods->webSaveSimpleItem($client, $params, $params->{'itemtemplate'}, $self->templates);
}

sub webRemoveItem {
	my ($self, $client, $params) = @_;

	if (!defined($self->items)) {
		my $itemConfiguration = $self->readItemConfiguration($client);
		$self->items($itemConfiguration->{'menus'});
	}
	return $self->webAdminMethods->webDeleteItem($client, $params, $params->{'item'}, $self->items);
}

sub webSaveNewSimpleItem {
	my ($self, $client, $params) = @_;

	if (!defined($self->templates)) {
		$self->templates($self->readTemplateConfiguration($client));
	}
	$params->{'items'} = $self->items;

	return $self->webAdminMethods->webSaveNewSimpleItem($client, $params, $params->{'itemtemplate'}, $self->templates);
}

sub webSaveNewItem {
	my ($self, $client, $params) = @_;
	$params->{'items'} = $self->items;
	return $self->webAdminMethods->webSaveNewItem($client, $params);
}

sub webSaveItem {
	my ($self, $client, $params) = @_;
	$params->{'items'} = $self->items;
	return $self->webAdminMethods->webSaveItem($client, $params);
}

1;
