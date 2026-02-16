# SplashWindow.md

This file provides guidance to agents implementing the Skippy app's splash window. This is the first window that automatically opens when you run the app.

## Feature Overview

The splash window offers quick controls to create a Skip project, open a new Skip project, or open one of your recent Skip projects. It is a borderless, non-resizable window with only a close control. It has a split-pane layout:

- On the left (larger) pane it shows a large Skippy app icon. Beneath the icon in large bold text it has the app name (Skippy), and beneath that in smaller lighter text, the app version number.
- Beneath the icon and version number are two large stacked buttons: New Skip Project and Open Skip Project.
- On the right pane is a selectable list of the last 10 recently-opened projects. Each entry in the list is the project's directory name in bold, and beneath it in lighter text is the path to the directory. 
- Double-clicking a list entry opens the selected Skip project.

## Functionality

We will implement the actions of these controls later. Stub them for now.
