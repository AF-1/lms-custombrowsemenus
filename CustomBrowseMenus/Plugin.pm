# CustomBrowseMenus plugin
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

package Plugins::CustomBrowseMenus::Plugin;

use strict;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Prefs;
use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use File::Spec::Functions qw(:ALL);
use File::Slurp;
use XML::Simple;
use FindBin qw($Bin);
use HTML::Entities;
use Scalar::Util qw(blessed);
use Text::Unidecode;
use Slim::Utils::PluginManager;
use Slim::Control::Jive;
use Time::HiRes;
use File::Basename;
use File::Copy;

use Plugins::CustomBrowseMenus::Settings;
use Plugins::CustomBrowseMenus::EnabledMenus;
use Plugins::CustomBrowseMenus::EnabledContextMenus;
use Plugins::CustomBrowseMenus::ManageMenus;

use Plugins::CustomBrowseMenus::ConfigManager::Main;
use Plugins::CustomBrowseMenus::ConfigManager::ContextMain;

use Plugins::CustomBrowseMenus::MenuHandler::Main;
use Plugins::CustomBrowseMenus::MenuHandler::ParameterHandler;

my $manageMenuHandler = undef;

my $browseMenusFlat;
my $lastChange;
my $contextBrowseMenusFlat;
my $templates;
my $sqlerrors = '';
my %uPNPCache = ();

my ($jiveMenu, $lastScanTime, $PLUGINVERSION, $configManager, $contextConfigManager, $menuHandler, $contextMenuHandler, $parameterHandler, $artistImages) = undef;

my $prefs = preferences('plugin.custombrowsemenus');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category' => 'plugin.custombrowsemenus',
	'defaultLevel' => 'WARN',
	'description' => 'PLUGIN_CUSTOMBROWSEMENUS',
});
my %choiceMapping = ();
my $CTIenabled;

sub getDisplayName {
	my $menuName = $prefs->get('menuname');
	if ($menuName) {
		Slim::Utils::Strings::setString( uc 'PLUGIN_CUSTOMBROWSEMENUS', $menuName );
	}
	return 'PLUGIN_CUSTOMBROWSEMENUS';
}

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);

	my %submenu = (
		'useMode' => 'PLUGIN.CustomBrowseMenus.Browse',
	);
	my $menuName = $prefs->get('menuname');
	Slim::Utils::Strings::setString(uc 'PLUGIN_CUSTOMBROWSEMENUS', $menuName) if $menuName;
	Slim::Buttons::Home::addSubMenu('BROWSE_MUSIC', 'PLUGIN_CUSTOMBROWSEMENUS', \%submenu) unless $prefs->get('toplevelmenuinextras');

	$PLUGINVERSION = Slim::Utils::PluginManager->dataForPlugin($class)->{'version'};

	if (main::WEBUI) {
		Plugins::CustomBrowseMenus::Settings->new($class);
		Plugins::CustomBrowseMenus::EnabledMenus->new($class);
		Plugins::CustomBrowseMenus::EnabledContextMenus->new($class);
		$manageMenuHandler = Plugins::CustomBrowseMenus::ManageMenus->new($class);
	}

	if (UNIVERSAL::can("Slim::Utils::UPnPMediaServer", "registerCallback")) {
		Slim::Utils::UPnPMediaServer::registerCallback( \&uPNPCallback );
	}

	initPrefs();

	registerTitleFormats();

	my %choiceFunctions = %{Slim::Buttons::Input::Choice::getFunctions()};
	$choiceFunctions{'insert'} = sub {Slim::Buttons::Input::Choice::callCallback('onInsert', @_)};
	Slim::Buttons::Common::addMode('PLUGIN.CustomBrowseMenus.Choice', \%choiceFunctions, \&Slim::Buttons::Input::Choice::setMode);
	for my $buttonPressMode (qw{repeat hold hold_release single double}) {
		if (!defined($choiceMapping{'play.' . $buttonPressMode})) {
			$choiceMapping{'play.' . $buttonPressMode} = 'dead';
		}
		if (!defined($choiceMapping{'add.' . $buttonPressMode})) {
			$choiceMapping{'add.' . $buttonPressMode} = 'dead';
		}
		if (!defined($choiceMapping{'search.' . $buttonPressMode})) {
			$choiceMapping{'search.' . $buttonPressMode} = 'passback';
		}
		if (!defined($choiceMapping{'stop.' . $buttonPressMode})) {
			$choiceMapping{'stop.' . $buttonPressMode} = 'passback';
		}
		if (!defined($choiceMapping{'pause.' . $buttonPressMode})) {
			$choiceMapping{'pause.' . $buttonPressMode} = 'passback';
		}
	}
	Slim::Hardware::IR::addModeDefaultMapping('PLUGIN.CustomBrowseMenus.Choice', \%choiceMapping);

	Slim::Buttons::Common::addMode('PLUGIN.CustomBrowseMenus.Browse', getFunctions(), \&setModeBrowse);
	Slim::Buttons::Common::addMode('PLUGIN.CustomBrowseMenus.Context', getFunctions(), \&setModeContext);
	if (UNIVERSAL::can("Slim::Buttons::TrackInfo", "getFunctions")) {
		Slim::Buttons::Common::addMode('PLUGIN.CustomBrowseMenus.trackinfo', Slim::Buttons::TrackInfo::getFunctions(), \&Slim::Buttons::TrackInfo::setMode);
	} else {
		Slim::Buttons::Common::addMode('PLUGIN.CustomBrowseMenus.trackinfo', undef, \&Slim::Buttons::TrackInfo::setMode);
	}

	if ($prefs->get('override_trackinfo')) {
		Slim::Buttons::Common::addMode('trackinfo', getFunctions(), \&setModeContext);
	}

	addPlayerMenus();

	$lastScanTime = time();
	Slim::Control::Request::subscribe(\&Plugins::CustomBrowseMenus::Plugin::rescanDone,[['rescan'],['done']]);
	Slim::Control::Request::addDispatch(['custombrowsemenus','browse'], [1, 1, 1, \&cliHandler]);
	Slim::Control::Request::addDispatch(['custombrowsemenus','browsecontext'], [1, 1, 1, \&cliHandler]);
	Slim::Control::Request::addDispatch(['custombrowsemenus','play'], [1, 0, 1, \&cliHandler]);
	Slim::Control::Request::addDispatch(['custombrowsemenus','playcontext'], [1, 0, 1, \&cliHandler]);
	Slim::Control::Request::addDispatch(['custombrowsemenus','add'], [1, 0, 1, \&cliHandler]);
	Slim::Control::Request::addDispatch(['custombrowsemenus','addcontext'], [1, 0, 1, \&cliHandler]);
	Slim::Control::Request::addDispatch(['custombrowsemenus','insert'], [1, 0, 1, \&cliHandler]);
	Slim::Control::Request::addDispatch(['custombrowsemenus','insertcontext'], [1, 0, 1, \&cliHandler]);
	Slim::Control::Request::addDispatch(['custombrowsemenus','browsejive'], [1, 1, 1, \&cliJiveHandler]);
	Slim::Control::Request::addDispatch(['custombrowsemenus','browsejivecontext'], [1, 1, 1, \&cliJiveHandler]);
	Slim::Control::Request::addDispatch(['custombrowsemenus','changedconfiguration'],[0, 0, 0, undef]);
}

sub initPrefs {
	$prefs->init({
		cbmparentfolderpath => $serverPrefs->get('playlistdir'),
		menuname => string('PLUGIN_CUSTOMBROWSEMENUS'),
		override_trackinfo => 1,
		header_value_separator => ', ',
		replaceplayermenus => 1,
		replacewebmenus => 1,
	});

	createCBMfolder();

	$prefs->setValidate(sub {
		return if (!$_[1] || !(-d $_[1]) || (main::ISWINDOWS && !(-d Win32::GetANSIPathName($_[1]))) || !(-d Slim::Utils::Unicode::encode_locale($_[1])));
		my $CBMfolderPath = catdir($_[1], 'CustomBrowseMenus');
		eval {
			mkdir($CBMfolderPath, 0755) unless (-d $CBMfolderPath);
			chdir($CBMfolderPath);
		} or do {
			$log->error("Could not create or access CustomBrowseMenus folder in parent folder '$_[1]'!");
			return;
		};

		my %subfolders = ('folder_browsemenus' => 'User_Created_BrowseMenus', 'folder_templates' => 'Custom_Templates_BrowseMenus', 'folder_contexttemplates' => 'Custom_Templates_ContextMenus', 'folder_customicons' => 'Custom_Icons', 'folder_imagecache' => 'ImageCache');
		eval {
			foreach my $subFolderPrefName (keys %subfolders) {
				my $subfolder = catdir($CBMfolderPath, $subfolders{$subFolderPrefName});
				mkdir($subfolder, 0755) unless (-d $subfolder);
				chdir($subfolder);
				$prefs->set("$subFolderPrefName", $subfolder);
			}
		};
		if ($@) {
			$log->error("Could not create or access subfolders in CustomBrowseMenus folder!");
			return;
		};
		return 1;
	}, 'cbmparentfolderpath');

	$prefs->setValidate('dir', 'folder_imagecache');

	my $prefVal = $prefs->get('properties');
	if (!$prefVal) {
		main::DEBUGLOG && $log->is_debug && $log->debug("Setting default values for plugin_custombrowsemenus_properties");
		my %properties = ();
		$properties{'libraryDir'} = $serverPrefs->get('audiodir');
		$properties{'libraryAudioDirUrl'} = Slim::Utils::Misc::fileURLFromPath($serverPrefs->get('audiodir'));
		$prefs->set('properties', \%properties);
	}
	$prefs->setValidate('hash','properties');

	%choiceMapping = (
		'arrow_left' => 'exit_left',
		'arrow_right' => 'exit_right',
		'knob_push' => 'exit_right',
		'play' => 'dead',
		'play.single' => 'play_0',
		'add' => 'dead',
		'add.single' => 'add_0',
		'add.hold' => 'insert_0',
		'search' => 'passback',
		'stop' => 'passback',
		'pause' => 'passback',
		'0.hold' => 'saveRating_0',
		'1.hold' => 'saveRating_1',
		'2.hold' => 'saveRating_2',
		'3.hold' => 'saveRating_3',
		'4.hold' => 'saveRating_4',
		'5.hold' => 'saveRating_5',
		'6.hold' => 'saveRating_6',
		'7.hold' => 'saveRating_7',
		'8.hold' => 'saveRating_8',
		'9.hold' => 'saveRating_9',
		'0.single' => 'numberScroll_0',
		'1.single' => 'numberScroll_1',
		'2.single' => 'numberScroll_2',
		'3.single' => 'numberScroll_3',
		'4.single' => 'numberScroll_4',
		'5.single' => 'numberScroll_5',
		'6.single' => 'numberScroll_6',
		'7.single' => 'numberScroll_7',
		'8.single' => 'numberScroll_8',
		'9.single' => 'numberScroll_9',
		'0' => 'dead',
		'1' => 'dead',
		'2' => 'dead',
		'3' => 'dead',
		'4' => 'dead',
		'5' => 'dead',
		'6' => 'dead',
		'7' => 'dead',
		'8' => 'dead',
		'9' => 'dead'
	);
}

sub registerTitleFormats {
	Slim::Music::TitleFormatter::addFormat("CUSTOMBROWSEMENUS_ARTIST",
		sub {
			main::DEBUGLOG && $log->is_debug && $log->debug("Retreiving title format: CUSTOMBROWSEMENUS_ARTIST");
			my $track = shift;
			if (ref($track) eq 'HASH' || ref($track) ne 'Slim::Schema::Track') {
				return undef;
			}
			my $result = '';
			my @output = ();
			for my $contributorTrack ($track->contributorTracks) {
				if ($contributorTrack->role == 1 || $contributorTrack->role == 6) {
					my $name = $contributorTrack->contributor->name;
					next if $name eq Slim::Utils::Strings::string('NO_ARTIST');
					push @output, $name
				}
			}
			main::DEBUGLOG && $log->is_debug && $log->debug("Returning title format: CUSTOMBROWSEMENUS_ARTIST");
			return (scalar @output ? join(' & ',@output) : '');
		});
	Slim::Music::TitleFormatter::addFormat("CUSTOMBROWSEMENUS_BAND",
		sub {
			main::DEBUGLOG && $log->is_debug && $log->debug("Retreiving title format: CUSTOMBROWSEMENUS_BAND");
			my $track = shift;
			if (ref($track) eq 'HASH' || ref($track) ne 'Slim::Schema::Track') {
				return undef;
			}
			my $result = '';
			my @output = ();
			for my $contributorTrack ($track->contributorTracks) {
				if ($contributorTrack->role == 4) {
					my $name = $contributorTrack->contributor->name;
					next if $name eq Slim::Utils::Strings::string('NO_ARTIST');
					push @output, $name
				}
			}
			main::DEBUGLOG && $log->is_debug && $log->debug("Returning title format: CUSTOMBROWSEMENUS_BAND");
			return (scalar @output ? join(' & ',@output) : '');
		});
	Slim::Music::TitleFormatter::addFormat("CUSTOMBROWSEMENUS_COMPOSER",
		sub {
			main::DEBUGLOG && $log->is_debug && $log->debug("Retreiving title format: CUSTOMBROWSEMENUS_COMPOSER");
			my $track = shift;
			if (ref($track) eq 'HASH' || ref($track) ne 'Slim::Schema::Track') {
				return undef;
			}
			my $result = '';
			my @output = ();
			for my $contributorTrack ($track->contributorTracks) {
				if ($contributorTrack->role == 2) {
					my $name = $contributorTrack->contributor->name;
					next if $name eq Slim::Utils::Strings::string('NO_ARTIST');
					push @output, $name
				}
			}
			main::DEBUGLOG && $log->is_debug && $log->debug("Returning title format: CUSTOMBROWSEMENUS_COMPOSER");
			return (scalar @output ? join(' & ',@output) : '');
		});
	Slim::Music::TitleFormatter::addFormat("CUSTOMBROWSEMENUS_CONDUCTOR",
		sub {
			main::DEBUGLOG && $log->is_debug && $log->debug("Retreiving title format: CUSTOMBROWSEMENUS_CONDUCTOR");
			my $track = shift;
			if (ref($track) eq 'HASH' || ref($track) ne 'Slim::Schema::Track') {
				return undef;
			}
			my $result = '';
			my @output = ();
			for my $contributorTrack ($track->contributorTracks) {
				if ($contributorTrack->role == 3) {
					my $name = $contributorTrack->contributor->name;
					next if $name eq Slim::Utils::Strings::string('NO_ARTIST');
					push @output, $name
				}
			}
			main::DEBUGLOG && $log->is_debug && $log->debug("Returning title format: CUSTOMBROWSEMENUS_CONDUCTOR");
			return (scalar @output ? join(' & ',@output) : '');
		});
}

