<?php

$hostname=`hostname`;
//$hostname="jimsdell";
$ds=DIRECTORY_SEPARATOR;
//print"hn:\"$hostname\" ds:$ds<br>";
$basedir="/home/content/55/5891655/html";
$incdir="/home/content/55/5891655/html/jpgraph";
if($hostname=="jimsdell\n"){
	$basedir="c:\progra~1\xitami\webpages";
	$incdir="c:\progra~1\xitami\webpages\jpgraph-1.22\src";
	}
include ("$incdir${ds}jpgraph.php");
include ("$incdir${ds}jpgraph_line.php");
include ("$incdir${ds}jpgraph_bar.php");
include ("$incdir${ds}jpgraph_log.php");
//chdir("c:\progra~1\xitami\webpages");
$file="$basedir${ds}datafile.csv";
$lines=file($file);
$count=0;

// ------- TYPICAL LINES -----------
//STARTED POLL APP at Wed Dec 19 23:32:35 2007 offset:1198128755
//HEADERS furn:$etypes{furn},$timesecs,$tempRet,$tempSup
//7,1198128755,63.5,66.2
//HEADERS rain:$etypes{rain},$timesecs,$cnt,$Rtotalcnt
//5,1198128756,0,0
//HEADERS sump:$etypes{sump},$timesecs,$cnt,$dur,$sumpOn,$Stotalcnt,$Stotaldur,$Pcnt,$Pdur,$pwrOn,$Ptotalcnt,$Ptotaldur
//3,1198128756,0,0,0,0,0,0,0,1,0,0
//7,1198128826,63.5,66.2
//5,1198128826,0,0

// eventually should honor headers, but this is a quickie

//Ping stuff
//2/1 00:19:07 2008  RESTARTED.  First response: 10 ms
//2/1 00:28:12 got response after 58 missed pings
//2/1 08:19:08 avg2:12 max2:15072 min2:8 missed2:58 over2:2 runsecs:28801 totover:2 totmissed:58

//--------- CONFIG ---------
$dispDays=7; // days of data to display
$hrsPerSample=1;
$doPwrText=1;
$doPingStats=1;
$doRainRate=1;
$configFile="/home/content/55/5891655/html/config.php";
$configFile="$basedir${ds}config.php";
$rainZeroPercent=3;
$waterZeroPercent=1;
include ($configFile);


//-------- INITS -----------
# trying to fix graphs showing time with +1day at right.
# might be due to TZ problems.  The +3600 below fixes it, but I
# think that's the wrong direction!  11/12/08  jw
$now=time()+3600;
$dispDur=3600*24*$dispDays; 
$startTime=$now-$dispDur;
//print "now is $now  dispDur=$dispDur  Start time=$startTime<br>\n";
$sumpid=3;
$rainid=5;
$tempid=11;
$furnid=7;
$waterid=15;
$lastlineid=999;
$done=0;
$sfile="$basedir${ds}sump.png";
$tfile="$basedir${ds}temp.png";
$pfile="$basedir${ds}ping.png";
$ffile="$basedir${ds}furn.png";
$wfile="$basedir${ds}water.png";
$sampleSecs=$hrsPerSample*3600;
$sample=0;
$newTime=0;	
//$lineTS=0;	// avoids warning?
array ($tempAvg);
$eventFile="$basedir${ds}eventfile.txt";
$firstEvent=1;
$isEvent=0;
$EoldPwrTime=0;
$EoldPwrCnt=0;
// call a rain event over after $rainZeroPercent of display
$rzThresh=($dispDays*24/$hrsPerSample/100*$rainZeroPercent);
//$wzThresh=3;
$wzThresh=($dispDays*24/$hrsPerSample/100*$waterZeroPercent);
$spinnerCal=114; //half-turns (counts) per gallon
//$spinnerCal=10; //testing

//clear power outage events 
if(is_file($eventFile)){unlink($eventFile);}

//Ping stat sutff
$pingFile="$basedir${ds}pingstats.csv";


