# MenuHandler::FolderMenu
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

package Plugins::CustomBrowseMenus::MenuHandler::FolderMenu;

use strict;

use Plugins::CustomBrowseMenus::MenuHandler::BaseMenu;
our @ISA = qw(Plugins::CustomBrowseMenus::MenuHandler::BaseMenu);

use File::Spec::Functions qw(:ALL);

__PACKAGE__->mk_accessor( rw => qw(itemParameterHandler propertyHandler) );

sub new {
	my ($class, $parameters) = @_;

	my $self = $class->SUPER::new($parameters);
	$self->itemParameterHandler($parameters->{'itemParameterHandler'});
	$self->propertyHandler($parameters->{'propertyHandler'});

	return $self;
}


sub prepareMenu {
	my ($self, $client, $menu, $item, $option, $result, $context) = @_;

	my $dir = $menu->{'menudata'};
	my $keywords = $self->combineKeywords($menu->{'keywordparameters'}, undef, $item->{'parameters'});
	$dir = $self->itemParameterHandler->replaceParameters($client, $dir, $keywords, $context);
	$dir = Slim::Utils::Unicode::utf8toLatin1($dir);
	for my $subdir (Slim::Utils::Misc::readDirectory($dir)) {
		my $subdirname = $subdir;
		$subdirname = Slim::Utils::Unicode::utf8on($subdirname);

		my $fullpath = catdir($dir, $subdir);
		if (Slim::Music::Info::isWinShortcut($fullpath)) {
			$subdirname = substr($subdir, 0, -4);
			$fullpath = Slim::Utils::Misc::pathFromWinShortcut(Slim::Utils::Misc::fileURLFromPath($fullpath));
			if ($fullpath ne '') {
				my $tmp = $fullpath;
				$fullpath = Slim::Utils::Misc::pathFromFileURL($fullpath);
				my $libraryAudioDirUrl = $self->propertyHandler->getProperty('libraryAudioDirUrl');
				$tmp =~ s/^$libraryAudioDirUrl//g;
				$tmp =~ s/^[\\\/]?//g;
				$subdir = unescape($tmp);
			}
		}
		if (-d $fullpath) {
			my %menuItem = (
				'itemid' => $self->_escapeSubDir($subdir),
				'itemname' => $subdirname,
				'itemlink' => uc(substr($subdirname, 0, 1))
			);
			$menuItem{'value'} = $item->{'value'}."_".$subdir;

			for my $menuKey (keys %{$menu}) {
				$menuItem{$menuKey} = $menu->{$menuKey};
			}
			my %parameters = ();
			$menuItem{'parameters'} = \%parameters;
			if (defined($item->{'parameters'})) {
				for my $param (keys %{$item->{'parameters'}}) {
					$menuItem{'parameters'}->{$param} = $item->{'parameters'}->{$param};
				}
			}
			if (defined($menu->{'contextid'})) {
				$menuItem{'parameters'}->{$menu->{'contextid'}} = $self->_escapeSubDir($subdir);
			}elsif (defined($menu->{'id'})) {
				$menuItem{'parameters'}->{$menu->{'id'}} = $self->_escapeSubDir($subdir);
			}
			push @$result, \%menuItem;
		}
		@$result = sort { $a->{'itemname'} cmp $b->{'itemname'} } @$result;
	}
	return undef;
}

sub _escapeSubDir {
	my ($self, $dir) = @_;
	my $result = Slim::Utils::Misc::fileURLFromPath($dir);
	if (Slim::Utils::OSDetect::OS() eq "win") {
		return substr($result, 8);
	} else {
		return substr($result, 3);
	}
}

sub unescape {
	my ($in, $isParam) = @_;

	$in =~ s/\+/ /g if $isParam;
	$in =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

	return $in;
}

1;