sub postinitPlugin {
	my $class = shift;
	eval {
		$artistImages = Slim::Utils::PluginManager->isEnabled('Plugins::MusicArtistInfo::Plugin');
		getConfigManager();
		getMenuHandler();
		readBrowseConfiguration();
		readContextBrowseConfiguration();
		registerJiveMenu($class);
	};
	if ($@) {
		$log->error("Failed to load Custom Browse:\n$@");
	}
	$CTIenabled = Slim::Utils::PluginManager->isEnabled('Plugins::CustomTagImporter::Plugin');
	if ($CTIenabled) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Plugin "Custom Tag Importer" is enabled');
		Slim::Control::Request::subscribe(\&Plugins::CustomBrowseMenus::Plugin::CTIRescanDone,[['customtagimporter'],['changedstatus']]);
	}
}


# Returns the display text for the currently selected item in the menu
sub getDisplayText {
	my ($client, $item) = @_;

	my $id = undef;
	my $name = '';
	if ($item) {
		$name = getMenuHandler()->getItemText($client, $item);
	}
	return $name;
}

# Returns the overlay to be display next to items in the menu
sub getOverlay {
	my ($client, $item) = @_;

	if ($item) {
		return getMenuHandler()->getItemOverlay($client, $item);
	} else {
		return [undef, undef];
	}
}

sub setMode {
	my ($class, $client, $method) = @_;
	setModeBrowse($client, $method);
}

sub setModeBrowse {
	my ($client, $method) = @_;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	readBrowseConfiguration($client);
	my $params = getMenuHandler()->getMenu($client, undef);

	if (defined($params)) {
		if (defined($params->{'useMode'})) {
			Slim::Buttons::Common::pushModeLeft($client, $params->{'useMode'}, $params->{'parameters'});
		} else {
			Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.CustomBrowseMenus.Choice', $params);
		}
	} else {
		$client->bumpRight();
	}
}

sub setModeContext {
	my ($client, $method) = @_;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}
	my $track = $client->modeParam('track');
	my %contextHash = ();
	if (defined($track) && !blessed($track)) {
		$track = Slim::Schema->objectForUrl({'url' => $track});
	}
	if (!defined($track)) {
		$contextHash{'itemtype'} = $client->modeParam('itemtype');
		$contextHash{'itemname'} = $client->modeParam('itemname');
		$contextHash{'itemid'} = $client->modeParam('itemid');
	} else {
		$contextHash{'itemtype'} = 'track';
		$contextHash{'itemname'} = Slim::Music::Info::standardTitle(undef, $track);
		$contextHash{'itemid'} = $track->id;
	}
	if ($client->modeParam('library')) {
		$contextHash{'library'} = $client->modeParam('library');
		$contextHash{'itemtype'} = 'library'.$contextHash{'itemtype'};
	}

	my $menus = getContextMenuHandler()->getMenuItems($client, undef, \%contextHash, 'player');
	my $currentMenu = undef;
	for my $menu (@$menus) {
		if ($menu->{'id'} eq 'group_'.$contextHash{'itemtype'}) {
			$currentMenu = $menu;
		}
	}
	my $params = undef;
	if (defined($currentMenu)) {
		$params = getContextMenuHandler()->getMenu($client, $currentMenu, \%contextHash);
	}
	if (defined($params)) {
		if (defined($params->{'useMode'})) {
			Slim::Buttons::Common::pushModeLeft($client, $params->{'useMode'}, $params->{'parameters'});
		} else {
			Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.CustomBrowseMenus.Choice', $params);
		}
	} else {
		$client->bumpRight();
	}
}

sub uPNPCallback {
	my ($device, $event) = @_;

	if ($event eq 'add') {
		main::DEBUGLOG && $log->is_debug && $log->debug("Adding uPNP ".$device->getfriendlyname."");
		$uPNPCache{$device->getudn} = $device;
	} else {
		main::DEBUGLOG && $log->is_debug && $log->debug("Removing uPNP ".$device->getfriendlyname."");
		$uPNPCache{$device->getudn} = undef;
	}
}

sub getAvailableTitleFormats {
	my @result = ();
	my $titleFormats = $serverPrefs->get('titleFormat');

	foreach my $format ( @$titleFormats ) {
		my %item = (
			'id' => $format,
			'name' => $format,
			'value' => $format
		);
		push @result, \%item;
	}
	return \@result;
}

sub getAvailableuPNPDevices {
	my @result = ();
	for my $key (keys %uPNPCache) {
		my $device = $uPNPCache{$key};
		my %item = (
			'id' => $device->getudn,
			'name' => $device->getfriendlyname,
			'value' => $device->getudn
		);
		push @result, \%item;
	}
	return \@result;
}

sub isuPNPDeviceAvailable {
	my ($client, $params) = @_;
	if (defined($params->{'device'})) {
		if (defined($uPNPCache{$params->{'device'}})) {
			return 1;
		}
	}
	return 0;
}

sub playLink {
	my ($self, $client, $keywords, $context) = @_;
	my @result = ();

	my $objectId = undef;
	if (defined($keywords->{'trackid'})) {
		$objectId = 'track.id='.$keywords->{'trackid'};
	} elsif (defined($keywords->{'albumid'})) {
		$objectId = 'album.id='.$keywords->{'albumid'};
	} elsif (defined($keywords->{'contributorid'})) {
		$objectId = 'contributor.id='.$keywords->{'contributorid'};
	} elsif (defined($keywords->{'genreid'})) {
		$objectId = 'genre.id='.$keywords->{'genreid'};
	} elsif (defined($keywords->{'playlistid'})) {
		$objectId = 'playlist.id='.$keywords->{'playlistid'};
	} elsif (defined($keywords->{'yearid'})) {
		$objectId = 'year.id='.$keywords->{'yearid'};
	}
	if (defined($objectId)) {
		$objectId = getParameterHandler()->replaceParameters($client, $objectId, $keywords, $context);

		my %item1 = (
			'id' => 1,
			'name' => string('PLAY').":status_header.html?command=playlist&subcommand=loadtracks&$objectId"
		);
		push @result, \%item1;
		my %item2 = (
			'id' => 2,
			'name' => string('ADD').":status_header.html?command=playlist&subcommand=addtracks&$objectId"
		);
		push @result, \%item2;
		my %item3 = (
			'id' => 3,
			'name' => string('NEXT').":status_header.html?command=playlist&subcommand=inserttracks&$objectId"
		);
		push @result, \%item3;
	}
	return \@result;
}

sub albumImages {
	my ($self, $client, $keywords, $context) = @_;
	my @result = ();

	my %excludedImages = ();
	if (defined($keywords->{'excludedimages'})) {
		for my $image (split(/\,/, $keywords->{'excludedimages'})) {
			$excludedImages{$image} = $image;
		}
	}
	my $albumId = $keywords->{'albumid'};
	$albumId = getParameterHandler()->replaceParameters($client, $albumId, $keywords, $context);
	my $album = Slim::Schema->resultset('Album')->find($albumId);
	my @tracks = $album->tracks;

	my %dirs = ();
	for my $track (@tracks) {
		my $path = Slim::Utils::Misc::pathFromFileURL($track->url);
		if ($path) {
			$path =~ s/^(.*)[\/\\](.*?)$/$1/;
			if (!$dirs{$path}) {
				$dirs{$path} = $path;
			}
		}
	}
	for my $dir (keys %dirs) {
		my @dircontents = Slim::Utils::Misc::readDirectory($dir, "jpg|gif|png");
		for my $item (@dircontents) {
			next if -d catdir($dir, $item);
			next unless lc($item) =~ /\.(jpg|gif|png)$/;
			next if defined($excludedImages{$item});
			my $extension = $1;
			if (defined($extension)) {
				my %item = (
					'id' => $item,
					'name' => "plugins/CustomBrowseMenus/custombrowsemenus_albumimage.$extension?album=".$album->id."&file=".$item
				);
				push @result, \%item;
			}
		}
	}

	return \@result;
}

sub albumFiles {
	my ($self, $client, $keywords, $context) = @_;
	my @result = ();

	my $albumId = $keywords->{'albumid'};
	$albumId = getParameterHandler()->replaceParameters($client, $albumId, $keywords, $context);
	my $album = Slim::Schema->resultset('Album')->find($albumId);
	my @tracks = $album->tracks;

	my %dirs = ();
	for my $track (@tracks) {
		my $path = Slim::Utils::Misc::pathFromFileURL($track->url);
		if ($path) {
			$path =~ s/^(.*)[\/\\](.*?)$/$1/;
			if (!$dirs{$path}) {
				$dirs{$path} = $path;
			}
		}
	}
	for my $dir (keys %dirs) {
		my @dircontents = Slim::Utils::Misc::readDirectory($dir, "txt|pdf|htm");
		for my $item (@dircontents) {
			next if -d catdir($dir, $item);
			next unless lc($item) =~ /\.(txt|pdf|htm)$/;
			my $extension = $1;
			if (defined($extension)) {
				my %item = (
					'id' => $item,
					'name' => "$item: plugins/CustomBrowseMenus/custombrowsemenus_albumfile.$extension?album=".$album->id."&file=".$item
				);
				push @result, \%item;
			}
		}
	}

	return \@result;
}