//******* MAIN READ LOOP ********
$go=0;

// add "last line" so we can do final processing
$lines[]="$lastlineid,$now\n";

// set up power outage ignore stuff
$pignvals=split("/",$pwrIgnoreDate);
$pwrIgnoreSecs=mktime(0,0,0,$pignvals[0],$pignvals[1]);
//print"pv0:$pignvals[0]  pv1:$pignvals[1]  pwrIgnoreSecs=$pwrIgnoreSecs<br>";


foreach($lines as $oneline){
		
//------ PROCESS BLOCK START LINES -----
$startline=preg_match_all("/STARTED POLL APP at(.*) offset:(\d+)/",$oneline,$matches);
if($startline){
	$offset=implode($matches[2]); // when this block started
	if($go==0){$startedAt=implode($matches[1]); // for graph title
	resetOlds();
	$startFound=1;
	continue;}
	} // end if $startline
	
	
//---- IGNORE HEADER LINES ----
if(preg_match("'HEADERS'",$oneline)){continue;}


//----- GET TIMESTAMP OF CURRENT DATA LINE -----
if($vals=split(",",$oneline)){
	$lineTS=$vals[1];
	if($lineTS<$offset){$lineTS+=$offset;}
	} //end if split works


//------ TIME TO START PAYING ATTENTION? -----
//$go says whether we're getting samples yet
if($go==0 && $lineTS> $startTime){$go=1; $newTime=$lineTS-1;
	//print"START: $lineTS<br>\n";
	}

// not time yet - ignore
if($go==0){continue;}


//------ START NEW SAMPLE ------
if($lineTS>$newTime){
	$newTime+=$sampleSecs;	// set up for next

	update(1);  // process accumulated data
	} // end if time for new sample



//--------- READ LINE DATA ---------
// This reads every sample, and is what we have
// to start with to find "events".

// special processing to close events
if($vals[0]==$lastlineid){$done=1;}

if($vals[0]==$sumpid){
	$logtime=$lineTS;
	$sumpCnt=$vals[5];
	if($firstSump){$firstSump=0;$oldSumpCnt=$sumpCnt;}
	$curPwrCnt=floatval($vals[10]);
	$curPwrTime=floatval($vals[11]); 
	$pwrOff=$vals[9]?0:1;
	
	
	// debug - prints out power info with real time stamps
	//$ts1=strftime("%m/%d %H:%M:%S",$lineTS);print"$ts1 $curPwrCnt;$curPwrTime;$pwrOff<br>\n";
	
	//------- FIND POWER OUT EVENTS --------
	// first spot event start/continues
	$deltaPwrTime=$curPwrTime-$EoldPwrTime;
	$deltaPwrCnt=$curPwrCnt-$EoldPwrCnt;
	
	// handle resets
	// didn't handle 1/31 event that ended with restart!
	if($deltaPwrCnt<0){$EoldPwrCnt=$curPwrCnt;}
	if($deltaPwrTime<0){
		$EoldPwrTime=$curPwrTime;
		$deltaPwrTime=0; // force end of event if needed
		$deltaPwrCnt=0;	

		if($eventTime>$pwrIgnoreSecs){
			$resetTime=strftime("%m/%d/%y %H:%M:%S",$lineTS);
			// $eventTime is when the most recent event started
			$eventStr1="pwr reset $resetTime";
			$eventStr2=($isEvent)?"  during outage starting $eventTime":"";
			$eventStr=$eventStr1.$eventStr2."\n";
			$mode='a';
			$fp=fopen($eventFile,$mode); // should check for failure!
			fwrite($fp,$eventStr);
			fclose($fp);
			}//end if event time > ignore time
		}// end if deltaPwrTime<0


	
	// check for new event
	// this might miss an outage on a restart if 1st sample had time
	if($deltaPwrTime>0 && $lineTS>$pwrIgnoreSecs){
		$pwrEventTime+=$deltaPwrTime;
		
		// start of new event?  record start time
		if($isEvent==0){$isEvent=1; $eventTime=strftime("%m/%d/%y %H:%M:%S",$lineTS);
			} // end if new event
	
		$EoldPwrTime=$curPwrTime;
		}// end found new duration


	// EVENT END AND POST TO FILE
	//if time not changing or this is last line ($done)
	// time posted is event start time
	if(($isEvent==1) && (($deltaPwrTime==0) || ($done==1))){
		$eventStr="$eventTime $deltaPwrCnt Power Outage(s), duration $pwrEventTime secs\n";
		$mode='a';
		if($firstEvent==1){$mode='w';$firstEvent=0;}
		$fp=fopen($eventFile,$mode); // should check for failure!
		fwrite($fp,$eventStr);
		fclose($fp);
	
		$EoldPwrCnt=$curPwrCnt; // only reset here at end of event
		$pwrEventTime=0;
		$isEvent=0;
		}//end found outage
	
	} // end if sumpid
	
if($vals[0]==$rainid){
	// need to add rain event
	$logtime=$lineTS;
	$rainCnt=$vals[3];
	if($firstRain){$firstRain=0;$oldRainCnt=$rainCnt;$rainTotOld=$rainCnt;}
	} // end if rainid
	
if($vals[0]==$waterid){
	// need to add water event?
	$logtime=$lineTS;
	$waterCnt=$vals[2];
	if($firstWater){$firstWater=0;$oldWaterCnt=$waterCnt;$waterTotOld=$waterCnt;}
	} // end if waterid
	
if($vals[0]==$tempid){
	// it sometimes fails and gets value of 0, which translates to 32F
	// we'll just skip those.  I hope no problems if zero samples...

// read outside temp
//	if($vals[3]!=32){
	$logtime=$lineTS;
	$OtempSum+=floatval($vals[3]);
	$OtempCnt++;
//	} // end unless temp=32
	
// read water temp
	if($vals[2]!=32){
	$WtempSum+=floatval($vals[2]);
	$WtempCnt++;
	} // end unless temp=32
	
	
//print"W: O: $WtempSum  $OtempSum<br>\n";	
} // end if tempid

if($vals[0]==$furnid){
	// it sometimes fails and gets value of 0, which translates to 32F
	// we'll just skip those.  I hope no problems if zero samples...

// read supply temp
	if($vals[3]!=32){
	$logtime=$lineTS;
	$StempSum+=floatval($vals[3]);
	$StempCnt++;
	} // end unless temp=32
	
// read return temp
	if($vals[2]!=32){
	$RtempSum+=floatval($vals[2]);
	$RtempCnt++;
	} // end unless temp=32
	
	
//print"S: R: $StempSum  $RtempSum<br>\n";	
	
} // end if furnid

} // end foreach line


