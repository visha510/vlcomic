use Comic;
use strict;
use warnings;
use Data::Dumper;
use POSIX qw( strftime );
use feature qw(say);# current_sub);


my $choice;

#(1)-----SETUP COMIC OBJECT----------------------------------------------------
my $CapableBrowser = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/78.0.3904.108 Safari/537.36';
my $ua = LWP::UserAgent->new;
$ua->agent($CapableBrowser);

my $comic = Comic->new( $ua, 'http://vlcomic.com/list-comic/' );
$comic->setPageDepth(5);


#(2)-----SAVE A SAMPLE BOOK----------------------------------------------------
my @bks = getBookListToDownload();
say for( @bks );
say (scalar @bks);
sub{ $comic->saveURLBook( $_ ); say "\n\nCOMPLETED\nNEXT BOOK \n\n"; }->() for( @bks );
print "\a";
die "\nsaveURLBook(...) completed\n";

sub getBookListToDownload
{
	my @ix;
	my @bks = ();
	if ( ( ( scalar @ARGV ) == 2 ) &&  
		   ( $ARGV[0] =~ /http:\/\/vlcomic\.com\/read\// ) &&  
		   ( $ARGV[1] =~ /^(\d+)\.\.(\d+)$/ ) ) {
		@ix = eval( $ARGV[1] );
		push ( @bks, $ARGV[0] . '/' . $_ ) for( @ix );
		return @bks
	}
	print "\n\ncorrect usage is as follows\n";
	print "client.pl [specific vlcomic URL] [start index]..[end index]\n\n\n";
	die;
}

#(3)-----GET URL ARRAY OF GENRES-----------------------------------------------
my @genres = $comic->getGenreLinks();
die "failed requesting genres list. aborting\n" unless ($#genres);

#(4)-----GET EDITIONS OF A BOOK------------------------------------------------
my @editions = $comic->getBookEditions( "http://vlcomic.com/read/comic-w-i-t-c-h-eng" );
say $_->content()->[0] . " " . $_->attr('href') foreach @editions;
say "Total of " . ($#editions+1) . " books";
die "done with getBookEditions() test\n";

#(5)-----SAVE ALL GENRE URLS TO FILE-------------------------------------------
$choice = getListChoice( $comic, @genres );

my $vlcomic_log = "vlcomic-" . strftime("%Y-%m-%d_%H%M%S", localtime) . ".txt";
$comic->persistBookURLs( $vlcomic_log, $choice, 0, @genres );
die "Intentional since we are done";

#(6)-----ASK USER A GENRE TO CHOOSE & LIST ALL BOOKS TO THE SET DEPTH----------
$choice = getListChoice( $comic, @genres );

my @booknames;
my @genreBooks = $comic->getGenreBooks( $genres[$choice], \@booknames );
say foreach(@booknames);
undef @booknames;
die;

#(7) Having selected a genre, select a page from that genre


#(8)Having selected a page from a genre, select a book

#(9)Having selected a book choose whether to down a book

#------------------------------------------------------------------------------
# Function				getListChoice
#
# Purpose				show columnwise numbered list of all genre names;
#						ask for	user choice of genre as a number
#
# Argument List			$comic	: reference to Comic object
#						@list	: array of urls of all list
#
# Return				zero based index of genre chosen by the user
#
#------------------------------------------------------------------------------
sub getListChoice
{
	my ( $comic, @list ) = @_;

	my $choice = -1;
	while( $choice < 1 || $choice > $#list+1 )
	{
		#say "" for(0..20);
		say "*" x 20;
		$comic->listGenres( 5, @list );
		print "Enter your choice: ";
		$choice = <STDIN>;
		chomp($choice);
	}
	return $choice-1;
}