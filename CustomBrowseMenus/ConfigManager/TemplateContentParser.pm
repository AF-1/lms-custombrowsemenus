# ConfigManager::TemplateContentParser
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

package Plugins::CustomBrowseMenus::ConfigManager::TemplateContentParser;

use strict;
use base qw(Slim::Utils::Accessor);
use Plugins::CustomBrowseMenus::ConfigManager::ContentParser;
our @ISA = qw(Plugins::CustomBrowseMenus::ConfigManager::ContentParser);

use Slim::Utils::Prefs;
use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use File::Spec::Functions qw(:ALL);
use File::Slurp;
use FindBin qw($Bin);

__PACKAGE__->mk_accessor( rw => qw(templatePluginHandler) );

my $prefs = preferences('plugin.custombrowsemenus');

sub new {
	my ($class, $parameters) = @_;

	$parameters->{'contentType'} = 'menu';
	my $self = $class->SUPER::new($parameters);
	$self->templatePluginHandler($parameters->{'templatePluginHandler'});

	return $self;
}

sub loadTemplate {
	my ($self, $client, $template, $parameters) = @_;

	$self->logHandler->debug("Searching for template: ".$template->{'id'}."");
	my $templateFileData = undef;
	my $doParsing = 1;
	if (defined($template->{lc($self->pluginId).'_plugin_template'})) {
		my $pluginTemplate = $template->{lc($self->pluginId).'_plugin_template'};
		if (defined($pluginTemplate->{'type'}) && $pluginTemplate->{'type'} eq 'final') {
			$doParsing = 0;
		}
		$templateFileData = $self->templatePluginHandler->readDataFromPlugin($client, $template, $parameters);
	} else {
		my $templateFile = $template->{'id'};
		$templateFile =~ s/\.xml$/.template/;
		my $templateDir = $prefs->get("folder_templates");
		my $path = undef;
		if (defined $templateDir && -d $templateDir && -e catfile($templateDir, $templateFile)) {
			$path = catfile($templateDir, $templateFile);
		}
		my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
		for my $plugindir (@pluginDirs) {
			if ( -d catdir($plugindir, "CustomBrowseMenus", "Templates") && -e catfile($plugindir, "CustomBrowseMenus", "Templates", $templateFile)) {
				if (defined($path)) {
					my $prevTimestamp = (stat ($path) )[9];
					my $thisTimestamp = (stat (catfile($plugindir, "CustomBrowseMenus", "Templates", $templateFile)) )[9];
					if ($prevTimestamp <= $thisTimestamp) {
						$path = catfile($plugindir, "CustomBrowseMenus", "Templates", $templateFile);
					}
				} else {
					$path = catfile($plugindir, "CustomBrowseMenus", "Templates", $templateFile);
				}
			}
		}
		if (defined($path)) {
			$self->logHandler->debug("Reading template: $templateFile");
			$templateFileData = eval { read_file($path) };
			if ($@) {
				$self->logHandler->warn("Unable to open file: $path\nBecause of:\n$@");
			} else {
				my $encoding = Slim::Utils::Unicode::encodingFromString($templateFileData);
				if ($encoding ne 'utf8') {
					$templateFileData = Slim::Utils::Unicode::latin1toUTF8($templateFileData);
					$templateFileData = Slim::Utils::Unicode::utf8on($templateFileData);
					$self->logHandler->debug("Loading $templateFile and converting from latin1");
				} else {
					$templateFileData = Slim::Utils::Unicode::utf8decode($templateFileData, 'utf8');
					$self->logHandler->debug("Loading $templateFile without conversion with encoding ".$encoding."");
				}
			}
		}
	}
	if (!defined($templateFileData)) {
		return undef;
	}
	my %result = (
		'data' => \$templateFileData,
		'parse' => $doParsing
	);
	return \%result;
}

sub parse {
	my ($self, $client, $item, $content, $items, $globalcontext, $localcontext) = @_;
	$localcontext->{'simple'} = 1;
	return $self->parseTemplateContent($client, $item, $content, $items, $globalcontext->{'templates'}, $globalcontext, $localcontext);
}


sub checkTemplateParameters {
	my ($self, $template, $parameters, $globalcontext, $localcontext) = @_;

	my $librarySupported = 0;
	for my $key (keys %$parameters) {
		if ($key eq 'library') {
			$librarySupported = 1;
			$localcontext->{'librarysupported'} = 1;
		}
	}
	if ($globalcontext->{'onlylibrarysupported'} && !$librarySupported) {
		return undef;
	}
	return 1;
}

sub checkTemplateValues {
	my ($self, $template, $xml, $globalcontext, $localcontext) = @_;

	my $forceEnabledBrowse = undef;
	if (defined($xml->{'enabledbrowse'})) {
		if (ref($xml->{'enabledbrowse'}) ne 'HASH') {
			$forceEnabledBrowse = $xml->{'enabledbrowse'};
		} else {
			$forceEnabledBrowse = '';
		}
	}
	if (defined($forceEnabledBrowse)) {
		$localcontext->{'forceenabledbrowse'} = $forceEnabledBrowse;
	}
	return 1;
}

*escape = \&URI::Escape::uri_escape_utf8;

1;
