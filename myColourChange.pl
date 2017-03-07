#!/usr/bin/perl -w
#
# Warning if you are using z lift then do not set it at the same as layer hight or first layer hight.
#
# If different temperatures is select in Slic3r then it will change temp just before unretracting at colour/tool change.
# You need to install Perl to get this working :) 
#
#
# toolChangeRetractionLength
#	The amount of retraction when changing tool one number for each tool separate by comma.
#
# useAutoPlacement
# 	Place tower based on size of print on bead.
#
# wipeTowerX 
# wipeTowerY
#	Position of tower, ignored if auto placement is used.
# 
# wipeTowerSize
#	Size of tower. Brim size will be taken form Slic3e
#
# wipeTowerInfillNoChange
#	The amount of infill of layers without colour/tool change 
#
# fastRetractionSpeed
#	The speed for retraction when doing colour/tool change.
#	When extruding the retraction the retraction speed from Slic3r is used.
#
# useYSplitChange
#	Retraction sequence suggested by Teilchen. (Not tested)
#	- retract some filament fast.
#	- unretract a smaller amount to get rid of the stringing and that bulb o_lampe was taking about.
#	- retract a large amount at a lower speed than usual to get the time for the filament to take the shape of Bowden.
#	- continue retracting fast until the splitter is free to insert the next colour.
#
# ySplitFirstRetractionSpeed
# ySplitFirstRetract
#	First retraction amount in sequence.
#
# ySplitUnretract
#	Then unretract this amount.
#
# ySplitSlowRetractionSpeed
#	Speed of the last retraction step.
#	The last retract step will use toolChangeRetractionLength to detriment how much more to retract.
#
# You need to add the path to this script in Print Settings->Output options->Post-processing script.
# You also need to insert these vars in "End G-code" window in Slic3r settings.
# The first line is also important as it serves as a indicator for the script to start reading vars.
#
#; WIPE TOWER PARAMS
#; Not Implemented:
#; forceToolChanges  =  false
#;
#; Implemented:
#; toolChangeRetractionLength = 120,120
#; useAutoPlacement = 1
#; wipeTowerX = 20
#; wipeTowerY = 20
#; wipeTowerSize = 20
#; wipeTowerInfillNoChange = 10
#; useYSplitChange = 1
#; ySplitFirstRetractionSpeed = 100
#; ySplitFirstRetract = 10
#; ySplitUnretract = 5
#; ySplitSlowRetractionSpeed = 20

use strict;
use warnings;
use Math::Round;
use Math::Complex;
use POSIX qw[ceil floor];
use List::Util qw[min max];
use constant PI    => 4 * atan2(1, 1);
use Scalar::Util qw(looks_like_number);
use Data::Dumper qw(Dumper);

# printer parameters with default values

our %slic3r;

