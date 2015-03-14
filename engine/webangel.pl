#!/usr/local/bin/perl 

##################################################################################################################
# 
# File         : webangel.pl
# Description  : simple web crawler
# Original Date: ~2000
# Author       : simran@dn.gs
#
##################################################################################################################


require 5.002;
use Socket;
use FileHandle;
use POSIX;
use Carp;
use HTML::LinkExtor;
use URI::URL;
use DBI;


########################################################################################################################
# read in arguments and set up some global vars that need to exist for some options (eg. version)
#
#

$version = "1.31";

$databaseType = "Pg"; # postgres!

($cmd = $0) =~ s:(.*/)::g;
($startdir = $0) =~ s/$cmd$//g;
$configfile = "${startdir}../etc/webangel.conf";

while (@ARGV) {
  $arg = "$ARGV[0]";
  $nextarg = "$ARGV[1]";

  if ($arg =~ /^-about$/i) {
    &about();
    exit(0);
  }
  elsif ($arg =~ /^-version$/i) {
    print "Version: $version\n";
    exit(0);
  }
  elsif ($arg =~ /^-c$/i) {
    $configfile = "$nextarg";
    usage("Valid configfile not defined after -c switch : $!") if (! -f "$configfile");
    shift(@ARGV);
    shift(@ARGV);
    next;
  }
  elsif ($arg =~ /^-get_only$/i) {
    $get_only = "$nextarg";
    open(GET_ONLY, "$get_only") || usage("Could not open file $get_only: $!");
    @get_only_a = <GET_ONLY>;
    close(GET_ONLY);
    $get_only = 1;
    shift(@ARGV);
    shift(@ARGV);
    next;
  }
  elsif ($arg =~ /^-ps$/i) {
    $print_stats = "$nextarg";
    die "Must specify integer greater than 0 with -ps option" if (! $print_stats || $print_stats !~ /^\d+$/);
    shift(@ARGV);
    shift(@ARGV);
    next;
  }
  elsif ($arg =~ /^-v$/i) {
    $verbose = 1;
    shift(@ARGV);
    next;
  }
  elsif ($arg =~ /^-nofork$/i) {
    $nofork = 1;
    shift(@ARGV);
    next;
  }
  elsif ($arg =~ /^-s$/i) {
    $startaturl = "$nextarg";

    if ($startaturl !~ /^http:\/\/(.*)/ ) {
       &usage("Unknown options supplied with -s switch");
    }
    shift(@ARGV);
    shift(@ARGV);
    next;
  }
  else {
    print "\n\nArgument $arg not understood.\n";
    &usage();
  }
}

# check for 'unoptional' arguments, or 'conflicting' args... 

if ($get_only && $starturl) { &usage("Cannot have both -s and -get_only switches!"); }
if ($nofork && $print_stats) { &usage("Cannot have both -ps and -nofork switches!"); }

#
#
#
########################################################################################################################

########################################################################################################################
# forward declare subroutines
#
#

sub readconf;   		# reads configuration file
sub connectDB;			# connects to the database
sub strip;			# strips leading and trailing whitespaces
sub dblogmsg;			# logs messages about interaction with the db
sub weblogmsg;  		# logs activity about urls we are getting / parsing
sub Reaper;			# reaps zombie processes
sub usage;			# prints program usage
sub spawn;			# forks code
sub about;			# prints about program
sub alarmcall;			# gets called when alarms are trigerred
sub traverse;			# gets info about the url then traverses links within it!
sub checkTraverseValidity;	# checks if it is okay for us to traverse a url
sub inExcludeList;		# checks urls agains exclude patterns
sub inIncludeList;		# checks urls agains include patterns
sub getDepth;			# returns the 'depth' of a url
sub getLastVisitTime;		# returns the last time we visited a url
sub getLinks;			# extracts links from a page and returns them
sub getEmails;			# extracts email address from a page and returns them
sub getAtags;			# used as 'callback' to HTML::LinkExtor to get all the 'a' tags
sub getIMGtags;			# used as 'callback' to HTML::LinkExtor to get all the 'img' tags
sub getCookies;			# works out and returns the cookies a server sent
sub getServer;			# works out the server type
sub getUrlId;			# get the URL id from the DB (creates if url is not already in db)
sub getEmailId;			# get the Email id from the DB (creates if email is not already in db)
sub getServerId;		# get the Server id from the DB (creates if server is not already in db)
sub getData;			# gets data for a given url
sub establishConnection;	# establishes a connection to a remote host / port
sub getRandomUrl;		# returns a random url from the db
sub update_urltbl;		# updates the url table
sub update_servertbl;		# updates the server table
sub getTitle;			# works out the title of a page
sub update_urlreltbl;		# updates the url/link relationship table in the db
sub update_emailreltbl;		# updates the email relationship table in the db



#
#
#
########################################################################################################################


####################################################################################################################
# 'main' part! 
#
# Global variables read:
#
# Global variables created/modified:
#					$dbconn - connect to database!
#
#

$| = 1;

$proto = getprotobyname('tcp');

$SIG{CHLD} = \&Reaper;
$SIG{ALRM} = \&alarmcall;

&readconf();


# if -get_only option was used, then get only those urls and exit!
if ($get_only) { 
  $dbconn = &connectDB("$dbname");
  foreach $url (@get_only_a) {
    chomp($url);
    $url = strip("$url");
    print STDERR "Traversing url : $url\n";
    &traverse("$url");
  }
  exit;
}

# if no -s switch was given then get a random url entry from the db!
if (! $startaturl) { 
  $dbconn = &connectDB("$dbname");
  $startaturl = &getRandomUrl();
  $dbconn->disconnect;
  undef $dbconn;
}


if ($nofork) { 
  if (! $startaturl) {
      $dbconn = &connectDB("$dbname");
      $url = &getRandomUrl();
      &traverse("$url");
      exit;
  }
  else {
       $dbconn = &connectDB("$dbname");
       &traverse("$startaturl");
       exit;
  }
}
else { 
  # fork a few processes...
  for ($children = 1; $children <= $maxforks; $children++) {
    # print STDERR "Launching copy $children\n" if ($print_stats);
    print "Launching copy $children\n" if ($verbose);
    if (! $startaturl) {
      spawn sub { 
        $dbconn = &connectDB("$dbname");
        $url = &getRandomUrl();
        &traverse("$url");
        return 1;
      };
    }
    else {
      spawn sub {
         $dbconn = &connectDB("$dbname");
         &traverse("$startaturl");
         return 1;
      };
    }
    sleep ($maxforks + 5); 
    $startaturl = ""; # so that in the next for loop we get a random url from the db
  }
}

