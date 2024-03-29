#!/usr/bin/env perl
use 5.016;
use warnings;

use Cwd qw(realpath);
use File::Spec::Functions qw(catfile splitpath updir);
use Unicode::UCD qw(prop_aliases);

my (%MA, %WS);

# TODO: fetch the data files on-demand and don't store them.
# http://www.unicode.org/Public/security/latest/confusables.txt
# http://www.unicode.org/Public/security/latest/confusablesWholeScript.txt

parse_confusable_file();
parse_ws_confusable_file();
write_file();

exit;


sub parse_confusable_file {
    my $file = catfile(
        (splitpath(realpath __FILE__))[0, 1], updir,
        qw(data confusables.txt)
    );
    open my $fh, '<', $file or die "$file: $!";
    while (<$fh>) {
        my ($source, $target) = /^([0-9A-F]+) ;\t((?:[0-9A-F]+ )+);\tMA\t/;
        next unless defined $source and defined $target;
        $target =~ s{([0-9A-F]+) }{ '\x{' . $1 . '}' }eg;
        $MA{ '\x{' . $source . '}' } = $target;
    }
    close $fh;

    die "$file: no confusables found" unless %MA;
}


sub parse_ws_confusable_file {
    my $file = catfile(
        (splitpath(realpath __FILE__))[0, 1], updir,
        qw(data confusablesWholeScript.txt)
    );
    open my $fh, '<', $file or die "$file: $!";
    while (<$fh>) {
        my ($lo, $hi, $source, $target) = m{
            ^ ([0-9A-F]+) (?:\.\. ([0-9A-F]+) )? \ +;\ (\w+);\ (\w+);\ A\ \#
        }x;
        next unless defined $source;

        for ($source, $target) {
            my @alias = prop_aliases($_) or die "unknown script: $_" ;
            $_ = $alias[1];
        }
        $hi //= $lo;

        $WS{$source}{$target}{sprintf "%04X", $_} = \1
            for hex $lo .. hex $hi;
    }
    close $fh;

    die "$file: no confusables found" unless %WS;
}


sub write_file {
    my $file = catfile(
        (splitpath(realpath __FILE__))[0, 1], updir,
        qw(lib Unicode Security Confusables.pm)
    );

    open my $fh, '>', $file or die "$file: $!";
    (my $header =<< "    __HEADER__") =~ s/^ +//gm;
        use strict;
        use warnings;

        =pod This data is auto-generated by scripts/generate-map.pl

        =cut

        %Unicode::Security::MA = (
    __HEADER__
    print $fh $header;

    for my $source (sort keys %MA) {
        printf $fh qq(    "%s" => "%s",\n), $source, $MA{$source};
    }
    print $fh ");\n";

    # TODO: compress the lists by converting to character ranges.
    print $fh qq<\n\%Unicode::Security::WS = (\n>;
    for my $source (sort keys %WS) {
        print $fh qq(    '$source' => {\n);
        for my $target (sort keys %{$WS{$source}}) {
            printf $fh qq(        '%s' => { map { \$_ => \\1 } %s },\n),
                $target,
                join ', ', map { qq("\\x{$_}") }
                    sort keys %{$WS{$source}{$target}};
        }
        print $fh qq(    },\n);
    }

    print $fh ");\n\n1;";
    close $fh;
}
