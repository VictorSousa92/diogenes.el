#!/usr/bin/env perl
# Every author and work Diogenes actually holds, one per line:
#
#     tlg 0086 025
#
# The authority that matters.  The Perseus catalogue covers 1627 authors where
# the TLG alone has 1823, so a number absent from IT proves nothing -- Epictetus,
# Philo and Hermogenes are all absent and all real.  Diogenes reads the .idt
# files of the databases themselves, and what is not there is not there.
#
# `phi 0012' is the case that wanted settling: Lewis & Short cites it once,
# meaning Homer, whose number that is in the TLG and not the PHI.  Diogenes
# answers nil for it.
#
# Run from the Diogenes server directory:
#
#   cd /usr/local/diogenes/server
#   perl -I/usr/local/diogenes/dependencies/CPAN -I. \
#        tools/list-diogenes-works.pl > /tmp/diogenes-works.txt

use strict;
use warnings;
use Diogenes::Base;

for my $type (qw(tlg phi)) {
    my $diogenes = Diogenes::Base->new(type => $type);
    my $dir = $type eq 'tlg' ? $diogenes->{tlg_dir} : $diogenes->{phi_dir};
    opendir(my $handle, $dir) or do {
        warn "cannot open $dir: $!\n";
        next;
    };
    my @numbers = sort map { /^[A-Z]+(\d{4})\.IDT$/i ? $1 : () } readdir($handle);
    closedir $handle;
    warn "$type: " . scalar(@numbers) . " authors\n";

    for my $author (@numbers) {
        # parse_idt fills %work and %level_label for this author, and returns
        # early if it has already read them.
        eval { $diogenes->parse_idt($author) };
        next if $@;
        my $works = $Diogenes::Base::work{$type}{$author};
        next unless $works;
        for my $work (sort keys %$works) {
            print "$type $author $work\n";
        }
    }
}
