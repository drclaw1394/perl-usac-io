use strict;
use warnings;
use feature ":all";
use List::Util qw<max>;

my $input=$ARGV[0]//"results.txt";
#Analysis
die "Can not open results"
	unless open my $fh, "<", $input;
my %series;
my %domains;
my @sizes;
my %labels;
my $max_rate=0;
while(<$fh>){
	chomp;
	next unless $_;
	my ($label, $rate, $buffer_size)=split " ";
	$domains{$buffer_size}{$label}=$rate;
	$labels{$label}=1;	#make the label as seen
	$max_rate=$rate if $rate> $max_rate;
	#push $series{$label}->@*, {x=>$buffer_size, y=>$rate};
	#push @sizes, $buffer_size;
}

my @domains=sort {$a <=> $b} keys %domains;
my @labels=sort keys %labels;

sub raw{
	say "Raw Rates";
	say join " ", "Buffer",@labels;
	for my $dom(@domains){
		say join " ", $dom, map $_//0, $domains{$dom}->@{@labels};
	}
}
sub normalized_to_buffer {

	say "";
	say "Normalised to row";
	say join " ", "Buffer",@labels;
	
	for my $dom(@domains){
		next if $dom == 0;
		my @row=map  $_//0 , $domains{$dom}->@{@labels};
		
		my $max=max @row;
		
		say join " ", $dom, map $_/$max, @row;
	}
}
sub normalized_to_max {

	say "";
	say "Normalised to max: $max_rate";
	say join " ", "Buffer",@labels;
	for my $dom(@domains){
		my @row= map $_//0, $domains{$dom}->@{@labels};
		#@row=map $_//0, @row;
		
		say join " ", $dom, map $_/$max_rate, @row;
	}
}

raw;
normalized_to_buffer;
normalized_to_max;