// compute what fraction of a cycle the last data is for
$fraction=($sampleSecs-($newTime-$logtime))/$sampleSecs;
if($fraction==0){print "fraction is $fraction sampsecs is $sampleSecs nT:$newTime lt:$logtime<br>\n";
}else{
$mult=1/$fraction;
$fraction*=100; // for print use
update($mult);
}





//---- GET PING STAT INFO --------
//2/1 00:19:07 2008  RESTARTED.  First response: 10 ms
//2/1 00:28:12 got response after 58 missed pings 
//2/1 08:19:08 avg2:12 max2:15072 min2:8 missed2:58 over2:2 runsecs:28801 totover:2 
//might still be a time zone issue, so might be an hour off

$go=0;
if($doPingStats){
if(is_file($pingFile)){
	$lines=file($pingFile);
foreach ($lines as $x => $line){
	if(preg_match("/^(\d+)\/(\d+)\/(\d+) (\d+):(\d+):(\d+)(.*)/",$line,$matches)){
		$month=0;$day=0;$hour=0;$min=0;$sec=0;
		$month=$matches[1];
		$day=$matches[2];
		$year=$matches[3];
		$hour=$matches[4];
		$min=$matches[5];
		$sec=$matches[6];
//print "mo:$month da:$day hr:$hour min:$min sec:$sec\n";
		$unixsecs=mktime($hour,$min,$sec,$month,$day,$year);
		$restOfLine=$matches[7];
		} // end of get date

		//$go says whether we're getting samples yet
		if($go==0 && ($unixsecs> $startTime)){$go=1;}
		// not time yet - ignore
		if($go==0){continue;}
		
//print "$unixsecs: $restOfLine<br>\n";

	 	if(preg_match("/got response after (\d+)/",$restOfLine,$matches)){
			//print"lossTime\n";
			$lossTime=intval($matches[1]);
//			$pLoss[]=$lossTime?$lossTime:1;
			if($lossTime==0){$pLoss[]=1;}else{$pLoss[]=$lossTime;}
			$pingTimes[]=floatval($unixsecs-$now)/24/3600;
			$tim=floatval($unixsecs-$now)/24/3600;
			//print "$tim loss:$lossTime<br>\n";
			} // end if got response

		if(preg_match("/totmissed:(\d+)/",$restOfLine,$matches)){
			//print"lossCnt\n";
			
			// these make sure there's a point at least every stats line
			$pLoss[]=1;
			$pingTimes[]=floatval($unixsecs-$now)/24/3600;

			$lossTot=$matches[1]; //should probably be floatval()
			$pLossTot[]=$lossTot;
			$pingTimes2[]=floatval($unixsecs-$now)/24/3600;
			$tim=floatval($unixsecs-$now)/24/3600;
//			print "$tim tot:$lossTot<br>\n";
		} // end if got response
			
	} // end foreach
} // end if is_file
else{print "file not found";}
}// end if dopingstats






