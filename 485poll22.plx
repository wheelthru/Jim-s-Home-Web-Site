#! perl -w
# new protocol with source addr started 11/23/07 jw
# now logs through a function so we can write partial files
# for upload to web site 12/14/07
# 485poll5 adds kickoff/check for transport process
#$ 485poll6 corrects temp calc for temps < 0C
# poll11 added check to not loop on dead sensor messages
# pol14 changed ftp address 6/16/09
# poll15 adds sprinkler controller 8/11/09
# poll 16,17 adds sprinkler timer control 8/22/09
# poll 18 adds 'no watering for N days'  8/26/09
# poll 19 adds first try at water meter sensor! 9/21/09
# poll 20 adds ?  also adds pid to $pidfile for watchdog  10/19/09
# poll 21 adds router power cycle/basement water sensors 10/21/09
# poll 22 adds first water sensor (wet1) 2/20/10
# still poll 22, but temporarily dropped 9, 10 as they're offline 8/10/10

use Term::ReadKey;
use POSIX "sys_wait_h";
use SendMail;

use threads("yield");
use threads::shared;
use Schedule::Cron;

#===========================
#     SAVE PID FOR WATCHDOG
#===========================
$pidfile="pidfile";
open PIDFILE,">$pidfile" or die "couldn't open \"$pidfile\" for write\n";
$mypid=$$;
print PIDFILE "$mypid";
print "Wrote PID $mypid to $pidfile\n";
close PIDFILE;



######################### We start with some black magic to print on failure.

BEGIN { $| = 1; print "485poll.plx loaded \n"; }
END {print "not ok 1\n" unless $loaded;}
use Win32::SerialPort 0.06;
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

#use strict;

#my $file = "COM4";
my $file = "COM1";
my $ob;
my $pass;
my $fail;
my $in;
my $in2;
my @opts;
my $out;
my $loc;
my $e;
my $tick;
my $tock;
my $char;
my $stat;
my $x;
my $buf;
my $sum;
my @arr;
my $lo;
my $hi;
my $i;
my $y;
my $err;
#my @necessary_param = Win32::SerialPort->set_test_mode_active;

# 2: Constructor

$ob = new Win32::SerialPort ($file) or die "Can't open $file\n";
    # next test will die at runtime unless $ob
$ob->databits(8);
$ob->baudrate(57600);
#$ob->baudrate(1200);
$ob->parity("none");
$ob->stopbits(1);
$ob->handshake("none");
$ob->buffers(100,100);
$ob->write_settings||undef $ob;
print "couldn't set up port\n" unless $ob;
#$ob->Verbose=1;


# 3: Prints Prompts to Port and Main Screen

$out= "\r\n\r\n++++++++++++++++++++++++++++++++++++++++++\r\n";
$tick= "485 net poller 2\r\n\r\n";
$e="\r\n....Bye\r\n";

print $out, $tick;


$ob->error_msg(1);		# use built-in error messages
$ob->user_msg(1);


$tick=$ob->read_interval(2);
$tick=$ob->read_interval(3);
print "read interval=$tick\n";
$tick=$ob->read_char_time(2);
$tick=$ob->read_char_time(3);
print "read char time=$tick\n";
$tick=$ob->read_const_time(30);
$tick=$ob->read_const_time(50);
print "read const time=$tick\n";
$tick=$ob->write_const_time;
print "write const time was $tick ";
$tick=$ob->write_const_time(1);
print "now $tick\n";
$tick=$ob->write_char_time;
print "write char time was $tick ";
$tick=$ob->write_char_time(1);
print "now $tick\n";
print "com port is $file\n";


$ob->rts_active("yes");
$ob->dtr_active;



#**********************************
# 	INITS
#**********************************
$testlog=1;	# if ==0, no test log created
$loopcnt=-2;
#$totalcnt=0;
#$totaldur=0;
#$lastdur=0;
$TOerr=0;
$dataErr=0;
$logfile="485log.txt";
$logfile2="485testlog.txt";
$updateFile="delta.txt";	# data file to append to file on web server
$updateInterval=300;	# secs between web server updates
$flagFile="sendit";	# tells transporter to send delta file
$errPoll=0;
#$outCnt=0;
$nopoll=0;
$rereq=0;
$details=0;
$firstLog=1;
$firstLog2=1;
$nextSend=time;
$pid=-2;	# phony - I hope it works!
$enableAlerts=1;
$disableEnd=0;
$cronIndex=0;


#**************************************************
#********  SPRINKLER CRON STUFF *******************
#**************************************************
# Since I couldn't find a good way to kill the cron thread to
# restart it, I keep an array of them.  To restart, I send a KILL 
# to the current one and start a new one.  The old one dies
# the next time it wakes up to trigger an event (and dies before
# it even calls the dispatch callback), so while there are 2
# cron threads running, only the newer will ever call dispatch.
my $zone :shared;
my $sprtime :shared;
my $cronFlag :shared;
my $sprinklerCronFile :shared;
my @cront;

$sprinklerCronFile="sprinkler-cron.txt";
# our official zone names: adams rose garage parkway overhang frt-step kitchen saylor
%relays=('adams'=>0, 'rose'=>1,'parkway'=>2,'overhang'=>3,'frt-step'=>4,'garage'=>5,
    'kitchen'=>6,'saylor'=>7);



#********  LAUNCH SPRINKLER CRON THREAD  **********
$cront[$cronIndex]=threads->create('cronsub');
$cront[$cronIndex]->detach;




#******** COMMON ROUTINES FOR ALL SENSORS **********
sub lenOcChk{
# call with expected len; assumes received string is in $locchars
($expLen)=(@_);
$len=@locchars;
$upperName=uc($s);

# pull out opcode
$OCstr="";
$recOC=($locchars[3]&0xf0)>>4;
if($recOC!=5){$OCstr="opcode $recOC";}
$detStr=$details?"opcode: $recOC len: $len ":"";

# override expected length for data ack
if($recOC==7){$expLen=7;}

if($expLen != $len){print "$upperName: bad length. Expected $expLen, received $len bytes\n";}

if($recOC == 6){logRestart();}
} # end lenOcChk


#***************************************************************
#=============== LOGIT - MAIN DATA LOGGING FUNCTION ============
#***************************************************************
#
# main value of this is headers in the log file as sorta self-describing data
# When you call it, first make sure you have a string of the var names in $logString!
sub logit{
if($firstLog==1){
	$headerString="HEADERS $s:$logString\n";
	print LOGFILE $headerString;
	push @updateLines,($headerString);
	}

print LOGFILE (@_);print LOGFILE "\n";

push @updateLines,(@_,"\n");

} # end logit


sub logit2{
if($testlog){
	if($firstLog2==1){
		$headerString="HEADERS $s:$logString\n";
		print LOGFILE2 $headerString;
		push @updateLines,($headerString);
		}
	
	print LOGFILE2 (@_);print LOGFILE2 "\n";
	
	#push @updateLines,(@_,"\n");
	}# end if $testlog
} # end logit2


