# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A collection of small utilities and tools designed to enhance the Claude Code CLI experience on Windows. Each tool lives in its own subdirectory.

## Language & Platform

- Primary platform: **Windows 10/11**
- Scripts: **PowerShell 5.1** (`powershell.exe`, not `pwsh.exe`) and **Batch files** (`.bat`)
- PowerShell scripts that use `System.Windows.Forms.Clipboard` must run in STA (Single-Threaded Apartment) mode — this is the default for `powershell.exe` 5.1 but NOT for `pwsh.exe` 7+

## Architecture

Each tool is a self-contained directory with its own scripts and an `install.bat` for one-click setup. Tools integrate with Claude Code via hooks configured in `~/.claude/settings.json`.

## Conventions

- User-facing messages should be in **Traditional Chinese (zh-TW)**
- Design specs are stored in `docs/superpowers/specs/` with format `YYYY-MM-DD-<topic>-design.md`
- When modifying `~/.claude/settings.json`, always use JSON merge (read → modify → write), never overwrite the entire file
