# MenuHandler::Main
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

package Plugins::CustomBrowseMenus::MenuHandler::Main;

use strict;

use base qw(Slim::Utils::Accessor);
use Plugins::CustomBrowseMenus::MenuHandler::BaseMenuHandler;
our @ISA = qw(Plugins::CustomBrowseMenus::MenuHandler::BaseMenuHandler);

use Plugins::CustomBrowseMenus::MenuHandler::SQLHandler;
use Plugins::CustomBrowseMenus::MenuHandler::ParameterHandler;
use Plugins::CustomBrowseMenus::MenuHandler::PropertyHandler;
use Plugins::CustomBrowseMenus::MenuHandler::FunctionMenu;
use Plugins::CustomBrowseMenus::MenuHandler::SQLMenu;
use Plugins::CustomBrowseMenus::MenuHandler::TrackDetailsMenu;
use Plugins::CustomBrowseMenus::MenuHandler::ModeMenu;
use Plugins::CustomBrowseMenus::MenuHandler::FolderMenu;
use Plugins::CustomBrowseMenus::MenuHandler::SQLPlay;
use Plugins::CustomBrowseMenus::MenuHandler::FunctionPlay;
use Plugins::CustomBrowseMenus::MenuHandler::FunctionCmdPlay;
use Plugins::CustomBrowseMenus::MenuHandler::CLICmdPlay;
use Plugins::CustomBrowseMenus::MenuHandler::AllPlay;

use File::Spec::Functions qw(:ALL);

sub new {
	my $class = shift;
	my $parameters = shift;

	my $propertyHandler = Plugins::CustomBrowseMenus::MenuHandler::PropertyHandler->new($parameters);
	$parameters->{'propertyHandler'} = $propertyHandler;
	my $parameterHandler = Plugins::CustomBrowseMenus::MenuHandler::ParameterHandler->new($parameters);
	$parameters->{'itemParameterHandler'} = $parameterHandler;
	my $sqlHandler = Plugins::CustomBrowseMenus::MenuHandler::SQLHandler->new($parameters);
	$parameters->{'sqlHandler'} = $sqlHandler;
	my %menuHandlers = (
		'function' => Plugins::CustomBrowseMenus::MenuHandler::FunctionMenu->new($parameters),
		'sql' => Plugins::CustomBrowseMenus::MenuHandler::SQLMenu->new($parameters),
		'trackdetails' => Plugins::CustomBrowseMenus::MenuHandler::TrackDetailsMenu->new($parameters),
		'mode' => Plugins::CustomBrowseMenus::MenuHandler::ModeMenu->new($parameters),
		'folder' => Plugins::CustomBrowseMenus::MenuHandler::FolderMenu->new($parameters)
	);
	my %playHandlers = (
		'sql' => Plugins::CustomBrowseMenus::MenuHandler::SQLPlay->new($parameters),
		'function' => Plugins::CustomBrowseMenus::MenuHandler::FunctionPlay->new($parameters),
		'functioncmd' => Plugins::CustomBrowseMenus::MenuHandler::FunctionCmdPlay->new($parameters),
		'clicmd' => Plugins::CustomBrowseMenus::MenuHandler::CLICmdPlay->new($parameters),
		'all' => Plugins::CustomBrowseMenus::MenuHandler::AllPlay->new($parameters),
	);
	$parameters->{'menuHandlers'} = \%menuHandlers;
	$parameters->{'playHandlers'} = \%playHandlers;
	my $self = $class->SUPER::new($parameters);

	return $self;
}

1;