#*************************************
#   DEFINE PROCESSING SUBROUTINES
# Must be done before building %sensors hash
#
# NEED TO DEAL WITH RETRANSMITS!
#
#*************************************

#---------------------------------------
# SPECIFIC PROCESSING FOR RAIN SENSOR
$rainref = sub {
$len=@locchars;
lenOcChk(7);
$cnt=$locchars[4];
$Rtotalcnt+=$cnt;
#unless($cnt==0 || $detStr==1)
	{
	printf ("RAIN OK: $detStr $OCstr %d cycles, total: %d\n",$cnt,$Rtotalcnt);
	}
#--------- LOG RAIN EVENTS --------
# event type, time, duration, float1, float2
#unless($cnt==0){
	# ugh.  Gotta keep these two strings in sync!
	$logString='$etypes{rain},$timesecs,$cnt,$Rtotalcnt';
	logit("$etypes{rain},$timesecs,$cnt,$Rtotalcnt");
#	print LOGFILE $logString;
#	print LOGFILE "$etypes{rain},$timesecs,$cnt,$Rtotalcnt\n";}
#$data{rain}[0]+=$cnt;
}; # end rain sub
#---------------------------------------


#---------------------------------------
# SPECIFIC PROCESSOR FOR SUMP/POWER SENSORS
$sumpref = sub {
# need special processing to deal with cycles that
# cross over from one sample to next
$len=@locchars;
lenOcChk(14);
$cnt=$locchars[4];
$dur=(256*$locchars[6]+$locchars[5])/5;
$sumpOn=$locchars[7];
$Stotalcnt+=$cnt;
$Stotaldur+=$dur;
$sumpState=$sumpOn?"ON":"off";

$Pcnt=$locchars[8];
$Pdur=(256*$locchars[10]+$locchars[9])/5;
$pwrOn=$locchars[11];
# is this appropriate?
#if($pwrOn==0){$outCnt++;}
$pwrState=$pwrOn?"":"POWER IS OFF!! ";
$Ptotalcnt+=$Pcnt;
$Ptotaldur+=$Pdur;
$sumpState=$sumpOn?"ON":"off";
#unless($cnt==0 && $dur==0 )
	{
	printf ("SUMP OK: $detStr$OCstr ");
	printf ("%d cycles, %01.1f sec, pump is: %s, total run secs:%01.1f total cyc:%d\n",$cnt,$dur, $sumpState,$Stotaldur,$Stotalcnt);
	printf ("and POWER OK: %s",$pwrState);
	printf ("%d cycles, %01.1f sec  total out secs: %01.1f %d outages",$Pcnt,$Pdur,$Ptotaldur,$Ptotalcnt);
	print "\n";
	}
#--------- LOG SUMP EVENTS --------
# event type, time, duration, float1, float2
# ugh.  Gotta keep these two strings in sync!
$logString='$etypes{sump},$timesecs,$cnt,$dur,$sumpOn,$Stotalcnt,$Stotaldur,$Pcnt,$Pdur,$pwrOn,$Ptotalcnt,$Ptotaldur';
logit( "$etypes{sump},$timesecs,$cnt,$dur,$sumpOn,$Stotalcnt,$Stotaldur,$Pcnt,$Pdur,$pwrOn,$Ptotalcnt,$Ptotaldur");

#$data{sump}[2]+=$cnt;
#$data{sump}[3]+=$dur;
#$data{sump}[4]+=$oflow; # effectively duration of overflow in sample times
}; # end sump sub
#---------------------------------------


#---------------------------------------
# NEED SPECIFIC PROCESSING FOR SPRINKLER!
$sprinklerref = sub {
$len=@locchars;
lenOcChk(9);
$timelo=$locchars[4];
# update these and change relay to $locchars[6] when firmware is upgraded
$timehi=$locchars[5];
$ssecs=256*$timehi+$timelo;
$relay=$locchars[6];
#$Rtotalcnt+=$cnt;
#unless($cnt==0 || $detStr==1)
	{
	printf ("SPRINKLER OK:  secs remaining: %d  valves ON (7-0): %08b\n",$ssecs,$relay);
	}
#--------- LOG SPRINKLER EVENTS --------
# nothing to log

}; # end sprinkler sub

#---------------------------------------


#---------------------------------------
# SPECIFIC PROCESSING FOR FURNACE TEMP
$furnref = sub {
$len=@locchars;
lenOcChk(11);
# NEED LOOCKUP/COMPUTE FUNCTIONS FOR THESE!
$tempRet=($locchars[4]*2+($locchars[5]&0x80)/128);
# handle signed Celsius temps - 9 bits, LSB=0.5C
if ($tempRet>255){
	$tempRet&=0xff; 		# mask off sign bit
	$tempRet^=0xff;			# invert
	$tempRet+=1;			# last correction for 2s complement
	$tempRet/=2;			# back to deg C (from half-degrees
	$tempRet=32-$tempRet*9/5;	# to F
	}
else{$tempRet=($locchars[4]+($locchars[5]&0x80)/256)*9/5+32;}

$tempSup=($locchars[6]*2+($locchars[7]&0x80)/128);
# handle signed Celsius temps - 9 bits, LSB=0.5C
if ($tempSup>255){
#print "negative...";
	$tempSup&=0xff; 		# mask off sign bit
#printf("%x ",$tempSup);
	$tempSup^=0xff;			# invert
#printf("%x ",$tempSup);
	$tempSup+=1;			# last correction for 2s complement
#printf("%x ",$tempSup);
	$tempSup/=2;			# back to deg C (from half-degrees
#printf("%x ",$tempSup);
	$tempSup=32-$tempSup*9/5;	# to F
#printf("%x ",$tempSup);
	}
else{$tempSup=($locchars[6]+($locchars[7]&0x80)/256)*9/5+32;}

printf ("FURN: $detStr$OCstr Ret:%0.1f degF  Sup:%0.1f degF\n",$tempRet,$tempSup);

#$airflow=$locchars[5];
# HOW DO WE MANAGE "UNUSUAL" PRINT FOR TEMPS?
#unless($cnt==0 && $dur==0 && $oflow==0)
#	{
#	printf ("OK: opcode: %s  len: %d  ",$opcode,$len);
#	printf ("%d cycles, %01.1f sec, overflow: %d",$cnt,$dur, $oflow);
#	print "\n";
#	}
	
#--------- LOG TEMP VALUES --------
# event type, time, supply, return, airflow
# ugh.  Gotta keep these two strings in sync!
$logString='$etypes{furn},$timesecs,$tempRet,$tempSup';
logit("$etypes{furn},$timesecs,$tempRet,$tempSup");

}; # end furn sub
#---------------------------------------