sub imageCacheFiles {
	my ($self, $client, $keywords, $context) = @_;
	my @result = ();

	my $type = $keywords->{'type'};
	if (defined($type) && $type ne '') {
		$type = getParameterHandler()->replaceParameters($client, $type, $keywords, $context);
	}
	my $section = $keywords->{'section'};
	if (defined($section) && $section ne '') {
		$section = getParameterHandler()->replaceParameters($client, $section, $keywords, $context);
		# We don't want to allow .. for security reason
		if ($section =~ /\.\./) {
			$section = undef;
		}
	}
	my $name = undef;

	my $contextParameter = '';
	if ($type eq 'artist') {
		my $artistId = $keywords->{'artist'};
		$artistId = getParameterHandler()->replaceParameters($client, $artistId, $keywords, $context);
		$contextParameter = "&artist=$artistId";
		my $artist = Slim::Schema->resultset('Contributor')->find($artistId);
		if (defined($artist)) {
			$name = $artist->name;
			$context->{'itemname'} = $name;
		}
	} elsif ($type eq 'album') {
		my $albumId = $keywords->{'album'};
		$albumId = getParameterHandler()->replaceParameters($client, $albumId, $keywords, $context);
		$contextParameter = "&album=$albumId";
		my $album = Slim::Schema->resultset('Album')->find($albumId);
		if (defined($album)) {
			$name = $album->title;
			$context->{'itemname'} = $name;
		}
	} elsif ($type eq 'year') {
		my $yearId = $keywords->{'year'};
		$yearId = getParameterHandler()->replaceParameters($client, $yearId, $keywords, $context);
		$contextParameter = "&year=$yearId";
		if (defined($yearId)) {
			if (!$yearId) {
				$yearId = string('UNK');
			}
			$name = $yearId;
			$context->{'itemname'} = $name;
		}
	} elsif ($type eq 'playlist') {
		my $playlistId = $keywords->{'playlist'};
		$playlistId = getParameterHandler()->replaceParameters($client, $playlistId, $keywords, $context);
		$contextParameter = "&playlist=$playlistId";
		my $playlist = Slim::Schema->resultset('Playlist')->find($playlistId);
		if (defined($playlist)) {
			$name = $playlist->title;
			$context->{'itemname'} = $name;
		}
	} elsif ($type eq 'genre') {
		my $genreId = $keywords->{'genre'};
		$genreId = getParameterHandler()->replaceParameters($client, $genreId, $keywords, $context);
		$contextParameter = "&genre=$genreId";
		my $genre = Slim::Schema->resultset('Genre')->find($genreId);
		if (defined($genre)) {
			$name = $genre->name;
			$context->{'itemname'} = $name;
		}
	} elsif ($type eq 'custom') {
		my $name = $keywords->{'custom'};
		$name = getParameterHandler()->replaceParameters($client, $name, $keywords, $context);
		$contextParameter = "&custom=$name";
		# We don't want to allow .. for security reason
		if ($name =~ /\.\./) {
			$name = undef;
		} else {
			$context->{'itemname'} = $name;
		}
	}

	my $linkurl = $keywords->{'linkurl'};
	if (defined($linkurl) && $linkurl ne '') {
		$linkurl = getParameterHandler()->replaceParameters($client, $linkurl, $keywords, $context);
	}
	my $linkurlascii = $keywords->{'linkurlascii'};
	if ($linkurlascii && defined($linkurl) && $linkurl ne '') {
		$linkurl = unidecode($linkurl);
	}

	my $dir = $prefs->get('folder_imagecache');

	if (defined($dir) && defined($name)) {
		my $extension = undef;
		my $file = $name;
		$name =~ s/[:\"]/ /g;
		if (defined($section) && $section ne '') {
			$file = catfile($section, $name);
		}
		if (-f catfile($dir, $file.".png")) {
			$extension = ".png";
		} elsif (-f catfile($dir, $file.".jpg")) {
			$extension = ".jpg";
		} elsif (-f catfile($dir, $file.".gif")) {
			$extension = ".gif";
		}
		if (defined($extension)) {
			my %item = (
				'id' => $name,
				'name' => ($linkurl?$linkurl.": ":"")."plugins/CustomBrowseMenus/custombrowsemenus_imagecachefile$extension?type=$type".(defined($section)?"&section=$section":"")."$contextParameter"
			);
			push @result, \%item;
		}
	}
	return \@result;
}

sub rescanDone {
	$lastScanTime = Slim::Music::Import->lastScanTime;
}

sub CTIisScanning {
	my $client = shift;

	if ($CTIenabled & $client) {
		my $isScanning = preferences('plugin.customtagimporter')->client($client)->get('scanningInProgress');
		return 1 if $isScanning;
	}
	return 0;
}

sub CTIRescanDone {
	my $request = shift;
	my $currentTime = time();
	if ($currentTime > $lastScanTime) {
		$lastScanTime = $currentTime;
	}
}

sub contextMenuBrowseBy {
	my $params = shift;
	my $client = $params->{'client'};
	my $item = $params->{'execargs'}->{'item'};

	my %p = ();
	if ($item && ref($item) eq 'Slim::Schema::Contributor') {
		%p = (
			'itemtype' => 'artist',
			'itemname' => $item->name,
			'itemid' => $item->id
		);
	} elsif ($item && ref($item) eq 'Slim::Schema::Album') {
		%p = (
			'itemtype' => 'album',
			'itemname' => $item->title,
			'itemid' => $item->id
		);
	} elsif ($item && ref($item) eq 'Slim::Schema::Track') {
		%p = (
			'itemtype' => 'track',
			'itemname' => Slim::Music::Info::standardTitle(undef, $item),
			'itemid' => $item->id
		);
	} elsif ($item && ref($item) eq 'Slim::Schema::Playlist') {
		%p = (
			'itemtype' => 'playlist',
			'itemname' => $item->title,
			'itemid' => $item->id
		);
	} elsif ($item && ref($item) eq 'Slim::Schema::Genre') {
		%p = (
			'itemtype' => 'genre',
			'itemname' => $item->name,
			'itemid' => $item->id
		);
	} elsif ($item && ref($item) eq 'Slim::Schema::Year') {
		%p = (
			'itemtype' => 'year',
			'itemname' => ($item->id?$item->id:$client->string('UNK')),
			'itemid' => $item->id
		);
	}

	Slim::Buttons::Common::pushModeLeft($client, 'PLUGIN.CustomBrowseMenus.Context', \%p);
	$client->update();
}

sub weight {
	return 80;
}

sub registerJiveMenu {
	my ($class, $client) = @_;

	# menuIcon is only used for iPeng at the moment
	my @menuItems = (
		{
			text => Slim::Utils::Strings::string(getDisplayName()),
			weight => 80,
			id => 'custombrowsemenus',
			menuIcon => 'iPeng/plugins/CustomBrowseMenus/html/images/custombrowsemenus.png',
			window => { titleStyle => 'mymusic', 'icon-id' => $class->_pluginDataFor('icon')},
			actions => {
				go => {
					cmd => ['custombrowsemenus', 'browsejive'],
				},
			},
		},
	);
	if ($prefs->get('toplevelmenuinextras')) {
		Slim::Control::Jive::registerPluginMenu(\@menuItems, 'extras');
	} else {
		Slim::Control::Jive::registerPluginMenu(\@menuItems, 'myMusic');
	}
}

sub callCallbackWithArg {
	my ($callbackName, $client, $funct, $functarg) = @_;

	my $valueRef = $client->modeParam('valueRef');
	my $callback = Slim::Buttons::Input::Choice::getParam($client, $callbackName);
	if (ref($callback) eq 'CODE') {
		my @args = ($client, $valueRef ? ($$valueRef) : undef, $functarg);
		eval { $callback->(@args) };
		if ($@) {
			logError("Couldn't run callback: [$callbackName] : $@");
		} elsif (Slim::Buttons::Input::Choice::getParam($client, 'pref')) {
			$client->update;
		}
	} else {
		Slim::Buttons::Input::Choice::passback($client, $funct, $functarg);
	}
}

sub title {
	return 'PLUGIN_CUSTOMBROWSEMENUS_CONTEXTMIXER';
}

sub getParameterHandler {
	if (!defined($parameterHandler)) {
		my %parameters = (
			'logHandler' => $log,
			'pluginId' => 'CustomBrowseMenus',
			'pluginVersion' => $PLUGINVERSION
		);
		$parameterHandler = Plugins::CustomBrowseMenus::MenuHandler::ParameterHandler->new(\%parameters);
	}
	return $parameterHandler;
}

sub getMenuHandler {
	if (!defined($menuHandler)) {
		my %parameters = (
			'logHandler' => $log,
			'pluginId' => 'CustomBrowseMenus',
			'pluginVersion' => $PLUGINVERSION,
			'menuTitle' => string('PLUGIN_CUSTOMBROWSEMENUS'),
			'menuMode' => 'PLUGIN.CustomBrowseMenus.Choice',
			'displayTextCallback' => \&getDisplayText,
			'overlayCallback' => \&getOverlay,
			'requestSource' => 'PLUGIN_CUSTOMBROWSEMENUS',
			'addSqlErrorCallback' => \&addSQLError,
		);
		$menuHandler = Plugins::CustomBrowseMenus::MenuHandler::Main->new(\%parameters);
	}
	return $menuHandler;
}

sub getContextMenuHandler {
	if (!defined($contextMenuHandler)) {
		my %parameters = (
			'logHandler' => $log,
			'pluginId' => 'CustomBrowseMenus',
			'pluginVersion' => $PLUGINVERSION,
			'menuTitle' => string('PLUGIN_CUSTOMBROWSEMENUS_CONTEXTMENU'),
			'menuMode' => 'PLUGIN.CustomBrowseMenus.Choice',
			'displayTextCallback' => \&getDisplayText,
			'overlayCallback' => \&getOverlay,
			'requestSource' => 'PLUGIN_CUSTOMBROWSEMENUS',
			'addSqlErrorCallback' => \&addSQLError,
		);
		$contextMenuHandler = Plugins::CustomBrowseMenus::MenuHandler::Main->new(\%parameters);
	}
	return $contextMenuHandler;
}

sub getConfigManager {
	if (!defined($configManager)) {
		my %parameters = (
			'logHandler' => $log,
			'pluginId' => 'CustomBrowseMenus',
			'pluginVersion' => $PLUGINVERSION,
			'addSqlErrorCallback' => \&addSQLError,
		);
		$configManager = Plugins::CustomBrowseMenus::ConfigManager::Main->new(\%parameters);
	}
	return $configManager;
}

sub getContextConfigManager {
	if (!defined($contextConfigManager)) {
		my %parameters = (
			'logHandler' => $log,
			'pluginId' => 'CustomBrowseMenus',
			'pluginVersion' => $PLUGINVERSION,
			'addSqlErrorCallback' => \&addSQLError,
		);
		$contextConfigManager = Plugins::CustomBrowseMenus::ConfigManager::ContextMain->new(\%parameters);
	}
	return $contextConfigManager;
}

sub addPlayerMenus {
	my $client = shift;
	my $menus = getMenuHandler()->getMenuItems($client, undef, undef, 'web');
	for my $menu (@{$menus}) {
		my $name = getMenuHandler()->getItemText($client, $menu);
		my $key = $name;

		if ($menu->{'enabledbrowse'} || ($name ne $key && $prefs->get('replaceplayermenus'))) {
			my %submenubrowse = (
				'useMode' => 'PLUGIN.CustomBrowseMenus.Browse',
				'selectedMenu' => $menu->{'id'},
				'mainBrowseMenu' => 1
			);
			my %submenuhome = (
				'useMode' => 'PLUGIN.CustomBrowseMenus.Browse',
				'selectedMenu' => $menu->{'id'},
				'mainBrowseMenu' => 1
			);
			Slim::Buttons::Home::addSubMenu('BROWSE_MUSIC', $key, \%submenubrowse);
			Slim::Buttons::Home::addMenuOption($key, \%submenuhome);
		} else {
			Slim::Buttons::Home::delSubMenu('BROWSE_MUSIC', $key);
			Slim::Buttons::Home::delMenuOption($key);
		}
	}
}

sub addJivePlayerMenus {
	my $client = shift;
	my $menus = getMenuHandler()->getMenuItems($client, undef, undef, 'jive');
	for my $menu (@$menus) {
		my $name = getMenuHandler()->getItemText($client, $menu);
		my $key = $name;
		if ($menu->{'enabledbrowse'} || ($name ne $key && ($prefs->get('replacecontrollermenus')))) {
			my %itemParams = ();
			if (defined($menu->{'contextid'})) {
				$itemParams{'hierarchy'} = $menu->{'contextid'};
			} else {
				$itemParams{'hierarchy'} = $menu->{'id'};
			}

			my $itemtype = undef;
			if (defined($menu->{'menu'})) {
				my $menuRef = $menu->{'menu'};
				my @submenus = ();
				if (ref($menuRef) eq 'ARRAY') {
					@submenus = @$menuRef;
				} else {
					push @submenus, $menuRef;
				}
				my $ignore = 0;
				foreach my $nextmenu (@submenus) {
					if (defined($nextmenu->{'itemtype'})) {
						if (!defined($itemtype)) {
							$itemtype = $nextmenu->{'itemtype'};
						} elsif ($itemtype ne $nextmenu->{'itemtype'}) {
							$itemtype = "NOTUSED";
						}
					}
					if (defined($nextmenu->{'menutype'}) && $nextmenu->{'menutype'} eq 'mode') {
						$ignore = 1;
						last;
					}
				}
				if ($ignore) {
					next;
				}
			}

			my %menuStyle = ();
			$menuStyle{titleStyle} = 'mymusic';
			if (defined($itemtype) && $itemtype eq 'album') {
				$menuStyle{'menuStyle'} = 'album';
			}
			$menuStyle{'icon-id'} = getIcon($name, 'EN');
			my @menuItems = (
				{
					text => $name,
					weight => defined($menu->{'menuorder'})?$menu->{'menuorder'}:80,
					id => $menu->{'id'},
					window => \%menuStyle,
					actions => {
						go => {
							cmd => ['custombrowsemenus', 'browsejive'],
							params => \%itemParams,
							itemsParams => 'params',
						},
					},
				},
			);
			# Provide icon for iPeng
			if ($name ne $key) {
				@menuItems[0]->{'menuIconID'} = $key;
			} else {
				@menuItems[0]->{'menuIcon'} = getIcon($name, 'iPeng', 1);
			}
			# Cacheable indicator
			if (defined($menu->{'cacheable'})) {
				@menuItems[0]->{'cacheable'} = 'true';
			}
			if ($menu->{'id'} ne $key && $prefs->get('replacecontrollermenus')) {
				Slim::Control::Jive::deleteMenuItem($key, $client);
			}
			Slim::Control::Jive::registerPluginMenu(\@menuItems, 'myMusic');
		} else {
			Slim::Control::Jive::deleteMenuItem($menu->{'id'});
		}
	}
}

sub getFunctions {
	# Functions to allow mapping of mixes to keypresses
	return {
		'up' => sub {
			my $client = shift;
			$client->bumpUp();
		},
		'down' => sub {
			my $client = shift;
			$client->bumpDown();
		},
		'left' => sub {
			my $client = shift;
			Slim::Buttons::Common::popModeRight($client);
		},
		'right' => sub {
			my $client = shift;
			$client->bumpRight();
		},
		'browse' => sub {
			my $client = shift;
			my $button = shift;
			my $args = shift;

			getMenuHandler()->browseTo($client, $args);
		},
	}
}

sub webPages {
	my $class = shift;
	my %pages = (
		"CustomBrowseMenus/custombrowsemenus_list\.(?:htm|xml)" => \&handleWebList,
		"CustomBrowseMenus/custombrowsemenus_header\.(?:htm|xml)" => \&handleWebHeader,
		"CustomBrowseMenus/custombrowsemenus_contextheader\.(?:htm|xml)" => \&handleWebHeader,
		"CustomBrowseMenus/custombrowsemenus_contextlist\.(?:htm|xml)" => \&handleWebContextList,
		"CustomBrowseMenus/custombrowsemenus_settings\.(?:htm|xml)" => \&handleWebSettings,
		"CustomBrowseMenus/custombrowsemenus_albumimage\.(?:jpg|gif|png)" => \&handleWebAlbumImage,
		"CustomBrowseMenus/custombrowsemenus_albumfile\.(?:txt|pdf|htm)" => \&handleWebAlbumFile,
		"CustomBrowseMenus/custombrowsemenus_imagecachefile\.(?:jpg|gif|png)" => \&handleWebImageCacheFile,
		"CustomBrowseMenus/webadminmethods_edititem\.(?:htm|xml)" => \&handleWebEditMenu,
		"CustomBrowseMenus/webadminmethods_hideitem\.(?:htm|xml)" => \&handleWebHideMenu,
		"CustomBrowseMenus/webadminmethods_showitem\.(?:htm|xml)" => \&handleWebShowMenu,
		"CustomBrowseMenus/webadminmethods_saveitem\.(?:htm|xml)" => \&handleWebSaveMenu,
		"CustomBrowseMenus/webadminmethods_savesimpleitem\.(?:htm|xml)" => \&handleWebSaveSimpleMenu,
		"CustomBrowseMenus/webadminmethods_savenewitem\.(?:htm|xml)" => \&handleWebSaveNewMenu,
		"CustomBrowseMenus/webadminmethods_savenewsimpleitem\.(?:htm|xml)" => \&handleWebSaveNewSimpleMenu,
		"CustomBrowseMenus/webadminmethods_removeitem\.(?:htm|xml)" => \&handleWebRemoveMenu,
		"CustomBrowseMenus/webadminmethods_newitemtypes\.(?:htm|xml)" => \&handleWebNewMenuTypes,
		"CustomBrowseMenus/webadminmethods_newitemparameters\.(?:htm|xml)" => \&handleWebNewMenuParameters,
		"CustomBrowseMenus/webadminmethods_newitem\.(?:htm|xml)" => \&handleWebNewMenu,
		"CustomBrowseMenus/webadminmethods_deleteitemtype\.(?:htm|xml)" => \&handleWebDeleteMenuType,
		"CustomBrowseMenus/custombrowsemenus_add\.(?:htm|xml)" => \&handleWebAdd,
		"CustomBrowseMenus/custombrowsemenus_play\.(?:htm|xml)" => \&handleWebPlay,
		"CustomBrowseMenus/custombrowsemenus_insert\.(?:htm|xml)" => \&handleWebInsert,
		"CustomBrowseMenus/custombrowsemenus_addall\.(?:htm|xml)" => \&handleWebAddAll,
		"CustomBrowseMenus/custombrowsemenus_insertall\.(?:htm|xml)" => \&handleWebInsertAll,
		"CustomBrowseMenus/custombrowsemenus_playall\.(?:htm|xml)" => \&handleWebPlayAll,
		"CustomBrowseMenus/custombrowsemenus_contextadd\.(?:htm|xml)" => \&handleWebContextAdd,
		"CustomBrowseMenus/custombrowsemenus_contextinsert\.(?:htm|xml)" => \&handleWebContextInsert,
		"CustomBrowseMenus/custombrowsemenus_contextplay\.(?:htm|xml)" => \&handleWebContextPlay,
		"CustomBrowseMenus/custombrowsemenus_contextaddall\.(?:htm|xml)" => \&handleWebContextAddAll,
		"CustomBrowseMenus/custombrowsemenus_contextinsertall\.(?:htm|xml)" => \&handleWebContextInsertAll,
		"CustomBrowseMenus/custombrowsemenus_contextplayall\.(?:htm|xml)" => \&handleWebContextPlayAll,
	);
	my $value = 'plugins/CustomBrowseMenus/custombrowsemenus_list.html';

	for my $page (keys %pages) {
		if (UNIVERSAL::can("Slim::Web::Pages", "addPageFunction")) {
			Slim::Web::Pages->addPageFunction($page, $pages{$page});
		} else {
			Slim::Web::HTTP::addPageFunction($page, $pages{$page});
		}
	}

	if (defined($value)) {
		addWebMenus(undef, $value);
		my $menuName = $prefs->get('menuname');
		if ($menuName) {
			Slim::Utils::Strings::setString(uc 'PLUGIN_CUSTOMBROWSEMENUS_CUSTOM_MENUNAME', $menuName);
		}
		if (!$prefs->get('toplevelmenuinextras')) {
			Slim::Web::Pages->addPageLinks("browse", {'PLUGIN_CUSTOMBROWSEMENUS' => $value});
			Slim::Web::Pages->addPageLinks("icons", {'PLUGIN_CUSTOMBROWSEMENUS' => 'plugins/CustomBrowseMenus/html/images/custombrowsemenus.png'});
		}
	}

	if (!$prefs->get('toplevelmenuinextras')) {
		return (\%pages);
	} else {
		Slim::Web::Pages->addPageLinks("plugins", { 'PLUGIN_CUSTOMBROWSEMENUS' => $value });
		Slim::Web::Pages->addPageLinks("icons", {'PLUGIN_CUSTOMBROWSEMENUS' => 'plugins/CustomBrowseMenus/html/images/custombrowsemenus.png'});
	}
}

sub addWebMenus {
	my ($client, $value) = @_;
	my $menus = getMenuHandler()->getMenuItems($client, undef, undef, 'web');
	for my $menu (@$menus) {
		my $name = getMenuHandler()->getItemText($client, $menu);
		my $key = $name;

		if (!Slim::Utils::Strings::stringExists($key)) {
			Slim::Utils::Strings::setString( uc $key, $name );
		}

		if ($menu->{'enabledbrowse'} || ($key ne $name && ($prefs->get('replacewebmenus')))) {
			if (defined($menu->{'menu'}) && ref($menu->{'menu'}) ne 'ARRAY' && getMenuHandler()->hasCustomUrl($client, $menu->{'menu'})) {
				my $url = getMenuHandler()->getCustomUrl($client, $menu->{'menu'});
				main::DEBUGLOG && $log->is_debug && $log->debug("Adding menu: $key = $name");
				Slim::Web::Pages->addPageLinks("browse", { $key => $url });
				Slim::Web::Pages->addPageLinks("browseiPeng", { $key => $url });
				Slim::Web::Pages->addPageLinks("icons", {$key => getIcon($name, 'EN') });
				if (UNIVERSAL::can("Slim::Plugin::Base", "addWeight")) {
					Slim::Plugin::Base->addWeight($key, defined($menu->{'menuorder'}) ? $menu->{'menuorder'} : 80);
					if ($serverPrefs->get("rank-$key")) {
						$serverPrefs->remove("rank-$key");
					}
				} else {
					$serverPrefs->set("rank-$key",(defined($menu->{'menuorder'}) ? $menu->{'menuorder'} : 80));
				}
			} else {
				main::DEBUGLOG && $log->is_debug && $log->debug("Adding menu: $key = $name");
				Slim::Web::Pages->addPageLinks("browse", { $key => $value."?hierarchy=".$menu->{'id'}."&mainBrowseMenu=1"});
				Slim::Web::Pages->addPageLinks("browseiPeng", { $key => $value."?hierarchy=".$menu->{'id'}."&mainBrowseMenu=1"});
				Slim::Web::Pages->addPageLinks("icons", {$key => getIcon($name, 'EN') });
				if (UNIVERSAL::can("Slim::Plugin::Base", "addWeight")) {
					Slim::Plugin::Base->addWeight($key,defined($menu->{'menuorder'}) ? $menu->{'menuorder'} : 80);
					if ($serverPrefs->get("rank-$key")) {
						$serverPrefs->remove("rank-$key");
					}
				} else {
					$serverPrefs->set("rank-$key",(defined($menu->{'menuorder'})?$menu->{'menuorder'}:80));
				}
			}
		} else {
			main::DEBUGLOG && $log->is_debug && $log->debug("Removing menu: $name");
			Slim::Web::Pages->addPageLinks("browse", {$name => undef});
			Slim::Web::Pages->addPageLinks("browseiPeng", {$name => undef});
		}
	}
}

# Draws the plugin's web page
sub handleWebList {
	my ($client, $params) = @_;
	$sqlerrors = '';
	if (defined($params->{'cleancache'}) && $params->{'cleancache'}) {
		my $cacheVersion = $PLUGINVERSION;
		$cacheVersion =~ s/^.*\.([^\.]+)$/\1/;
		my $cache = Slim::Utils::Cache->new("PluginCache/CustomBrowseMenus", $cacheVersion);
		$cache->clear();
	}
	if (defined($params->{'refresh'})) {
		readBrowseConfiguration($client);
		readContextBrowseConfiguration($client);
	}
	my $items = getMenuHandler()->getPageItemsForContext($client, $params, undef, 0, 'web');
	my $context = getMenuHandler()->getContext($client, $params, 1);

	if ($items->{'artwork'}) {
		$params->{'pluginCustomBrowseMenusArtworkSupported'} = 1;
	}
	$params->{'pluginCustomBrowseMenusPageInfo'} = $items->{'pageinfo'};
	$params->{'pluginCustomBrowseMenusOptions'} = $items->{'options'};
	$params->{'pluginCustomBrowseMenusItems'} = $items->{'items'};
	$params->{'pluginCustomBrowseMenusContext'} = $context;
	$params->{'pluginCustomBrowseMenusSelectedOption'} = $params->{'option'};
	if ($params->{'mainBrowseMenu'}) {
		$params->{'pluginCustomBrowseMenusMainBrowseMenu'} = 1;
	}
	$params->{'pluginCustomBrowseMenusValueSeparator'} = $prefs->get("header_value_separator");
	if (defined($params->{'pluginCustomBrowseMenusValueSeparator'})) {
		$params->{'pluginCustomBrowseMenusValueSeparator'} =~ s/\\\\/\\/;
		$params->{'pluginCustomBrowseMenusValueSeparator'} =~ s/\\n/\n/;
	}

	$params->{'pluginCustomBrowseMenusPlayAddAll'} = 1;
	if (defined($context) && scalar(@$context) > 0) {
		$params->{'pluginCustomBrowseMenusCurrentContext'} = $context->[scalar(@$context)-1];
		$params->{'pluginCustomBrowseMenusMenu'} = $context->[0];
	}
	if (defined($items->{'playable'}) && !$items->{'playable'}) {
		$params->{'pluginCustomBrowseMenusPlayAddAll'} = 0;
	}
	if (defined($params->{'pluginCustomBrowseMenusCurrentContext'})) {
		$params->{'pluginCustomBrowseMenusHeaderItems'} = getHeaderItems($client, $params, $params->{'pluginCustomBrowseMenusCurrentContext'}, undef, "header");
		$params->{'pluginCustomBrowseMenusFooterItems'} = getHeaderItems($client, $params, $params->{'pluginCustomBrowseMenusCurrentContext'}, undef, "footer");
	}
	if ($sqlerrors && $sqlerrors ne '') {
		$params->{'pluginCustomBrowseMenusError'} = $sqlerrors;
	}
	if (Slim::Music::Import->stillScanning || CTIisScanning($client)) {
		$params->{'pluginCustomBrowseMenusScanWarning'} = 1;
	}

	return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowseMenus/custombrowsemenus_list.html', $params);
}

sub isPluginsInstalled {
	my ($client, $pluginList) = @_;
	my $enabledPlugin = 1;
	foreach my $plugin (split /,/, $pluginList) {
		if ($enabledPlugin) {
			$enabledPlugin = grep(/$plugin/, Slim::Utils::PluginManager->enabledPlugins($client));
		}
	}
	return $enabledPlugin;
}

sub handleWebHeader {
	my ($client, $params) = @_;

	$sqlerrors = '';
	my $context = undef;
	my $contextParams = undef;
	if ($params->{'path'} =~ /contextheader/) {
		if (defined($params->{'contexttype'})) {
			if (defined($params->{'hierarchy'})) {
				my $regExp = "^group_".$params->{'contexttype'}.".*";
				if ($params->{'hierarchy'} !~ /$regExp/) {
					$params->{'hierarchy'} = 'group_'.$params->{'contexttype'}.','.$params->{'hierarchy'};
				}
			} else {
				$params->{'hierarchy'} = 'group_'.$params->{'contexttype'};
			}
		}
		if (defined($params->{'contextid'})) {
			my %c = (
				'itemid' => $params->{'contextid'},
				'itemtype' => $params->{'contexttype'},
				'itemname' => $params->{'contextname'}
			);
			my $contextString = '';
			if (defined($c{'itemid'})) {
				$contextString .= "&contextid=".$c{'itemid'};
			}
			if (defined($c{'itemtype'})) {
				$contextString .= "&contexttype=".$c{'itemtype'};
			}
			if (defined($c{'itemname'})) {
				$contextString .= "&contextname=".escape($c{'itemname'});
			}
			$c{'itemurl'} = $contextString;
			if ($params->{'noitems'}) {
				$c{'noitems'} = '&noitems=1';
			}
			$contextParams = \%c;
		}
		$context = getContextMenuHandler()->getContext($client, $params, 1);
		if (scalar(@$context) > 0) {
			if (defined($contextParams->{'itemname'})) {
				$context->[0]->{'name'} = Slim::Utils::Unicode::utf8decode($contextParams->{'itemname'}, 'utf8');
			} else {
				$context->[0]->{'name'} = "Context";
			}
		}

		for my $ctx (@$context) {
			$ctx->{'valueUrl'} .= $contextParams->{'itemurl'};
		}
	} else {
		$context = getMenuHandler()->getContext($client, $params, 1);
	}

	$params->{'pluginCustomBrowseMenusContext'} = $context;
	$params->{'pluginCustomBrowseMenusSelectedOption'} = $params->{'option'};
	if ($params->{'mainBrowseMenu'}) {
		$params->{'pluginCustomBrowseMenusMainBrowseMenu'} = 1;
	}
	$params->{'pluginCustomBrowseMenusValueSeparator'} = $prefs->get("header_value_separator");
	if (defined($params->{'pluginCustomBrowseMenusValueSeparator'})) {
		$params->{'pluginCustomBrowseMenusValueSeparator'} =~ s/\\\\/\\/;
		$params->{'pluginCustomBrowseMenusValueSeparator'} =~ s/\\n/\n/;
	}

	if (defined($context) && scalar(@$context) > 0) {
		$params->{'pluginCustomBrowseMenusCurrentContext'} = $context->[scalar(@$context)-1];
	}
	if (defined($params->{'pluginCustomBrowseMenusCurrentContext'})) {
		$params->{'pluginCustomBrowseMenusHeaderItems'} = getHeaderItems($client, $params, $params->{'pluginCustomBrowseMenusCurrentContext'}, $contextParams, "header");
	}
	if ($sqlerrors && $sqlerrors ne '') {
		$params->{'pluginCustomBrowseMenusError'} = $sqlerrors;
	}
	if (Slim::Music::Import->stillScanning || CTIisScanning($client)) {
		$params->{'pluginCustomBrowseMenusScanWarning'} = 1;
	}

	if (defined($params->{'customtemplate'}) && $params->{'customtemplate'} && $params->{'customtemplate'} !~ /\.\./ && $params->{'customtemplate'} !~ /\//) {
		return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowseMenus/'.$params->{'customtemplate'}, $params);
	} else {
		return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowseMenus/custombrowsemenus_header.html', $params);
	}
}

sub getHeaderItems {
	my ($client, $params, $currentContext, $context, $headerType) = @_;

	my $result = undef;
	if (defined($currentContext)) {
		my $header = undef;
		my $useContext = 0;
		if (defined($currentContext->{'item'}->{'menuweb'.$headerType})) {
			$header = $currentContext->{'item'}->{'menuweb'.$headerType};
		}
		if (!defined($header) && defined($currentContext->{'item'}->{'itemtype'}) && $currentContext->{'item'}->{'itemtype'} ne 'sql') {
			$header = $currentContext->{'item'}->{'itemtype'}.$headerType;
		}
		if (!defined($header) && defined($currentContext->{'type'})) {
			$header = $currentContext->{'type'}.$headerType;
		}
		if (!defined($header) && defined($context) && defined($context->{'itemtype'})) {
			$header = $context->{'itemtype'}.$headerType;
			$useContext = 1;
		}
		if (defined($header)) {
			my %c = (
				'itemid' => $currentContext->{'value'},
				'itemtype' => $header,
				'itemname' => $currentContext->{'name'}
			);
			if ($useContext) {
				$c{'itemid'} = $context->{'itemid'};
				$c{'itemname'} = $context->{'itemname'};
			}
			my $contextString = '';
			$c{'itemurl'} = $contextString;
			$c{'hierarchy'} = '&hierarchy=';
			$params->{'hierarchy'} = 'group_'.$c{'itemtype'};
			$params->{'itemsperpage'} = 100;
			delete $params->{'mainBrowseMenu'};
			my $headerResult = getContextMenuHandler()->getPageItemsForContext($client, $params, \%c, 1, 'web');
			my $headerItems = $headerResult->{'items'};
			if (defined($headerItems) && scalar(@$headerItems) > 0) {
				$result = structureContextItems($headerItems);
			}
		}
	}
	return $result;
}

sub handleWebContextList {
	my ($client, $params) = @_;
	$sqlerrors = '';
	if (defined($params->{'refresh'})) {
		readBrowseConfiguration($client);
		readContextBrowseConfiguration($client);
	}
	if (defined($params->{'contexttype'})) {
		if (defined($params->{'hierarchy'})) {
			my $regExp = "^group_".$params->{'contexttype'}.".*";
			if ($params->{'hierarchy'} !~ /$regExp/) {
				$params->{'hierarchy'} = 'group_'.$params->{'contexttype'}.','.$params->{'hierarchy'};
			}
		} else {
			$params->{'hierarchy'} = 'group_'.$params->{'contexttype'};
		}
	}
	my $contextParams = undef;
	if (defined($params->{'contextid'})) {
		my %c = (
			'itemid' => $params->{'contextid'},
			'itemtype' => $params->{'contexttype'},
			'itemname' => Slim::Utils::Unicode::utf8on(unescape($params->{'contextname'})),
		);
		my $contextString = '';
		if (defined($c{'itemid'})) {
			$contextString .= "&contextid=".$c{'itemid'};
		}
		if (defined($c{'itemtype'})) {
			$contextString .= "&contexttype=".$c{'itemtype'};
		}
		if (defined($c{'itemname'})) {
			$contextString .= "&contextname=".escape(escape($c{'itemname'}));
		}
		$c{'itemurl'} = $contextString;
		if ($params->{'noitems'}) {
			$c{'noitems'} = '&noitems=1';
		}
		$contextParams = \%c;
	}
	my $items = getContextMenuHandler()->getPageItemsForContext($client, $params, $contextParams, 0, 'web');
	my $context = getContextMenuHandler()->getContext($client, $params, 1);
	if (scalar(@$context) > 0) {
		if (defined($contextParams->{'itemname'})) {
			$context->[0]->{'name'} = Slim::Utils::Unicode::utf8decode($contextParams->{'itemname'}, 'utf8');
		} else {
			$context->[0]->{'name'} = "Context";
		}
	}

	for my $ctx (@$context) {
		$ctx->{'valueUrl'} .= $contextParams->{'itemurl'};
	}
	if ($items->{'artwork'}) {
		$params->{'pluginCustomBrowseMenusArtworkSupported'} = 1;
	}
	$params->{'pluginCustomBrowseMenusPageInfo'} = $items->{'pageinfo'};
	$params->{'pluginCustomBrowseMenusOptions'} = $items->{'options'};

	# Make sure we only show play/add all if the items are of same type
	my $playAllItems = $items->{'items'};
	my $prevItem = undef;
	for my $it (@$playAllItems) {
		if (defined($prevItem) && (!defined($prevItem->{'itemtype'}) || !defined($it->{'itemtype'}) || $prevItem->{'itemtype'} ne $it->{'itemtype'})) {
			$prevItem = undef;
			last;
		} else {
			$prevItem = $it;
		}
	}
	if (defined($prevItem)) {
		$params->{'pluginCustomBrowseMenusPlayAddAll'} = 1;
	}

	if ($params->{'path'} =~ /contextlist/) {
		if (defined($params->{'noitems'})) {
			$params->{'pluginCustomBrowseMenusNoItems'} = 1;
		} else {
			$params->{'pluginCustomBrowseMenusItems'} = $items->{'items'};
		}
	} else {
		$params->{'pluginCustomBrowseMenusItems'} = structureContextItems($items->{'items'});
	}
	$params->{'pluginCustomBrowseMenusContext'} = $context;
	$params->{'pluginCustomBrowseMenusSelectedOption'} = $params->{'option'};
	if ($params->{'mainBrowseMenu'}) {
		$params->{'pluginCustomBrowseMenusMainBrowseMenu'} = 1;
	}
	$params->{'pluginCustomBrowseMenusValueSeparator'} = $prefs->get("header_value_separator");
	if (defined($params->{'pluginCustomBrowseMenusValueSeparator'})) {
		$params->{'pluginCustomBrowseMenusValueSeparator'} =~ s/\\\\/\\/;
		$params->{'pluginCustomBrowseMenusValueSeparator'} =~ s/\\n/\n/;
	}

	if (defined($context) && scalar(@$context) > 0) {
		$params->{'pluginCustomBrowseMenusCurrentContext'} = $context->[scalar(@$context)-1];
	}
	if (defined($items->{'playable'}) && !$items->{'playable'}) {
		$params->{'pluginCustomBrowseMenusPlayAddAll'} = 0;
	}

	if (defined($params->{'pluginCustomBrowseMenusCurrentContext'})) {
		$params->{'pluginCustomBrowseMenusHeaderItems'} = getHeaderItems($client, $params, $params->{'pluginCustomBrowseMenusCurrentContext'}, $contextParams, "header");
		$params->{'pluginCustomBrowseMenusFooterItems'} = getHeaderItems($client, $params, $params->{'pluginCustomBrowseMenusCurrentContext'}, $contextParams, "footer");
	}
	if ($sqlerrors && $sqlerrors ne '') {
		$params->{'pluginCustomBrowseMenusError'} = $sqlerrors;
	}
	if (Slim::Music::Import->stillScanning || CTIisScanning($client)) {
		$params->{'pluginCustomBrowseMenusScanWarning'} = 1;
	}

	return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowseMenus/custombrowsemenus_contextlist.html', $params);
}

sub handleWebAlbumImage {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	my $albumId = $params->{'album'};
	my $album = Slim::Schema->resultset('Album')->find($albumId);
	my @tracks = $album->tracks;

	my %dirs = ();
	for my $track (@tracks) {
		my $path = Slim::Utils::Misc::pathFromFileURL($track->url);
		if ($path) {
			$path =~ s/^(.*)[\/\\](.*?)$/$1/;
			if (!$dirs{$path}) {
				$dirs{$path} = $path;
			}
		}
	}
	for my $dir (keys %dirs) {
		next unless -f catfile($dir, $params->{'file'});
		main::DEBUGLOG && $log->is_debug && $log->debug("Reading: ".catfile($dir, $params->{'file'})."");
		my $content = read_file(catfile($dir, $params->{'file'}));
		return \$content;
	}
	return undef;
}

sub handleWebAlbumFile {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	my $albumId = $params->{'album'};
	my $album = Slim::Schema->resultset('Album')->find($albumId);
	my @tracks = $album->tracks;

	my %dirs = ();
	for my $track (@tracks) {
		my $path = Slim::Utils::Misc::pathFromFileURL($track->url);
		if ($path) {
			$path =~ s/^(.*)[\/\\](.*?)$/$1/;
			if (!$dirs{$path}) {
				$dirs{$path} = $path;
			}
		}
	}
	for my $dir (keys %dirs) {
		next unless -f catfile($dir, $params->{'file'});
		main::DEBUGLOG && $log->is_debug && $log->debug("Reading: ".catfile($dir, $params->{'file'})."");
		my $content = read_file(catfile($dir, $params->{'file'}));
		return \$content;
	}
	return undef;
}

sub handleWebImageCacheFile {
	my ($client, $params, $callback, $httpClient, $response) = @_;
	my $type = $params->{'type'};
	my $name = undef;
	my $section = $params->{'section'};
	# We don't want to allow .. for security reason
	if (defined($section) && $section ne '') {
		if ($section =~ /\.\./) {
			$section = undef;
		}
	}
	if (defined($type) && $type eq 'artist') {
		my $artistId = $params->{'artist'};
		my $artist = Slim::Schema->resultset('Contributor')->find($artistId);
		if (defined($artist)) {
			$name = $artist->name;
		}
	} elsif (defined($type) && $type eq 'album') {
		my $albumId = $params->{'album'};
		my $album = Slim::Schema->resultset('Album')->find($albumId);
		if (defined($album)) {
			$name = $album->title;
		}
	} elsif (defined($type) && $type eq 'genre') {
		my $genreId = $params->{'genre'};
		my $genre = Slim::Schema->resultset('Genre')->find($genreId);
		if (defined($genre)) {
			$name = $genre->name;
		}
	} elsif (defined($type) && $type eq 'playlist') {
		my $playlistId = $params->{'playlist'};
		my $playlist = Slim::Schema->resultset('Playlist')->find($playlistId);
		if (defined($playlist)) {
			$name = $playlist->title;
		}
	} elsif (defined($type) && $type eq 'year') {
		my $yearId = $params->{'year'};
		if (defined($yearId)) {
			if (!$yearId) {
				$yearId = string('UNK');
			}
			$name = $yearId;
		}
	} elsif (defined($type) && $type eq 'custom') {
		$name = $params->{'custom'};
		# We don't want to allow .. for security reason
		if ($name =~ /\.\./) {
			$name = undef;
		}
	}

	my $dir = $prefs->get('folder_imagecache');

	if (defined($dir) && defined($name)) {
		my $extension = undef;
		my $file = $name;
		$name =~ s/[:\"]/ /g;
		if (defined($section) && $section ne '') {
			$file = catfile($section, $name);
		}
		if (-f catfile($dir, $file.".png")) {
			$extension = ".png";
		} elsif (-f catfile($dir, $file.".jpg")) {
			$extension = ".jpg";
		} elsif (-f catfile($dir, $file.".gif")) {
			$extension = ".gif";
		}
		if (defined($extension)) {
			main::DEBUGLOG && $log->is_debug && $log->debug("Reading: ".catfile($dir, $file.$extension)."");
			my $content = read_file(catfile($dir, $file.$extension));
			return \$content;
		}
	}
	return undef;
}

sub handleWebSettings {
	my ($client, $params) = @_;

	if (defined($params->{'refresh'})) {
		readBrowseConfiguration($client);
		readContextBrowseConfiguration($client);
	}

	return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowseMenus/custombrowsemenus_settings.html', $params);
}

sub structureContextItems {
	my $items = shift;
	my @result = ();

	my $previous = undef;
	for my $item (@$items) {

		if ($previous && $previous eq $item->{'itemname'}) {
			my $previousItem = @result[scalar(@result) - 1];
			if (!defined($previousItem->{'multipleitems'})) {
				my @newArray = ();
				push @newArray, $previousItem;
				$previousItem->{'multipleitems'} = \@newArray;
			}
			my $previousItems = $previousItem->{'multipleitems'};
			push @$previousItems, $item;
			$previousItem->{'multipleitems'} = $previousItems;
			@result[scalar(@result)-1] = $previousItem;
		} else {
			push @result, $item;
		}
		$previous = $item->{'itemname'}
	}
	return \@result;
}

sub prepareManagingMenus {
	my ($client, $params) = @_;
	Plugins::CustomBrowseMenus::Plugin::readBrowseConfiguration($client, $params);
	$manageMenuHandler->prepare($client, $params);
}

sub prepareManagingContextMenus {
	my ($client, $params) = @_;
	Plugins::CustomBrowseMenus::Plugin::readContextBrowseConfiguration($client, $params);
	$manageMenuHandler->prepare($client, $params);
}

sub handleWebEditMenus {
	my ($client, $params) = @_;
	if ($params->{'webadminmethodshandler'} eq 'context') {
		return getContextConfigManager()->webEditItems($client, $params);
	} else {
		return getConfigManager()->webEditItems($client, $params);
	}
}

sub handleWebEditMenu {
	my ($client, $params) = @_;
	if ($params->{'webadminmethodshandler'} eq 'context') {
		return getContextConfigManager()->webEditItem($client, $params);
	} else {
		return getConfigManager()->webEditItem($client, $params);
	}
}

sub handleWebHideMenu {
	my ($client, $params) = @_;
	if ($params->{'webadminmethodshandler'} eq 'context') {
		hideMenu($client, $params, getContextConfigManager(), 1, 'context_menu_');
	} else {
		hideMenu($client, $params, getConfigManager(), 1, 'menu_');
	}
	return handleWebEditMenus($client, $params);
}

sub handleWebShowMenu {
	my ($client, $params) = @_;
	if ($params->{'webadminmethodshandler'} eq 'context') {
		hideMenu($client, $params, getContextConfigManager(), 0, 'context_menu_');
	} else {
		hideMenu($client, $params, getConfigManager(), 0, 'menu_');
	}
	return handleWebEditMenus($client, $params);
}

sub handleWebDeleteMenuType {
	my ($client, $params) = @_;
	if ($params->{'webadminmethodshandler'} eq 'context') {
		return getContextConfigManager()->webDeleteItemType($client, $params);
	} else {
		return getConfigManager()->webDeleteItemType($client, $params);
	}
}

sub handleWebNewMenuTypes {
	my ($client, $params) = @_;
	if ($params->{'webadminmethodshandler'} eq 'context') {
		return getContextConfigManager()->webNewItemTypes($client, $params);
	} else {
		return getConfigManager()->webNewItemTypes($client, $params);
	}
}

sub handleWebNewMenuParameters {
	my ($client, $params) = @_;
	if ($params->{'webadminmethodshandler'} eq 'context') {
		return getContextConfigManager()->webNewItemParameters($client, $params);
	} else {
		return getConfigManager()->webNewItemParameters($client, $params);
	}
}

sub handleWebNewMenu {
	my ($client, $params) = @_;
	if ($params->{'webadminmethodshandler'} eq 'context') {
		return getContextConfigManager()->webNewItem($client, $params);
	} else {
		return getConfigManager()->webNewItem($client, $params);
	}
}

sub handleWebSaveSimpleMenu {
	my ($client, $params) = @_;
	if ($params->{'webadminmethodshandler'} eq 'context') {
		return getContextConfigManager()->webSaveSimpleItem($client, $params);
	} else {
		return getConfigManager()->webSaveSimpleItem($client, $params);
	}
}

sub handleWebRemoveMenu {
	my ($client, $params) = @_;
	if ($params->{'webadminmethodshandler'} eq 'context') {
		return getContextConfigManager()->webRemoveItem($client, $params);
	} else {
		return getConfigManager()->webRemoveItem($client, $params);
	}
}

sub handleWebSaveNewSimpleMenu {
	my ($client, $params) = @_;
	if ($params->{'webadminmethodshandler'} eq 'context') {
		return getContextConfigManager()->webSaveNewSimpleItem($client, $params);
	} else {
		return getConfigManager()->webSaveNewSimpleItem($client, $params);
	}
}

sub handleWebSaveNewMenu {
	my ($client, $params) = @_;
	if ($params->{'webadminmethodshandler'} eq 'context') {
		return getContextConfigManager()->webSaveNewItem($client, $params);
	} else {
		return getConfigManager()->webSaveNewItem($client, $params);
	}
}

sub handleWebSaveMenu {
	my ($client, $params) = @_;
	if ($params->{'webadminmethodshandler'} eq 'context') {
		return getContextConfigManager()->webSaveItem($client, $params);
	} else {
		return getConfigManager()->webSaveItem($client, $params);
	}
}

sub handleWebPlayAdd {
	my ($client, $params, $addOnly, $insert, $gotoparent, $usecontext) = @_;
	return unless $client;
	if (!defined($params->{'hierarchy'})) {
		readBrowseConfiguration($client);
	}
	my $items = undef;
	if ($usecontext) {
		if (defined($params->{'contexttype'})) {
			if (defined($params->{'hierarchy'})) {
				my $regExp = "^group_".$params->{'contexttype'}.".*";
				if ($params->{'hierarchy'} !~ /$regExp/) {
					$params->{'hierarchy'} = 'group_'.$params->{'contexttype'}.','.$params->{'hierarchy'};
				}
			} else {
				$params->{'hierarchy'} = 'group_'.$params->{'contexttype'};
			}
		}
		my $contextParams = undef;
		if (defined($params->{'contextid'})) {
			my %c = (
				'itemid' => $params->{'contextid'},
				'itemtype' => $params->{'contexttype'},
				'itemname' => $params->{'contextname'}
			);
			my $contextString = '';
			if (defined($c{'itemid'})) {
				$contextString .= "&contextid=".$c{'itemid'};
			}
			if (defined($c{'itemtype'})) {
				$contextString .= "&contexttype=".$c{'itemtype'};
			}
			if (defined($c{'itemname'})) {
				$contextString .= "&contextname=".escape($c{'itemname'});
			}
			$c{'itemurl'} = $contextString;
			$contextParams = \%c;
		}
		my $it = getContextMenuHandler()->getPageItem($client, $params, $contextParams, 0, 'web');
		getContextMenuHandler()->playAddItem($client, undef, $it, $addOnly, $insert, $contextParams);
	} else {
		my $it = getMenuHandler()->getPageItem($client, $params, undef, 0, 'web');
		getMenuHandler()->playAddItem($client, undef, $it, $addOnly, $insert, undef);
	}

	my $hierarchy = $params->{'hierarchy'};
	if (defined($hierarchy)) {
		my @hierarchyItems = (split /,/, $hierarchy);
		my $newHierarchy = '';
		my $i = 0;
		my $noOfHierarchiesToUse = scalar(@hierarchyItems) - 1;
		foreach my $hierarchyItem (@hierarchyItems) {
			if ($i && $i < $noOfHierarchiesToUse) {
				$newHierarchy = $newHierarchy.',';
			}
			if ($i < $noOfHierarchiesToUse) {
				$newHierarchy .= $hierarchyItem;
			}
			$i = $i + 1;
		}
		if ($newHierarchy ne '') {
			$params->{'hierarchy'} = $newHierarchy;
		} else {
			delete $params->{'hierarchy'};
		}
	}
	if ($gotoparent) {
		$hierarchy = $params->{'hierarchy'};
		if ($params->{'url_query'} =~ /[&?]hierarchy=/) {
			$params->{'url_query'} =~ s/([&?]hierarchy=)([^&]*)/$1$hierarchy/;
		}
		if ($params->{'url_query'} =~ /[&?]hierarchy=&/) {
			$params->{'url_query'} =~ s/[&?]hierarchy=&//;
		}
	}
	if ($usecontext) {
		$params->{'CustomBrowseMenusReloadPath'} = 'plugins/CustomBrowseMenus/custombrowsemenus_contextlist.html';
		$params->{'CustomBrowseMenusReloadQuery'} = $params->{'url_query'};
		return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowseMenus/custombrowsemenus_reload.html', $params);
	} else {
		$params->{'CustomBrowseMenusReloadPath'} = 'plugins/CustomBrowseMenus/custombrowsemenus_list.html';
		$params->{'CustomBrowseMenusReloadQuery'} = $params->{'url_query'};
		return Slim::Web::HTTP::filltemplatefile('plugins/CustomBrowseMenus/custombrowsemenus_reload.html', $params);
	}
}

sub handleWebPlay {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client, $params,0,0,1);
}

sub handleWebAdd {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client, $params,1,0,1);
}

