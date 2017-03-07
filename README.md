# Multi-Extrusion post-processing scripts for Slic3r
useful post-processing scripts for Slic3r for adding wipe towers and other multi-extrusion features. Written in Perl.
![example g-code](https://raw.githubusercontent.com/TheNEStOnline/Multi-Extrusion-post-processing-scripts-for-Slic3r/6c7a91dbf7c16d14acc304833537346e233451eb/Example_Images/2_Color_Dice.png)
## Features:
- adding wipe towers
- highly configurable
- Works with as many colours as you can fit towers in a single row.
- Auto find the number of tool change per layer to determine the number of towers needed.
- Detect layer change even with the wired layers when Slic3r is creating support material. (Tries to correct layer height when printing tower)
- Only fill the tower if there is a tool change on that layer.
- Manuel placement of tower.
- Auto placement of tower according to size of print.
- Imports settings form Slic3r for brim and other stuff needed so you don't need to add them.
- Supports Z-lift. (If not the same as layer hight)
- Uses the square around the tower to wipe after colour change.
- It will create brim according to Slic3r settings.
- Change temp while changing tool/colour.
- Retraction sequence suggested by Teilchen.

## Changelog
See [Wiki](https://github.com/TheNEStOnline/Multi-Extrusion-post-processing-scripts-for-Slic3r/wiki)

## To do:
See [myColourChange](https://github.com/TheNEStOnline/Multi-Extrusion-post-processing-scripts-for-Slic3r/projects/1)

## Known Issues:
- If skirt is added the script will detect an extra colour change.

## How to use
In order to get the scripts working properly, I suggest creating print and printer settings in slic3r exclusively for use with those scripts, and modifying these settings as described below.

See [Wiki](https://github.com/TheNEStOnline/Multi-Extrusion-post-processing-scripts-for-Slic3r/wiki)

### Installation
See [Wiki](https://github.com/TheNEStOnline/Multi-Extrusion-post-processing-scripts-for-Slic3r/wiki)

## Disclaimer / License
I've never written a line of Perl before this project. I'm still learning, but also had to make this work. Any suggestions are heavily welcome.
All scripts in this repository are licensed under the GPLv3.