#---------------------------------------
# SPECIFIC PROCESSING FOR proto SENSOR
$protoref = sub {
$len=@locchars;
if($len != 7){print "PROTO: bad length - $len, expected 7\n";}
$dur=($locchars[4])/50;
$cnt=$locchars[3];
#$totaldur+=$dur;
#$totalcnt+=$cnt;
#unless($cnt==0 && $dur==0)
	{
	printf ("PROTO OK: opcode: %s  len: %d data: ",$opcode,$len);
	printf ("%d cycles, %d sec",$cnt,$dur);
	print "\n";
	}
$data{proto}[2]+=$cnt;
$data{proto}[3]+=$dur;
}; # end proto sub
#---------------------------------------


#---------------------------------------
# SPECIFIC PROCESSING FOR TEMPSENSOR TESTING
$temp2ref = sub {
$len=@locchars;
lenOcChk(11);
# NEED LOOCKUP/COMPUTE FUNCTIONS FOR THESE!
$tempRet=($locchars[4]*2+($locchars[5]&0x80)/128);
# handle signed Celsius temps - 9 bits, LSB=0.5C
if ($tempRet>255){
	$tempRet&=0xff; 		# mask off sign bit
	$tempRet^=0xff;			# invert
	$tempRet+=1;			# last correction for 2s complement
	$tempRet/=2;			# back to deg C (from half-degrees
	$tempRet=32-$tempRet*9/5;	# to F
	}
else{$tempRet=($locchars[4]+($locchars[5]&0x80)/256)*9/5+32;}

$tempSup=($locchars[6]*2+($locchars[7]&0x80)/128);
# handle signed Celsius temps - 9 bits, LSB=0.5C
if ($tempSup>255){
#print "negative...";
	$tempSup&=0xff; 		# mask off sign bit
#printf("%x ",$tempSup);
	$tempSup^=0xff;			# invert
#printf("%x ",$tempSup);
	$tempSup+=1;			# last correction for 2s complement
#printf("%x ",$tempSup);
	$tempSup/=2;			# back to deg C (from half-degrees
#printf("%x ",$tempSup);
	$tempSup=32-$tempSup*9/5;	# to F
#printf("%x ",$tempSup);
	}
else{$tempSup=($locchars[6]+($locchars[7]&0x80)/256)*9/5+32;}

#$addr75=$locchars[8];	# LM75 address from 2 input bits

#printf ("TEMP2: $detStr$OCstr Ret:%0.1f degF  Sup:%0.1f degF\n",$tempRet,$tempSup);
printf ("TEMP2: $detStr$OCstr Outside:%0.1f degF  WPipe:%0.1f degF\n",$tempRet,$tempSup);

#--------- LOG TEMP VALUES --------
# event type, time, supply, return, airflow
# ugh.  Gotta keep these two strings in sync!
$logString='$etypes{temp2},$timesecs,$tempSup,$tempRet';
logit("$etypes{temp2},$timesecs,$tempSup,$tempRet");

}; # end temp2 sub
#---------------------------------------


#---------------------------------------
# SPECIFIC PROCESSING FOR WATER METER SENSOR
$waterref = sub {
$len=@locchars;
lenOcChk(8);
$vallo=$locchars[4];
$valhi=$locchars[5];
$Wval=$vallo+256*$valhi;
$Wtotalval+=$Wval;
	{
	printf ("WATER METER OK: $detStr $OCstr value: %d  total: %d\n",$Wval, $Wtotalval);
	}
#--------- LOG WATER METER EVENTS --------
# event type, time, duration, float1, float2
#unless($cnt==0){
	# ugh.  Gotta keep these two strings in sync!  WHY???
	$logString='$etypes{water},$timesecs,$Wtotalval';
	logit("$etypes{water},$timesecs,$Wtotalval");
#	print LOGFILE2 $logString;
#$data{water}[0]+=$cnt;
}; # end watermeter sub
#---------------------------------------


#---------------------------------------
# SPECIFIC PROCESSING FOR WET FLOOR SENSOR 1

# WARNING: DEAD SENSOR CHECK DEFEATED WITH sentMsg{wet1}=1!

$wet1ref = sub {
$len=@locchars;
lenOcChk(8);
$wetbits=$locchars[4];
$volt=$locchars[5];
	{
	printf ("WATER SENSOR 1 OK: $detStr $OCstr sensors: %08b  voltage: %d\n",$wetbits, $volt);
	}
#--------- LOG WATER SENSOR 1 EVENTS --------
# event type, time, duration, float1, float2
#unless($cnt==0){
	# ugh.  Gotta keep these two strings in sync!  WHY???
	$logString='$etypes{wet1},$timesecs,$wetbits,$wvolt';
	#logit("$etypes{wet1},$timesecs,$wetbits,$volt");
#	print LOGFILE2 $logString;
#$data{wet1}[0]+=$cnt;
}; # end wet1meter sub
#---------------------------------------


#---------------------------------------
# SPECIFIC PROCESSING FOR ROUTER RESET CONTROLLER
$routerref = sub {
$len=@locchars;
lenOcChk(8);
$Cval=$locchars[4];
#$valhi=$locchars[5];
#$Cval=$vallo+256*$valhi;
#$Ctotalval+=$Cval;
	{
	printf ("ROUTER RESETTER OK: $detStr $OCstr value: %d\n",$Cval);
	}
#--------- LOG ROUTER RESET EVENTS --------
# event type, time, duration, float1, float2
#unless($cnt==0){
	# ugh.  Gotta keep these two strings in sync!  WHY???
	#$logString='$etypes{router},$timesecs,$Cval';
	#logit("$etypes{router},$timesecs,$Cval");
#	print LOGFILE2 $logString;
#$data{router}[0]+=$cnt;
}; # end router reset sub
#---------------------------------------


#---------------------------------------
# SPECIFIC PROCESSING FOR ERROR POLLS
# assumes $s is sensor name!
$errref = sub {
$len=@locchars;
if($len != 9){print "ERRPOLL: bad length - $len, expected 9\n";}
$crcErrCnt=$locchars[4];
$sanErrCnt=$locchars[5];
$errFlags=$locchars[6];
	{
	printf ("ERRS %s:  crcErrCnt: %d  sanErrCnt: %d errFlags: %02x ",$s,$crcErrCnt,$sanErrCnt,$errFlags);
	printf "ErrRetry: %d TORetry: %d  TimeOut: %d\n",
		$errs{$s}[0],$errs{$s}[1],$errs{$s}[2];
	$errStrLine="$errtypes{$s},$timesecs,$crcErrCnt,$sanErrCnt,$errFlags,";
	$errStrLine.="$errs{$s}[0],$errs{$s}[1],$errs{$s}[2]\n";
	# THIS SHOULD USE logit! - or not: doesn't work for first time
	print LOGFILE $errStrLine;
	push @updateLines,($errStrLine);
	}
#$data{$s}[5]+=$crcErrCnt;
#$data{$s}[6]+=$sanErrCnt;
}; # end err poll sub
#---------------------------------------