# Where are we
our $currentE=0;
our $currentX=0;
our $currentY=0;
our $currentZ=0;
our $currentF=0;
our $absolutePositioning=0;
our $absoluteExtrusion=0;
our @startCorner=(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
our $zLift=0;
our $zBeforeWipe = 0;

my $Zmoved = 0;
my $extruderA = 0;
my $extruderB = 0;
my $extruderChangeTemp = 0;

# Define Vars for gcode builder
my $numOfToolChangeOnLayer = 0;
my $maxX = 0;
my $maxY = 0;
my $minX = 99999999999;
my $minY = 99999999999;
my $lastZ = 0;
our $currLayer = 1;
my $afterLayerNum = 0;
our $currTool = 0;
our $nextTool = 0;
my $firstToolChange=1;
my $finishWhipe = 0;
our $toolChangeNum = 0;
my $layerChange = 0;
my $layerHightAtLastChange = 0;
my $zAtFirstLayer = 0;
our $brimDone = 0;
my $skipSkirtToolChange = 0;

# (1) quit unless we have the correct number of command-line args
my $num_args = $#ARGV + 1;

if ($num_args != 1) {
    print "\nUsage: name.pl first_name last_name\n";
    exit;
}

open(our $fh, '<', $ARGV[0]);
chomp(my @lines = <$fh>);
close $fh;
open($fh, '>', $ARGV[0])  or die "Could not open file!";
#open($fh, '>', 'TestGDice.txt')  or die "Could not open file!";

# Get all vars from Slic3r
my $paramsFound = 0;
my $numOfTower = 0;

foreach my $line (@lines) {
	if($paramsFound) {
		getSlic3r($line);
	}
	if($line eq "; WIPE TOWER PARAMS") {
		$paramsFound = 1;
	}
}
getCalcPrc(); # Calc speeds that is based on a % of another speed and change % to a numeric value


# Find Num of towers
# Get max num of tool change per layer
# Get max and min x and y for tower placement
foreach my $line (@lines) {
	if($line=~/^T(\d*\.?\d*)/) {
		if($firstToolChange == 1) {
			$firstToolChange = 0;
		} else {
			# Tool change found
			if($slic3r{'skirts'} > 0 and $skipSkirtToolChange == 0) {
				$skipSkirtToolChange = 1;
			} else {
				$numOfToolChangeOnLayer++;
			}
		}
	}elsif($line=~/^G90/){
		print $fh $line."\n";
		$absolutePositioning=1;
	}elsif($line=~/^G91/){
		print $fh $line."\n";
		$absolutePositioning=0;
	} else {
		if($line=~/^G[01]( X(-?\d*\.?\d*))?( Y(-?\d*\.?\d*))?( Z(-?\d*\.?\d*))?( E(-?\d*\.?\d*))?/) {
			if($2){
				if($absolutePositioning){
					$currentX=$2;
				}else{
					$currentX+=$2;
				}
				if($currentX > $maxX) {
					$maxX = $currentX;
				}
				if($currentX < $minX) {
					$minX = $currentX;
				}
			}
			if($4){
				if($absolutePositioning){
					$currentY=$4;
				}else{
					$currentY+=$4;
				}
				if($currentY > $maxY) {
					$maxY = $currentY
				}
				if($currentY < $minY) {
					$minY = $currentY
				}
			}
			if($6){
				$lastZ = $currentZ;
				if($absolutePositioning){
					$currentZ=$6;
				}else{
					$currentZ+=$6;
				}
				
				# Find z lift
				if($absolutePositioning){
					if($slic3r{'retract_lift'}[$currTool] == digitize($currentZ - $lastZ, 2) and $slic3r{'retract_lift'}[$currTool] > 0) {
						$zLift = 1;
					}
				}else{
					if($slic3r{'retract_lift'}[$currTool] == digitize($6, 2) and $slic3r{'retract_lift'}[$currTool] > 0) {
						$zLift = 1;
					}
				}
				
				# Find first layer
				if($currentZ == $slic3r{'first_layer_height'} and !$zAtFirstLayer) {
					$zAtFirstLayer = 1;
				}
				
				# Find layer change
				if(digitize($currLayer * $slic3r{'layer_height'} + $slic3r{'first_layer_height'}, 2) <= digitize($currentZ, 2) and $zLift == 0 and $zAtFirstLayer) {
					$layerChange = 1;
				}
				if($layerChange) {
					if($numOfToolChangeOnLayer > $numOfTower) {
						$numOfTower = $numOfToolChangeOnLayer;
					}
					$numOfToolChangeOnLayer = 0;
					$currLayer++;
					$layerChange = 0;
				}
				
				# Find z lower
				if($absolutePositioning){
					if($slic3r{'retract_lift'}[$currTool] == digitize($currentZ - $lastZ, 2)*-1 and $slic3r{'retract_lift'}[$currTool] > 0) {
						$zLift = 0;
					}
				}else{
					if($slic3r{'retract_lift'}[$currTool] == digitize($6, 2)*-1 and $slic3r{'retract_lift'}[$currTool] > 0) {
						$zLift = 0;
					}
				}
			}
		}
	}
}

if($slic3r{'useAutoPlacement'}) {
	if ($slic3r{'brim_width'} > 0) {
		$slic3r{'wipeTowerY'} = $maxY + $slic3r{'brim_width'} + $slic3r{'nozzle_diameter'}[$currTool] * $slic3r{'first_layer_extrusion_width'};
	} else {
		$slic3r{'wipeTowerY'} = $maxY + 5;
	}
	$slic3r{'wipeTowerX'} = 170/2 - (($slic3r{'wipeTowerSize'} * $numOfTower) / 2);
}

# New G-code Builder
$firstToolChange = 1;
$zAtFirstLayer = 0;
$currLayer = 1;
$currentE=0;
$currentX=0;
$currentY=0;
$currentZ=0;
$currentF=0;
$absolutePositioning=0;
$absoluteExtrusion=0;
$zLift=0;
$zBeforeWipe = 0;
$lastZ = 0;
$skipSkirtToolChange = 0;
foreach my $line (@lines) {
	if($line=~/^T(\d*\.?\d*)/) {
		if($firstToolChange == 1) {
			$currTool = $1;
			$firstToolChange = 0;
		} else {
			if($slic3r{'skirts'} > 0 and $skipSkirtToolChange == 0) {
				$skipSkirtToolChange = 1;
				print $fh comment("Tool change skiped do to skirt found");
			} else {
				print $fh comment("Tool change found");
				$nextTool = $1;
				$zBeforeWipe = $currentZ;
				print $fh toolChange();
				$finishWhipe = 1;
				$toolChangeNum+= 1;
			}
		}
	} elsif($line eq "; after layer") {
		print $fh $line."\n";
	}elsif($line=~/^G90/){
		print $fh $line."\n";
		$absolutePositioning=1;
	}elsif($line=~/^G91/){
		print $fh $line."\n";
		$absolutePositioning=0;
	}elsif($line=~/^M82/){
		print $fh $line."\n";
		$absoluteExtrusion=1;
	}elsif($line=~/^M83/){
		print $fh $line."\n";
		$absoluteExtrusion=0;
	} else {
		if($finishWhipe) {
			if($line=~/^G[01] X(\d*\.?\d*) Y(\d*\.?\d*)/) {
				print $fh comment("Extrude retraction after whipe");
				#print $fh lower($slic3r{'retract_lift'}[$currTool]);
				print $fh extrudeEF($slic3r{'retract_length'}[$currTool], $slic3r{'retract_speed'}[$currTool] * 60);
				$finishWhipe = 0;
			}
		}
		if($line=~/^G[01]( X(-?\d*\.?\d*))?( Y(-?\d*\.?\d*))?( Z(-?\d*\.?\d*))?( E(-?\d*\.?\d*))?/) {
			if($2){
				if($absolutePositioning){
					$currentX=$2;
				}else{
					$currentX+=$2;
				}
			}
			if($4){
				if($absolutePositioning){
					$currentY=$4;
				}else{
					$currentY+=$4;
				}
			}
			if($6){
				$lastZ = $currentZ;
				if($absolutePositioning){
					$currentZ=$6;
				}else{
					$currentZ+=$6;
				}
				
				# Find z lift
				if($absolutePositioning){
					if($slic3r{'retract_lift'}[$currTool] == digitize($currentZ - $lastZ, 2) and $slic3r{'retract_lift'}[$currTool] > 0) {
						$zLift = 1;
						print $fh comment("Lift found: ".digitize($currentZ - $lastZ, 2));
					}
				}else{
					if($slic3r{'retract_lift'}[$currTool] == digitize($6, 2) and $slic3r{'retract_lift'}[$currTool] > 0) {
						$zLift = 1;
					}
				}
				
				# Find first layer
				if($currentZ == $slic3r{'first_layer_height'} and !$zAtFirstLayer) {
					$zAtFirstLayer = 1;
					print $fh comment("First print layer found starting layer count");
				}
				
				# Find layer change
				if(digitize($currLayer * $slic3r{'layer_height'} + $slic3r{'first_layer_height'}, 2) <= digitize($currentZ, 2) and $zLift == 0 and $zAtFirstLayer) {
					$layerChange = 1;
					print $fh comment("Layer Change Found at: ".($currLayer * $slic3r{'layer_height'} + $slic3r{'first_layer_height'})."<=".$currentZ);
				} else {
					print $fh comment("Not layer change: ".($currLayer * $slic3r{'layer_height'} + $slic3r{'first_layer_height'})."<=".$currentZ);
				}
				if($layerChange) {
					#print 'Layer chnage found'.$currLayer." , ";

					if($toolChangeNum == $numOfTower) {
						print $fh comment("Tool change is done skipping tower print");
					} else {
						$zBeforeWipe = $currentZ;
						while($toolChangeNum < $numOfTower){
							print $fh whipeTower();
							$toolChangeNum+= 1;
						}
						$finishWhipe = 1;
					}
					$toolChangeNum = 0;
					$currLayer++;
					#print 'Layer chnage found: '.$currLayer;
					$layerChange = 0;

				}
				
				# Find z lower
				if($absolutePositioning){
					if($slic3r{'retract_lift'}[$currTool] == digitize($currentZ - $lastZ, 2)*-1 and $slic3r{'retract_lift'}[$currTool] > 0) {
						$zLift = 0;
						print $fh comment("Lower found: ".digitize($currentZ - $lastZ, 2));
					}
				}else{
					if($slic3r{'retract_lift'}[$currTool] == digitize($6, 2)*-1 and $slic3r{'retract_lift'}[$currTool] > 0) {
						$zLift = 0;
					}
				}
			}
			if($8){
				if($absolutePositioning){
					$currentE=$8;
				}else{
					$currentE+=$8;
				}
			}
		}
		print $fh $line."\n";
	}
}

close $fh;


# Functions

sub getSlic3r{ # Import Slic3r vars into Hash if there is a value per extruder they will be in an array.
			   # Get the value by slic3r{'Var name from slic3r'}[extruder num].
	if($_[0]=~/; (\D*\.?\D*) = (.*)/) {
		my $varKey = $1;
		my $varValue = $2;
		if (looks_like_number($varValue)) {
			$slic3r{$varKey} = $varValue*1.0;
		} else {
			if (index($varValue, ",") != -1) {
				$slic3r{$varKey} = [split /,/, $varValue];
				foreach my $key (keys @{ $slic3r{$varKey} }) {
					if (looks_like_number($slic3r{$varKey}[$key])) {
						$slic3r{$varKey}[$key] = $slic3r{$varKey}[$key] * 1.0;
					}
					if($slic3r{$varKey}[$key]=~/(\d*\.?\d*)%/) { # change % to number 
						$slic3r{$varKey}[$key] = $1 / 100;
					}
				}
			} else {
				$slic3r{$varKey} = $varValue;
			}
		}
	}
}

sub getCalcPrc{ # Calc speeds that is based on a % of another speed and change % to a numeric value
	foreach my $varKey (keys %slic3r ) {
		if($slic3r{$varKey}=~/(\d*\.?\d*)%/) { # Change % to number
			$slic3r{$varKey} = $1 / 100;
			if($varKey eq "small_perimeter_speed") {
				$slic3r{$varKey} = $slic3r{'perimeter_speed'} * $slic3r{$varKey};
			}
			if($varKey eq "external_perimeter_speed") {
				$slic3r{$varKey} = $slic3r{'perimeter_speed'} * $slic3r{$varKey};
			}
			if($varKey eq "solid_infill_speed") {
				$slic3r{$varKey} = $slic3r{'infill_speed'} * $slic3r{$varKey};
			}
			if($varKey eq "top_solid_infill_speed") {
				$slic3r{$varKey} = $slic3r{'infill_speed'} * $slic3r{$varKey};
			}
			if($varKey eq "support_material_interface_speed") {
				$slic3r{$varKey} = $slic3r{'support_material_speed'} * $slic3r{$varKey};
			}
			if($varKey eq "first_layer_speed") {
				$slic3r{$varKey} = $slic3r{'perimeter_speed'} * $slic3r{$varKey};
			}
			if($varKey eq "first_layer_extrusion_width") {
				$slic3r{$varKey} = $slic3r{'extrusion_width'} * $slic3r{$varKey};
			}
		}
	}
}

sub getRectlinearMove{ # Get Rectilinear move distances along side of rectangle based on % of infill. Remember to divide by 2 on the first line.
	my $infillPrc = $_[0];
	my $extrutionWidth = $slic3r{'nozzle_diameter'}[$currTool];
	if($currLayer == 1) {
		$extrutionWidth = $slic3r{'first_layer_extrusion_width'};
	}
	my $infillDistMultiply = 100 / $infillPrc;
	my $infillDist = $extrutionWidth * $infillDistMultiply;
	my $moveDist = sqrt($infillDist**2+$infillDist**2);
	return $moveDist;
}

sub getRectilinearPoints{ 	#Plot all points in a square for rectilinear move based on fill prc
							#Translate pivot to centre, rotate and move pivot to corner and translate to x,y
	my $x = $_[0]; # Translate to X
	my $y = $_[1]; # Translate to Y
	my $r = $_[2]; # Start corner 0 - 3
	my $squareSize = $_[3];
	my $infillPrc = $_[4];
	my $moveDist = getRectlinearMove($infillPrc);
	my $totalMove = $squareSize * 2;
	my $firstPoint = 1;
	my $movedX = 0;
	my $movedY = 0;
	my @points = ();
	my $moveInX = 1;
	my $YchangeDir = 0;
	
	# Plot points along X axis.
	while(1) {
		push @points, [$movedX, 0];
		if($firstPoint) {
			$movedX+= $moveDist/2;
			if($movedX < $squareSize) {
				push @points, [$movedX,0];
			} else {
				$YchangeDir = 0;
				last;
			}
			$firstPoint = 0;
		} else {
			$movedX+= $moveDist;
			if($movedX < $squareSize) {
				push @points, [$movedX,0];
			} else {
				$YchangeDir = 0;
				last;
			}
		}
		push @points, [0,$movedX];
		$movedX+= $moveDist;
		if($movedX < $squareSize) {
			push @points, [0,$movedX];
		} else {
			$YchangeDir = 1;
			last;
		}
	}
	
	# If stop on Y axis move to far side.
	$firstPoint = 1;
	if($movedY < $squareSize) {
		if($YchangeDir) {
			$movedY = $movedX - $squareSize;
			push @points, [0, $squareSize];
			push @points, [$movedY, $squareSize];
			$firstPoint = 0;
		}
	}
	
	# Plot points along Y axis.
	while(1) {
		push @points, [$squareSize, $movedY];
		if($firstPoint) {
			$movedY = $movedX - $squareSize;
			if($movedY < $squareSize) {
				push @points, [$squareSize,$movedY];
			} else {
				last;
			}
			$firstPoint = 0;
		} else {
			$movedY+= $moveDist;
			if($movedY < $squareSize) {
				push @points, [$squareSize,$movedY];
			} else {
				last;
			}
		}
		push @points, [$movedY,$squareSize];
		$movedY+= $moveDist;
		if($movedY < $squareSize) {
			push @points, [$movedY,$squareSize];
		} else {
			last;
		}
	}
	push @points, [$squareSize,$squareSize];
	
	# Flip and translate to x,y
	foreach my $key (keys @points ) {
		if($r == 3 or $r == 2) {
			$points[$key][0]*=-1;
			$points[$key][0]+=$squareSize;
		}
		if($r == 1 or $r == 2) {
			$points[$key][1]*=-1;
			$points[$key][1]+=$squareSize;
		}
		$points[$key][0]+=$x;
		$points[$key][1]+=$y;
	}
	
	return @points;
}

sub makeRectilinearSquare{ # Extrude a rectilinear square, starting at point x,y and ending at point x,y
	my $startX = $_[0];
	my $startY = $_[1];
	my $squareSize = $_[2];
	my $infillPrc = $_[3];
	my $gCode = "";
	my @points = getRectilinearPoints($startX, $startY, $startCorner[$toolChangeNum], $squareSize, $infillPrc);
	my $infillSpeed;
	if($infillPrc > 90) {
		$infillSpeed = $slic3r{'solid_infill_speed'};
	} else {
		$infillSpeed = $slic3r{'infill_speed'};
	}
	$startCorner[$toolChangeNum]+= 1;
	if($startCorner[$toolChangeNum] > 3) {
		$startCorner[$toolChangeNum] = 0;
	}
	
	#Print Moves 
	foreach my $key (keys @points) {
		if($key == 0) {
			$gCode.= travelToXYF($points[$key][0], $points[$key][1], $slic3r{'travel_speed'} * 60);
		} else {
			if($currLayer == 1) {
				$gCode.= extrudeToXYFL($points[$key][0], $points[$key][1], $slic3r{'first_layer_speed'} * 60, $slic3r{'first_layer_height'});
			} else {
				$gCode.= extrudeToXYFL($points[$key][0], $points[$key][1], $infillSpeed * 60, $slic3r{'layer_height'});
			}
		}
	}
	
	return $gCode;
}

sub getSquare{
	my $x = $_[0]; # Translate to X
	my $y = $_[1]; # Translate to Y
	my $r = $_[2]; # Start corner 0 - 3
	my $xSize = $_[3];
	my $ySize = $_[4];
	my @points = ([0,0],[$xSize,0],[$xSize,$ySize],[0,$ySize],[0,0]);
	
	# Flip and translate to x,y
	foreach my $key (keys @points ) {
		if($r == 3 or $r == 2) {
			$points[$key][0]*=-1;
			$points[$key][0]+=$xSize;
		}
		if($r == 1 or $r == 2) {
			$points[$key][1]*=-1;
			$points[$key][1]+=$ySize;
		}
		$points[$key][0]+=$x;
		$points[$key][1]+=$y;
	}
	return @points
}

sub makeSquare{ # Extrude a square, starting at point x,y
	my $startX = $_[0];
	my $startY = $_[1];
	my $xSize = $_[2];
	my $ySize = $_[3];
	my $gCode = "";
	my @points = getSquare($startX, $startY, $startCorner[$toolChangeNum], $xSize, $ySize);
	
	#Print Moves 
	foreach my $key (keys @points) {
		if($key == 0) {
			$gCode.= travelToXYF($points[$key][0], $points[$key][1], $slic3r{'travel_speed'} * 60);
		} else {
			if($currLayer == 1) {
				$gCode.= extrudeToXYFL($points[$key][0], $points[$key][1], $slic3r{'first_layer_speed'} * 60, $slic3r{'first_layer_height'});
			} else {
				$gCode.= extrudeToXYFL($points[$key][0], $points[$key][1], $slic3r{'infill_speed'} * 60, $slic3r{'layer_height'});
			}
		}
	}
	
	return $gCode;
}

sub makeBrim{
	my $gCode = "";
	my $numOfLines = round($slic3r{'brim_width'}/$slic3r{'first_layer_extrusion_width'});
	my $x = 0;
	my $y = 0;
	my $sizeX = 0;
	my $sizeY = 0;
	
	while($numOfLines > 0) {
		$x = $slic3r{'wipeTowerX'} - $numOfLines * $slic3r{'first_layer_extrusion_width'};
		$y = $slic3r{'wipeTowerY'} - $numOfLines * $slic3r{'first_layer_extrusion_width'};
		if($numOfTower > 1) {
			$sizeX = ($slic3r{'wipeTowerSize'} * $numOfTower + $slic3r{'nozzle_diameter'}[$currTool]) + $numOfLines * $slic3r{'first_layer_extrusion_width'} * 2;
		} else {
			$sizeX = $slic3r{'wipeTowerSize'} + $numOfLines * $slic3r{'first_layer_extrusion_width'} * 2;
		}
		$sizeY = $slic3r{'wipeTowerSize'} + $numOfLines * $slic3r{'first_layer_extrusion_width'} * 2;
		$gCode.= makeSquare($x, $y, $sizeX, $sizeY);
		$numOfLines-= 1;
	}
	
	return $gCode;
}

sub getWipeElength{
	my $squareSize = $_[0];
	my @points = getSquare(0, 0, 0, $squareSize);
	my $eLen = 0;
	my $lastX = 0;
	my $lastY = 0;
	
	foreach my $key (keys @points) {
		$eLen+= extrusionXYXYL($lastX, $lastY, $points[$key][0], $points[$key][1], $slic3r{'layer_height'});
	}
	return $eLen;
}

sub digitize { # cut floats to size
	my $num=$_[0];
	my $digits=$_[1];
	my $factor=10**$digits;
	return (round($num*$factor))/$factor;
}

sub dist{ # calculate distances between 2d points
	my $x1=$_[0];
	my $y1=$_[1];
	my $x2=$_[2];
	my $y2=$_[3];
	return sqrt(($x2-$x1)**2+($y2-$y1)**2);
}

sub extrusionXYXYL{ # calculate the extrusion length for a move from (x1,y1) to (x2,y2)
	my $x1=$_[0];
	my $y1=$_[1];
	my $x2=$_[2];
	my $y2=$_[3];
	my $l=$_[4];
	my $filamentArea=$slic3r{'filament_diameter'}[$currTool]*$slic3r{'filament_diameter'}[$currTool]/4*PI;
	my $lineLength=dist($x1,$y1,$x2,$y2);
	my $eDist = 0;
	if($currLayer==1) {
		$eDist=$lineLength*$slic3r{'first_layer_extrusion_width'}/$filamentArea;
	} else {
		$eDist=$lineLength*$slic3r{'nozzle_diameter'}[$currTool]/$filamentArea;
	}
	$eDist*=$l;
	if($currLayer==1){
		$eDist*=$slic3r{'extrusion_multiplier'}[$currTool];
	}else{
		$eDist*=$slic3r{'extrusion_multiplier'}[$currTool];
	}
	return digitize($eDist,4);
}

sub extrusionXYL { # calculate the extrusion length for a move from the current extruder position to (x,y) taking a layer height
	my $x=$_[0];
	my $y=$_[1];
	my $l=$_[2];
	if($absolutePositioning){
		return extrusionXYXYL($currentX, $currentY, $x, $y, $l);
	}else{
		return extrusionXYXYL(0, 0, $x, $y, $l);
	}
}

sub travelToZ{ # appends a trave move
	my $z=$_[0];
	return "G1 Z".digitize($z,4)."\n";
}

sub travelToXYF{ # appends a trave move
	my $x=$_[0];
	my $y=$_[1];
	my $f=$_[2];
	
  if($absolutePositioning){
		$currentX=$x;
		$currentY=$y;
	}else{
		$currentX+=$x;
		$currentY+=$y;
	}
	
  return "G1 X".digitize($x,4)." Y".digitize($y,4)." F".$f."\n";
}

sub lift{
	my $gcode="";
	$gcode.=relativePositioning();
	$gcode.=travelToZ($_[0]);
	$gcode.=absolutePositioning();
	return $gcode;
}

sub lower{
	my $gcode="";
	$gcode.=relativePositioning();
	$gcode.=travelToZ(-$_[0]);
	$gcode.=absolutePositioning();
	return $gcode;
}

sub extrudeEF{ # appends an extrusion (=printing) move
	my $e=$_[0];
	my $f=$_[1];
	$currentE+=$e;
	if(!$slic3r{'use_relative_e_distances'}){
		return "G1 E".digitize($currentE,4)." F".digitize($f,4)."\n";
	}else{
		return "G1 E".digitize($e,4)." F".digitize($f,4)."\n";
	}
}

sub extrudeToXYFL{ #Extrude to x,y from current x,y with f feed rate and l layer height
	my $x=$_[0];
	my $y=$_[1];
	my $f=$_[2];
	my $l=$_[3];
	my $extrusionLength=extrusionXYL($x,$y,$l);
	$currentE+=$extrusionLength;
	
	if($absolutePositioning){
		$currentX=$x;
		$currentY=$y;
	}else{
		$currentX+=$x;
		$currentY+=$y;
	}
	$currentF=$f;
  
	if($absoluteExtrusion){
		return "G1 X".digitize($x,4)." Y".digitize($y,4)." E".digitize($currentE,4)." F".digitize($f,4)."\n";
	}else{
		return "G1 X".digitize($x,4)." Y".digitize($y,4)." E".digitize($extrusionLength,4)." F".digitize($f,4)."\n";
	}
}

sub toolChange{
	my $gCode = "";
	my $startX = $slic3r{'wipeTowerX'} + $slic3r{'wipeTowerSize'} * $toolChangeNum + $slic3r{'nozzle_diameter'}[$currTool] * $toolChangeNum;
	my $startY = $slic3r{'wipeTowerY'};
	my $startXrect = $startX+($slic3r{'nozzle_diameter'}[$currTool] * (1-$slic3r{'infill_overlap'}));
	my $startYrect = $startY+($slic3r{'nozzle_diameter'}[$currTool] * (1-$slic3r{'infill_overlap'}));
	my $rectSize = $slic3r{'wipeTowerSize'}-($slic3r{'nozzle_diameter'}[$currTool] * (1-$slic3r{'infill_overlap'}) * 2);
	my $eLength = 0;
	
	$gCode.= comment("tool change in <- Script");
	$gCode.= extrudeEF(-$slic3r{'retract_length'}[$currTool], $slic3r{'retract_speed'}[$currTool] * 60);
	if(!$zLift) {
		$gCode.= lift($slic3r{'retract_lift'}[$currTool]);
	}
	$gCode.= travelToXYF($slic3r{'wipeTowerX'}, $slic3r{'wipeTowerY'}, $slic3r{'travel_speed'} * 60);
	
	if($slic3r{'useYSplitChange'}) {
		# First retract
		$gCode.= extrudeEF(-$slic3r{'ySplitFirstRetract'}, $slic3r{'ySplitFirstRetractionSpeed'} * 60);
		
		# Unretract
		$gCode.= extrudeEF($slic3r{'ySplitUnretract'}, $slic3r{'retract_speed'}[$currTool] * 60);
		
		# Slow retract to form end of filament
		$gCode.= extrudeEF(-$slic3r{'ySplitSlowRetract'}, $slic3r{'ySplitSlowRetractionSpeed'} * 60);
		
		# Farst recract the last peace
		$eLength = $slic3r{'toolChangeRetractionLength'}[$currTool] - $slic3r{'ySplitFirstRetract'} - $slic3r{'ySplitSlowRetract'} - $slic3r{'retract_length'}[$currTool] + $slic3r{'ySplitUnretract'};
		while($eLength > 100) {
			$gCode.= extrudeEF(-100, $slic3r{'retract_speed'}[$currTool] * 60);
			$eLength-= 100;
		}
		$gCode.= extrudeEF(-$eLength, $slic3r{'ySplitLarstRetractionSpeed'} * 60);
		
	} else {
		$gCode.= extrudeEF(-$slic3r{'toolChangeRetractionLength'}[$currTool] + $slic3r{'retract_length'}[$currTool], $slic3r{'retract_speed'} * 60);
	}
	$gCode.= selectExtruder($nextTool);
	$currTool = $nextTool;
	if($currLayer == 1) {
		$gCode.= "M109 S".$slic3r{'first_layer_temperature'}[$currTool]."\n";
	} else {
		$gCode.= "M109 S".$slic3r{'temperature'}[$currTool]."\n";
	}
	$gCode.= lower($slic3r{'retract_lift'}[$currTool]);
	$gCode.= comment("Correct for layer change befor tower:");
	$gCode.= travelToZ((($currLayer - 1) * $slic3r{'layer_height'}) + $slic3r{'first_layer_height'});
	# Unretract new color 
	$eLength = $slic3r{'toolChangeRetractionLength'}[$currTool] - getWipeElength($slic3r{'wipeTowerSize'}) / 2;
	while($eLength > 100) {
		$gCode.= extrudeEF(100, $slic3r{'ySplitUnRetractAfterToolChangeSpeed'} * 60);
		$eLength-= 100;
	}
	$gCode.= extrudeEF($eLength, $slic3r{'ySplitUnRetractAfterToolChangeSpeed'} * 60);
	if($currLayer == 1 and $slic3r{'brim_width'} > 0) {
		if(!$brimDone) {
			$gCode.= makeBrim();
			$brimDone = 1;
		}
	}
	$gCode.= makeSquare($startX, $startY, $slic3r{'wipeTowerSize'}, $slic3r{'wipeTowerSize'});
	$gCode.= makeRectilinearSquare($startXrect, $startYrect, $rectSize, 100);
	$gCode.= extrudeEF(-$slic3r{'retract_length'}[$currTool], $slic3r{'retract_speed'}[$currTool] * 60);
	#if($zLift) {
	#	$gCode.= lift($slic3r{'retract_lift'}[$currTool]);
	#}
	$gCode.= comment("Reset correct for layer change befor tower:");
	$gCode.= travelToZ($zBeforeWipe);
	$gCode.= comment("tool change out <- Script");
	return $gCode;
}

sub whipeTower{
	my $gCode = "";
	my $startX = $slic3r{'wipeTowerX'} + $slic3r{'wipeTowerSize'} * $toolChangeNum + $slic3r{'nozzle_diameter'}[$currTool] * $toolChangeNum;
	my $startY = $slic3r{'wipeTowerY'};
	my $startXrect = $startX+($slic3r{'nozzle_diameter'}[$currTool] * (1-$slic3r{'infill_overlap'}));
	my $startYrect = $startY+($slic3r{'nozzle_diameter'}[$currTool] * (1-$slic3r{'infill_overlap'}));
	my $rectSize = $slic3r{'wipeTowerSize'}-($slic3r{'nozzle_diameter'}[$currTool] * (1-$slic3r{'infill_overlap'}) * 2);
	
	$gCode.= comment("Print tower witout tool change");
	$gCode.= extrudeEF(-$slic3r{'retract_length'}[$currTool], $slic3r{'retract_speed'}[$currTool] * 60);
	if(!$zLift) {
		$gCode.= lift($slic3r{'retract_lift'}[$currTool]);
	}
	$gCode.= travelToXYF($slic3r{'wipeTowerX'}, $slic3r{'wipeTowerY'}, $slic3r{'travel_speed'} * 60);
	$gCode.= lower($slic3r{'retract_lift'}[$currTool]);
	$gCode.= comment("Correct for layer change befor tower:");
	$gCode.= travelToZ((($currLayer - 1) * $slic3r{'layer_height'}) + $slic3r{'first_layer_height'});
	$gCode.= extrudeEF($slic3r{'retract_length'}[$currTool], $slic3r{'retract_speed'}[$currTool] * 60);
	if($currLayer == 1 and $slic3r{'brim_width'} > 0) {
		if(!$brimDone) {
			$gCode.= makeBrim();
			$brimDone = 1;
		}
		$gCode.= makeSquare($startX, $startY, $slic3r{'wipeTowerSize'}, $slic3r{'wipeTowerSize'});
		$gCode.= makeRectilinearSquare($startXrect, $startYrect, $rectSize, 100);
	} else {
		$gCode.= makeSquare($startX, $startY, $slic3r{'wipeTowerSize'}, $slic3r{'wipeTowerSize'});
		$gCode.= makeRectilinearSquare($startXrect, $startYrect, $rectSize, $slic3r{'wipeTowerInfillNoChange'});
	}
	$gCode.= extrudeEF(-$slic3r{'retract_length'}[$currTool], $slic3r{'retract_speed'}[$currTool] * 60);
	#if($zLift) {
	#	$gCode.= lift($slic3r{'retract_lift'}[$currTool]);
	#}
	$gCode.= comment("Reset correct for layer change befor tower:");
	$gCode.= travelToZ($zBeforeWipe);
	$gCode.= comment("Whipe Tower out");
	
	return $gCode;
}

sub absolutePositioning{ # changes coordinate mode and appends the necessary G-code
	$absolutePositioning=1;
	return "G90 ; set absolute positioning\n";
}

sub relativePositioning{ # changes coordinate mode and appends the necessary G-code
	$absolutePositioning=0;
	return "G91 ; set relative positioning\n";
}

sub selectExtruder{ # switches the used extruder and appends the necessary G-code, does NOT change $activeExtruder since we want to switch back to $activeExtruder
	return "T".$_[0]."\n";
}

sub dwell{ # appends a dwelling G-code with the argument as seconds
	return "G4 S".$_[0]."\n";
}

sub comment{ # appends the argument to the currently read G-code line and comments it out with a "; "
	return "; ".$_[0]."\n";
}
