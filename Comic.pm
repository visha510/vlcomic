package Comic;


use strict;
use warnings;
use vars qw( $VERSION );

use URI;
use LWP::Simple qw(get);
use HTTP::Cookies;
use HTML::TreeBuilder;
use HTML::TreeBuilder::XPath;

use Cwd;
use feature qw ( say );

$VERSION = 1.00;

#Globals
my %handler_phases = (
#		'request_preprepare' => \&cbrequest_preprepare,
#		'request_prepare' => \&cbrequest_prepare,
#		'request_send' =>\&cbrequest_send,
#		'response_header' => \&cbresponse_header,
		'response_data' => \&_cbresponse_data,
#		'response_done' => \&cbresponse_done,
#		'response_redirect' => \&cbresponse_redirect
	  );
my %imgtypes = ( "image/png" => "png",
				 "image/jpeg" => "jpg",
				 "image/gif" => "gif",
				 "image/x-ms-bmp" => "bmp",
				 "text/plain" => "txt",
				 "image/svg+xml" => "svg" );
#------------------------------------------------------------------------------
# Function				new( _ua, _genresListPage )
#
# Purpose				INTERFACE FUNCTION
#						Create a new object; initialize the attributes
#
#
# Argument List			$_[0]	: auto-supplied by PERL
#						$_[1]	: URL to page having genres listed
#
# Return				reference to Comic object
#
#------------------------------------------------------------------------------
sub new
{
	_showCallstack((caller(0))[3],@_);
	my ($class, $arg) = @_;

	my $objref = {
					_ua=>$_[1],
					_genresListPage=> $_[2],
					_pageDepth=>2
				 };
	bless $objref, $class;
	return $objref;
}
#bad url : missing images
#http://vlcomic.com/read/comic-crossed-family-values-eng/1
#Fables
#http://vlcomic.com/read/comic-fables-eng/140

