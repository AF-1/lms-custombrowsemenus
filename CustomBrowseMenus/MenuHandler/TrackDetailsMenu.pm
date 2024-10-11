# MenuHandler::TrackDetails
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

package Plugins::CustomBrowseMenus::MenuHandler::TrackDetailsMenu;

use strict;
use Plugins::CustomBrowseMenus::MenuHandler::BaseMenu;
our @ISA = qw(Plugins::CustomBrowseMenus::MenuHandler::BaseMenu);

use File::Spec::Functions qw(:ALL);

__PACKAGE__->mk_accessor( rw => qw(itemParameterHandler) );

sub new {
	my ($class, $parameters) = @_;

	my $self = $class->SUPER::new($parameters);
	$self->itemParameterHandler($parameters->{'itemParameterHandler'});

	return $self;
}

sub prepareMenu {
	my ($self, $client, $menu, $item, $option, $result, $context) = @_;

	my $keywords = $self->combineKeywords($menu->{'keywordparameters'}, undef, $item->{'parameters'});
	my @parameters = split(/\|/, $menu->{'menudata'});
	my $trackid = $keywords->{@parameters[0]};
	$trackid = $self->itemParameterHandler->replaceParameters($client, $trackid, $keywords, $context);
	my $track = Slim::Schema->resultset('Track')->find($trackid);
	if (defined($track)) {
		my %params = (
			'useMode' => 'trackinfo',
			'parameters' =>
			{
				'track' => $track
			}
		);
		if (scalar(@parameters) > 1) {
			if (@parameters[1]) {
				$params{'useMode'} ='PLUGIN.CustomBrowseMenus.trackinfo';
			}
			shift @parameters;
			shift @parameters;
			for my $p (@parameters) {
				if ($p =~ /^(.*?)=(.*)$/) {
					$params{'parameters'}{$1} = $self->itemParameterHandler->replaceParameters($client, $2, $keywords, $context);
				}
			}
		}
		return \%params;
	}
	return undef;
}
sub hasCustomUrl {
	return 1;
}

sub getCustomUrl {
	my ($self, $client, $item, $params, $parent, $context) = @_;

	my $keywords = $self->combineKeywords($item->{'menu'}->{'keywordparameters'}, undef, $item->{'parameters'});
	my @parameters = split(/\|/, $item->{'menu'}->{'menudata'});
	my $trackid = $keywords->{@parameters[0]};
	$trackid = $self->itemParameterHandler->replaceParameters($client, $trackid, $keywords, $context);

	my $id = $trackid;
	if (@parameters[1]) {
		return 'songinfo.html?item='.escape($id).'&player='.$params->{'player'};
	} else {
		my $track = undef;
		if (defined($item->{'itemobj'})) {
			$track = $item->{'itemobj'};
		} else {
			$track = Slim::Schema->resultset('Track')->find($id);
		}
		return 'plugins/CustomBrowseMenus/custombrowsemenus_contextlist.html?noitems=1&contextid='.escape($id).'&contexttype=track&contextname='.escape($track->title).(defined($params->{'player'})?'&player='.$params->{'player'}:'');
	}
}

sub getOverlay {
	my ($self, $client, $item) = @_;

	my @parameters = split(/\|/, $item->{'menudata'});
	if (scalar(@parameters) > 2 && @parameters[2]) {
		return $client->symbols('rightarrow');
	}
	return undef;
}

*escape = \&URI::Escape::uri_escape_utf8;

1;