print "\n";

if ($print_stats) { 

  my $start_time = time;

  my ($num1, $num2, $num3, $num5, $num5, $result, $time_gone);

  my $dbconn = &connectDB("$dbname");
  my $query1 = "select count(*) from urltbl";
  my $query2 = "select count(*) from emailtbl";
  my $query3 = "select count(*) from servertbl";
  my $query4 = "select count(*) from urlreltbl";
  my $query5 = "select count(*) from emailreltbl";

  while ($print_stats) { 
  
   $result = $dbconn->exec("$query1");
   ($num1  = $result->fetchrow) =~ s///g;
   $result = $dbconn->exec("$query2");
   ($num2  = $result->fetchrow) =~ s///g;
   $result = $dbconn->exec("$query3");
   ($num3  = $result->fetchrow) =~ s///g;
   $result = $dbconn->exec("$query4");
   ($num4  = $result->fetchrow) =~ s///g;
   $result = $dbconn->exec("$query5");
   ($num5  = $result->fetchrow) =~ s///g;
 
   $time_gone = time - $start_time;
   # print "URLTBL=$num1 EMAILTBL=$num2 SERVERTBL=$num3 URLRELTBL=$num4 EMAILRELTBL=$num5 (num seconds: $time_gone)\r";
   print "URLTBL=$num1 EMAILTBL=$num2 SERVERTBL=$num3 URLRELTBL=$num4 EMAILRELTBL=$num5 (num seconds: $time_gone)\n";

   sleep $print_stats;
  }
}

#
#
#
####################################################################################################################