sub handleWebInsert {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client, $params,1,1,1);
}

sub handleWebPlayAll {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client, $params,0,0,0);
}

sub handleWebAddAll {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client, $params,1,0,0);
}

sub handleWebInsertAll {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client, $params,1,1,0);
}

sub handleWebContextPlay {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client, $params,0,0,1,1);
}

sub handleWebContextAdd {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client, $params,1,0,1,1);
}

sub handleWebContextInsert {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client, $params,1,1,1,1);
}

sub handleWebContextPlayAll {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client, $params,0,0,0,1);
}

sub handleWebContextAddAll {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client, $params,1,0,0,1);
}

sub handleWebContextInsertAll {
	my ($client, $params) = @_;
	return handleWebPlayAdd($client, $params,1,1,0,1);
}

sub hideMenu {
	my ($client, $params, $cfgMgr, $hide, $prefix) = @_;

	my $items = $cfgMgr->items();
	my $itemId = escape($params->{'item'});
	if (defined($items->{$itemId})) {
		if ($hide) {
			$prefs->set($prefix.$itemId.'_enabled', 0);
			$items->{$itemId}->{'enabled'} = 0;
		} else {
			$prefs->set($prefix.$itemId.'_enabled', 1);
			$items->{$itemId}->{'enabled'} = 1;
		}
	}
}


