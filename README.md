# Multi-Extrusion post-processing scripts for Slic3r
useful postprocessing scripts for Slic3r for adding wipe towers and other multi-extrusion features. Written in Perl.
![example g-code](https://raw.githubusercontent.com/TheNEStOnline/Multi-Extrusion-post-processing-scripts-for-Slic3r/6c7a91dbf7c16d14acc304833537346e233451eb/Example_Images/2_Color_Dice.png)
## Available scripts
### myColorChange.pl
- adding wipe towers
- resorting print order to a sequential build for finest results
- highly configurable

## Changelog


## How to use
In order to get the scripts working properly, I suggest creating print and printer settings in slic3r exclusively for use with those scripts, and modifying these settings as described below.

### Installation
Copy the scripts to a directory of your choice, note that directory.

### In the print settings:
Add the full path to the script as noted above in the _Print Settings -> Output options -> Post-processing scripts_ field
I suggest only using one post-processing Script at a time.

### In the printer settings:
1. Tick "Use relative E distances" in Printer Settings -> General

2. In Printer Settings -> Custom G-Code, add the following to the very end of your "End G-code" right after you own custom G-Code:
```
; end g-code
; WIPE TOWER PARAMS
; Not Implemented:
; forceToolChanges = false
;
; Implemented:
; toolChangeRetractionLength = 150,150
; useAutoPlacement = 1
; wipeTowerX = 20
; wipeTowerY = 20
; wipeTowerSize = 30
; wipeTowerInfillNoChange = 10
; useYSplitChange = 1
; ySplitFirstRetractionSpeed = 2
; ySplitFirstRetract = 11
; ySplitUnretract = 7
; ySplitSlowRetractionSpeed = 150
; ySplitSlowRetract = 0
; ySplitLarstRetractionSpeed = 150
; ySplitUnRetractAfterToolChangeSpeed = 40
```

4. The "Tool change G-code" you can leave this one empty if you have no special code:

## Disclaimer / License
I've never written a line of Perl before this project. I'm still learning, but also had to make this work. Any suggestions are heavily welcome.
All scripts in this repository are licensed under the GPLv3.