#*************************************
#          OPEN LOG FILE
#*************************************
open LOGFILE, ">>$logfile" or die "couldn't open $logfile\n";
select LOGFILE;
$|=1;
$time0=time();
$tsecs=localtime($time0);
$startStr="\nSTARTED POLL APP at $tsecs offset:$time0\n";
# SHOULD USE logit!!
print LOGFILE ($startStr);
push @updateLines, ($startStr);

select STDOUT;
$|=1;

#------------- open special test logfile ------------
if($testlog){
	open LOGFILE2, ">>$logfile2" or die "couldn't open $logfile2\n";
	select LOGFILE2;
	$|=1;
	$time0=time();
	$tsecs=localtime($time0);
	$startStr="\nSTARTED POLL APP at $tsecs offset:$time0\n";
	# SHOULD USE logit!!
	print LOGFILE2 ($startStr);

	select STDOUT;
}# end if testlog


#*************************************
#       SET UP ALL KNOWN SENSORS
#*************************************
# What we know about each sensor:
# - name
# - address ( 0-15) (0 is master)
# - poll rate
# - and what kind of data it returns.  
# We call a sensor-specific subroutine for each.
# All necessary PROCESSING is done there.
#
# We also keep a hash of the data associated with each
# sensor.  Not well defined yet.  We have:
#
# cycles: count of whatever it's counting
# totalDuration: of whatever it's watching
#
# We also keep a hash of error counts per sensor.  These
# are pretty cut and dried.  So far we have:
# dataErrs: count of checksum/data validation on receipt
# TOerrs: sensor didn't respond in time
# totErrCnt: don't remember 
#*************************************
#$sensors{sensor-name} =>[addr,pollrate,name of PROCESSING sub]
#$errs{sensor-name} = [dataErrs,TOerrs,totErrCnt];
#$errtypes{sensor-name} = small int to identify error type
#$etypes{sensor-name} = small int to identify event type
#$retypes{sensor-name} = small int to identify Restart event type

#$sensors{power} = [2,5,$powerref];
$errs{power}=[0,0,0];
#data{power} [cycles,duration(2B)]
$data{power} = [0,0];
$etypes{power}=1;
$retypes{power}=2;

$sensors{sump} = [3,5,$sumpref];
$errs{sump}=[0,0,0];
#$data{sump} [cycles, duration(2B), float]
$data{sump} = [0,0,0,0,0,0];
$etypes{sump}=3;
$errtypes{sump}=11;
$retypes{sump}=4;

$sensors{rain} = [1,60,$rainref];
$errs{rain}=[0,0,0];
#data{rain} [tip count]
$data{rain} = [0];
$etypes{rain}=5;
$errtypes{rain}=12;
$retypes{rain}=6;

$sensors{furn} = [6,5,$furnref];
$errs{furn}=[0,0,0];
# doesn't make sense...
#$data{furn} [returnTemp,supplyTemp]
$data{furn} = [0,0];
$etypes{furn}=7;
$errtypes{furn}=13;
$retypes{furn}=8;

#$sensors{proto} = [4,5,$protoref];
$errs{proto}=[0,0,0];
$data{proto} = [0,0,0,0,0,0];
$etypes{proto}=9;
$errtypes{proto}=14;
$retypes{proto}=10;

$sensors{temp2} = [5,5,$temp2ref];
$errs{temp2}=[0,0,0];
# doesn't make sense...
#$data{temp2} [returnTemp,supplyTemp]
$data{temp2} = [0,0];
$etypes{temp2}=11;
$errtypes{temp2}=15;
$retypes{temp2}=12;

$sensors{sprinkler} = [7,5,$sprinklerref];
$errs{sprinkler}=[0,0,0];
#$data{sprinkler} [cycles, duration(2B), float]
$data{sprinkler} = [0,0,0,0,0,0];
$etypes{sprinkler}=13;
$errtypes{sprinkler}=16;
$retypes{sprinkler}=17;

$sensors{water} = [8,5,$waterref];
$errs{water}=[0,0,0];
$data{water} = [0,0,0,0,0,0];
$etypes{water}=15;
$errtypes{water}=17;
$retypes{water}=16;

#$sensors{router} = [9,5,$routerref];
$errs{router}=[0,0,0];
$data{router} = [0,0,0,0,0,0];
$etypes{router}=18;
$errtypes{router}=20;
$retypes{router}=19;

#$sensors{wet1} = [10,5,$wet1ref];
$sentMsg{wet1}=1;	# don't do dead check on me
$errs{wet1}=[0,0,0];
$data{wet1} = [0,0,0,0,0,0];
$etypes{wet1}=21;
$errtypes{wet1}=23;
$retypes{wet1}=22;

#----------- OTHER ERROR TYPES --------
$etypes{badaddr}=99;


# --------- Reverse lookup from addr to string name --------
for $name (keys(%sensors)){
	$names[$sensors{$name}[0]]=$name;	
	}





#*************************************
#       MAIN POLL ONE SENSOR ROUTINE
# set $dest, $opcode [, @sendData] before calling
#*************************************
sub pollit{
	$pollDebug=$details;
	if($pollDebug){print"sensor \'$s\'  ";}
	# @sendData is what we send to operate a sensor
	$srcAddr=0;	# master address
	$len=@sendData+2;
	$oplen=16*$opcode+$len;
	
	# compute checksum
	$sum=0;
	$sum+=0x55; #header
	$sum+=$srcAddr;
	$sum+=$dest;
	$sum+=$oplen;
	for ($i=0;$i<@sendData;$i++){$sum+=ord($sendData[$i]);}
	$sum &=0xffff;
	$sum1=$sum&0xff;
	$sum2=$sum/256;
#	if($pollDebug){printf ("sum is 0x%x %0x %0x\n",$sum,$sum2, $sum1);}
	
#$string=chr(85).chr($dest).chr($oplen).$data.chr($sum1).chr($sum2);
	$string=chr(85).chr($srcAddr).chr($dest).chr($oplen);
	for($i=0;$i<@sendData;$i++){$string.=$sendData[$i];}
	$string.=chr($sum1).chr($sum2);
	
	if($pollDebug){printf ("POLL opcode/length is 0x%x  ",$oplen);
	printf ("sum is 0x%x\n",$sum);
	print"POLL string sent: ";
	for($i=0;$i<length($string);$i++){
		printf ("%02x ",ord(substr($string,$i,1)));
		}
	print "\n";
#	print "sending \"$string\" sum=$sum\n";
	}
	$ob->rts_active("no");
	# pause to allow direction control to stabliize?
	select undef,undef,undef,.06;

	$ob->write($string);
	select undef,undef,undef,.006;
#	for($x=0;$x< 300;$x++){$tick=$x*$x*1.23;}
	$ob->rts_active("yes");

} # end pollit()