sub cliJiveHandler {
	main::DEBUGLOG && $log->is_debug && $log->debug("Entering cliJiveHandler");
	my $request = shift;
	my $client = $request->client();

	if (!$request->isQuery([['custombrowsemenus'], ['browsejive']]) && !$request->isQuery([['custombrowsemenus'], ['browsejivecontext']])) {
		$log->warn("Incorrect command");
		$request->setStatusBadDispatch();
		main::DEBUGLOG && $log->is_debug && $log->debug("Exiting cliJiveHandler");
		return;
	}
	if (!defined $client) {
		$log->warn("Client required");
		$request->setStatusNeedsClient();
		main::DEBUGLOG && $log->is_debug && $log->debug("Exiting cliJiveHandler");
		return;
	}
	my $context = undef;
	if ($request->isQuery([['custombrowsemenus'], ['browsejivecontext']])) {
		$context = {
			'itemtype' => $request->getParam('contexttype'),
			'itemid' => $request->getParam('contextid'),
			'itemname' => $request->getParam('contextname'),
		};
	} else {
	}

	cliJiveHandlerImpl($client, $request, $context);
}

sub cliJiveHandlerImpl {
	my ($client, $request, $browseContext) = @_;

	if (!$browseMenusFlat) {
		readBrowseConfiguration($client);
	}
	my $params = $request->getParamsCopy();

	for my $k (keys %$params) {
		main::DEBUGLOG && $log->is_debug && $log->debug("Got: $k = ".$params->{$k}."");
	}

	my $start = $request->getParam('start');
	if (!defined($start)) {
		$start = $request->getParam('_start');
		if (!defined($start)) {
			$start = $request->getParam('_p2');
		}
	}
	if (!defined($start) || $start eq '') {
		$start = 0;
	}
	if ($start > 0 && (!$prefs->get("touchtoplay") || !$serverPrefs->client($client)->get("playtrackalbum"))) {
		# Decrease to compensate for "Play All" item on first chunk
		$start--;
	}
	$params->{'start'}=$start;
	my $itemsPerPage = $request->getParam('itemsPerResponse');
	if (!defined($itemsPerPage)) {
		$itemsPerPage = $request->getParam('_itemsPerResponse');
		if (!defined($itemsPerPage)) {
			$itemsPerPage = $request->getParam('_p3');
		}
	}
	if (defined($itemsPerPage) || $itemsPerPage ne '') {
		$params->{'itemsperpage'} = $itemsPerPage;
	}
	if (defined($params->{'hierarchy'})) {
		#I am not sure why this is needed, but it solves the case where menu id is non ascii characters
		$params->{'hierarchy'} = unescape($params->{'hierarchy'});
		$params->{'hierarchy'} = Slim::Utils::Unicode::utf8on($params->{'hierarchy'});
	}

	my $menuResult = undef;
	my $context = undef;
	my $menuAge = $lastChange;
	my $menuIcon = 0;
	if (!defined($browseContext)) {
		main::DEBUGLOG && $log->is_debug && $log->debug("Executing CLI browsejive command");
		$menuResult = getMenuHandler()->getPageItemsForContext($client, $params, undef, 0, 'jive');
		$context = getMenuHandler()->getContext($client, $params, 1);
		if (defined($params->{'hierarchy'})) {
			my @hierarchies = split(/,/, $params->{'hierarchy'});
			foreach my $hierarchy (@hierarchies) {
				if (exists $browseMenusFlat->{$hierarchy} && exists $browseMenusFlat->{$hierarchy}->{'timestamp'}) {
					if (defined($browseMenusFlat->{$hierarchy}->{'cached'}) && !$browseMenusFlat->{$hierarchy}->{'cached'}) {
						$menuAge = undef;
					} else {
						$menuAge = $browseMenusFlat->{$hierarchy}->{'timestamp'};
					}
					last;
				}
			}
		} else {
			$menuIcon = 1;
		}
	} else {
		main::DEBUGLOG && $log->is_debug && $log->debug("Executing CLI browsejivecontext command");
		if (defined $browseContext->{'itemtype'}) {
			$params->{'contexttype'} = $browseContext->{'itemtype'};
		}
		if (defined $browseContext->{'itemid'}) {
			$params->{'contextid'} = $browseContext->{'itemid'};
		}
		if (defined $browseContext->{'itemname'}) {
			$params->{'contextname'} = $browseContext->{'itemname'};
		}
		if (defined($params->{'contexttype'})) {
			if (defined($params->{'hierarchy'})) {
				my $regExp = "^group_".$params->{'contexttype'}.".*";
				if ($params->{'hierarchy'} !~ /$regExp/) {
					$params->{'hierarchy'} = 'group_'.$params->{'contexttype'}.','.$params->{'hierarchy'};
				}
			} else {
				$params->{'hierarchy'} = 'group_'.$params->{'contexttype'};
			}
		}
		$menuResult = getContextMenuHandler()->getPageItemsForContext($client, $params, $browseContext, 0,'jive');
		$context = getContextMenuHandler()->getContext($client, $params, 1);
		if (scalar(@$context) > 0) {
			if (defined($browseContext->{'itemname'})) {
				$context->[0]->{'name'} = Slim::Utils::Unicode::utf8decode($browseContext->{'itemname'}, 'utf8');
			} else {
				$context->[0]->{'name'} = "Context";
			}
		}
	}
	if (defined($lastScanTime) && $lastScanTime > $menuAge) {
		$menuAge = $lastScanTime;
	}

	my $currentContext = undef;
	if (defined($context) && scalar(@$context) > 0) {
		$currentContext = $context->[scalar(@$context)-1];
	}
	my $menuItems = $menuResult->{'items'};
	my $count = $menuResult->{'pageinfo'}->{'totalitems'};
	my %baseParams = ();
	foreach my $param (keys %$params) {
		if ($param ne 'hierarchy' && $param ne 'start' && $param ne 'itemsperpage' && $param !~ /^_/) {
			$baseParams{$param} = $params->{$param};
		}
	}
	my $baseMenu = {
		'actions' => {
			'go' => {
				'cmd' => ['custombrowsemenus', 'browsejive'],
				'params' => \%baseParams,
				'itemsParams' => 'params',
			},
			'add' => {
				'cmd' => ['custombrowsemenus', 'add'],
				'params' => \%baseParams,
				'itemsParams' => 'params',
			},
			'add-hold' => {
				'cmd' => ['custombrowsemenus', 'insert'],
				'params' => \%baseParams,
				'itemsParams' => 'params',
			},
			'play' => {
				'cmd' => ['custombrowsemenus', 'play'],
				'params' => \%baseParams,
				'itemsParams' => 'params',
				'nextWindow' => 'nowPlaying',
			},
		}
	};
	if (defined($browseContext)) {
		$baseMenu->{'actions'}->{'go'}->{'cmd'} = ['custombrowsemenus', 'browsejivecontext'];
		$baseMenu->{'actions'}->{'play'}->{'cmd'} = ['custombrowsemenus', 'playcontext'];
		$baseMenu->{'actions'}->{'add'}->{'cmd'} = ['custombrowsemenus', 'addcontext'];
		$baseMenu->{'actions'}->{'add-hold'}->{'cmd'} = ['custombrowsemenus', 'insertcontext'];
	}
	$request->addResult('base', $baseMenu);

	my $cnt = 0;
	if (scalar(@$menuItems) > 1 && defined($menuResult->{'playable'}) && $menuResult->{'playable'} && defined($currentContext)) {
		if (!$prefs->get("touchtoplay") || !$serverPrefs->client($client)->get("playtrackalbum")) {
			$count++;
			if ($start == 0) {
				my %itemParams = ();
				%itemParams = %{$currentContext->{'parameters'}};
				$itemParams{'hierarchy'} = $currentContext->{'valuePath'};
				my $actions = {
					'go' => {
						'cmd' => ['custombrowsemenus', 'play'],
						'params' => \%itemParams,
						'itemsParams' => 'params',
						'nextWindow' => 'nowPlaying',
					},
					'add-hold' => undef,
					'do' => {
						'cmd' => ['custombrowsemenus', 'play'],
						'params' => \%itemParams,
						'itemsParams' => 'params',
						'nextWindow' => 'nowPlaying',
					},
				};
				$request->addResultLoop('item_loop', $cnt, 'playAction', 'do');
				$request->addResultLoop('item_loop', $cnt, 'playHoldAction', 'do');
				$request->addResultLoop('item_loop', $cnt, 'style', 'itemplay');
				$request->addResultLoop('item_loop', $cnt, 'type', 'playall'); # This is used by iPeng

				$request->addResultLoop('item_loop', $cnt, 'params', \%itemParams);
				$request->addResultLoop('item_loop', $cnt, 'actions', $actions);
				$request->addResultLoop('item_loop', $cnt, 'text', string('JIVE_PLAY_ALL'));
				$cnt++;

				if (defined($itemsPerPage) && scalar(@$menuItems) >= $itemsPerPage) {
					main::DEBUGLOG && $log->is_debug && $log->debug("Removing item to make space for play all item, requested $itemsPerPage and got ".(scalar(@$menuItems))." items");
					# Remove last menu item
					my $popped = pop @$menuItems;
				}
			}
		}
	}
	foreach my $item (@$menuItems) {
		my $name;
		my $itemkey;
		if (defined($item->{'itemvalue'})) {
			$name = $item->{'itemname'}.': '.$item->{'itemvalue'};
		} else {
			$name = $item->{'itemname'};
		}
		my $jivePattern = undef;
		if (defined($item->{'itemtype'}) && defined($item->{$item->{'itemtype'}.'jivepattern'})) {
			$jivePattern = $item->{$item->{'itemtype'}.'jivepattern'};
		} elsif (defined($item->{'jivepattern'})) {
			$jivePattern = $item->{'jivepattern'};
		}
		if (defined($jivePattern)) {
			if ($name =~ /$jivePattern/) {
				if (defined($1)) {
					$name = $1;
					if (defined($2)) {
						$name .= "\n".$2;
					}
					if (defined($3)) {
						$name .= "\n".$3;
					}
				}
			}
		}
		my $firstRowName = $name;
		if ($firstRowName =~ /^(.*?)\n/) {
			$firstRowName = $1;
		}
		if (defined($item->{'itemlink'})) {
			$itemkey = $item->{'itemlink'};
		}

		my $itemtype = undef;
		if (defined($item->{'menu'})) {
			my $menuRef = $item->{'menu'};
			my @submenus = ();
			if (ref($menuRef) eq 'ARRAY') {
				@submenus = @$menuRef;
			} else {
				push @submenus, $menuRef;
			}
			my $ignore = 0;
			foreach my $nextmenu (@submenus) {
				if (defined($nextmenu->{'itemtype'})) {
					if (!defined($itemtype)) {
						$itemtype = $nextmenu->{'itemtype'};
					} elsif ($itemtype ne $nextmenu->{'itemtype'}) {
						$itemtype = "NOTUSED";
					}
				}
				if (defined($nextmenu->{'menutype'}) && $nextmenu->{'menutype'} eq 'mode') {
					$ignore = 1;
					last;
				}
			}
			if ($ignore) {
				$count = $count-1;
				next;
			}
		}
		if ((defined($itemtype) && $itemtype eq 'album')) {
			if ($item->{'image'}) {
				$request->addResultLoop('item_loop', $cnt, 'window', {'titleStyle' => 'album', 'icon' => $item->{'image'}});
				$request->addResultLoop('item_loop', $cnt, 'icon', $item->{'image'});
			} elsif ($menuResult->{'artwork'}) {
				$request->addResultLoop('item_loop', $cnt, 'window', {'titleStyle' => 'album', 'menuStyle' => 'album'});
			} elsif ($item->{'coverThumb'}) {
				$request->addResultLoop('item_loop', $cnt, 'window', {'titleStyle' => 'album', 'icon-id' => $item->{'coverThumb'}});
			} else {
				$request->addResultLoop('item_loop', $cnt, 'window', {'menuStyle' => 'album'});
			}
		} elsif ((defined($itemtype) && $itemtype eq 'artist')) {
			if ($menuResult->{'artwork'}) {
				$request->addResultLoop('item_loop', $cnt, 'window', {'titleStyle' => 'album', 'menuStyle' => 'album'});
			} elsif ($item->{'coverThumb'}) {
				$request->addResultLoop('item_loop', $cnt, 'window', {'titleStyle' => 'album', 'icon-id' => $item->{'coverThumb'}});
			} elsif ($item->{'image'}) {
				$request->addResultLoop('item_loop', $cnt, 'window', {'titleStyle' => 'album', 'icon' => $item->{'image'}});
				$request->addResultLoop('item_loop', $cnt, 'icon', $item->{'image'});
			} else {
				$request->addResultLoop('item_loop', $cnt, 'window', {'menuStyle' => 'album'});
			}
		} elsif ($menuResult->{'artwork'} && defined($item->{'coverThumb'})) {
			if (defined($item->{'itemsubtype'}) && $item->{'itemsubtype'} eq 'album') {
				$request->addResultLoop('item_loop', $cnt, 'window', {'menuStyle' => 'album','text'=>$firstRowName,'icon-id'=>''});
			} else {
				$request->addResultLoop('item_loop', $cnt, 'window', {'titleStyle' => 'album'});
			}
		} elsif (defined($item->{'coverThumb'})) {
			if (defined($item->{'itemsubtype'}) && $item->{'itemsubtype'} eq 'album') {
				$request->addResultLoop('item_loop', $cnt, 'window',{'titleStyle' => 'album', 'icon-id' => $item->{'coverThumb'}});
			} else {
				$request->addResultLoop('item_loop', $cnt, 'window',{'titleStyle' => 'album', 'icon-id' => $item->{'coverThumb'}});
			}
		} elsif (defined($item->{'itemsubtype'}) && $item->{'itemsubtype'} eq 'album') {
			$request->addResultLoop('item_loop', $cnt, 'window', {'menuStyle' => 'album'});
		} elsif (defined($item->{'itemtype'}) && $item->{'itemtype'} eq 'album') {
			$request->addResultLoop('item_loop', $cnt, 'window', {'titleStyle' => 'album'});
		}

		my %itemParams = ();
		if (defined($item->{'contextid'})) {
			if (defined($params->{'hierarchy'}) && $params->{'hierarchy'} ne '') {
				$itemParams{'hierarchy'} = $params->{'hierarchy'}.','.$item->{'contextid'};
			} else {
				$itemParams{'hierarchy'} = $item->{'contextid'};
			}
			$itemParams{$item->{'contextid'}} = $item->{'itemid'};
		} else {
			if (defined($params->{'hierarchy'}) && $params->{'hierarchy'} ne '') {
				$itemParams{'hierarchy'} = $params->{'hierarchy'}.','.$item->{'id'};
			} else {
				$itemParams{'hierarchy'} = $item->{'id'};
			}
			$itemParams{$item->{'id'}} = $item->{'itemid'};
		}
		if ($itemkey) {
			$itemParams{'textkey'} = $itemkey;
			$request->addResultLoop('item_loop', $cnt, 'textkey', $itemkey);
		}
		my $actions = undef;
		if (defined($item->{'mixes'})) {
			foreach my $p (keys %baseParams) {
				if (!exists $itemParams{$p}) {
					$itemParams{$p} = $baseParams{$p};
				}
			}
			$actions = {
				'play-hold' => {
					'cmd' => ['custombrowsemenus', 'mixesjive'],
					'params' => \%itemParams,
					'itemsParams' => 'params',
				},
			};
			if (defined($browseContext)) {
				$actions->{'play-hold'}->{'cmd'} = ['custombrowsemenus', 'mixesjivecontext'];
			}
			$request->addResultLoop('item_loop', $cnt, 'playHoldAction', 'go');
		}
		if (defined($item->{'playtype'}) && $item->{'playtype'} eq 'none') {
			foreach my $p (keys %baseParams) {
				$itemParams{$p} = $baseParams{$p};
			}
			if (!defined($actions)) {
				$actions = {};
			}
			$actions->{'go'} = {
				'cmd' => ['custombrowsemenus', 'browsejive'],
				'params' => \%itemParams,
				'itemsParams' => 'params',
			};
			if (defined($browseContext)) {
				$actions->{'go'}->{'cmd'} = ['custombrowsemenus', 'browsejivecontext'];
			}
		} else {
			$request->addResultLoop('item_loop', $cnt, 'params', \%itemParams);
		}

		if (defined($item->{'itemtype'})) {
			my %contextMenuParams = (
				$item->{'itemtype'}.'_id' => $item->{'itemid'},
				'menu' => $item->{'itemtype'},
				'isContextMenu' => 1,
			);
			if ($item->{'itemtype'} eq 'year') {
				$contextMenuParams{'year'} = $contextMenuParams{'year_id'};
				delete $contextMenuParams{'year_id'};
			}
			$actions->{'more'} = {
				'cmd' => ['contextmenu'],
				'params' => \%contextMenuParams,
				'itemParams' => 'params',
			};
		}

		if (defined($actions)) {
			$request->addResultLoop('item_loop', $cnt, 'actions', $actions);
		}

		$request->addResultLoop('item_loop', $cnt, 'text', $name);

		#iPeng icon
		if ($menuIcon) {
			$request->addResultLoop('item_loop', $cnt, 'menuIcon',getIcon($firstRowName,'iPeng', 1));
		}
		#Cacheable indicator
		if (defined($item->{'cacheable'})) {
			$request->addResultLoop('item_loop', $cnt, 'cacheable','true');
		}
		if (defined($item->{'itemtype'})) {
			$request->addResultLoop('item_loop', $cnt, 'type', $item->{'itemtype'}); # This is used by iPeng
		}

		if ($menuResult->{'artwork'} || (defined($item->{'itemtype'}) && $item->{'itemtype'} eq 'album')) {
			if (defined($item->{'coverThumb'})) {
				$request->addResultLoop('item_loop', $cnt,'icon-id', $item->{'coverThumb'});
			}
		}
		if (defined($item->{'menu'})) {
			my @submenus = ();
			if (ref($item->{'menu'}) eq 'ARRAY') {
				my $m = $item->{'menu'};
				@submenus = @$m;
			} else {
				push @submenus, $item->{'menu'};
			}
			my $songInfo = 0;
			my $mode = 0;
			foreach my $submenu (@submenus) {
				if (defined($submenu->{'menutype'}) && $submenu->{'menutype'} eq 'trackdetails') {
					$songInfo = 1;
					last;
				} elsif (defined($submenu->{'menutype'}) && $submenu->{'menutype'} eq 'mode') {
					$mode = 1;
					last;
				}
			}
			if ($songInfo) {
				if ($prefs->get("touchtoplay")) {
					if (!defined($item->{'playtype'}) || $item->{'playtype'} ne 'none') {
						$request->addResultLoop('item_loop', $cnt, 'goAction', 'play');
					}
				} else {
					my $songInfoParams = {
						track_id => $item->{'itemid'},
						menu => 'nowhere',
					};
					my $contextMenuParams = {
						track_id => $item->{'itemid'},
						menu => 'track',
						'isContextMenu' => 1,
					};
					my $actions = {
						'go' => {
							'cmd' => ['trackinfo', 'items'],
							'params' => $songInfoParams,
						},
						'more' => {
							'cmd' => ['contextmenu'],
							'params' => $contextMenuParams,
						},
					};
					$request->addResultLoop('item_loop', $cnt, 'actions', $actions);

				}
			} elsif ($mode) {
				$request->addResultLoop('item_loop', $cnt, 'style', 'itemNoAction');
			}
		} elsif (!defined($item->{'menufunction'})) {
			if (!defined($item->{'playtype'}) || $item->{'playtype'} ne 'none') {
				$request->addResultLoop('item_loop', $cnt, 'goAction', 'play');
			}
			$request->addResultLoop('item_loop', $cnt, 'style', 'itemNoAction');
		}
		$cnt++;
	}
	if ($start > 0 && (!$prefs->get("touchtoplay") || !$serverPrefs->client($client)->get("playtrackalbum"))) {
		$start++;
	}
	$request->addResult('offset', $start);
	$request->addResult('count', $count);
	if (!defined($browseContext) && defined($menuAge)) {
		$request->addResult('lastChanged', $menuAge);
	}

	$request->setStatusDone();
	main::DEBUGLOG && $log->is_debug && $log->debug("Exiting cliJiveHandler");
}