####################################################################################################################
# readconf
# 
# Input: 
#
# Output: 
#
# Global variables read:
#			$configfile	- configuration file
#
# Global variables created/modified: 
#			$connection_timeout   - number of seconds we should timeout after if there is no connection established
#			$data_timeout         - number of seconds we should timeout after if there has been no data received
#			$expired_after        - consider a URL "expired" if it is older than
#			$maxdepth             - maximum depth we should go into the server
#			$maxforks             - maximum number of child process we are allowed to create
#			$proxy                - set to "1" if proxy was defined in config file
#			$proxyhost            - proxy host (if proxy line was defined)
#			$proxyport            - proxy port (if proxy line was defined)
#			%exclude              - "keys" contain patterns we should not get info for
#			  $exclude{"$ptrn"}   - ... (has higher precedence than include)
#			%include              - "keys" contain patterns. If url does not match one of the patterns in 
#					      - in %include then ignore it!  
#			  $include{"$ptrn"}   - ... (has lower precedence than exclude)
#			$weblog               - log file name (if defined opens file for writing as WEBLOG filehandle)
#			  WEBLOG	      - ... 
#			$dblog                - log file name (if defined opens file for writing as DBLOG  filehandle)
#			  DBLOG		      - ... 
#			$dbname               - the database name
#			$emailreltbl	      - = 1 if we want to store the email relation table!
#			$urlreltbl	      - = 1 if we want to store the url/link relation table!
#			$exclude_list	      - The number of elements in '%exclude'
#			$include_list	      - The number of elements in '%include'
#			
#
sub readconf {

  my (@conffile, $tag, $confline, $conffile_linenum, $rest);

  open(CONFFILE, "$configfile") || &usage("Could not open $configfile : $!");
  @conffile = <CONFFILE>;
  close(CONFFILE);

  $confile_linenum = 1;
  while(@conffile) {
    $confline = shift(@conffile);
    chomp($confline);
    if ($confline =~ /^[\s\t]*#/i) { $conffile_linenum++; next; }    # ignore comment lines
    if ($confline =~ /^[\s\t]*$/i) { $conffile_linenum++; next; }    # ignore blank lines

    $confline =~ s/#.*$//g; # remote comments bits after the '#' symbol in conffile

    $conffile_linenum++;

    # handle 'proxy' line
    if ($confline =~ /^proxy:/i) {
      ($tag, $rest) = split(/:/,"$confline", 2);
      ($proxyhost, $proxyport) = split(/:/, "$rest", 2);
      $proxyhost = strip("$proxyhost");
      $proxyport = strip("$proxyport");
      $proxy = 1;
      if (! $proxyhost) {
        die "proxy host not defined, please comment line if not needed - config file line $conffile_linenum:";
      }
      elsif ($proxyport !~ /^\d+$/) {
        die "proxy port is either not defined or not numeric - config file line $conffile_linenum:";
      }
      print "Using $proxyhost port $proxyport as proxy\n" if ($verbose);
    }
    # handle 'maxforks' line
    elsif ($confline =~ /^maxforks:/i) {
      ($tag,$maxforks) = split(/:/, "$confline", 2);
      $maxforks = strip("$maxforks");
      if ($maxforks !~ /^\d+$/) {
        die "maxforks must be a numeric number - config file line $conffile_linenum:";
      }
      print "Will launch a maximum of $maxforks forked processes\n" if ($verbose);
    }
    # handle 'dbname' line
    elsif ($confline =~ /^dbname:/i) {
      ($tag,$dbname) = split(/:/, "$confline", 2);
      $dbname = strip("$dbname");
      print "Using database $dbname\n"  if ($verbose);
    }
    # handle 'connection_timeout' line
    elsif ($confline =~ /^connection_timeout:/i) {
      ($tag,$connection_timeout) = split(/:/, "$confline", 2);
      $connection_timeout = strip("$connection_timeout");
      if ($connection_timeout !~ /^\d+$/) {
        die "connection_timeout must be a numeric number - config file line $conffile_linenum:";
      }
      print "Connection timeout value is $connection_timeout\n" if ($verbose);
    }
    # handle 'data_timeout' line
    elsif ($confline =~ /^data_timeout:/i) {
      ($tag,$data_timeout) = split(/:/, "$confline", 2);
      $data_timeout = strip("$data_timeout");
      if ($data_timeout !~ /^\d+$/) {
        die "data_timeout must be a numeric number - config file line $conffile_linenum:";
      }
    print "Data timeout value is $data_timeout\n" if ($verbose);
    }
    # handle 'expired_after' line
    elsif ($confline =~ /^expired_after:/i) {
      ($tag,$expired_after) = split(/:/, "$confline", 2);
      $expired_after = strip("$expired_after");
      if ($expired_after !~ /^\d+$/) {
        die "expired_after must be a numeric number - config file line $conffile_linenum:";
      }
      print "Will consider visited urls 'expired' after $expired_after seconds\n" if ($verbose);
    }
    # handle 'maxdepth' line
    elsif ($confline =~ /^maxdepth:/i) {
      ($tag,$maxdepth) = split(/:/, "$confline", 2);
      $maxdepth = strip("$maxdepth");
      if ($maxdepth !~ /^\d+$/) {
        die "maxdepth must be a numeric number - config file line $conffile_linenum:";
      }
      print "Will go to a maximum depth of $maxdepth within any server\n" if ($verbose);
    }
    # handle 'exclude' line
    elsif ($confline =~ /^exclude:/i) {
      ($tag,$rest) = split(/:/, "$confline", 2);
      $rest = strip("$rest");
      $exclude{"$rest"} = 1;
      $exclude_list++;
      print "Will not visit any urls that match $rest\n" if ($verbose);
    }
    # handle 'table' line
    elsif ($confline =~ /^table:/i) {
      ($tag,$rest) = split(/:/, "$confline", 2);
      $rest = strip("$rest");

      if ($rest =~ /^emailreltbl$/i) { 
         $emailreltbl = 1;
         print "Including EMAIL relation table\n" if ($verbose);
      }
      elsif ($rest =~ /^urlreltbl$/i) { 
         $urlreltbl = 1;
         print "Including URL relation table\n" if ($verbose);
      }
      else {
         die "could not understand $rest for option reltbl - config file line $conffile_linenum:";
      }
    }
    # handle 'include' line
    elsif ($confline =~ /^include:/i) {
      ($tag,$rest) = split(/:/, "$confline", 2);
      $rest = strip("$rest");
      $include{"$rest"} = 1;
      $include_list++;
      print "Will only visit any urls that match $rest\n" if ($verbose);
    }
    # handle 'weblog' line
    elsif ($confline =~ /^weblog:/i) {
      ($tag,$weblog) = split(/:/, "$confline", 2);
      $weblog = strip("$weblog");
      if (! open(WEBLOG, ">> $weblog")) {
        die "Could not open logfile $weblog for writing : $!";
      }
      WEBLOG->autoflush(1);
      print "Will store web related logs to logfile $weblog\n" if ($verbose);
    }
    # handle 'dblog' line
    elsif ($confline =~ /^dblog:/i) {
      ($tag,$dblog) = split(/:/, "$confline", 2);
      $dblog = strip("$dblog");
      if (! open(DBLOG, ">> $dblog")) {
        die "Could not open logfile $dblog for writing : $!";
      }
      DBLOG->autoflush(1);
      print "Will store database related logs to logfile $dblog\n" if ($verbose);
    }
    else {
      die "Did not understand \"$confline\" - config file line $conffile_linenum:";
    } # end if/elsif/else
  } # end while

  # check for essential variables... and if not defined... exit...
  die "connection_timeout not defined in config file or not greater than zero" if (! $connection_timeout);
  die "data_timeout not defined in config file or not greater than zero" if (! $data_timeout);
  die "expired_after not defined in config file or not greater than zero" if (! $expired_after);
  die "maxdepth not defined in config file or not greater than zero" if (! $maxdepth);
  die "maxforks not defined in config file or not greater than zero" if (! $maxforks);
  die "dbname not defined in config file" if (! $dbname);

} # end sub

#
#
#
####################################################################################################################


####################################################################################################################
# connectDB	-	Connects to the database
# 
# Input: ($dbname)
#		$dbname - database name
#
# Output: $dbconn
#		$dbconn - reference to connected database
#
# Global variables read:
#
# Global variables created/modified: 
#
#
sub connectDB {
  my ($dbname) = @_;

  my $dbconn;

  if (! ($dbconn = DBI->connect("dbi:$databaseType:dbname=$dbname", "", "", {PrintError => 0}))) { 
    dblogmsg "connectDB: could not open connect to $dbname ... exiting";
    die "$DBI::errstr";
  }

  return $dbconn;

}
#
#
#
####################################################################################################################





####################################################################################################################
# strip		-	strips all leading and trailing whitespaces
# 
# Input: $str
#		$str - string
#
# Output: ($c,$d)
#		$str - string with all leading and trailing whitespaces stripped off!
#
# Global variables read:
#
# Global variables created/modified: 
#
#
sub strip {
  $_ = "@_";
  $_ =~ s/(^[\s\t]*)|([\s\t]*$)//g;
  return "$_";
}
#
#
#
####################################################################################################################



####################################################################################################################
# dblogmsg	-	logs general activity to/from the db to the filehandle DBLOG
# 
# Input: $message
#    or: @message
#
# Output: 
#
# Global variables read:
#			DBLOG (FILEHANDLE)
#
# Global variables created/modified: 
#
#
sub dblogmsg {
  if ($dblog) {
    print DBLOG "$$:" . scalar(localtime) . " @_ \n";
  }
}
#
#
#
####################################################################################################################


####################################################################################################################
# Reaper	-	Reaps zombie processes!
#		-	starts another process after reaping one that just finished!
# 
# Input: 
#
# Output:
#
# Global variables read:
#
# Global variables created/modified: 
#
#
sub Reaper {
  my ($child, $url);
  my $sleepseconds;
  $SIG{CHLD} = \&Reaper;
  while ($child = waitpid(-1,WNOHANG) > 0) {
    $Kid_Status{$child} = $?;
  }

  # weblogmsg "reaped $waitpid" . ($? ? " with exit $?" : "");

  $sleepseconds = $maxforks + 15;

  weblogmsg "Reaper: About to launch another process in $sleepseconds seconds";

  sleep ($sleepseconds); 

  $dbconn = &connectDB("$dbname");

  $url = getRandomUrl();

  spawn sub { &traverse("$url") };
}
#
#
#
####################################################################################################################



####################################################################################################################
# usage		-	prints out program usage
# 
# Input: $message
#		$message - [optional]	
#
# Output: 
#
# Global variables read:
#
# Global variables created/modified: 
#
#
sub usage {
  print "\n\n@_\n";
  print << "EOUSAGE";

Usage: $cmd [options]

   # no options - assumes webangel.conf file is in the directory as '${startdir}../etc/'

   -c file          # [optional] file to use as config file...

   -s url	    # [optional] start from the given url (eg. -s http://www.perl.com/)

   -about           # about this program

   -version	    # program version!

   -ps int	    # print stats ever 'int' seconds! 

   -v		    # turn verbose mode on! Will print out what program reads from config file etc.. 

   -nofork	    # do not fork processes! If this option is specified, it will ignore the 'maxforks'
                    # option in the config file and not fork any processes and just use the 'master' process
                    # to do the traversing! Also, the -ps option is ignored if the -nofork is specified 
                    # option as the traversal is not happening in the background so you cannot keep printing 
                    # stats on the screen as traversal is going on too (and we don't want to print stats from 
                    # within the traversal sub as that has the potential of slowing things down too much!) 

  -get_only file    # will get info for ONLY URL's contained within 'file'. We still extract links
                    # from the pages retrieved (for urlreltbl) but don't traverse them! 
                    # if the -get_only option is used, no processes will be forked, only the main process
                    # will be used for traversal!
                    # 'file' must contain only one URL per line! 

EOUSAGE
  exit(0);
}
#
#
#
####################################################################################################################


####################################################################################################################
# spawn		- spawns code
# 
# Input: $refererence_to_code
#
# Output: 
#
# Global variables read:
#
# Global variables created/modified: 
#
# Usage: spawn sub { code_you_want_to_spawn };
#   NOTE: the ';' at the end of the previous line! 
#
#
sub spawn {
  my $coderef = shift;
  unless (@_ == 0 && $coderef && ref($coderef) eq 'CODE') {
    confess "usage: spawn CODEREF";
  }
  my $pid;
  if (!defined($pid = fork)) {
    weblogmsg "spawn: cannot fork: $!"; 
    return;
  }
  elsif ($pid) {
    # weblogmsg "spawn: begat $pid";
    return; # i'm the parent
  }
  # else i'm the child -- go spawn

  # open(STDIN,  "<&Client")   || die "can't dup client to stdin";
  # open(STDOUT, ">&Client")   || die "can't dup client to stdout";
  ## open(STDERR, ">&STDOUT") || die "can't dup stdout to stderr";
  exit &$coderef();
}
#
#
#
####################################################################################################################


####################################################################################################################
# alarmcall	-	is called when an alarm is set off!
# 
# Input: 
#
# Output: 
#
# Global variables read:
#			$alarmreason - reason that the alarm was trigerred!
#
# Global variables created/modified: 
#			$alarmcalled - set to "1";
#
#
sub alarmcall {
  my $signame = shift;
  weblogmsg "alarmcall: $alarmreason\n";
  $alamrcalled = 1;
  return;
}
#
#
#
####################################################################################################################



####################################################################################################################
# traverse	-	Parses the info for url we pass it then traverses all links within it!
# 
# Input: ($url)
#		$url - URL 
#
# Output: 
#
# Global variables read:
#
# Global variables created/modified: 
#
#
sub traverse {
  my ($url) = @_;
  chomp($url);

  return 0 if ($url =~ /\'/); # can't have "'"'s in anything, postgres gets confused!

  my $traverse_time = time;
  my $base_page_size;

  my ($url_id, $response_time, $header, @content, $title, @emails, @links);
  my ($email, $link, $email_id, $link_id, $cookies, $server, $server_id);
  my ($numlinks, $numemails, $numimages, @images);

  if (! &checkTraverseValidity("$url")) { 
    # weblogmsg "traverse: checkTraverseValidity returned false, not getting url $url"; 
    return; 
  }
  else { 
    weblogmsg "traverse: starting traversal of $url";
  }

  $url_id = getUrlId("$url");

  ($response_time, $base_page_size, $header, @content) = getData("$url");


  if (! $header) { 
    weblogmsg "traverse: Could not get info for $url"; 
    return; 
  }

  $title = getTitle(@content);

  @links  = getLinks($url, @content);
  @emails = getEmails($url, @content);
  @images = getImages($url, @content);

  $server  = getServer("$header");
  $cookies = getCookies("$header");

  $server_id = getServerId("$server");

  $numlinks  = scalar @links;
  $numemails = scalar @emails;
  $numimages = scalar @images;

  update_urltbl("$url_id", "$url", "$title", "$cookies", "$numlinks", "$numemails", "$numimages", 
                "$server_id", "$traverse_time", "$response_time", "$base_page_size");
  update_servertbl("$server_id", "$traverse_time");

  foreach $email (@emails) {
    $email_id = getEmailId("$email");
    update_emailreltbl("$url_id", "$email_id") if ($emailreltbl);
  }

  foreach $link (@links) {
    $link_id = getUrlId("$link") if ($urlreltbl);
    update_urlreltbl("$url_id", "$link_id") if ($urlreltbl);
  }


  if (! $get_only) { 
    foreach $link (@links) {
      &traverse("$link");
    }
  }

}
#
#
#
####################################################################################################################



####################################################################################################################
# checkTraverseValidity	-	Checks if it is okay for us to traverse the url or if we should ignore it! 
# 
# Input: ($url)
#
# Output: $return_code
#		$return_code = 0, if it matched an exclusion rule or has not expired etc... 
#			     = 1, otherwise
#			     
# Global variables read:
#
# Global variables created/modified: 
#
#
sub checkTraverseValidity {
  my ($url) = @_;

  my $lastvisit;


  if (! &inIncludeList("$url") && $include_list) { 
    weblogmsg("checkTraverseValidity: not traversing $url - does not match any patterns in include list");
    return 0;
  }

  if (&inExcludeList("$url") && $exclude_list) {
    weblogmsg("checkTraverseValidity: not traversing $url - matches exclude list");
    return 0;
  }

  if (&getDepth("$url") > $maxdepth) {
    weblogmsg("checkTraverseValidity: not traversing $url - depth is greater than $maxdepth");
    return 0;
  }

  print "LastVisitTime = $lastvisit for $url\n";

  if (time - $lastvisit < $expired_after) {
    # weblogmsg("checkTraverseValidity: not traversing $url - not yet expired");
    return 0;
  }

  return 1;

}
#
#
#
####################################################################################################################



####################################################################################################################
# inExcludeList		-	checks if any patterns in our exclude list match the url 
# 
# Input: ($url)
#
# Output: $return_code
#		$return_code = 1, if a pattern in the exclude list matches the url
#		             = 0, otherwise
#
# Global variables read:
#
# Global variables created/modified: 
#
#
sub inExcludeList {
  my ($url) = @_;

  my $pattern;

  foreach $pattern (keys %exclude) {
    if ($url =~ /$pattern/i) {
       return 1;
    }
  }

  return 0;
}
#
#
#
####################################################################################################################


####################################################################################################################
# inIncludeList         -       checks if any patterns in our include list match the url
#
# Input: ($url)
#
# Output: $return_code
#               $return_code = 1, if a pattern in the include list matches the url
#                            = 0, otherwise
#
# Global variables read:
#
# Global variables created/modified:
#
#
sub inIncludeList {
  my ($url) = @_;

  my $pattern;

  foreach $pattern (keys %include) {
    if ($url =~ /$pattern/i) {
       return 1;
    }
  }

  return 0;
}
#
#
#
####################################################################################################################




####################################################################################################################
# getDepth	-	gets the depth of the url (how many directories deep we are)
# 
# Input: ($url)
#
# Output: $depth
#
# Global variables read:
#
# Global variables created/modified: 
#
#
sub getDepth {
  my ($url) = @_;

  my $depth;

  $_ = "$url";
  $depth = tr/\//\// - 2; # the number of /'s - 2;
                          # so that 'http://www.cse.unsw.edu.au/~simran/art/art.html' a depth of 3

  return $depth;
}
#
#
#
####################################################################################################################


####################################################################################################################
# getLastVisitTime	-	returns the last visit time of the url 
# 
# Input: ($url)
#
# Output: $epoch_time
#
# Global variables read:
#
# Global variables created/modified: 
#
#
sub getLastVisitTime {
  my ($url) = @_;

  my $query = "select LAST_VISITED from URLTBL
               where URL = '$url'";

  my $prepared = $dbconn->prepare("$query");
 
  my $result = $prepared->execute;
  
  my $rows = $prepared->rows;

  if ($dbconn->err) { 
     return "";
  }

  return @{$prepared->fetch}[0];

}
#
#
#
####################################################################################################################




####################################################################################################################
# getLinks	- works out all the links contained within the current page
# 
# Input: ($url, @content)
#		@content = the page! 
#
# Output: @links
#		@links - contains a list of URLs in @content
#
# Global variables read:
#
# Global variables created/modified: 
#				    @atags;
#
#
sub getLinks {
  my ($url, @content) = @_;

  my ($linke, $link);
  my (@links);

  @atags = (); # initialise @atags array that gets inserted into from getAtags

  $linke = HTML::LinkExtor->new(\&getAtags);
  $linke->parse("@content");

  my $base = "$url";
  
  # make urls in @atags absolute!
  @atags = map { $_ = url($_, $base)->abs; } @atags; 

  foreach $link (@atags) {
    if ($link =~ /^http/) {
       # weblogmsg "getLinks: extracted $link from $url";
       $link =~ s/\#.*//g;  # get rid of anything after the "#" as it usually refering to a particular
                            # "section" within another/the_same document!
       push(@links, "$link");
    }
    else {
      # weblogmsg "getLinks: skipping $link from $url";
      next;
    }
  }

  return @links;
}
#
#
#
####################################################################################################################


####################################################################################################################
# getImages      - works out all the links contained within the current page
#
# Input: ($url, @content)
#               @content = the page!
#
# Output: @images
#               @images - contains a list of images in @content
#
# Global variables read:
#
# Global variables created/modified:
#                                   @imgtags;
#
#
sub getImages {
  my ($url, @content) = @_;

  my ($linke, $image, $link);
  my (@images);

  @imgtags = (); # initialise @atags array that gets inserted into from getAtags

  $linke = HTML::LinkExtor->new(\&getIMGtags);
  $linke->parse("@content");

  my $base = "$url";

  # make urls in @images absolute!
  # @imgtags = map { $_ = url($_, $base)->abs; } @imgtags; # commented out as we are not storing
                                                           # images anywhere, only using the array
                                                           # to see how many images there are in 
 							   # a page we do not need to do extra
							   # processing! 
                                      

  foreach $link (@imgtags) {
    # weblogmsg "getImages: extracted $link from $url";
    $link =~ s/\#.*//g;  # get rid of anything after the "#" as it usually refering to a particular
                         # "section" within another/the_same document!
    push(@images, "$link");
  }

  return @images;
}
#
#
#
####################################################################################################################




####################################################################################################################
# getEmails	- works out all the emails contained within the current page
# 
# Input: ($url,@content)
#		@content = the page!
#
# Output: @emails
#		@emails - contains a list of email addresses in @content
#
# Global variables read:
#
# Global variables created/modified: 
#				    @atags;
#
#
sub getEmails {
  my ($url, @content) = @_;

  my ($email, $tag, $link, $linke);
  my (@emails);

  @atags = (); # initialise @atags array that gets inserted into from getAtags

  $linke = HTML::LinkExtor->new(\&getAtags);
  $linke->parse("@content");

  my $base = "$url";

  # make urls in @atags absolute!
  @atags = map { $_ = url($_, $base)->abs; } @atags;

  foreach $link (@atags) {
    if ($link =~ /^mailto/) {
       ($tag, $email) = split(/:/, "$link", 2);
       $email =~ s/\'//g; # get rid of "'"'s - postgres gets confused!
       # weblogmsg "getEmails: extracted $email from $url";
       push(@emails, "$email");
    }
    else {
      # weblogmsg "getEmails: skipping $link from $url";
      next;
    }
  }

  return @emails;
}
#
#
#
####################################################################################################################


####################################################################################################################
# getAtags	-	used as 'callback' sub for HTML::LinkExtor
# 
# Input: (internal from HTML::LinkExtor)
#
# Output: 
#
# Global variables read:
#
# Global variables created/modified: 
#
#
sub getAtags {
  my($tag, %attr) = @_;
  return if $tag ne 'a';  # we only look closer at <a ...>
  push(@atags, values %attr);
}
#
#
#
####################################################################################################################

####################################################################################################################
# getIMGtags      -       used as 'callback' sub for HTML::LinkExtor
#
# Input: (internal from HTML::LinkExtor)
#
# Output:
#
# Global variables read:
#
# Global variables created/modified:
#
#
sub getIMGtags {
  my($tag, %attr) = @_;
  return if $tag ne 'img';  # we only look closer at <img ...>
  push(@imgtags, values %attr);
}
#
#
#
####################################################################################################################




####################################################################################################################
# getServer	-	works out the type of server that served us the url
# 
# Input: ($header)
#		$header - header info that we get back from server
#
# Output: $server_type
#		$server_type - the type of server (eg. Apache/1.3.1 )
#
# Global variables read:
#
# Global variables created/modified: 
#
#
sub getServer {
  my ($header) = @_;

  my $server;

  foreach $line (split(/\n/, $header)) {
    if ($line =~ /^Server:(.*)/i) {
       $server = "$1";
       $server = strip("$server");
       $server =~ s/\'//g; # get rid of "'"'s - postgres gets confused!
       return $server;
    }
  }

  return "";

}
#
#
#
####################################################################################################################


####################################################################################################################
# getCookies	-	works out the cookies that the server tried to set!
# 
# Input: ($header)
#		$header - header info that we get back from server
#
# Output: $server_type
#		$cookies - cookies
#
# Global variables read:
#
# Global variables created/modified: 
#
#
sub getCookies {
  my ($header) = @_;

  my $cookies;

  foreach $line (split(/\n/, $header)) {
    if ($line =~ /^Set-cookie:(.*)$/i) {
       $cookies .= "$1";
    }
  }

  $cookies =~ s/\'//g; # get rid of "'"'s - postgres gets confused!
  return $cookies;

}
#
#
#
####################################################################################################################




####################################################################################################################
# getUrlId	-	returns ID of URL if URL is already in dataase
#		-	else creates URL entry and returns ID
# 
# Input: ($url)
#
# Output: $url_id
#
# Global variables read:
#
# Global variables created/modified: 
#
#
sub getUrlId {
  my ($url) = @_;

  my ($errormsg, $loopnum);



  my $query = "select ID from URLTBL
               where URL = '$url'";

  my $prepared = $dbconn->prepare("$query");

  my $result = $prepared->execute;

  my $rows = $prepared->rows;

  my $url_id;

  if ($rows > 0) { 
    $url_id = @{$prepared->fetch}[0]; 
    return "$url_id";
  }


  # if the url was not in the table create it! 
  while (! $url_id) {

    $url_id = $verified_at = time;

    $query = "insert into URLTBL
               (ID,URL,TITLE,COOKIES,NUM_LINKS,NUM_EMAILS,NUM_IMAGES,SERVER_ID,LAST_VISITED,RESPONSE_TIME,BASE_PAGE_SIZE)
               VALUES ('$url_id','$url','','','','','','','','','')";

    $prepared = $dbconn->prepare("$query");
 
    $result = $prepared->execute;

    $rows = $prepared->rows;

    if ($rows > 0) {
       return $url_id;
    }
    else {
       $errormsg = $dbconn->errstr;
       chomp($errormsg);
       # dblogmsg "getUrlId: Could not assign $url_id as ID in URLTBL for url $url - $errormsg";
       $url_id = "";
    }

    sleep($maxforks + 5); # sleep for a few seconds before trying again!

    if ($loopnum++ > 7) { 
       dblogmsg "getUrlId: exiting program... could not resolve error $errormsg";
       exit(1);
    }

  }

  return $url_id;


}
#
#
#
####################################################################################################################



####################################################################################################################
# getEmailId	-	returns ID of ADDRESS if ADDRESS is already in dataase
#		-	else creates ADDRESS entry and returns ID
# 
# Input: ($email)
#
# Output: $email_id
#
# Global variables read:
#
# Global variables created/modified: 
#
#
sub getEmailId {
  my ($email) = @_;

  my ($errormsg, $loopnum);

  my $query = "select ID from EMAILTBL
               where ADDRESS = '$email'";

  my $prepared = $dbconn->prepare("$query");

  my $result = $prepared->execute;

  my $rows = $prepared->rows;

  my $email_id;

  if ($rows > 0) {
     $email_id = @{$prepared->fetch}[0];
     return $email_id;
  }

  # if the email was not in the table create it!
  while (! $email_id) {
    $email_id = $verified_at = time;

    $query = "insert into EMAILTBL
               (ID, ADDRESS, VERIFIED_AT)
               VALUES
               ('$email_id', '$email', '$verified_at')";


    $prepared = $dbconn->prepare("$query");
  
    $result = $prepared->execute;

    $rows = $prepared->rows;

    if ($rows > 0) {
       return $email_id;
    }
    else {
       $errormsg = $dbconn->errstr;
       chomp($errormsg);
       dblogmsg "getEmailId: Could not assign $email_id as ID in EMAILTBL - $errormsg";
       $email_id = "";
    }

    sleep($maxforks + 5); # sleep for a few seconds before trying again!

    if ($loopnum++ > 7) {
       dblogmsg "getEmailId: exiting program... could not resolve error $errormsg";
       exit(1);
    }


  }

  return $email_id;


}
#
#
#
####################################################################################################################



####################################################################################################################
# getServerId	-	returns ID of SERVER_TYPE if SERVER_TYPE is already in dataase
#		-	else creates SERVER_TYPE entry and returns ID
# 
# Input: ($server)
#
# Output: $server_id
#
# Global variables read:
#
# Global variables created/modified: 
#
#
sub getServerId {
  my ($server) = @_;

  my ($errormsg, $loopnum);

  my $query = "select ID from SERVERTBL
               where SERVER_TYPE = '$server'";

  my $prepared = $dbconn->prepare("$query");

  my $result = $prepared->execute;

  my $rows = $prepared->rows;

  my $server_id;

  if ($rows > 0) {
     $email_id = @{$prepared->fetch}[0];
     return $email_id;
  }


  # if the server was not in the table create it!
  while (! $server_id) {
    $server_id = $verified_at = time;

    $query = "insert into SERVERTBL
              (ID, SERVER_TYPE, LAST_ENCOUNTERED)
               VALUES ('$server_id','$server', '$verified_at')";


    $prepared = $dbconn->prepare("$query");

    $result = $prepared->execute;

    $rows = $prepared->rows;

    if ($rows > 0) {
       dblogmsg "getServerId: created server type $server with id $server_id";
       return $server_id;
    }
    else {
       $errormsg = $dbconn->errstr;
       chomp($errormsg);
       dblogmsg "getServerId: Could not assign $server_id as ID in SERVERTBL - $errormsg";
       $server_id = "";
    }

    sleep($maxforks + 5); # sleep for a few seconds before trying again!

    if ($loopnum++ > 7) {
       dblogmsg "getServerId: exiting program... could not resolve error $errormsg";
       exit(1);
    }


  }

  return $server_id;

}
#
#
#
####################################################################################################################




####################################################################################################################
# getData	-	gets the contents of URL 
# 
# Input: ($url)
#
# Output: ($response_time, $header, @content)
#		$response_time - in seconds
#		$header        - header returned by server
#		@content       - page content
#
# Global variables read:
#			RemoteHost (FILEHANDLE) - created via establishConnection called from within sub!
#
# Global variables created/modified: 
#				$alarmreason - reason if alarm is trigerred!
#
#
sub getData {
  my ($url) = @_;

  my ($remotehost, $remoetport, $uri, @tosend, $line, $rhost, $rport);
  my ($header, @content, $response_time);
  my ($time_after, $time_before, $base_page_size);

  # decompose the url!
  if ($url =~ /http:\/\/(.*?):(\d+)\/(.*)$/) { # http://www.perl.com:8080/...
     $remotehost = "$1";
     $remoteport = "/$2";
     $uri = "$3";
  }
  elsif ($url =~ /^http:\/\/(.*?)\/(.*)$/) { # http://www.perl.com/...
     $remotehost = "$1";
     $uri = "/$2";
     $remoteport = 80;
  }
  elsif ($url =~ /^http:\/\/(.*?)$/) {	# http://www.perl.com
     $remotehost = "$1";
     $uri = "/";
     $remoteport = 80;
  }
  else {
     weblogmsg "getData: could not decompose url $url";
     return 0;
  }

  # set up alarms...
  $alarmreason = "Could not connect to remotehost $remotehost on port $remoteport within $connection_timeout seconds";
  alarm($connection_timeout);

  # make conneciton to remote host! - sets up filehandle RemoteHost 
  if ($proxy) {
    $uri = "$url";
    $rhost = "$proxyhost";
    $rport = "$proxyport";
  }
  else {
    $rhost = "$remotehost";
    $rport = "$remoteport";
  }

  if (! &establishConnection($rhost, $rport)) {
    weblogmsg "getData: Could not establish connection to $rhost on $rport";
    return 0;
  }
    
  if ($alarmcalled) {
     $alarmcalled = 0;
     weblogmsg "getData: Alarm call caught due to connection timeout";
     return 0;
  } 

  # set up timeouts for receiving data...
  $alarmreason = "The remote server $remotehost on port $remoteport did not start sending data within $data_timeout seconds";
  alarm $data_timeout;

  undef(@tosend);
  push(@tosend, "GET $uri HTTP/1.0\n");
  push(@tosend, "User-Agent: WebAngel $version\n");
  push(@tosend, "\n"); # don't forget to have this newline by itself at the end of @tosend!!!


  if (! send(RemoteHost, join('',@tosend), 0)) {
     weblogmsg "getData: send error: $!";
     return 0;
  }

  $time_before = time;

  # read in the header
  while ($line = <RemoteHost>) {

    if ($alarmcalled) {
       $alarmcalled = 0;
       weblogmsg "getData: Alarm call caught due to data timeout";
       return 0;
    }

    chomp($line);
    $line =~ s///g;
    last if ($line =~ /^\s*$/); # we will be in the content now!

    $header .= "$line\n";
  }

  # read in the content
  # @content = <RemoteHost>;
 
  while($line = <RemoteHost>) {
    $base_page_size += length($line);
    $line =~ s//\n/g;
    push(@content, "$line");
  }

  $time_after = time;
  $response_time = $time_after - $time_before;

  # cancel all alarms
  alarm 0;

  return ($response_time, $base_page_size, $header, @content);
}
#
#
#
####################################################################################################################




####################################################################################################################
# establishConnection	-	establishes connection with remote host
# 
# Input: ($host, $port)
#		$host - remote hostname
#		$port - remote port 
#
# Output: ($c,$d)
#		$c = asdfasdf
#		$d = asdfasdfasdf
#
# Global variables read:
#
# Global variables created/modified: 
#
#
sub establishConnection {
  my ($host, $port) = @_;

  $remote_iaddr = inet_aton($host);
  $remote_paddr = sockaddr_in($port,$remote_iaddr);

  socket(RemoteHost, PF_INET, SOCK_STREAM, $proto) or die "socket: $!";

  if (! connect(RemoteHost, $remote_paddr)) {
    weblogmsg("establishConnection: could not connect to remotehost $host on port $port");
    close(RemoteHost);
    return 0;
  }

  return 1;

}
#
#
#
####################################################################################################################



####################################################################################################################
# getRandomUrl		-	returns random url from database
# 
# Input: 
#
# Output: $url
#
# Global variables read:
#
# Global variables created/modified: 
#
#
sub getRandomUrl {
  my (@urls, $randurl);

  my $query = "select URL from URLTBL";

  my $prepared = $dbconn->prepare("$query");

  my $result = $prepared->execute;

  while ($_ = $prepared->fetch) {
    push(@urls, &strip("@$_"));
  }

  srand(time);
  $randurl = splice(@urls, rand $#urls, 1);


  if (! $randurl) {
      die "getRandomUrl: there are no URL's in the database to start from, please use -s switch on startup!";
      # $randurl = "http://www.perl.com/";
  }
  
  weblogmsg("getRandomUrl: random url requested - returning $randurl");

  return "$randurl";

}
#
#
#
####################################################################################################################



####################################################################################################################
# update_urltbl		-	updates the url table
# 
# Input: ($url_id, $url, $title, $cookies, $server_id, $last_visited, $response_time)
#	$last_visited - epoch time
#
# Output: 
#
# Global variables read:
#
# Global variables created/modified: 
#
#
sub update_urltbl {
  my ($url_id, $url, $title, $cookies, $numlinks, $numemails, $numimages, $server_id, $traverse_time, $response_time, $base_page_size) = @_;

  my ($query, $errormsg);

  $query = "update URLTBL set
                   ID = $url_id,
                   TITLE = '$title',
                   COOKIES = '$cookies',
                   NUM_LINKS = $numlinks,
                   NUM_EMAILS = $numemails,
                   NUM_IMAGES = $numimages,
                   SERVER_ID = $server_id,
                   LAST_VISITED = $traverse_time,
                   RESPONSE_TIME = $response_time,
		   BASE_PAGE_SIZE = $base_page_size
            where  URL = '$url'";


  my $prepared = $dbconn->prepare("$query");
  my $result = $prepared->execute;
  my $rows = $prepared->rows;

  if ($dbconn->err) { 
     $errormsg = $dbconn->errstr;
     chomp($errormsg);
     dblogmsg "update_urltbl: Could not update URLTBL for url $url - $errormsg - fatal error";
     die "update_urltbl: Quitting ... fatal error!";
     return 0;
  }

  return 1;
  

}
#
#
#
####################################################################################################################


####################################################################################################################
# update_servertbl         -       updates the server table
#
# Input: ($server_id, $last_visited)
#       $last_visited - epoch time
#
# Output:
#
# Global variables read:
#
# Global variables created/modified:
#
#
sub update_servertbl {
  my ($server_id, $last_encountered) = @_;

  my ($query, $errormsg);

  $query = "update SERVERTBL set
                   LAST_ENCOUNTERED = $last_encountered
            where  ID = $server_id";

  my $prepared = $dbconn->prepare("$query");
  my $result = $prepared->execute;
  my $rows = $prepared->rows;


  if ($dbconn->err) {
     $errormsg = $dbconn->errstr;
     chomp($errormsg);
     dblogmsg "update_servertbl: Could not update SERVERTBL for server id $server_id - $errormsg";
     return 0;
  }

  return 1;

}
#
#
#
####################################################################################################################




####################################################################################################################
# getTitle
# 
# Input: (@content)
#		@content - the page!
#
# Output: $title
#
# Global variables read:
#
# Global variables created/modified: 
#
#
sub getTitle {
  my (@content) = @_;

  my $con = join('', @content);

  if ($con =~ /<title>(.*?)<\/title>/i) {
     my $title = "$1";
     $title =~ s/\'//g; # get rid of "'"'s - postgres gets confused!
     return strip("$title");
  }
  else { return ""; }
}
#
#
#
####################################################################################################################


####################################################################################################################
# update_urlreltbl	-	updates the url/link relationship table
# 
# Input: ($url_id, $link_id)
#
# Output: 
#
# Global variables read:
#
# Global variables created/modified: 
#
#
sub update_urlreltbl {
  my ($url_id, $link_id) = @_;

  my ($errormsg, $query, $result);

  my $verified_at = time;


  # check if $url_id and $link_id are already in the database!
  $query = "select * from URLRELTBL
            where URL_A_ID = $url_id
              and URL_B_ID = $link_id";


  my $prepared = $dbconn->prepare("$query");
  my $result = $prepared->execute;
  my $rows = $prepared->rows;


  if ($rows > 0) { # yup, in the db already so just update!
    $query = "update URLRELTBL set
                       VERIFIED_AT = $verified_at
                 where URL_A_ID = $url_id
                   and URL_B_ID = $link_id";
    $prepared = $dbconn->prepare("$query");
    $result = $prepared->execute;
    $rows = $prepared->rows;
    if ($dbconn->err) {
      $errormsg = $dbconn->errstr;
      chomp($errormsg);
      dblogmsg "update_urlreltbl: could not update link relationship for urlid=$url_id linkid=$link_id - $errormsg";
      return 0;
    }
  }
  else { # create entry in db!
    $query = "insert into URLRELTBL
              (URL_A_ID,URL_B_ID,VERIFIED_AT)
              VALUES ('$url_id', '$link_id', '$verified_at')";
    $prepared = $dbconn->prepare("$query");
    $result = $prepared->execute;
    $rows = $prepared->rows;
    if ($dbconn->err) {
      $errormsg = $dbconn->errstr;
      chomp($errormsg);
      dblogmsg "update_urlreltbl: could not create link relationship for urlid=$url_id linkid=$link_id - $errormsg";
      return 0;
    }
  }

  return 1;
}
#
#
#
####################################################################################################################


####################################################################################################################
# update_emailreltbl	-	updates the email relationship table
# 
# Input: ($url_id, $email_id)
#
# Output: 
#
# Global variables read:
#
# Global variables created/modified: 
#
#
sub update_emailreltbl {
  my ($url_id, $email_id) = @_;

  my ($errormsg, $query, $result);

  my $verified_at = time;


  # check if $url_id and $email_id are already in the database!
  $query = "select * from EMAILRELTBL
            where URL_ID = $url_id
              and EMAIL_ID = $email_id";


  my $prepared = $dbconn->prepare("$query");
  my $result = $prepared->execute;
  my $rows = $prepared->rows;

  if ($rows > 0) { # yup, in the db already so just update!
    $query = "update EMAILRELTBL set
                     VERIFIED_AT = $verified_at
               where URL_ID = $url_id
                 and EMAIL_ID = $email_id";
    $prepared = $dbconn->prepare("$query");
    $result = $prepared->execute;
    $rows = $prepared->rows;
    if ($dbconn->err) {
      $errormsg = $dbconn->errstr;
      chomp($errormsg);
      dblogmsg "update_emailreltbl: could not update email relationship for urlid=$url_id emailid=$email_id - $errormsg";
      return 0;
    }
  }
  else { # create entry in db!
   $query = "insert into EMAILRELTBL
              (URL_ID,EMAIL_ID,VERIFIED_AT)
              VALUES ('$url_id', '$email_id', '$verified_at')";
    $prepared = $dbconn->prepare("$query");
    $result = $prepared->execute;
    $rows = $prepared->rows;
    if ($dbconn->err) {
      $errormsg = $dbconn->errstr;
      chomp($errormsg);
      dblogmsg "update_emailreltbl: could not create email relationship for urlid=$url_id emailid=$email_id - $errormsg";
      return 0;
    }
  }

  return 1;
}
#
#
#
####################################################################################################################


####################################################################################################################
# weblogmsg      -       logs general activity about urls we are getting / parsing
#
# Input: $message
#    or: @message
#
# Output:
#
# Global variables read:
#                       WEBLOG (FILEHANDLE)
#
# Global variables created/modified:
#
#
sub weblogmsg {
  if ($weblog) { 
    print WEBLOG "$$:" . scalar(localtime) . " @_ \n";
  }
}
#
#
#
####################################################################################################################



####################################################################################################################
# about         -       prints out stuff 'about' this program!
#
# Input: 
#
# Output:
#
# Global variables read:
#
# Global variables created/modified:
#
#
sub about {
  print << "ABOUT";

Please read the 'README' file for more informaiton. 
Send any comments/sugessitions to simran\@cse.unsw.edu.au :-) 

ABOUT
  exit(0);
}
#
#
#
####################################################################################################################

