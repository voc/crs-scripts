#!/usr/bin/perl -W

require POSIX;
require CRS::Fuse::VDV;
require C3TT::Client;

# Call this script with secret and project slug as parameter!

my ($secret, $project, $token) = ($ENV{'CRS_SECRET'}, $ENV{'CRS_SLUG'}, $ENV{'CRS_TOKEN'});

if (!defined($project)) {
	# print usage
	print STDERR "Too few parameters given!\nUsage:\n\n";
	print STDERR "./script-.... <secret> <project slug>\n\n";
	exit 1;
}

# default padding of record start and stop:
my $startpadding = 300;
my $endpadding = 900;

#######################################

$|=1;

my $tracker = C3TT::Client->new('https://tracker.fem.tu-ilmenau.de/rpc', $token, $secret);
#$tracker->setCurrentProject($project);

foreach ('scheduled', 'recording') {
	my $state = $_;
	print "querying tickets in state $state ...";
	my $tickets = $tracker->getUnassignedTicketsInState($state);
	print "\n";
	if (!($tickets) || 0 == scalar(@$tickets)) {
		print "no tickets currently $state.\n";
		next;
	}
	print "found " . scalar(@$tickets) ." tickets\n";
	foreach (@$tickets) {
		my %ticket = %$_;
		my $tid = $ticket{'id'};
		if (defined($tid) && $tid > 0) {
			print "inspecting ticket # $tid .";

			# fetch metadata

			my $props = $tracker->getTicketProperties($tid);
			my $cur_endpadding = $endpadding;
			if (defined($props->{'Record.EndPadding'})) {$cur_endpadding = $props->{'Record.EndPadding'}; }
			my $startdate = $props->{'Fahrplan.Date'};
			my $starttime = $props->{'Fahrplan.Start'};
			my $duration = $props->{'Fahrplan.Duration'};

			# check minimal metadata

			if (!defined($startdate) || !defined($duration) || !defined($starttime)) {
				print STDERR "NOT ENOUGH METADATA! (ticket# $tid)\n";
				next;
			}


			# transformation of metadata

			print ".";
			my $start = $startdate . '-' . $starttime; # put date and time together
			my ($paddedstart, $paddedend, undef) = CRS::Fuse::getPaddedTimes($start, $duration, $startpadding, $cur_endpadding);
			my $now = POSIX::strftime('%Y.%m.%d-%H_%M_%S', localtime());

			print ".\n";

			# evaluation

			if ((($state eq 'scheduled') and ($now gt $paddedstart)) or
				(($state eq 'recording') and ($now gt $paddedend))) {
				print "moving ticket # $tid from state $state to next state ...";
				$tracker->setTicketNextState($tid, $state, 'Recording Scheduler: ' .
					"the current time is over schedule for state $state.");
				print "\n";
			}
		}
	}
}