sub cliHandler {
	main::DEBUGLOG && $log->is_debug && $log->debug("Entering cliHandler");
	my $request = shift;
	my $client = $request->client();

	my $cmd = undef;
	if ($request->isQuery([['custombrowsemenus'], ['browse']])) {
		$cmd = 'browse';
	} elsif ($request->isQuery([['custombrowsemenus'], ['browsecontext']])) {
		$cmd = 'browsecontext';
	} elsif ($request->isCommand([['custombrowsemenus'], ['play']])) {
		$cmd = 'play';
	} elsif ($request->isCommand([['custombrowsemenus'], ['playcontext']])) {
		$cmd = 'playcontext';
	} elsif ($request->isCommand([['custombrowsemenus'], ['add']])) {
		$cmd = 'add';
	} elsif ($request->isCommand([['custombrowsemenus'], ['addcontext']])) {
		$cmd = 'addcontext';
	} elsif ($request->isCommand([['custombrowsemenus'], ['insert']])) {
		$cmd = 'insert';
	} elsif ($request->isCommand([['custombrowsemenus'], ['insertcontext']])) {
		$cmd = 'insertcontext';
	} else {
		$log->warn("Incorrect command");
		$request->setStatusBadDispatch();
		main::DEBUGLOG && $log->is_debug && $log->debug("Exiting cliHandler");
		return;
	}
	if (!defined $client) {
		$log->warn("Client required");
		$request->setStatusNeedsClient();
		main::DEBUGLOG && $log->is_debug && $log->debug("Exiting cliHandler");
		return;
	}

	if (!$browseMenusFlat) {
		readBrowseConfiguration($client);
	}
	my $paramNo = 2;
	my $params = $request->getParamsCopy();
	if ($cmd =~ /^browse/) {
		my $start = $request->getParam('start');
		if (!defined($start)) {
			$start = $request->getParam('_start');
			if (!defined($start)) {
				$start = $request->getParam('_p'.$paramNo);
			}
		}
		if (!defined($start) || $start eq '') {
			$log->warn("_start not defined");
			$request->setStatusBadParams();
			main::DEBUGLOG && $log->is_debug && $log->debug("Exiting cliHandler");
			return;
		}
		$params->{'start'} = $start;
		$paramNo++;
		my $itemsPerPage = $request->getParam('itemsPerResponse');
		if (!defined($itemsPerPage)) {
			$itemsPerPage = $request->getParam('_itemsPerResponse');
			if (!defined($itemsPerPage)) {
				$itemsPerPage = $request->getParam('_p'.$paramNo);
			}
		}
		if (!defined($itemsPerPage) || $itemsPerPage eq '') {
			$log->warn("_itemsPerResponse not defined");
			$request->setStatusBadParams();
			main::DEBUGLOG && $log->is_debug && $log->debug("Exiting cliHandler");
			return;
		}
		$params->{'itemsperpage'} = $itemsPerPage;
		$paramNo++;
	}
	my %emptyHash = ();
	my $context = \%emptyHash;
	if ($cmd =~ /context$/) {
		my $contexttype = $request->getParam('contexttype');
		if (!defined($contexttype)) {
			$contexttype = $request->getParam('_contexttype');
			if (!defined($contexttype)) {
				$contexttype = $request->getParam('_p'.$paramNo)
			}
		}
		if (!defined $contexttype || $contexttype eq '') {
			$log->warn("contexttype not defined");
			$request->setStatusBadParams();
			main::DEBUGLOG && $log->is_debug && $log->debug("Exiting cliHandler");
			return;
		}
		$paramNo++;
		my $contextid = $request->getParam('contextid');
		if (!defined($contextid)) {
			$contextid = $request->getParam('_contextid');
			if (!defined($contextid)) {
				$contextid = $request->getParam('_p'.$paramNo)
			}
		}
		if (!defined $contextid || $contextid eq '') {
			$log->warn("contextid not defined");
			$request->setStatusBadParams();
			main::DEBUGLOG && $log->is_debug && $log->debug("Exiting cliHandler");
			return;
		}
		$paramNo++;

		my %localContext = (
			'itemtype' => $contexttype,
			'itemid' => $contextid
		);
		$context = \%localContext;
	}

	for my $k (keys %$params) {
		main::DEBUGLOG && $log->is_debug && $log->debug("Got: $k = ".$params->{$k}."");
	}
	if (defined($context->{'itemtype'})) {
		if (defined($params->{'hierarchy'})) {
			my $regExp = "^group_".$context->{'itemtype'}.".*";
			if ($params->{'hierarchy'} !~ /$regExp/) {
				$params->{'hierarchy'} = 'group_'.$context->{'itemtype'}.','.$params->{'hierarchy'};
			}
		} else {
			$params->{'hierarchy'} = 'group_'.$context->{'itemtype'};
		}
	}
	if ($cmd =~ /^browse/) {
		main::DEBUGLOG && $log->is_debug && $log->debug("Starting to prepare CLI browse/browsecontext command");
		my $menuResult = undef;
		if ($cmd eq 'browse') {
			main::DEBUGLOG && $log->is_debug && $log->debug("Executing CLI browse command");
			$menuResult = getMenuHandler()->getPageItemsForContext($client, $params, undef, 0, 'cli');
		} else {
			main::DEBUGLOG && $log->is_debug && $log->debug("Executing CLI browsecontext command");
			$menuResult = getContextMenuHandler()->getPageItemsForContext($client, $params, $context, 0, 'cli');
		}
		prepareCLIBrowseResponse($request, $menuResult->{'items'});
	} elsif ($cmd =~ /^play/ || $cmd =~ /^add/ || $cmd =~ /^insert/) {
		main::DEBUGLOG && $log->is_debug && $log->debug("Starting to prepare CLI play/add/insert/playcontext/addcontext/insertcontext command");
		my $menuResult = undef;
		if ($cmd =~ /context$/) {
			$menuResult = getContextMenuHandler()->getPageItem($client, $params, $context, 0, 'cli');
		} else {
			$menuResult = getMenuHandler()->getPageItem($client, $params, undef, 0, 'cli');
		}
		my $addOnly = 0;
		my $insert = 0;
		if ($cmd =~ /^add/) {
			$addOnly = 1;
		} elsif ($cmd =~ /^insert/) {
			$addOnly = 1;
			$insert = 1;
		}
		if (defined($menuResult)) {
			if ($cmd =~ /context$/) {
				getContextMenuHandler()->playAddItem($client, undef, $menuResult, $addOnly, $insert, $context);
			} else {
				my $parentItems = undef;
				if ($menuResult->{'playtype'} eq 'all' && ($cmd eq 'play' || !$prefs->get("touchtoplay") || !$serverPrefs->client($client)->get("playtrackalbum"))) {
					if (defined($params->{'hierarchy'})) {
						if ($params->{'hierarchy'} =~ /^(.*),([^,]*)$/) {
							$params->{'hierarchy'} = $1;
						} else {
							$params->{'hierarchy'} = undef;
						}
					}
					if ($cmd =~ /context$/) {
						$parentItems = getContextMenuHandler()->getPageItem($client, $params, $context, 0, 'cli');
					} else {
						$parentItems = getMenuHandler()->getPageItem($client, $params, undef, 0, 'cli');
					}
					my @empty = ();
					if (defined($parentItems) && ref($parentItems) ne 'ARRAY') {
						push @empty, $parentItems;
						$parentItems = \@empty;
					}
				}
				getMenuHandler()->playAddItem($client, $parentItems, $menuResult, $addOnly, $insert, undef);
			}
		}
	}
	$request->setStatusDone();
	main::DEBUGLOG && $log->is_debug && $log->debug("Exiting cliHandler");
}