//---- PUT OUT CRUDE POWER OUTAGE INFO FILE --------
// uses data in array built by update()
$pwrfile="$basedir${ds}pwrinfo.csv";
if(is_file($pwrfile)){unlink($pwrfile);}
$fp=fopen($pwrfile,'w');
foreach($pwrCnt as $sample=>$oneVal){
	$timeArray=getdate($now+($daysAgo[$sample]*24*3600));
	$decDay=$timeArray["hours"]/24+$timeArray["minutes"]/24/60+$timeArray["seconds"]/24/3600;
	$decDay+=$timeArray["mday"];
	$dAtimeStr=sprintf("%d/%.2f",$timeArray["mon"],$decDay);
	
	fwrite ($fp, "$dAtimeStr;$oneVal;$pwrTime[$sample], ");
	} // end foreach sample
fwrite ($fp,"done\n");
fclose ($fp);

//------------






//-------- CREATE THE GRAPHS ---------

//---------- ABORT IF NO STARTED LINE FOUND ---------
if($startFound!= 1){
	print "Aborting - datafile had no STARTED line!\n";
	exit(2);
	}

// clear old ones!
//print "removing file...<br>";
if(is_file($sfile)){unlink("$sfile");}
if(is_file($tfile)){unlink("$tfile");}
if(is_file($ffile)){unlink("$ffile");}
if(is_file($wfile)){unlink("$wfile");}


