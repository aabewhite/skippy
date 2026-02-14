# Emulator.md

This file provides guidance to agents implementing the Skippy app's Android emulator management functionality.

## Feature Overview

Skippy's emulator management allows users to Add, Remove, List, and Start Android emulators. It is a GUI frontend to the `skip android emulator` command line tool, which has the following suite of commands:

```
USAGE: skip android emulator <subcommand>

SUBCOMMANDS:
  create            Install and create an Android emulator image
  list              List installed Android emulators
  launch            Launch an Android emulator

---

USAGE: # Creates a custom Android emulator
       skip android emulator create --name 'pixel_7_api_36' --device-profile pixel_7 --android-api-level 36

OPTIONS:
  --android-api-level <level>
                          Android API emulator level (default: 34)
  --device-profile <profile>
                          Android emulator device profile (default: pixel_7)
  -n, --name <name>       Android emulator name

---

USAGE: skip android emulator list

---

USAGE: # Launches the most recently created or used emulator
       skip android emulator launch

       # Launches an emulator with a certain name
       skip android emulator launch --name emulator-34-medium_phone
```

## Locating the `skip` Command

Factor out the command-locating code from the Logcat.swift file into its own file and reuse it to locate the `skip` command line tool. We will also be using the `avdmanager` command line tool, which you will find the same way.

## Emulators Window

Skippy can open an Emulators window that has the following functionality:
- A list of the available emulators.
- A Toolbar button to create an emulator. This opens the New Emulator window.
- A toolbar button to refresh the list.
- A Toolbar button to launch the currently-selected emulator in the list.
- A Toolbar button to delete the currently-selected emulator in the list.

`skip android emulator` does not support deleting emulators. Instead, use `avdmanager delete avd -name <name>` to delete.

## New Emulator Window

This window is a frontend to `skip android emulator create` command. It displays a form where the user can select the new emulators's Device Profile (dropdown menu), Android API Level (dropdown menu), and Name (text field). The Name defaults to a concatenation of the Device Profile and Android API Level, but can be edited by the user.

Use the `avdmanager list target` command to populate the available Android API Levels. Each outputted entry will look something like:

```
----------
id: 1 or "android-34"
     Name: Android API 34, extension level 7
     Type: Platform
     API level: 34
     Revision: 3
```

Use the part of the "id" field in quotation marks as the API Level to use in the API Level dropdown menu and in the command we'll run to create the emulator.

Use the `avdmanager list device` command to populate the available Device Profiles. Each outputted entry will look something like:

```
---------
id: 29 or "pixel_7"
    Name: Pixel 7
    OEM : Google
```

Use the part of the "id" field in quotation marks as the Device Profile to use in the Device Profile dropdown menu and in the command we'll run to create the emulator.

Apart from the form to select these values, the New Emulator window has a Toolbar button to create the emulator and a large read-only text field. When the user clicks to create the emulator, the text field displays the `skip android emulator create` command we use to create the emulator and all of the output from that command. When the command completes we refresh the list in the Emulators window.
 

## Emulator Menu

Skippy should have an Emulator app menu with two options:
- Manage Emulators: Open the Emulators window.
- Launch: Launches the last-used Android emulator. If there are no available emulators, display an alert telling the user that they must create an emulator first.