#***********************************************
#***********************************************
#      CHECKIT - VALIDATE RECEIVED MESSAGE
#***********************************************
#***********************************************
sub checkit{
$timesecs=time()-$time0; #used to try to save a couple of bytes/line
#$timesecs=time();
#$loc="";
$sum=0;

# this is the number of bytes physically received
# not necessarily what the protocol says!
$reclen=length($loc);
if($reclen < 6){print "too short: reclen=$reclen\n";return (-1);}
if($details==1){print "bytes recvd (reclen):$reclen\n";}
# take off CRC
#$reclen -=2;

# break received msg into bytes
#(@arr,$lo,$hi)=unpack "C*CC",$loc;
(@locchars)=unpack "C*",$loc;

# GENERIC BYTE PRINTER
if($details==1){
	print"checkit RECEIVED:";
	for ($byte=0;$byte<$reclen;$byte++){
		printf ("0x%02x ",$locchars[$byte]);
		if ($reclen-$byte == 3){print ("sum:");}
	}
print"\n";
#print"\$loc is \"$loc\"\n";
}


# ------- CHECK SOURCE, DEST ADDRESSES ---------
$srcAddr=($locchars[1]) ;
$destAddr=($locchars[2]);

# master addr must be 0
$badAddr=0;
#print "expecting from src addr $sensors{$s}[0]\n";
if(($destAddr != 0) || ($srcAddr != $sensors{$s}[0])){#logMsg;
	$badAddr=1;	# ignore this message!
	$errstring=sprintf ("BAD SRC/DEST ADDR: 0x0%x 0x0%x\n",$locchars[1],$locchars[2]);
	print $errstring;
	print LOGFILE "$etypes{badaddr},$timesecs,$errstring";
	}


# parse out opcode
$recOC=($locchars[3]& 0xF0)>>4;

## parse out length provided by sender
$len=($locchars[3]& 0xF);

# debug hack
#if($srcAddr==7){$reclen--;}

if ($len != $reclen-4){print "bad length: from oplen:$len  btyes rec: $reclen\n"; return(-1);}

for ($i=0;$i<$len+2;$i++) {$sum+=$locchars[$i];}
$lo=$locchars[$len+2];
$hi=$locchars[$len+3];
#print "OC: $recOC  len: $len  lo: $lo  hi: $hi sum: $sum\n";
if($badAddr!=0 || $sum != ($lo+256*$hi)){return $sum;}
#if($sum != ($lo+256*$hi)){print "bad sum\n";return $sum;}
else {return 0;}

} # end checkit



#********************************************
#        VARIOUS GENERIC LOGGERS
#********************************************
sub logRestart(){
$eventType=$retypes{$s};

print LOGFILE "$eventType,$timesecs\n";

# disabled logging restarts 2/25/10 because temp2 was returning opcode 6
# with every poll.  Huh? 
#push @updateLines,("$eventType,$timesecs\n");
} # end sub logRestart

sub logMsg(){
$msglen=@locchars;
print LOGFILE "$etypes{badmsg},$timesecs";
for ($byte=0;$byte<$msglen;$byte++){
		printf LOGFILE ("0x%02x ",$locchars[4+$byte]);
	}
print LOGFILE "\n";
} # end of logMsg


#print "EXITING TEST MODE\n";
#exit();



#********************************************
#     READIT - MAIN READ AND HANDLE RESPONSE
#********************************************
sub readit() {
# MAIN READ [LOOP]
$ErrRetry=0;
$TOretry=0;

readAgain:
	$tick=999;
	$loc=$ob->read(100);
	$len=length($loc);
	if ($loc ne "") {
		$tick=checkit;
	}

# GENERIC BYTE PRINTER
#	print"RECEIVED:";
#	for ($byte=0;$byte<$len;$byte++){
#		printf ("0x%02x ",$locchars[3+$byte]);
#		if ($len-$byte == 3){print ("sum:");}
#	}
	
	
	# HANDLE RESPONSES
	if ($tick==0 && $locchars[0]==0x55 && $locchars[2]==0) {
	#  HANDLE GOOD RESPONSE
		$opcode=($locchars[3]&0xf0)>>4;
		$len=($locchars[3]&0x0f);
		$sender=($locchars[1]);

		# CALL OPCODE/SENSOR-SPECIFIC PROCESSING ROUTINE
OPCODES:{
		#print"  OPCODE: $opcode  len:$len  reclen:$reclen\n";
		if($errPoll){&{$errref}; last OPCODES;}
		# NEEDS TO BE UPDATED WHEN SPRINKLER FIRMWARE IS UPDATED!
		if($opcode==7 && $reclen==7 && $len==3){
			print"  $names[$sender] ACK received OK\n"; last OPCODES;}
		&{$sensors{$s}[2]}; last OPCODES;
		} # end OPCODES block
	
	} # end if good response
	else {

		# HANDLE DATA ERR
		if($tick != 999){
			if($ErrRetry<3){$ErrRetry++;print "+";pollit;goto readAgain;}
			print "Data Error ";
			@locchars=unpack("C*",$loc);
			for $onechar (@locchars){printf ("%x ",$onechar)}
			print "\n";
		
			$dataErr++;
			goto finish;
			}
			
		
		# HANDLE TIMEOUT
		if($tick==999){
			if($TOretry<3){$TOretry++;print"*";pollit;goto readAgain;}
			$TOerr++;
			print "\nTIMEOUT  ";
			$errs{$s}[2]++; # timeout count
			print "\"$loc\"\n";
			@locchars=unpack("C*",$loc);
			for $onechar (@locchars){
				printf ("%x ",$onechar)}
			print "\n";
		} # end if tick==999
	} # end else
	
finish:
# update retry counts for this sensor
$errs{$s}[0]+=$ErrRetry;
$errs{$s}[1]+=$TOretry;

#*********** DEAD SENSOR CHECK ****************
#  NEEDS SOME KIND OF RESET!!
if(($errs{$s}[2]==5)&&($sentMsg{$s}!=1)){
	@retvals=sendSMS("dead sensor","$s sensor timed out 5 times");
	if($retvals[0]){print "ALERT ERROR: $retvals[1]\n";};
	$sentMsg{$s}=1;
	} # end timeout check

#sleep(1);

return();
} # end readit

#********************************************
#         END READIT
#********************************************