if(1){
//***********************************************************
// Create the TEMP graph. These two calls are always required
//***********************************************************
$tempGr = new Graph(500,180,"auto");    
$tempGr->SetScale("lin");
//$tempGr->SetY2Scale("lin");
//$tempGr->SetTickDensity(TICKD_NORMAL,TICKD_NORMAL);
//$tempGr->SetTickDensity(TICKD_VERYSPARSE,TICKD_VERYSPARSE);

// Create the linear plot
//$lineplot=new LinePlot($ydata,$xdata);
//$WaterPlot=new LinePlot($WtempAvg,$daysAgo);
$OutsidePlot=new LinePlot($OtempAvg,$daysAgo);

// Add the plot to the graph
$tempGr->Add($OutsidePlot);
//$tempGr->AddY2($WaterPlot);

$tempGr->xaxis->HideLabels(False,False);

$tempGr->img->SetMargin(40,50,20,20);
$tempGr->title->Set("Outside temperature");

$tempGr->xaxis->title->Set("time, days ago");
$tempGr->yaxis->title->Set("deg F");
//$tempGr->y2axis->title->Set("House water supply pipe, deg F");
$tempGr->yaxis->title->SetColor("blue");
//$tempGr->y2axis->title->SetColor("deeppink3");

$tempGr->title->SetFont(FF_FONT1,FS_BOLD);
$tempGr->yaxis->title->SetFont(FF_FONT1,FS_BOLD);
//$tempGr->y2axis->title->SetFont(FF_FONT1,FS_BOLD);
//$tempGr->y2axis->title->SetMargin(4);
$tempGr->xaxis->title->SetFont(FF_FONT1,FS_BOLD);
$tempGr->xgrid->Show(True);
//$tempGr->xscale->ticks->Set(12,4);

$OutsidePlot->SetColor("blue");
//$WaterPlot->SetColor("deeppink3");
$OutsidePlot->SetWeight(1);
//$WaterPlot->SetWeight(1);
$tempGr->yaxis->SetColor("blue");
$tempGr->yaxis->SetWeight(1);
//$tempGr->y2axis->SetColor("deeppink3");
//$tempGr->y2axis->SetWeight(1);

// Display the graph
$tempGr->Stroke("$tfile");
}


if(1){
//***********************************************************
// Create the FURN graph. These two calls are always required
//***********************************************************
$furnGr = new Graph(500,200,"auto");    
$furnGr->SetScale("linlin");
$furnGr->SetY2Scale("lin");
//$furnGr->SetTickDensity(TICKD_NORMAL,TICKD_NORMAL);
//$furnGr->SetTickDensity(TICKD_VERYSPARSE,TICKD_VERYSPARSE);

// Create the linear plot
//$lineplot=new LinePlot($ydata,$xdata);
$SupplyPlot=new LinePlot($StempAvg,$daysAgo);
$ReturnPlot=new LinePlot($RtempAvg,$daysAgo);
//$lineplot->mark->SetType(MARK_UTRIANGLE);

// Add the plot to the graph
$furnGr->Add($SupplyPlot);
$furnGr->AddY2($ReturnPlot);

$furnGr->xaxis->HideLabels(False,False);

$furnGr->img->SetMargin(40,50,20,20);
$furnGr->title->Set("Furnace Duct Temperatures");
//$furnGr->subtitle->Set("Supply temp");
//$furnGr->subsubtitle->Set("Return temp");
//$furnGr->subtitle->SetColor("blue");
//$furnGr->subsubtitle->SetColor("deeppink3");

$furnGr->xaxis->title->Set("time, days ago");
$furnGr->yaxis->title->Set("Supply, deg F");
$furnGr->y2axis->title->Set("Return, deg F");
$furnGr->yaxis->title->SetColor("blue");
$furnGr->y2axis->title->SetColor("deeppink3");

$furnGr->title->SetFont(FF_FONT1,FS_BOLD);
$furnGr->yaxis->title->SetFont(FF_FONT1,FS_BOLD);
$furnGr->y2axis->title->SetFont(FF_FONT1,FS_BOLD);
$furnGr->y2axis->title->SetMargin(4);
$furnGr->xaxis->title->SetFont(FF_FONT1,FS_BOLD);
$furnGr->xgrid->Show(True);
//$furnGr->xscale->ticks->Set(12,4);

$SupplyPlot->SetColor("blue");
$ReturnPlot->SetColor("deeppink3");
$SupplyPlot->SetWeight(1);
$ReturnPlot->SetWeight(1);
$furnGr->yaxis->SetColor("blue");
$furnGr->yaxis->SetWeight(1);
$furnGr->y2axis->SetColor("deeppink3");
$furnGr->y2axis->SetWeight(1);

// Display the graph
$furnGr->Stroke("$ffile");
}



