#!/bin/sh
# Prints which of the closed standard names in Sources/SiftCore/InitReceiverRuling.swift an installed
# SDK declares as an associated type, a type alias or a generic parameter, one per line, sorted. Re-run
# it after an Xcode or SDK update: its output must equal `sdkBoundNames` in that file.
#
# Usage:  sh Scripts/sdk-generic-names.sh
#
# Read: every *.swiftinterface under the macOS and iOS SDKs (`xcrun --sdk … --show-sdk-path`) and the
# toolchain's usr/lib/swift. A name has a hit where a line holds `associatedtype <Name>` or
# `typealias <Name>` (a protocol extension's or an open class's alias, SwiftUI's
# `typealias Data = Content.Data`, is in scope unwritten in every conformer or subclass), or where it is a
# parameter of the generic parameter clause that follows a declaration's name: `struct`, `class`,
# `enum`, `actor`, `protocol`, `typealias`, `macro`, `func` (an operator's too), `init` or
# `subscript`, the clause read with its nested brackets balanced and split at its top-level commas, a
# parameter's name being the identifier that opens it after an optional `each`. A name only used as a
# generic argument (`Range<Int>` in an inlinable body) is no hit, since that binds nothing.
#
# Exit:  0  the names are printed (none when no SDK declares any)
#        1  the closed list cannot be read from the source, or no interface file is found
set -eu

for VAR in $(env | sed -n 's/^\(GIT_[A-Za-z0-9_]*\)=.*/\1/p'); do
    unset "$VAR"
done

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$REPO/Sources/SiftCore/InitReceiverRuling.swift"
NAMES="$(perl -0ne 'print join("|", $1 =~ /"(\w+)"/g) if /standardNames: Set<String> = \[(.*?)\]/s' "$SOURCE")"
[ -n "$NAMES" ] || { echo "no standardNames list in $SOURCE" >&2; exit 1; }

TOOLCHAIN="$(dirname "$(dirname "$(xcrun --find swift)")")/lib/swift"
FILES="$(mktemp "${TMPDIR:-/tmp}/sdk-generic-names.XXXXXX")"
trap 'rm -f "$FILES"' EXIT
# The trailing slash makes find descend an SDK path that is itself a symlink (the versioned SDK name links to the bare one).
find "$(xcrun --sdk macosx --show-sdk-path)/" "$(xcrun --sdk iphoneos --show-sdk-path)/" "$TOOLCHAIN/" \
    -name '*.swiftinterface' -print0 > "$FILES"
[ -s "$FILES" ] || { echo "no .swiftinterface files found" >&2; exit 1; }

xargs -0 perl -ne '
    BEGIN { $names = qr/(?:'"$NAMES"')/; }
    $hit{$1} = 1 while /\b(?:associatedtype|typealias)\s+($names)\b/g;
    while (/\b(?:(?:struct|class|enum|actor|protocol|typealias|macro)\s+`?\w+`?|func\s+(?:`?\w+`?|[-+*\/%<>=!&|^~?.]+)|init[?!]?|subscript)\s*(<(?:[^<>]++|(?-1))*>)/g) {
        my $clause = substr($1, 1, -1);
        my ($depth, $start) = (0, 0);
        my @parameters;
        for my $i (0 .. length($clause)) {
            my $c = $i < length($clause) ? substr($clause, $i, 1) : ",";
            $depth++ if $c eq "<" || $c eq "(" || $c eq "[";
            $depth-- if $c eq ">" || $c eq ")" || $c eq "]";
            if ($c eq "," && $depth == 0) { push @parameters, substr($clause, $start, $i - $start); $start = $i + 1; }
        }
        for (@parameters) { $hit{$1} = 1 if /^\s*(?:each\s+)?($names)\b/; }
    }
    END { print "$_\n" for keys %hit; }
' < "$FILES" | sort -u
