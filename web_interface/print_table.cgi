#!/usr/local/bin/perl

use CGI;
use DBI;

$| = 1;

# $debug = 1;

$dbType = "Pg"; # postgres... 
$dbname = "webangel";

###################################################################################

print "Content-type: text/html\n\n";


################################################################
# connect to the db

if (! ($dbconn = DBI->connect("dbi:$dbType:dbname=$dbname", "", "", {PrintError => 0}))) {
  $errormsg = $dbconn->errstr;
  print "Could not connect to database $dbname - $errormsg\n";
  exit(1);
}

#
################################################################

################################################################
# work out cgi form elements! 

$cgiquery = new CGI;


#################################################################
# Work out which table to use and define some default calculation
# conversions etc... 

$table = $cgiquery->param("TABLENAME");
@extratables = $cgiquery->param("EXTRA_TABLE");

$special_calculate{"1"} = "scalar localtime(ID)";
$special_calculate{"2"} = "URLTBL.SERVER_ID = SERVERTBL.ID";
$special_calculate{"3"} = "scalar localtime(LAST_VISITED)";
$special_calculate{"4"} = "scalar localtime(VERIFIED_AT)";
$special_calculate{"5"} = "scalar localtime(LAST_ENCOUNTERED)";
$special_calculate{"6"} = "URLTBL.ID = EMAILRELTBL.URL_ID";
$special_calculate{"7"} = "EMAILTBL.ID = EMAILRELTBL.EMAIL_ID";
$special_calculate{"8"} = "A_URLTBL.ID = URLRELTBL.URL_A_ID";
$special_calculate{"9"} = "B_URLTBL.ID = URLRELTBL.URL_B_ID";

if ($table eq "EMAILTBL") {
  @valid_fields = qw(ID ADDRESS VERIFIED_AT);
  @special_calculations = qw(ID_EPOCH_TO_STANDARD VA_EPOCH_TO_STANDARD);
}
elsif ($table eq "URLTBL") {
  @valid_fields = qw(ID URL TITLE COOKIES NUM_LINKS NUM_EMAILS NUM_IMAGES SERVER_ID LAST_VISITED RESPONSE_TIME BASE_PAGE_SIZE);
  @sql_calculations = qw(SERVERTBL.SERVER_TYPE);
  @special_calculations = qw(LV_EPOCH_TO_STANDARD ID_EPOCH_TO_STANDARD);
}
elsif ($table eq "SERVERTBL") {
  @valid_fields = qw(ID SERVER_TYPE LAST_ENCOUNTERED);
  @special_calculations = qw(ID_EPOCH_TO_STANDARD LE_EPOCH_TO_STANDARD);
}
elsif ($table eq "EMAILRELTBL") {
  @sql_calculations = qw(URLTBL.URL EMAILTBL.ADDRESS);
  @valid_fields = qw(URL_ID EMAIL_ID VERIFIED_AT);
  @special_calculations = qw(VA_EPOCH_TO_STANDARD);
}
elsif ($table eq "URLRELTBL") {
  @sql_calculations = qw(A_URLTBL.URL B_URLTBL.URL);
  @valid_fields = qw(URL_A_ID URL_B_ID VERIFIED_AT);
  @special_calculations = qw(VA_EPOCH_TO_STANDARD);
}
else {
  print "Could not work out which table to access!\n";
  exit;
}

#
################################################################

###############################################################
# read in all valid fields!
foreach $field_name (@valid_fields) { 
  $field_value = $cgiquery->param("$field_name");
  next if (! $field_value);
  push(@fields, "${table}.${field_name}");
}

###############################################################
# work out where clauses for sql calculations
foreach $field_name (@sql_calculations) { 
  $field_value = $cgiquery->param("$field_name");
  next if (! $field_value);
  $field_value = $special_calculate{"$field_value"};
  push(@fields, "${field_name}");
  push(@whereclause, "$field_value");
  $where = "where";
  $extratables_incl = ", " . join(',', @extratables);
}



###############################################################
# work out the "special" calculations
foreach $field_name (@special_calculations) {
  $field_value = $cgiquery->param("$field_name");
  next if (! $field_value);
  $field_value = $special_calculate{"$field_value"};
  push(@workout, "${field_name}:${field_value}");
}


###############################################################
# get and check some of the fields! 

$sortby = $cgiquery->param("SORTBY");

if ($sortby) { 
  foreach $field_name (@fields) { 
    $sortbyok = 1 if ("${table}.$sortby" eq "${field_name}");
  }
 
  if (! $sortbyok) { 
     print "Sort by field not correct!\n";
     exit;
  }


  $sortbyline = "order by ${table}.${sortby}";
}

if ($#fields < 0) { 
  print "Please select some checkboxes and try again!\n";
  exit(1);
}


###############################################################
# Generate the query string!

$dbquery = "select " . 
            join(",", @fields) . " " . 
           "from $table " . "$extratables_incl " .  
           "$where " . join(" and ", @whereclause) . " " . 
           "$sortbyline";

if ($debug) { 
  print "<PRE> DBQUERY\n---------\n$dbquery</PRE>\n";
  exit;
}

###############################################################
# do the query! 

$prepared = $dbconn->prepare("$dbquery");
$result = $prepared->execute;
$rows = $prepared->rows;


###############################################################
# print out the results... 

if ($rows <= 0) { 
  print "There is no data in this table!\n";
  exit;
}

if ($rows > 0) { 


  print "<table border=8 cellpadding=5>\n";
    
  print "<th>Row Number</th>\n";
  foreach $element (@fields) {
    $element =~ s/(.*?\.)//g; # get rid of the "tablename" that is before the "." it looks nicer
			      # on the screen without it :-) 
    print "<th>$element</th>\n";
  }

  @copy_workout = @workout;
  foreach $element (@copy_workout) { 
    $element =~ s/(.*?)://g; # get rid of everything up to and including the first ':'
    print "<th>$element</th>\n";
  }

  while (@line = @{$prepared->fetch}) { 
    next if $printed{"@line"}; # to avoid duplicates!
    $rownum++;
    print "<tr>\n";
    print "<td>$rownum</td>\n";

    foreach $element (@line) {
      print "<td>$element</td>\n";
    }
    foreach $element (@workout) { 
      ($field_name, $field_value) = split(/:/, "$element", 2);
      foreach $field_element (@fields) { 
        $field_value =~ s/$field_element/$line[$i]/g;
        $i++;
      }
      $i = 0;
      $workout_result = eval $field_value; 
      print "<td>$workout_result</td>\n";
    }
    $printed{"@line"} = 1;

  }

  print "</table>\n";
}
else {
  print "An error occured " . $dbconn->errorMessage . "\n";
}