//***********************************************************
// Create the SUMP/RAIN graph. These two calls are always required
//***********************************************************
$sumpGr = new Graph(500,180,"auto");    
$sumpGr->SetScale("linlin");
$sumpGr->SetY2Scale("lin");
//$sumpGr->SetTickDensity(TICKD_NORMAL,TICKD_NORMAL);
//$sumpGr->SetTickDensity(TICKD_VERYSPARSE,TICKD_VERYSPARSE);

// Create the linear plot
//$lineplot=new LinePlot($ydata,$xdata);
$sumpPlot=new LinePlot($sumpRate,$daysAgo);
if($doRainRate){$rainPlot=new LinePlot($rainRate,$daysAgo);}
else{$rainPlot=new LinePlot($rainTot,$daysAgo);}
//$sumpPlot->mark->SetType(MARK_UTRIANGLE);

// Add the plot to the graph
$sumpGr->Add($sumpPlot);
$sumpGr->AddY2($rainPlot);

$sumpGr->xaxis->HideLabels(False,False);

$sumpGr->img->SetMargin(40,50,20,20);
$sumpGr->title->Set("Sump cycle rate and Rainfall");
$sumpGr->xaxis->title->Set("time, days ago");
$sumpGr->yaxis->title->Set("sump cycles/hr");
if($doRainRate){$sumpGr->y2axis->title->Set("rainfall rate inch/hr");}
else{$sumpGr->y2axis->title->Set("rainfall, inches");}
$sumpGr->yaxis->title->SetColor("darkcyan");
$sumpGr->y2axis->title->SetColor("brown");
$sumpGr->y2axis->title->SetMargin(4);

$sumpGr->title->SetFont(FF_FONT1,FS_BOLD);
$sumpGr->yaxis->title->SetFont(FF_FONT1,FS_BOLD);
$sumpGr->y2axis->title->SetFont(FF_FONT1,FS_BOLD);
$sumpGr->xaxis->title->SetFont(FF_FONT1,FS_BOLD);
$sumpGr->xgrid->Show(True);
//$sumpGr->xscale->ticks->Set(12,4);

$sumpPlot->SetColor("darkcyan");
$sumpPlot->SetWeight(1);
$rainPlot->SetColor("brown");
$rainPlot->SetWeight(1);
$sumpGr->yaxis->SetColor("darkcyan");
$sumpGr->yaxis->SetWeight(1);
$sumpGr->y2axis->SetColor("brown");
$sumpGr->y2axis->SetWeight(1);

// Display the graph
$sumpGr->Stroke("$sfile");



//***********************************************************
// Create the WATER/SPRINKLER graph. These two calls are always required
//***********************************************************
$waterGr = new Graph(500,180,"auto");    
$waterGr->SetScale("linlin");
//$waterGr->SetY2Scale("lin");

// Create the linear plot
$meterPlot=new LinePlot($waterTot,$daysAgo);
//$sprinkPlot=new BarPlot($sprinkTot,$daysAgo);

// Add the plots to the graph
$waterGr->Add($meterPlot);
//$waterGr->AddY2($sprinkPlot);

$waterGr->xaxis->HideLabels(False,False);

$waterGr->img->SetMargin(40,50,20,20);
$waterGr->title->Set("WaterMtr Cnt");
$waterGr->xaxis->title->Set("time, days ago");
$waterGr->yaxis->title->Set("water, gals");
$waterGr->yaxis->title->SetColor("darkcyan");
//$waterGr->y2axis->title->Set("sprinkler, ~gals");
//$waterGr->y2axis->title->SetColor("brown");
//$waterGr->y2axis->title->SetMargin(4);

$waterGr->title->SetFont(FF_FONT1,FS_BOLD);
$waterGr->yaxis->title->SetFont(FF_FONT1,FS_BOLD);
//$waterGr->y2axis->title->SetFont(FF_FONT1,FS_BOLD);
$waterGr->xaxis->title->SetFont(FF_FONT1,FS_BOLD);
$waterGr->xgrid->Show(True);