#********************************************
#********************************************
#        MAIN POLL LOOP
#********************************************
#********************************************
$loopDebug=1;
while(1){
#--------- DON'T POLL FOR KEYPRESSES --------
if($nopoll){$nopoll=0;goto SKIPPEDPOLL;}

#--------- POLL FOR ERRORS ---------
if (0 && $loopcnt%60==0){$errPoll=1;}

#----------- CHECK FOR CRON JOBS (SPRINKLER ET AL) ----------
if($cronFlag){
	$cronFlag=0;
	$sprts=shortTS();
	
	#------ handle moisture calc -------
	if($zone eq "calc"){
		print "  RECALCULATING SOIL MOISTURE...\n";
		# put code to do it here!
		
		} # end if calc
	
	#------ handle sprinkler trigger ------
	elsif (defined $relays{$zone}){
		if($disableEnd > time()){
			print"  Sprinkler \'$zone\' triggered but watering is disabled.\n";
			} # end if still disabled
		else{
		print "  SPRINKLER: turning on \"$zone\" for $sprtime minutes at $sprts\n";
		$relayNum=$relays{$zone};
		$s="sprinkler";
		$relayDur=int(6*$sprtime); # in units of 10 sec
#print"relayNum:\"$relayNum\"  relayDur:\"$relayDur\"\n";

		$sendData[0]=chr (2*$relayNum+1);
		$sendData[1]=chr ($relayDur);
		$dest=7;$opcode=5;
		pollit;
		readit;
		} # end else not disabled
		} # end if defined $relays{$zone}
	else{print"  CRON TASK \"$zone\" UNDEFINED - IGNORING!\n";}
	} # end if $cronFlag
	

# the $s that gets set here is used by others!
#*********** LOOP THRU ALL CONFIGURED SENSORS ***************
for $s (keys %sensors){
	# set up poll params
	# if errPoll, use get err opcode, else poll
	$opcode=1;
	$opcode=$errPoll?"4":"$opcode";
	$opcode=$rereq?"2":"$opcode";
	$retrans=$rereq?"RETRANS ":"";
#	@sendData=("1");
	@sendData=();
	$dest=$sensors{$s}[0];
	if($loopDebug){print "polling $retrans$s addr $dest  \n";}
	
	#----------- handle temporarily skipped sensors ----------
	unless($skip[$dest]){
		#----------- POLL THE SENSOR-------------
		pollit;

		#----------- READ RESPONSE FROM SENSOR ---------------
		readit();
		
	}# end unless skip
	else {print" skipping $dest\n";}
	
} # end for $s

#------------ END MAIN LOOP THROUGH SENSORS -------------



SKIPPEDPOLL:
#-------------- MAKE SURE TRANSPORT PROCESS IS RUNNING --------
# this should be redone with threads!
$retval=waitpid($pid,WNOHANG);
#print "\twaitpid returned $retval\n";
		
#----------- CHECK FOR START/RESTART TRANSPORT CHILD -----------
# check two cases
if($retval==$pid){print "CHILD DIED!\n";$startChild=1;}
if($retval == -1){print "NO CHILD!\n"; $startChild=1;}
		
#------------- START/RESTART HERE ---------
if($startChild){
	$startChild=0;
	$pid = fork();
	#print "pid is $pid\n";
	if (not defined $pid) {print "resources not avilable.\n";} 
	elsif ($pid == 0) {goto TRANSPORT;}

	print "starting/restarting transport - child pid is $pid\n";
	} # end restart code



#---------- TIME TO SEND SOME DATA TO WEB SITE? --------
if((! -f $flagFile) and ($nextSend-time <=0)){
	# here's update data to be appended to datafile on web server
	open UPDATE, ">$updateFile";	# need to log error here!
	for $line (@updateLines){print UPDATE $line;}
	close UPDATE;
	@updateLines="";

	# this file tells transporter to send $updateFile to web server
	open FLAG, ">$flagFile";
	$ts=localtime;
	print FLAG $ts;
	close FLAG;
	
	$nextSend=time+$updateInterval;
	print".";	# flag that we're trying to transport
	}

$rereq=0;
$errPoll=0;
$firstLog=0;
$firstLog2=0;


$SLEEPTIME=60;
#sleep ($SLEEPTIME);

#---------- SLEEP BETWEEN POLLS WITH KEYBOARD CHECK -----
ReadMode(3); # allow ctrl chars, else raw
if(not defined($key=ReadKey($SLEEPTIME))){
	# fall through if not keypress
	}else{
	#print"key was $key\n";

#	UPDATE THIS HELP WITH EACH NEW OPTION!
	#-------- LIST OPTIONS -------
	if($key eq "?"){
print "PID is $mypid\n";
print "	a text alerts off
	A text alerts on
	d details off
	D details on
	r next poll is all retransmits
	R reset one sensor (it will ask which)
	e do error poll
	f flush any pending input
	s print err stats
	t transmit ftp updates
	w control a sprinkler relay
	n no watering for a while
	c restart cron thread
	S skip sensor temporarily
	u unskip sensor
	j trigger router power cycle
	? this help message\n";
	$nopoll=1;
		}
	
	#-------- RETRANS FROM ALL -------
	if($key eq "r"){
		print"  Requesting retrans...\n";
		$rereq=1;}
	
	#-------- TURN ON DETAILS -------
	if($key eq "D"){
		print"  Details ON\n";
		$details=1;}
	
	#-------- TURN OFF DETAILS -------
	if($key eq "d"){
		print"  Details OFF\n";
		$details=0;
		$nopoll=1;}
	
	#---------- RESET ONE SENSOR --------
	if($key eq "R"){
		ReadMode(0);
askReset: print "addr of sensor to reset (? for list): ";
		$dest=<>; 
		chomp $dest;
		if($dest eq "?"){
			my $i=0;
			for $sens (keys %sensors){
				print"$sens:$sensors{$sens}[0] ";
				#if(++$i==4){print"\n";}
				} # end for $sens
				print"\n";
			goto askReset;
			} # end if dest eq ?
		$opcode=3;
		pollit;	
		sleep(3);	
		}
	
	#-------- DO ERROR POLL -------
	if($key eq "e"){$errPoll=1;}
	
	#---------- FLUSH SERIAL INPUT BUFFER --------
	if($key eq "f"){
		print "flushing... ";
		$loc=$ob->read(1000);
		$len=length($loc);
		print "dumped $len bytes\n";
		}

	#-------- SHOW ERR STATS -------
	if($key eq "s"){
	    for $s (keys %errs){
		#print "$s: ErrRetry:$errs{$s}[0] TOretry:$errs{$s}[1] Timeouts:$errs{$s}[2]\n";
		printf "%10s: ErrRetry:%d TOretry:%d Timeouts:%d\n",
			$s,$errs{$s}[0],$errs{$s}[1],$errs{$s}[2];
			}
		$nopoll=1;
		} # end err stats
	
	#-------- TRANSMIT FTP UPDATE -------
	if($key eq "t"){$nextSend=0; $nopoll=1;}
	
	#---------- CONTROL SPRINKLER --------
	if($key eq "w"){
		ReadMode(0);
		print "on or off (1/0): ";
		$relayState=<>;
		chomp $relayState;
		if($relayState eq ""){$relayState=0;}
		
		#------ display relay list -----
		$si=0;
		for $sprzone (keys %relays){
			print"$sprzone:$relays{$sprzone} ";
			if(++$si==4){print"\n";}
			} # end for $sprzone
			print"\n";

askRelay:	print "relay to control (0-7): ";
		$relayNum=<>; 
		chomp $relayNum;
		if($relayNum eq ""){$relayNum=0;}
		$onoff=$relayState?"ON":"OFF";
		
		print "duration (1=10sec): ";
		$relayDur=<>;
		chomp $relayDur;
		if($relayDur eq ""){$relayDur=0;}
		$relay10Dur=10*$relayDur;
		if($relayNum==8 or $relayDur==0){
			print"Turning ALL relays OFF\n";
			}
		else{
			print "Turning sprinkler relay $relayNum $onoff for $relay10Dur sec\n";
			}
		$sendData[0]=chr (2*$relayNum+$relayState);
		$sendData[1]=chr ($relayDur);
		$s="sprinkler";
		$dest=7;$opcode=5;
		pollit;	
		readit;
		$nopoll=1;
		}
	
	#-------- TURN ON TEXT ALERTS -------
	if($key eq "A"){$enableAlerts=1; print "\nText Alerts ON\n\n";$nopoll=1;}
	
	#-------- TURN OFF TEXT ALERTS -------
	if($key eq "a"){$enableAlerts=0; print "\nText Alerts OFF\n\n";$nopoll=1;}
	
	#-------- SKIP A SENSOR TEMPORARILY -------
	if($key eq "S"){
		ReadMode(0);
askSkip: print "addr of sensor to skip (? for list): ";
		$dest=<>; 
		chomp $dest;
		if($dest eq "?"){
			my $i=0;
			for $sens (keys %sensors){
				print"$sens:$sensors{$sens}[0] ";
				#if(++$i==4){print"\n";}
				} # end for $sens
				print"\n";
			goto askSkip;
		} # end if dest eq ?
		
		$skip[$dest]=1;
	} # end if 'S'
	
	#-------- STOP SKIPPING A SENSOR -------
	if($key eq "u"){
		ReadMode(0);
askUnSkip: print "addr of sensor to stop skipping (? for list): ";
		$dest=<>; 
		chomp $dest;
		if($dest eq "?"){
			my $i=0;
			for $sens (keys %sensors){
				print"$sens:$sensors{$sens}[0] ";
				#if(++$i==4){print"\n";}
				} # end for $sens
				print"\n";
			goto askUnSkip;
		} # end if dest eq ?
		
		$skip[$dest]=0;
	} # end if 'u'
	
	
	#---------- TRIGGER ROUTER POWER CYCLE -------------
	if($key eq "j" or $key eq "J"){
		$sendData[0]=$key;
		$s="router";
		$dest=9;$opcode=5;
		pollit;	
		readit;
		$nopoll=1;
		
		}# end if j
	
	
	#-------- TURN OFF WATERING -------
	if($key eq "n"){
		ReadMode(0);
		if(time()<$disableEnd){
			($sec,$mins,$hour,$mday,$mon,$year,$wday,$x)=localtime($disableEnd);
			$DoW=("Sun","Mon","Tue","Wed","Thu","Fri","Sat")[$wday];
			$waterEnd=sprintf "%s %d/%d %02d:%02d",$DoW,$mon,$mday,$hour,$mins;
			print"  Watering is currently disabled until $waterEnd.\n"
			} # end if time<$dE
		print"Number of days to disable watering: (<cr> for no change)";
		$disableDays=<>;
		chomp $disableDays;
		if($disableDays eq ""){print "No change to watering.\n";}
		else{
			$disableEnd=time()+$disableDays*24*3600;
			($sec,$mins,$hour,$mday,$mon,$year,$wday,$x)=localtime($disableEnd);
			$DoW=("Sun","Mon","Tue","Wed","Thu","Fri","Sat")[$wday];
			$waterEnd=sprintf "%s %d/%d %02d:%02d",$DoW,$mon,$mday,$hour,$mins;
			print"  Disabling watering for $disableDays days - until $waterEnd\n";
			}
		$nopoll=1;
		}# end $key eq 'n'
	
	#-------- RESTART CRON THREAD  -------
	# really starts a new one and tells old to die next time it wakes up
	if($key eq "c"){
		print "  Restarting cron thread...\n";
		print"  sending KILL to thread $cronIndex...";
		$cront[$cronIndex]->kill('KILL');
		print" starting new cron thread $cronIndex...";
		#********  LAUNCH SPRINKLER CRON THREAD  **********
		$cront[++$cronIndex]=threads->create('cronsub');
		$cront[$cronIndex]->detach;
		if($cront[$cronIndex]->is_running()){print" OK\n";}
			else{print" FAILED!\n";}
		$nopoll=1;
		} # end if "c"
	
	
	} # end check for keypress
ReadMode(0);



if (0 && $loopcnt%60==0){

	$ts=time;
#	print "totalcnt: $totalcnt  totaldur: $totaldur  TO errs: $TOerr  Bad: $dataErr\n";

#	for $s (keys %data){
	$statsStr="$errtypes{$s},$timesecs,$errs{$s}[0],$errs{$s}[1],$errs{$s}[2],";
#	$statsStr.="
#		print LOGFILE "$ts,$s,$sensors{$s}[0],$data{$s}[0],$data{$s}[1],$data{$s}[2],$data{$s}[3]\n";
#		}
	}

$loopcnt++;

} # end main loop