#------------------------------------------------------------------------------
# Function				persistBookURLs( $fname, $gNo, $listEditions, @genres )
#
# Purpose				INTERFACE FUNCTION
#						Save list of urls to books for each of the genres to a 
#						text file with given name
#
# Argument List			$_[0]			: reference to self auto-spplied by PERL
#						$fname			: name of the text file to save to
#						$gNo			: genre no. to persist; if this is 0
#										  all genres are saved
#						$listEditions	: editions enumerted if this is not 0
#						@genres			: array of urls to genres
#
# Return				nothing
#
#------------------------------------------------------------------------------
sub persistBookURLs
{
	_showCallstack( (caller(0))[3], ($_[1],$_[2],$_[3]),\$_[4] );
	my ( $self, $fname, $genreNumber, $listEditions, @genres  ) = @_;
	
	my $ub = $genreNumber ? $genreNumber : $#genres;
	my $lb = $genreNumber ? $genreNumber : 0;

	my $fh;
	if ( open( $fh, '>', $fname ) ){
		for my $i($lb..$ub)
		{
			my $genre = $genres[$i];
			my ($genreName) = ( $genre =~ /.*\/(.*)$/);
			$genreName =~ s/%20/ /g;
			my @booknames;
			my @genreBooks = _getGenreBooksInternal( $self->{_ua}, 
													 $genre, 
													 \@booknames, 
													 $self->{_pageDepth} );
			next unless($#genreBooks+1);
			print "[[$genreName]: writing ". (scalar @genreBooks) . " book entries]\n";
			print $fh "<genre name=\"$genreName\" ";
			print $fh "count=\"". ($#genreBooks+1) . "\">\n";
			foreach my $book ( @genreBooks ) {
					print $fh "\t<book url=\"" . $book ."\">\n";
					if ( $listEditions ){
						my @editions = _getBookEditions( $self->{_ua}, $book );
						foreach my $ed(@editions)
						{
							print $fh "\t\t<edition href=\"" . $ed->attr('href');
							print $fh "\">";
							print $fh $ed->content()->[0] if( $ed->content() );
							print $fh "</edition>\n";
						}
					}
					print $fh "\t</book>\n";
			}
			print $fh "</genre>\n";
		}
		
		close ($fh) if ($fh);
	} else {
		print "Error opening $fname for write\n";
		return;
	}
}

#------------------------------------------------------------------------------
# Function				getBookEditions( $book )
#
# Purpose				INTERFACE FUNCTION
#						Obtain list of editions of a book
#
# Argument List			$_[0]		: reference to self auto-spplied by PERL
#						$book		: URL to a book
#
# Return				array containing node elements of editions
#
#------------------------------------------------------------------------------
sub getBookEditions
{
	_showCallstack((caller(0))[3],@_);
	my( $self, $book ) = @_;
	
	my @editions = _getBookEditions( $self->{ _ua}, $book );
	return @editions;
}

#------------------------------------------------------------------------------
# Function				_getBookEditions( $ua, $book, $xpath )
#
# Purpose				INTERNAL FUNCTION
#						Obtain list of editions of a book
#
# Argument List			$ua			: reference to self auto-spplied by PERL
#						$book		: URL to a book
#						$xpath		: xpath to select editions
#
# Return				array containing node elements of editions
#
#------------------------------------------------------------------------------
sub _getBookEditions
{
	_showCallstack((caller(0))[3],@_);
	my ( $ua, $book ) = @_;

	my $xpath = '//ul[@class=\'basic-list\']/li/a[@class=\'ch-name\']';#vlcomic specific
	return _getSomeNodes( $ua, $book, $xpath );
}

#------------------------------------------------------------------------------
# Function				getGenreBooks( $genre, $booknames )
#
# Purpose				INTERFACE FUNCTION
#						Obtain array of URLs of all books for a given genre
#						upto the _pageDepth pages
#
# Argument List			$_[0]		: reference to self auto-spplied by PERL
#						$genre		: URL to a genre
#						$booknames	: reference to an array that will be filled
#									  up with the book's actual name
#
# Return				array containing URLs of all books upto a set pageDepth
#						for a given genre
#
#------------------------------------------------------------------------------
sub getGenreBooks
{
	_showCallstack((caller(0))[3],@_);
	my ( $self, $genre, $booknames ) = @_;

	@$booknames = ();
	return _getGenreBooksInternal(  $self->{ _ua}, 
									$genre, 
									$booknames, 
									$self->{_pageDepth} );
}

#------------------------------------------------------------------------------
# Function				_getGenreBooksInternal
#						( $ua, $genre, $booknames, $pageDepth )
#
# Purpose				INTERNAL FUNCTION
#						Obtain array of URLs of all books for a given genre
#						upto the _pageDepth pages
#
# Argument List			$genre		: URL to a genre
#						$booknames	: reference to an array that will be filled
#									  up with the book's actual name
#						$pageDepth	: maximum no. of pages of a genre to lookup
#
# Return				array containing URLs of all books for the genre upto
#						the set page depth for the genre
#
#------------------------------------------------------------------------------
sub _getGenreBooksInternal
{
	_showCallstack((caller(0))[3],@_);
	my ( $ua, $genre, $booknames, $pageDepth ) = @_;

	my @allbooksforpage;
	for( 1..$pageDepth )
	{
		my $genpage = $genre . '/' . $_;
		my @pagebooks = _genrePageBooks( $ua, $genpage, $booknames );
		push @allbooksforpage, @pagebooks;
		last unless ($#pagebooks+1);
	}
	return @allbooksforpage;
}
#------------------------------------------------------------------------------
# Function				_genrePageBooks( $ua, $genpage, $booknames )
#
# Purpose				INTERNAL FUNCTION
#						Obtain array of URLs of all books for a given page number
#						of a genre
#
# Argument List			$ua			: reference to a UserAgent object
#						$genpage	: URL to a page of a genre
#						$booknames	: reference to an array that will be filled
#									  up with the book's actual name
#
# Return				array containing URLs of all books for given page
#
#------------------------------------------------------------------------------
sub _genrePageBooks
{
	_showCallstack((caller(0))[3],@_);
	my ( $ua, $genpage, $booknames ) = @_;

	my $xpath = '//a[@class=\'igb-image\']';#vlcomic specific
	my @nodes = _getSomeNodes(	$ua, $genpage, $xpath );

	return () unless($#nodes+1);
	
	my ( $bookurl, @books );
	foreach my $node (@nodes)
	{
		$bookurl = $node->attr('href');
		my $uri = URI->new($bookurl);
		if ( $bookurl !~ /^http/ ) {
			$uri  = URI->new_abs($bookurl, $genpage);
		}
		push @books, $uri;
		push @$booknames, $node->attr('title') if ($booknames);
	}
	return @books;
}

#------------------------------------------------------------------------------
# Function				getGenreLinks
#
# Purpose				INTERFACE FUNCTION
#						Get list of all genres listed in the page pointed by the 
#						URL	contained in the _genresListPage attribute
#
# Argument List			$_[0]		: reference to self auto-spplied by PERL
#
# Return				array of URLs of all genres for _genresListPage
#
#------------------------------------------------------------------------------
sub getGenreLinks
{
	_showCallstack((caller(0))[3],@_);
	my ( $self )  = @_;
	
	#vlcomic specific
	my $xpath = '//ul[@class=\'lf-list\']/li/a[contains(@href, \'list-comic\')]';
	my @nodes = _getSomeNodes( $self->{ _ua}, 
							   $self->{_genresListPage}, $xpath );
	my ( $url, @genres );
	foreach my $node (@nodes)
	{
		$url = $node->attr('href');
		my $uri = URI->new($url);
		if ( $url !~ /^http/ ) {
			$uri  = URI->new_abs($url, $self->{_genresListPage});
		}
		push @genres, $uri;
	}
	return @genres;
}

#------------------------------------------------------------------------------
# Function				saveURLBook( $bookurl )
#
# Purpose				INTERFACE FUNCTION
#						For a given URL save all pictures in it to appropriate
#						relative folders
#
# Argument List			$bookurl	: URL to a page( e.g. to a comic book )
#
# Return				nothing
#
#------------------------------------------------------------------------------
sub saveURLBook
{
	_showCallstack((caller(0))[3],@_);
	my ($self,$bookurl) = @_;

	my $curdir = getcwd;

	my $uri = URI->new( $bookurl );
	_setCookieJar( $curdir, $uri, $self->{ _ua} );

	my $xpath = '//div[@class=\'comics\']/img';#vlcomic specific
	my @imagenodes = _getSomeNodes( $self->{ _ua}, $bookurl, $xpath );

	$self->{_ua}->remove_handler();
	foreach my $handler_name ( keys %handler_phases ) {
		$self->{_ua}->add_handler( $handler_name => $handler_phases{$handler_name} );
	}
	foreach my $url_count ( 0..$#imagenodes ) {
		my $stat_text = "[" . ($url_count+1) . " of " . (scalar @imagenodes) . "]";
		my $stat1 = chr(178) x ( $url_count + 1 );
		my $stat2 = chr(176) x ( (scalar @imagenodes) - $url_count - 1 );
		my $status_bar = $stat1 . $stat2;
		print "\n$stat_text\n";
		print "$status_bar\n";
		_saveImageFromLink( $self->{_ua}, $curdir, $imagenodes[$url_count]->{src}, $uri  );
	}
	$self->{_ua}->remove_handler();
}

#------------------------------------------------------------------------------
# Function				_saveImageFromLink( $ua, $curdir, $url, $srcuri )
#
# Purpose				INTERNAL FUNCTION
#						Callback function when user agent makes a get call to 
#						the remote http/https server
#
# Argument List			$ua			: user agent object
#						$curdir		: directory in which script is executing
#						$url		: url of the file being downloaded
#						$srcuri		: URI object for URL to the book
#
# Return				nothing
#
#------------------------------------------------------------------------------
sub _saveImageFromLink
{
	_showCallstack((caller(0))[3],@_);
	my ( $ua, $curdir, $url, $srcuri ) = @_;

	our $path_extended = $curdir;
	our $fileBytesDowned = 0;
	our $fh;
	our $savefilename = '';
	my @subdirs = ();
	my $path_level;

	my $srcurl = "$srcuri";
	if ( $url !~ /^http/ ) {
		$url  = URI->new_abs($url, $srcurl);
	}
	my $uri = URI->new($url);

	my @srcurlsplit = _getSplitUrl( $srcuri );
	unshift( @subdirs, @srcurlsplit );

	foreach $path_level ( @subdirs ) {
		if ( $path_level ) {
			$path_extended .= "/" . $path_level;
			if ( not( -e $path_extended and -d $path_extended ) ) {
				print "creating " . $path_extended . "\n";
				mkdir $path_extended;
				if ( not( -e $path_extended and -d $path_extended ) ) {
					say "Error creating $path_extended";
					return;
				}
			}
		}
	}

	my $response = $ua->get( $uri );
	if ( $fh ) {
		close $fh;
	}
}

#------------------------------------------------------------------------------
# Function				_cbresponse_data( $response, $ua, $handler, $data )
#
# Purpose				INTERNAL FUNCTION
#						Callback function when user agent makes a get call to 
#						the remote http/https server
#
# Argument List			$response	: response object
#						$ua			: user agent object
#						$handler	: what the hell is this!
#						$data		: data received from the server
#
# Return				1 if no error occurred else terminate abruptly
#
#------------------------------------------------------------------------------
sub _cbresponse_data
{
	my ( $response, $ua, $handler, $data ) = @_;
	
	return undef unless ( $response->is_success );

	our $fh;
	our $savefilename;
	our $path_extended;

	if ( not $savefilename ) {
		$savefilename = _getFilenameFromResponse($response, $data );
		$savefilename = $path_extended . '/' . $savefilename;
		print "Saving... $savefilename\n\n";
		if ( -e $savefilename ) {
			return undef;
		}
		open($fh, '>', $savefilename) || die "error opening $savefilename for W\n";
		binmode $fh;
	}
	#print "*";
	print $fh $data;
	return 1;
}

#------------------------------------------------------------------------------
# Function				_getFilenameFromResponse( $response, $data )
#
# Purpose				INTERNAL FUNCTION
#						Try to get a filename for the file being downloaded
#						from the response data or make one up based on time
#
# Argument List			$response	: response object
#						$data		: data received from the server
#
# Return				filename of the file being downloaded
#
#------------------------------------------------------------------------------
sub _getFilenameFromResponse
{
	my ( $response, $data ) = @_;

	my $savefilename;
	if ( defined $response->filename() ) {
		$savefilename = $response->filename();
	} else {
		$savefilename = strftime("%Y-%m-%d_%H%M%S", localtime);
	}
	
	my ($ext_resfile) = $savefilename =~ /\.(\w\w+)$/;
	my $exts = join('-', values %imgtypes );
	if ( (not $ext_resfile) or ( $exts !~ /$ext_resfile/ ) )
	{
		my $ext_exp = $imgtypes{$response->{"_headers"}->{"content-type"}};
		if ( $exts =~ /$ext_exp/ ) {
			$savefilename .= '.' . $ext_exp;
		} else {
			my $dig_ext;
			$dig_ext = 'gif' if ( $data =~ /^GIF/ );
			$dig_ext = 'png' if ( $data =~ /^.PNG/ );
			$savefilename .= '.' . $dig_ext;
		}
	}
	return $savefilename;
}
#------------------------------------------------------------------------------
# Function				_getSomeNodes( $ua, $url, $xpath )
#
# Purpose				INTERNAL FUNCTION
#						Get list of elements that satify a particular criterion 
#						in the html of a given URL
#
# Argument List			$ua			: reference to a UserAgent object
#						$url		: some url in which to lookup $xpath
#						$xpath		: xpath criterion
#
# Return				array of URLs of all elements meeting xpath criterion
#
#------------------------------------------------------------------------------
sub _getSomeNodes
{
	_showCallstack((caller(0))[3],@_);
	my ( $ua, $url, $xpath ) = @_;

	my $uri = URI->new( $url );
	my $response = $ua->get( $uri );
	if ( not $response->is_success ) {
		print $response->status_line . "\n";
		print "GET: $url unsucessful\n";
		return ();
	}
	my $troot = HTML::TreeBuilder->new_from_content( $response->content );
	my @nodes = $troot->findnodes( $xpath );
	print "[returning " . ($#nodes+1) . " elements]\n\n";
	return @nodes;
}

#------------------------------------------------------------------------------
# Function				listGenres( $self, $cols, @genres )
#
# Purpose				INTERFACE FUNCTION
#						Neatly list all genres in specified number of columsn
#						on the console
#
# Argument List			$_[0]		: reference to self auto-spplied by PERL
#						$cols		: number of colums to use in display
#						@genres		: array having URLs to genres
#
# Return				nothing
#
#------------------------------------------------------------------------------
sub listGenres
{
	_showCallstack((caller(0))[3],@_);
	my ( $self, $cols, @genres ) = @_;

	_prettyPrintList( $cols, @genres );
}

#------------------------------------------------------------------------------
# Function				listGenres( $cols, @someList )
#
# Purpose				INTERNAL FUNCTION
#						Neatly list all elements of a given list in specified 
#						number of columsn on the console
#
# Argument List			$cols		: no. of columns to use
#						@someList	: an array
#
# Return				nothing
#
#------------------------------------------------------------------------------
sub _prettyPrintList
{
	my ( $cols, @someList ) = @_;

	my $total = $#someList + 1;
	my $rows = int($total/$cols);
	my $tofill = ($cols - $total % $cols) % $cols;

	if ( $tofill ) {
		for my $k(1..$tofill)
		{
			$someList[$total-1+$k] = '';
		}
		$total = $#someList + 1;
		$rows = int($total/$cols);
		my $tofill = ($cols - $total % $cols) % $cols;
	}
	for my $k(0..$rows-1)
	{
		my $fmtstr = '';
		for my $j(0..$cols-1) {
			my $elemnum = $k*$cols+$j;
			my ($c) = ( $someList[$elemnum] =~ /.*\/(.*)/);
			if ( $c ) {
				$c =~ s/%20/ /g;
				my $colstr = sprintf "(%2d)%-20s", $elemnum+1, $c ;
				$fmtstr .= $colstr;
			}
		}
		print $fmtstr . "\n";
	}
}

#------------------------------------------------------------------------------
# Function				setPageDepth( $depth )
#
# Purpose				INTERFACE FUNCTION
#						Set the value of the _pageDepth attibute
#
# Argument List			$_[0]	: reference to self auto-spplied by PERL
#						$depth	: integer value indicating page depth to be
#								  used when enumerating books in a genre
#
# Return				previous value of _pageDepth attribte
#
#------------------------------------------------------------------------------
sub setPageDepth
{
	my ($self, $depth) = @_;
	my ($prevDepth) = $self->{_pageDepth};
	$self->{_pageDepth} = $depth;
	return $prevDepth;
}

#------------------------------------------------------------------------------
# Function				_getSplitUrl( $ua, $url, $xpath )
#
# Purpose				INTERNAL FUNCTION
#						Split a url for use in creating folder structure
#
# Argument List			$uri	: Any URI ( e.g. of a comic book page )
#
# Return				array of components of the URL thus split 
#
#------------------------------------------------------------------------------
sub _getSplitUrl
{
	my ( $uri ) = @_;
	#_showCallstack((caller(0))[3],@_);

	my @subdirs = split( /\//, $uri->path() );
	shift(@subdirs);
	unshift(@subdirs,$uri->host());
	s/(.{1,32}).*/$1/ foreach @subdirs;
	return @subdirs;
}

#------------------------------------------------------------------------------
# Function				_setCookieJar( $ua, $url, $xpath )
#
# Purpose				INTERNAL FUNCTION
#						Set cookie for the site currently being processed
#
# Argument List			$curdir	: any URI ( e.g. of a comic book page )
#						$uri	: URI for the page (e.g. of a book )
#						$ua		: user agent
#
# Return				nothing
#
#------------------------------------------------------------------------------
sub _setCookieJar
{
	_showCallstack((caller(0))[3],@_);
	my ( $curdir, $uri, $ua ) = @_;

	my $hostname =  $uri->host();
	$hostname =~ s/\.//g;
	my $cookie_jar = HTTP::Cookies->new( file => "$curdir/$hostname" , autosave => 1);
	$ua->cookie_jar( $cookie_jar );
}

#------------------------------------------------------------------------------
# Function				_showCallstack( $subname, @subargs  )
#
# Purpose				INTERNAL FUNCTION
#						Display called function and it arguments for debuggin
#						purposes
#
# Argument List			$subname : name of the subroutine executing
#						@subargs : list of arguments passed to the subroutine
#
# Return				nothing
#
#------------------------------------------------------------------------------
sub _showCallstack
{
	my ( $subname, @subargs ) = @_;
	my $subnamex = (caller(0))[3];
	
	my @callers;
	my $c = 1;
	while($subnamex){
		$subnamex =~ s/(\w+::)//;
		unshift (@callers, $subnamex);
		$subnamex = (caller($c))[3];
		$c++;
	}

	pop @callers;
	print $_ . '=>' foreach @callers;
	#print "\n";

	print "(" . join(",", @subargs) . ")\n";
}

#------------------------------------------------------------------------------
# Functions below will not be used in the eventual version of the module and 
# are INTENDED TO BE DELETED. These are here only for experimental reasons
#------------------------------------------------------------------------------
sub import
{
	
}
1;