$meterPlot->SetColor("darkcyan");
$meterPlot->SetWeight(1);
//$sprinkPlot->SetColor("brown");
//$sprinkPlot->SetFillColor("brown");
//$sprinkPlot->SetAbsWidth(2);
$waterGr->yaxis->SetColor("darkcyan");
$waterGr->yaxis->SetWeight(1);
//$waterGr->y2axis->SetColor("brown");
//$waterGr->y2axis->SetWeight(1);

// Display the graph
$waterGr->Stroke("$wfile");



//var_dump($pLoss);

if($doPingStats){
$pt=0;
if($doPingTot){$pt=1;}
//***********************************************************
// Create the PING graph. These two calls are always required
//***********************************************************
$pingGr = new Graph(500,180,"auto");    
$pingGr->SetScale("linlog");
if($pt){$pingGr->SetY2Scale("lin");}

// Create the linear plot
$pingLossPlot=new BarPlot($pLoss,$pingTimes);
$pingLossPlot->SetColor("red");
$pingLossPlot->SetFillColor("red");
$pingLossPlot->SetColor("red");
//$pingLossPlot->SetWidth(0.05);
$pingLossPlot->SetAbsWidth(2);
if($pt){
	$pingTotPlot=new BarPlot($pLossTot,$pingTimes2);
	$pingTotPlot->SetColor("brown");
	$pingTotPlot->SetFillColor("brown");
	$pingTotPlot->SetColor("brown");
	$pingTotPlot->SetWidth(0.1);
}

// Add the plot to the graph
$pingGr->Add($pingLossPlot);
if($pt){$pingGr->AddY2($pingTotPlot);}

$pingGr->xaxis->HideLabels(False,False);

$pingGr->img->SetMargin(50,10,20,20);
$pingGr->title->Set("Ping Loss to ISP");
$pingGr->xaxis->title->Set("time, days ago");

$pingGr->title->SetFont(FF_FONT1,FS_BOLD);
$pingGr->yaxis->title->Set("pings lost");
$pingGr->yaxis->title->SetColor("red");
$pingGr->yaxis->title->SetFont(FF_FONT1,FS_BOLD);
$pingGr->yaxis->setTitleMargin(35);
if($pt){
	$pingGr->y2axis->title->Set("total outage time");
	$pingGr->y2axis->title->SetColor("brown");
	$pingGr->y2axis->title->SetFont(FF_FONT1,FS_BOLD);
}
$pingGr->xaxis->title->SetFont(FF_FONT1,FS_BOLD);
$pingGr->xgrid->Show(True);

// Display the graph
$pingGr->Stroke("$pfile");
}//end if dopingstats






if(0){
print"<TEXTAREA rows=5 cols=70>";
foreach ($ydata as $value){
	print ",$value";
}
print"</TEXTAREA><br>\n";
}


//----- COMPUTE AVERAGES ETC -----
// this computes an aggregated update once/hr or whatever
// and puts results in an array (per data type) indexed by "sample",
// a small int that reliably increases by 1 for every sample period.
// Array $daysAgo also has an entry per "sample", indexed the same,
// containing a (negative) timestamp in "days ago" for the sample.