#*************************************************************************
#*********************** SPRINKLER CRON TAB STUFF ********************
#*************************************************************************
# default dispatcher
sub cronDispatch{
	$zone=$_[0];
	$sprtime=$_[1];
print"  CRON dispatcher sub triggering \'$zone\' for $sprtime mins\n";
$cronFlag=1;
}# end cronDispatch


#*************************  CRON THREAD CODE  ****************************
# this executes as a separate thread, reading crontab and calling
# cronDispatch when it's time to do something
sub cronsub{
# arrange so we can be killed by main thread
$SIG{'KILL'} = sub {print"  Cron thread KILLed - exiting\n"; threads->exit(); };

my $cron = new Schedule::Cron(\&cronDispatch);

$cron->load_crontab(file=>"$sprinklerCronFile",eval=>1);
print"\n  cron sub started...\n";
$cron->run();
}# end cronsub
#*************************************************************************


#*************************************************************************
#make shortish timestamp: 12/30/2007 12:3:23
sub shortTS(){
($sec,$mins,$hour,$mday,$mon,$year,$x)=localtime();
$year+=1900;
if($sec<10){$sec="0$sec"};
if($mins<10){$mins="0$mins"};
if($hour<10){$hour="0$hour"};
$mon++;	# this one is 0-based!
$tstamp=$mon."/".$mday."/".$year." ".$hour.":".$mins.":".$sec;
return $tstamp;
}# end shortTS
#*************************************************************************


