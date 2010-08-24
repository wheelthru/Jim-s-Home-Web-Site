<?php

// redirect for SpringExtravaganza
$referrer = $_SERVER['SERVER_NAME'];
if (preg_match("/springextravaganza.com/",$referrer)) {
header('Location: http://springextravaganza.com/springextravaganza/index.htm');
};


include ("graphs.php");

$color="d0ffff"; // from web host
$hostname=`hostname`;
$ds=DIRECTORY_SEPARATOR;
$basedir="/home/content/55/5891655/html";
if($hostname=="jimsdell\n"){
	$basedir="c:\progra~1\xitami\webpages";
	$color="d0ffd0"; //localhost
	}


print"<html><head><title>Jim's home web site</title>
<style>
.menu {
     text-decoration: none;
     background-color: #e0e0e0;
     padding: 5px;
     color: maroon;
     font-family: Arial;
     font-size: 12pt;
     font-weight: normal;
}
.menu:hover {
	 color: white;
     background-color: #5A8EC6;
}
</style>
</head>
<body bgcolor=$color ><font face=\"Arial\">


<!--
<table><tr><td>
<h3><font color=red><i>If you're looking for &nbsp;
</font></h3></td>
<td> <a href=springextravaganza><img src=logoSmall.gif></a></td></tr></table>
<h3><font color=red><i>
<a href=springextravaganza>click here</a>. &nbsp;Please excuse our dust!<hr></font></h3><P>
-->

<h1>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Jim's home web site</h1><p>
<div>
<a class=\"menu\" href=\"homeAuto.htm\" title=\"About the home automation system behind this page\">&nbsp;Home Automation</a>
<a class=\"menu\" href=\"projects/index.html\" title=\"My projects - electronic and other\">&nbsp;Projects</a>
<a class=\"menu\" href=\"squaredance/\" title=\"Square Dance Stuff\">&nbsp;Square Dance</a>
<a class=\"menu\" href=\"HummelsEtc/index.html\" title=\"Some collectibles we're trying to sell\">&nbsp;Collectibles</a>
<a class=\"menu\" href=\"aboutme.html\" title=\"A little about me\">&nbsp;About Jim</a>
</div>


"; # end of html print

#---------- DATAFILE AGE ------------
$now=time();
$df="datafile.csv";
$size=filesize($df);
$secs=$now-filemtime($df);
$hrs=intval($secs/3600);
$mins=intval(($secs-3600*$hrs)/60);
$secs=$secs-3600*$hrs-60*$mins;

#------ new watchdog check -----
$wd="wdlog.txt";
$wdsize=filesize($wd);
$wdsecs=$now-filemtime($wd);
$wdhrs=intval($wdsecs/3600);
$wdmins=intval(($wdsecs-3600*$wdhrs)/60);
$wdsecs=$wdsecs-3600*$wdhrs-60*$wdmins;
$loggen=file("wdcnt");

echo "<P><table><tr><td>";  #set up table to put df age next to refresh button
print "<form><input type=button value=\"refresh\" onClick=\"window.location.reload()\"></form>";
echo "</td><td><font face=\"Arial\">";
echo "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;(datafile is $size bytes, age ${hrs}H ${mins}M ${secs}S)";
echo "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;(watchdog $loggen[0] is $wdsize bytes, age ${wdhrs}H ${wdmins}M ${wdsecs}S)";
if($secs > 600){print "<font color=red><b> Datafile is OLD!</b></font>";}
echo "</td></tr></table>";

#print "<hr>\n";
print "<h4> SUMP CYCLE COUNTS, RAINFALL<br><img src=\"sump.png\"></h4>";
print "<h4> FURNACE DUCT TEMPS<br><img src=\"furn.png\"></h4>";
print "<h4> OUTSIDE TEMPERATURE<br><img src=\"temp.png\"></h4>";
print "<h4> WATER USAGE FROM WATER METER<br><img src=\"water.png\"></h4>";


$configFile="config.php";
include("$basedir${ds}$configFile");


print"<form action=setconfig.php>";
print"Days of data to display: <input type=input name=dd size=1 value=$dispDays>";
print" &nbsp Hours per sample: <input type=text name=\"hps\" size=1 value=$hrsPerSample >";
print" &nbsp <input type=submit value=submit></form>";


//$wdfile="watchdogout.htm";
//$thresh=2*60;
//$now=time();
//if(is_file($wdfile)){$wdtime=filemtime($wdfile);}
//else{print"<h4><font color=red>WATCHDOG FILE MISSING!</font></h4><P>\n";}

//$delta=$now-$wdtime;
//print "<br>wd file age is $delta secs<br>\n";
//if($wdtime && ($delta > $thresh)){
//	print "<h4><font color=red>WATCHDOG IS OLD: $delta seconds</font></h4><P>\n";
//}


print"<hr><h4>POWER OUTAGES</h4>";

$lines="";
$eventFile="$basedir${ds}eventfile.txt";
if(is_file($eventFile)){
$lines=file($eventFile);

if($lines){print "Times shown are 2 hours <i>earlier</i> than actual outage :-(<br>\n";}
foreach($lines as $line){print "$line<br>\n";}
}
// set up power outage ignore stuff
$pignvals=split("/",$pwrIgnoreDate);

$pwrIgnoreSecs=mktime(0,0,0,$pignvals[0],$pignvals[1]);
//print"pv0:$pignvals[0]  pv1:$pignvals[1]  pwrIgnoreSecs=$pwrIgnoreSecs<br>";
$startTime=time()-$dispDays*24*3600;
if($startTime > $pwrIgnoreSecs){
	$pigText="in past $dispDays days";
	}else{
	$pigText="since $pwrIgnoreDate";
	}

if(!$lines){print "No power outages $pigText.<br>\n";}




if($doPwrText){
print "<TEXTAREA rows=8 cols=70>";
print "Power outages records (decimal days): date;count;duration in secs\n";
$lines=file("$basedir${ds}pwrinfo.csv");
foreach($lines as $line){print "$line\n";}
print "</TEXTAREA><br>";

print"<table><tr><td>";
print"<form action=setconfig.php>";
print"<input type=hidden name=dpt value=0.0>";
print"<input type=submit value=\"hide power outage detail\"><hr></form>";

}
else{
print"<table><tr><td>";
print"<form action=setconfig.php>";
print"<input type=hidden name=dpt value=1>";
print"<input type=submit value=\"show power outage detail\"></form>";

}// end if don't do pwt txt
print"</td><td>";

print"<form action=setconfig.php>";
print" &nbsp ignore outages before (m/d): <input type=text name=pign value=$pwrIgnoreDate size=2>";
print"<input type=submit value=submit new ignore date></form>";
print"</td></tr></table><hr>";



if($doPingStats){
print"<h4>PING STATS TO MY ISP</h4>";
print "<img src=ping.png>\n";
print "<br><form action=setconfig.php>";
print"<input type=hidden name=dps value=0.0>";
print" &nbsp <input type=submit value=\"hide ping stats\"></form>";
}
else{
print"<form action=setconfig.php>";
print"<input type=hidden name=dps value=1>";
print"<input type=submit value=\"show ping stats\"></form>";
}
?>



<hr>
<a href=config1.php>configuration</a> &nbsp (though most can be done from this page)<hr><br>

<a href=getit.php>getit.php</a><br>
<a href=watchdogout.htm>watchdog output</a><br>
<hr>


</body></html>
