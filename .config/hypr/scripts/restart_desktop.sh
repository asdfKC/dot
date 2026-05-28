#!/bin/bash
pkill waybar; sleep 0.5; waybar &
pkill mpvpaper; sleep 0.5
mpvpaper -o "no-audio loop" DP-4 ~/Wallpapers/live.mp4 &
mpvpaper -o "no-audio loop" HDMI-A-1 ~/Wallpapers/live.mp4 &