sub prepareCLIBrowseResponse {
	my ($request, $items) = @_;

	my $count = scalar(@$items);
	$request->addResult('count', $count);

	$count = 0;
	foreach my $item (@$items) {
		if (defined($item->{'contextid'})) {
			$request->addResultLoop('items_loop', $count, 'level', $item->{'contextid'});
		} else {
			$request->addResultLoop('items_loop', $count, 'level', $item->{'id'});
		}
		$request->addResultLoop('items_loop', $count, 'itemid', $item->{'itemid'});
		if (defined($item->{'itemvalue'})) {
			$request->addResultLoop('items_loop', $count, 'itemname', $item->{'itemvalue'});
		} else {
			$request->addResultLoop('items_loop', $count, 'itemname', $item->{'itemname'});
		}
		if (defined($item->{'itemtype'})) {
			$request->addResultLoop('items_loop', $count, 'itemtype', $item->{'itemtype'});
			$request->addResultLoop('items_loop', $count, 'itemcontext', $item->{'itemtype'});
		} elsif ($item->{'id'} =~ /^group_/) {
			$request->addResultLoop('items_loop', $count, 'itemtype', 'group');
		} else {
			$request->addResultLoop('items_loop', $count, 'itemtype', 'custom');
		}
		if (defined($item->{'playtype'}) && $item->{'playtype'} eq 'none') {
			$request->addResultLoop('items_loop', $count, 'itemplayable', '0');
		} else {
			$request->addResultLoop('items_loop', $count, 'itemplayable', '1');
		}
		if (defined($item->{'playtype'}) && $item->{'playtype'} eq 'none') {
			$request->addResultLoop('items_loop', $count, 'itemplayable', '0');
		} else {
			$request->addResultLoop('items_loop', $count, 'itemplayable', '1');
		}
		$count++;
	}
}