function update($mult){
global $hrsPerSample,$sumpRate,$sumpCnt,$rainRate,$rainCnt,$oldRainCnt,$pwrCnt,$curPwrCnt,$pwrTime,$curPwrTime,$StempCnt,$StempAvg,$StempSum,$RtempCnt,$RtempAvg,$RtempSum,$sample,$oldSumpCnt,$daysAgo,$rainTot,$rainTotOld,$rainZero,$rzThresh,$logtime,$lineTS,$now,$WtempCnt,$WtempAvg,$WtempSum,$OtempCnt,$OtempAvg,$OtempSum,$waterRate,$waterCnt,$oldWaterCnt,$waterTot,$waterTotOld,$waterZero,$wzThresh,$spinnerCal;

if ($mult> 100) {$mult=100;} # just in case

// here's a timestamp in days everybody can use, indexed by $sample:
$daysAgo[]=($lineTS-$now)/(3600*24);


//print "Sample $sample sumpCnt $sumpCnt oldSumpCnt $oldSumpCnt\n";
$sumpRate[$sample]=$mult*($sumpCnt-$oldSumpCnt)/$hrsPerSample; # cycles/hr
if($sumpRate[$sample]<0){$sumpRate[$sample]="";}
$oldSumpCnt=$sumpCnt;


//$rainRate[$sample]=$mult*((($rainCnt-$oldRainCnt)/$hrsPerSample)/100)+.0048; //inches/hr
$rainRate[$sample]=$mult*((($rainCnt-$oldRainCnt)/$hrsPerSample)/100); //inches/hr
if($rainRate[$sample]<0){$rainRate[$sample]="";}
$oldRainCnt=$rainCnt;
//print "$sample:$rainRate[$sample]<br>\n";


if($rainCnt<$rainTotOld){$rainTotOld=$rainCnt;}
$rainTot[$sample]=($rainCnt-$rainTotOld)/100;
if(($rainRate[$sample]==0) && ($rainTot[$sample]>0)){$rainZero++;}
else{$rainZero=0;}
if($rainZero>$rzThresh){$rainTotOld=$rainCnt;}
//print "$sample:$rainCnt[$sample]<br>\n";
		
		
$waterRate[$sample]=$mult*((($waterCnt-$oldWaterCnt)/$hrsPerSample)/$spinnerCal); //gal/hr?
if($waterRate[$sample]<0){$waterRate[$sample]="";}
$oldWaterCnt=$waterCnt;
//print "$sample:$rainRate[$sample]<br>\n";


if($waterCnt<$waterTotOld){$waterTotOld=$waterCnt;}
$waterTot[$sample]=(($waterCnt-$waterTotOld)/$spinnerCal);
if(($waterRate[$sample]==0) && ($waterTot[$sample]>0)){$waterZero++;}
else{$waterZero=0;}
if($waterZero>$wzThresh){$waterTotOld=$waterCnt;}
//print "$sample:w:$waterTot[$sample]<br>\n";
		
		
$pC=$curPwrCnt-$oldPwrCnt;
$pwrCnt[$sample]=($pC<0)?"":$pC;
$oldPwrCnt=$curPwrCnt;


$pT=$curPwrTime-$oldPwrTime;
$pwrTime[$sample]=($pT<0)?"":$pT;
$oldPwrTime=$curPwrTime;


if($StempCnt!=0){$StempAvg[$sample]=$StempSum/$StempCnt+.04;}
else{$StempAvg[$sample]="";}
$StempSum=0;$StempCnt=0;

		
if($RtempCnt!=0){$RtempAvg[$sample]=$RtempSum/$RtempCnt+.04;}
else{$RtempAvg[$sample]="";}
$RtempSum=0;$RtempCnt=0;
		
if($WtempCnt!=0){$WtempAvg[$sample]=$WtempSum/$WtempCnt+.04;}
else{$WtempAvg[$sample]="";}
$WtempSum=0;$WtempCnt=0;

		
if($OtempCnt!=0){$OtempAvg[$sample]=$OtempSum/$OtempCnt+.04;}
else{$OtempAvg[$sample]="";}
$OtempSum=0;$OtempCnt=0;

//print"S R W O $StempAvg[$sample] $RtempAvg[$sample] $WtempAvg[$sample] $OtempAvg[$sample] <br>\n";
		
$sample++;
//print ".";


} //end update


// perl code

// end perl code

function resetOlds(){
// deal gracefully with discontinuity in logs by resetting "old" values

global $firstRain,$firstSump, $firstWater;
$firstRain=1;
$firstSump=1;
$firstWater=1;
} // end function resetOlds
?>