#*************************************************************************
#*********************** SMS SEND ALERT SUROUTINE ********************
#*************************************************************************
sub sendSMS{
unless($enableAlerts){return(0,"SMS MESSAGES TURNED OFF");}
	# be sure you include "use SendMail"!
	# usage: sendSMS("message subject","message body");
	# returns, (0 if OK or -1 , error message if any)
	
       $smtpserver	     = "smtp.sbcglobal.yahoo.com";
       $smtpport	     = 25;
       $sender		     = "Jim Williams <jimlaurwilliams\@sbcglobal.net>";
       $userid		     = "jimlaurwilliams\@sbcglobal.net";
       $password	     = "jimw123";
       $subject		     = "SMS test";
       $recipient	     = "Jims Treo <6306054718\@vtext.com>";
       
       $replyto		     = $sender;
       $header		     = "X-Mailer";
       $headervalue	     = "Perl SendMail Module 1.09";

 	my ($subj,$msg);
 	$arg1=$_[0];$arg2=$_[1];
 	chomp $arg1; chomp $arg2;
 	$subj=($arg1)?$arg1:"message from home";
 	$msg=($arg2)?$arg2:"no message body provided";
 	
       $obj = new SendMail();
       $obj = new SendMail($smtpserver);
       $obj = new SendMail($smtpserver,	$smtpport);

       $obj->setDebug($obj->ON);
       $obj->setDebug($obj->OFF);

       $obj->From($sender);
       $obj->Subject($subj);
       $obj->To($recipient);
       $obj->setAuth($obj->AUTHLOGIN, $userid, $password);
       $obj->setMailHeader($header, $headervalue);
       $obj->setMailBody($msg);
       $retval=$obj->sendMail();
       # returns 0 if OK, -1 under at least some other cases
       #if ($retval != 0) {print"mail error:". $obj->{'error'}."\n";}
       
	$errmsg=$obj->{'error'};

       $obj->reset();
       return ($retval,$errmsg);
} # end sendSMS




#*************************************************************************
#*************************************************************************
#
#*********************** TRANSPORT CHILD PROCESS CODE ********************
#
#*************************************************************************
#*************************************************************************
TRANSPORT:
# checks for flag file, and does autoftp of deltas to data file to append to web site
# autoftp.pl -u jimw@midsummermania.com -p jimw123 -a -t datafile.csv midsummermania.com;www/jim;;delta.txt
#---------- TRANSPORT INITS ----------
#$user="jimw\@midsummermania.com";
$user="jimwhosting";
#$passwd="jimw123";
$passwd="Jimw1234";
$target="datafile.csv";
$target2="pingstats.csv";
#$site="midsummermania.com";
$site="jimlaurwilliams.org";
#$dir="www/jim";
#$dir="/public_html/jim";
$dir="/";
$fileToSend="delta.txt";
$fileToSend2="pingxfer.txt";
$flagFile="sendit";
$flagFile2="sendit2";
$sleeptime=10;
$success=0;
$success2=0;
$fails=0;
$fails2=0;
$report=0; # print report line this time?


#--------- TRANSPORT MAIN LOOP ------------
while(1){

#make shortish timestamp: 12/30/2007 12:3:23
#($sec,$mins,$hour,$mday,$mon,$year,$x)=localtime();
#$year+=1900;
#if($sec<10){$sec="0$sec"};
#if($mins<10){$mins="0$mins"};
#if($hour<10){$hour="0$hour"};
#$mon++;	# this one is 0-based!
#$tstamp=$mon."/".$mday."/".$year." ".$hour.":".$mins.":".$sec;
$tstamp=shortTS();

-f $flagFile; -f $fileToSend; #is this to stat the files??  why??


#------------- SEND 485 SENSORS ---------
if((-f $flagFile) and (-f $fileToSend)){
	$report=1;
	$cmd="autoftp.pl -u $user -p $passwd -a -t $target $site;$dir;;$fileToSend";
	#print "cmd is $cmd\n";
	$return=system("$cmd");

	# error message if send failed; else increment successes and remove flag file
	if ($return) {$fails++; print "    TRANSPORT: send failed $tstamp!\n";}
		else {$success++;
		unless (unlink $flagFile) {print "    TRANSPORT: couldn't remove $flagFile!\n";}
		}
	
	} # end if flagfile

#---------- SEND PING STATS ----------
if((-f $flagFile2) and (-f $fileToSend2)){
	$report=1;
	$cmd="autoftp.pl -u $user -p $passwd -a -t $target2 $site;$dir;;$fileToSend2";
	$return=system("$cmd");

	# error message if send failed; else increment successes and remove flag file
	if ($return) {$fails2++; print "    TRANSPORT: send2 failed $tstamp!\n";}
		else {$success2++;
		unless (unlink $flagFile2) {print "    TRANSPORT: couldn't remove $flagFile2!\n";}
		} # end else
	} # end if flagfile
		

#------------ REPORT IF WE DID ANYTHING ----------
if($report){
	$report=0;
	print "    TRANSPORT: successful: $success/$success2  failed:$fails/$fails2  $tstamp\n";
	}
	
sleep $sleeptime;
} # end main loop for transport

#*************************************************************************
#*************************************************************************
#                             END TRANSPORT CODE
#*************************************************************************
#*************************************************************************






# LEFTOVERS!
##---------------------------------------
## SPECIFIC PROCESSING FOR POWER OUTAGE
#$powerref = sub {
#$recOC=($locchars[2]&0xf0)>>4;
#$len=@locchars;
##if($len != 8){print "POWER: bad length - $len, expected 8\n";}
#$cnt=$locchars[3];
#$dur=($locchars[4]+256*$locchars[5])/50;
## looks like an attempt to not have duration count
## until power is back on
##if($dur==0){$totaldur+=$lastdur;}
##$lastdur=$dur;
#$totaldur+=$dur;
#$pwrOn=$locchars[6];
#if($pwrOn==0){$outCnt++;}
#$pwrState=$pwrOn?"":"POWER IS OFF!! ";
##unless($cnt==0 && $dur==0  && $pwrOn==1)
#	{
#	printf ("POWER OK: %sopcode: %s  len: %d  ",$pwrState,$recOC,$len);
#	printf ("%d cycles, %01.1f sec  total out secs: %01.1f",$cnt,$dur,$totaldur);
#	print "\n";
#	}
##$data{power}[0]+=$cnt;
##$data{power}[1]+=$dur;
##--------- LOG POWER EVENTS --------
## event type, time, duration, float1, float2
## should we reset anything if PIC restarts?
#if($recOC == 6){logRestart();}
#print LOGFILE "$etypes{power},$timesecs,$cnt,$dur,$totaldur,$outCnt\n";
#
##$data{sump}[2]+=$cnt;
##$data{sump}[3]+=$dur;
#}; # end power sub
##---------------------------------------