sub readBrowseConfiguration {
	my $client = shift;

	my $itemConfiguration = getConfigManager()->readItemConfiguration($client, undef, undef, 1, 1);
	my $localBrowseMenus = $itemConfiguration->{'menus'};
	my $localLastChange = undef;
	foreach my $menu (keys %$localBrowseMenus) {
		if (!defined($lastChange) || $localLastChange < $localBrowseMenus->{$menu}->{'timestamp'}) {
			$localLastChange = $localBrowseMenus->{$menu}->{'timestamp'};
		}
	}

	$templates = $itemConfiguration->{'templates'};

	my @menus = ();
	getMenuHandler()->setMenuItems($localBrowseMenus);
	$browseMenusFlat = $localBrowseMenus;

	my $value = 'plugins/CustomBrowseMenus/custombrowsemenus_list.html';
	addWebMenus($client, $value);
	addPlayerMenus($client);
	addJivePlayerMenus($client);
	$lastChange = $localLastChange;
	return $browseMenusFlat;
}

sub readContextBrowseConfiguration {
	my $client = shift;

	my $itemConfiguration = getContextConfigManager()->readItemConfiguration($client, undef, undef, 1, 1);
	my $localBrowseMenus = $itemConfiguration->{'menus'};
	$templates = $itemConfiguration->{'templates'};

	my @menus = ();
	getContextMenuHandler()->setMenuItems($localBrowseMenus);
	$contextBrowseMenusFlat = $localBrowseMenus;
	return $contextBrowseMenusFlat;
}

sub getVirtualLibraries {
	my @items;
	my $libraries = Slim::Music::VirtualLibraries->getLibraries();
	main::DEBUGLOG && $log->is_debug && $log->debug('ALL virtual libraries: '.Data::Dump::dump($libraries));

	while (my ($key, $values) = each %{$libraries}) {
		my $count = Slim::Music::VirtualLibraries->getTrackCount($key);
		my $name = $values->{'name'};
		my $displayName = Slim::Utils::Unicode::utf8decode($name, 'utf8').' ('.Slim::Utils::Misc::delimitThousands($count).($count == 1 ? ' track' : ' tracks').')';
		main::DEBUGLOG && $log->is_debug && $log->debug("VL: ".$displayName);
		my $persistentVLID = $values->{'id'};

		push @items, {
			name => $displayName,
			sortName => Slim::Utils::Unicode::utf8decode($name, 'utf8'),
			value => $persistentVLID,
			id => $persistentVLID,
		};
	}
	if (scalar @items == 0) {
		push @items, {
			name => 'No virtual libraries found',
			value => '',
			id => '',
		};
	}

	if (scalar @items > 1) {
		@items = sort {lc($a->{sortName}) cmp lc($b->{sortName})} @items;
	}
	return \@items;
}

sub createCBMfolder {
	my $CBMparentFolderPath = $prefs->get('cbmparentfolderpath') || $serverPrefs->get('playlistdir');
	my $CBMfolderPath = catdir($CBMparentFolderPath, 'CustomBrowseMenus');
	eval {
		mkdir($CBMfolderPath, 0755) unless (-d $CBMfolderPath);
		chdir($CBMfolderPath);
	};
	if ($@) {
		$log->error("Could not create or access CustomBrowseMenus folder in parent folder '$CBMparentFolderPath'!");
		return;
	};

	my %subfolders = ('folder_browsemenus' => 'User_Created_BrowseMenus', 'folder_templates' => 'Custom_Templates_BrowseMenus', 'folder_contexttemplates' => 'Custom_Templates_ContextMenus', 'folder_customicons' => 'Custom_Icons', 'folder_imagecache' => 'ImageCache');
	eval {
		foreach my $subFolderPrefName (keys %subfolders) {
			my $subfolder = catdir($CBMfolderPath, $subfolders{$subFolderPrefName});
			mkdir($subfolder, 0755) unless (-d $subfolder);
			chdir($subfolder);
			$prefs->set("$subFolderPrefName", $subfolder);
		}
	};
	if ($@) {
		$log->error("Could not create or access subfolders in CustomBrowseMenus folder!");
	};
}

sub itemFormatPath {
	my ($self, $client, $item) = @_;
	if ($item->{'itemname'} =~ /^file:\/\//i) {
		my $path = Slim::Utils::Misc::pathFromFileURL($item->{'itemname'});
		return Slim::Utils::Unicode::utf8decode($path, 'utf8')
	} else {
		return $item->{'itemname'};
	}
}

sub validateProperty {
	my $arg = shift;
	if ($arg eq '' || $arg =~ /^[a-zA-Z0-9_]+\s*=\s*.+$/) {
		return $arg;
	} else {
		return undef;
	}
}

sub validateIntOrEmpty {
	my $arg = shift;
	if (!$arg || $arg eq '' || $arg =~ /^\d+$/) {
		return $arg;
	}
	return undef;
}

sub commit {
	my $dbh = shift;
	if (!$dbh->{'AutoCommit'}) {
		$dbh->commit();
	}
}

sub rollback {
	my $dbh = shift;
	if (!$dbh->{'AutoCommit'}) {
		$dbh->rollback();
	}
}

*escape = \&URI::Escape::uri_escape_utf8;

sub unescape {
	my $in = shift;
	my $isParam = shift;
	$in =~ s/\+/ /g if $isParam;
	$in =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
	return $in;
}

sub addSQLError {
	my $error = shift;
	$sqlerrors .= $error;
}

sub getIcon {
	my ($menuName, $skin, $skinPrefix) = @_;

	my $icon = $menuName.".png";
	$icon =~ s/ /_/g;

	my $iconPath;
	my $dir = $prefs->get('folder_customicons');
	if (!defined($dir) || $dir eq '') {
		$iconPath = dirname(__FILE__)."/HTML/$skin/plugins/CustomBrowseMenus/html/images/custombrowsemenus_$icon";
		if ( -e $iconPath) {
			return ($skinPrefix?$skin."/":"")."plugins/CustomBrowseMenus/html/images/custombrowsemenus_$icon";
		} else {
			return ($skinPrefix?$skin."/":"")."plugins/CustomBrowseMenus/html/images/custombrowsemenus.png";
		}
	}
	if (-e catfile($dir, $skin, $icon)) {
		$iconPath = catfile($dir, $skin, $icon);
	} elsif (-e catfile($dir, $icon)) {
		$iconPath = catfile($dir, $icon);
	}
	if (defined($iconPath) && -e $iconPath) {
		my $iconCopyPath;
		$iconCopyPath = dirname(__FILE__)."/HTML/$skin/plugins/CustomBrowseMenus/html/images/custombrowsemenus_$icon";

		my $iconUrl = ($skinPrefix?$skin."/":"")."plugins/CustomBrowseMenus/html/images/custombrowsemenus_$icon";
		if (-e $iconCopyPath) {
			if ((stat($iconPath))[9] > (stat($iconCopyPath))[9]) {
				if (File::Copy::copy($iconPath, $iconCopyPath)) {
					my @timestamp = ( stat($iconPath)) [8,9];
					utime @timestamp, $iconCopyPath;
				} else {
					$iconUrl = ($skinPrefix?$skin."/":"")."plugins/CustomBrowseMenus/html/images/custombrowsemenus.png";
				}
			}
		} else {
			if (File::Copy::copy($iconPath, $iconCopyPath)) {
				my @timestamp = ( stat($iconPath)) [8,9];
				utime @timestamp, $iconCopyPath;
			} else {
				$iconUrl = ($skinPrefix?$skin."/":"")."plugins/CustomBrowseMenus/html/images/custombrowsemenus.png";
			}
		}
		$iconPath = $iconUrl;
	} else {
		$iconPath = ($skinPrefix?$skin."/":"")."plugins/CustomBrowseMenus/html/images/custombrowsemenus.png";
	}

	return $iconPath;
}

1;
