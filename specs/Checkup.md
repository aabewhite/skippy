# Checkup.md

This file provides guidance to agents implementing the Skippy app's `skip checkup` and `skip doctor` debug commands.

## Feature Overview

Skippy allows users to execute the `skip doctor` and `skip checkup` commands from its Debug app menu. These commands are placed in their own group within the menu.

## Doctor

Run `skip doctor --native --log-file <path>` and display a window showing the output, using our standard command output view. Add window toolbar buttons to copy the output to the clipboard and to save the output to a text file.

## Checkup

Run `skip checkup --native --log-file <path>` and display a window showing the output, using our standard command output view. Add window toolbar buttons to copy the output to the clipboard and to save the output to a text file.

## Log Files

Select a temporary file path for the `--log-file` argument value. When the command completes, append some linkified text to the output scroll view offering to open the log file. When the user clicks the linkified text, ask the system to open the file path.