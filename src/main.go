package main

/*
#cgo CFLAGS: -x objective-c -fobjc-arc
#cgo LDFLAGS: -framework Cocoa -framework Carbon -framework ApplicationServices
#include <Cocoa/Cocoa.h>
#include <stdlib.h>
#include "bridge.h"
*/
import "C"

import (
	"encoding/xml"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"unsafe"
)

type Action struct {
	ID         int
	Identifier string
	Label      string
}

// Action IDs must match the Objective-C bridge (bridge.m) so hotkeys map to actions.
const (
	ActionLeft = iota + 1
	ActionRight
	ActionTop
	ActionBottom
	ActionTopLeft
	ActionTopRight
	ActionBottomLeft
	ActionBottomRight
	ActionLeftThirdTop
	ActionLeftThirdBottom
	ActionCenterThirdTop
	ActionCenterThirdBottom
	ActionRightThirdTop
	ActionRightThirdBottom
	ActionLeftThird
	ActionCenterThird
	ActionRightThird
	ActionCenter
	ActionToggleZoom
	ActionMaximize
	ActionToggleFullScreen
	ActionIncrease
	ActionReduce
	ActionNextScreen
	ActionPreviousScreen
)

var actions = []Action{
	{ActionLeft, "left", "Left"},
	{ActionRight, "right", "Right"},
	{ActionTop, "top", "Top"},
	{ActionBottom, "bottom", "Bottom"},
	{ActionTopLeft, "tl", "Top Left"},
	{ActionTopRight, "tr", "Top Right"},
	{ActionBottomLeft, "bl", "Bottom Left"},
	{ActionBottomRight, "br", "Bottom Right"},
	{ActionLeftThirdTop, "ltt", "Left Third Top"},
	{ActionLeftThirdBottom, "ltb", "Left Third Bottom"},
	{ActionCenterThirdTop, "ctt", "Center Third Top"},
	{ActionCenterThirdBottom, "ctb", "Center Third Bottom"},
	{ActionRightThirdTop, "rtt", "Right Third Top"},
	{ActionRightThirdBottom, "rtb", "Right Third Bottom"},
	{ActionLeftThird, "lt", "Left Third"},
	{ActionCenterThird, "ct", "Center Third"},
	{ActionRightThird, "rt", "Right Third"},
	{ActionCenter, "center", "Center"},
	{ActionToggleZoom, "zoom", "Toggle Zoom"},
	{ActionMaximize, "maximize", "Maximize"},
	{ActionToggleFullScreen, "fullScreen", "Toggle Full Screen"},
	{ActionIncrease, "increase", "Increase"},
	{ActionReduce, "reduce", "Reduce"},
	{ActionNextScreen, "nextscreen", "Next Screen"},
	{ActionPreviousScreen, "previousscreen", "Previous Screen"},
}

var debugEnabled bool

//export GoHandleAction
func GoHandleAction(actionID C.int) {
	// Callback invoked by Objective-C when a hotkey fires.
	if debugEnabled {
		if a, ok := actionByID(int(actionID)); ok {
			fmt.Fprintf(os.Stderr, "[ShiftItGo] handle action id=%d identifier=%s label=%s\n", a.ID, a.Identifier, a.Label)
		} else {
			fmt.Fprintf(os.Stderr, "[ShiftItGo] handle action id=%d\n", int(actionID))
		}
	}
	C.SI_PerformAction(actionID)
}

func main() {
	flag.BoolVar(&debugEnabled, "debug", false, "enable debug logging")
	flag.Parse()
	if debugEnabled {
		C.SI_SetDebug(1)
		fmt.Fprintf(os.Stderr, "[ShiftItGo] debug enabled (pid=%d)\n", os.Getpid())
	}

	// Resolve resources (menu bar icon + defaults plist) relative to app bundle or repo.
	iconPath := findResourcePath("SHIFTIT_ICON_PATH", []string{
		filepath.Join("..", "Resources", "ShiftItMenuIcon.png"),
		filepath.Join("..", "..", "resources", "ShiftItMenuIcon.png"),
		filepath.Join("..", "resources", "ShiftItMenuIcon.png"),
	})
	if _, err := os.Stat(iconPath); err == nil {
		cpath := C.CString(iconPath)
		C.SI_SetStatusIcon(cpath)
		C.free(unsafe.Pointer(cpath))
	}

	defaultsPath := findResourcePath("SHIFTIT_DEFAULTS_PATH", []string{
		filepath.Join("..", "Resources", "ShiftIt-defaults.plist"),
		filepath.Join("..", "..", "resources", "ShiftIt-defaults.plist"),
		filepath.Join("..", "resources", "ShiftIt-defaults.plist"),
	})

	// Load defaults for hotkeys and size delta config.
	defaults, err := readPlistValues(defaultsPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "[ShiftItGo] failed to read defaults plist: %v (path=%s)\n", err, defaultsPath)
	} else if debugEnabled {
		fmt.Fprintf(os.Stderr, "[ShiftItGo] loaded defaults plist: %s\n", defaultsPath)
	}

	// Size delta config for increase/reduce actions.
	if defaults != nil {
		sizeDeltaType := int(getInt(defaults, "sizeDeltaType", 3003))
		fixedW := getFloat(defaults, "fixedSizeWidthDelta", 50)
		fixedH := getFloat(defaults, "fixedSizeHeightDelta", 28)
		windowPct := getFloat(defaults, "windowSizeDelta", 10)
		screenPct := getFloat(defaults, "screenSizeDelta", 6.25)
		C.SI_SetSizeDeltaConfig(C.int(sizeDeltaType), C.double(fixedW), C.double(fixedH), C.double(windowPct), C.double(screenPct))
	}

	// Register hotkeys for supported actions and add menu items with shortcuts.
	for _, action := range actions {
		keyCodeKey := action.Identifier + "KeyCode"
		modsKey := action.Identifier + "Modifiers"
		keyCode := int(getInt(defaults, keyCodeKey, -1))
		mods := uint32(getInt(defaults, modsKey, 0))
		if keyCode < 0 {
			if debugEnabled {
				fmt.Fprintf(os.Stderr, "[ShiftItGo] skip action id=%d identifier=%s (no keycode)\n", action.ID, action.Identifier)
			}
			continue
		}
		if debugEnabled {
			fmt.Fprintf(os.Stderr, "[ShiftItGo] register action id=%d identifier=%s keyCode=%d modifiers=%d\n", action.ID, action.Identifier, keyCode, mods)
		}
		C.SI_RegisterHotKey(C.int(action.ID), C.int(keyCode), C.uint(mods))

		title := action.Label
		if shortcut := shortcutString(keyCode, mods); shortcut != "" {
			title = fmt.Sprintf("%s — %s", action.Label, shortcut)
		}
		ctitle := C.CString(title)
		C.SI_AddMenuItem(C.int(action.ID), ctitle)
		C.free(unsafe.Pointer(ctitle))
	}

	// Start Cocoa app loop and begin handling events.
	C.SI_RunApp()
}

type plistValue struct {
	Key   string
	Value interface{}
}

func readPlistValues(path string) (map[string]interface{}, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	dec := xml.NewDecoder(f)
	values := make(map[string]interface{})

	for {
		tok, err := dec.Token()
		if err != nil {
			if strings.Contains(err.Error(), "EOF") {
				break
			}
			return values, err
		}

		switch se := tok.(type) {
		case xml.StartElement:
			if se.Name.Local == "key" {
				var key string
				if err := dec.DecodeElement(&key, &se); err != nil {
					return values, err
				}
				val, err := readNextValue(dec)
				if err == nil {
					values[key] = val
				}
			}
		}
	}
	return values, nil
}

func findResourcePath(envVar string, rels []string) string {
	// Allow explicit override for local testing.
	if v := os.Getenv(envVar); v != "" {
		return v
	}
	candidates := buildCandidatePaths(rels)
	if p := firstExistingPath(candidates...); p != "" {
		return p
	}
	if len(candidates) > 0 {
		return candidates[0]
	}
	return ""
}

func buildCandidatePaths(rels []string) []string {
	// First, try relative to the executable (app bundle), then repo-relative.
	candidates := make([]string, 0, len(rels)*2)
	if exePath, err := os.Executable(); err == nil {
		exeDir := filepath.Dir(exePath)
		for _, rel := range rels {
			candidates = append(candidates, filepath.Clean(filepath.Join(exeDir, rel)))
		}
	}
	for _, rel := range rels {
		candidates = append(candidates, filepath.Clean(rel))
	}
	return candidates
}

func firstExistingPath(paths ...string) string {
	for _, p := range paths {
		if p == "" {
			continue
		}
		if _, err := os.Stat(p); err == nil {
			return p
		}
	}
	return ""
}

func readNextValue(dec *xml.Decoder) (interface{}, error) {
	// Minimal plist decoder: enough for the defaults we use (integer/real/string/bool).
	for {
		tok, err := dec.Token()
		if err != nil {
			return nil, err
		}
		switch se := tok.(type) {
		case xml.StartElement:
			switch se.Name.Local {
			case "integer":
				var s string
				if err := dec.DecodeElement(&s, &se); err != nil {
					return nil, err
				}
				v, _ := strconv.ParseInt(strings.TrimSpace(s), 10, 64)
				return v, nil
			case "real":
				var s string
				if err := dec.DecodeElement(&s, &se); err != nil {
					return nil, err
				}
				v, _ := strconv.ParseFloat(strings.TrimSpace(s), 64)
				return v, nil
			case "string":
				var s string
				if err := dec.DecodeElement(&s, &se); err != nil {
					return nil, err
				}
				return s, nil
			case "true":
				_ = dec.Skip()
				return true, nil
			case "false":
				_ = dec.Skip()
				return false, nil
			default:
				_ = dec.Skip()
				return nil, nil
			}
		}
	}
}

func shortcutString(keyCode int, mods uint32) string {
	// Build a macOS-style shortcut string (e.g. ⌃⌥⌘←).
	if keyCode < 0 {
		return ""
	}
	var b strings.Builder
	if mods&uint32(C.NSEventModifierFlagControl) != 0 {
		b.WriteString("⌃")
	}
	if mods&uint32(C.NSEventModifierFlagOption) != 0 {
		b.WriteString("⌥")
	}
	if mods&uint32(C.NSEventModifierFlagShift) != 0 {
		b.WriteString("⇧")
	}
	if mods&uint32(C.NSEventModifierFlagCommand) != 0 {
		b.WriteString("⌘")
	}
	key := keyCodeToString(keyCode)
	if key == "" {
		return b.String()
	}
	b.WriteString(key)
	return b.String()
}

func keyCodeToString(keyCode int) string {
	if v, ok := keyCodeMap[keyCode]; ok {
		return v
	}
	return ""
}

var keyCodeMap = map[int]string{
	0:   "A",
	1:   "S",
	2:   "D",
	3:   "F",
	4:   "H",
	5:   "G",
	6:   "Z",
	7:   "X",
	8:   "C",
	9:   "V",
	11:  "B",
	12:  "Q",
	13:  "W",
	14:  "E",
	15:  "R",
	16:  "Y",
	17:  "T",
	18:  "1",
	19:  "2",
	20:  "3",
	21:  "4",
	22:  "6",
	23:  "5",
	24:  "=",
	25:  "9",
	26:  "7",
	27:  "-",
	28:  "8",
	29:  "0",
	30:  "]",
	31:  "O",
	32:  "U",
	33:  "[",
	34:  "I",
	35:  "P",
	36:  "Return",
	37:  "L",
	38:  "J",
	39:  "'",
	40:  "K",
	41:  ";",
	42:  "\\",
	43:  ",",
	44:  "/",
	45:  "N",
	46:  "M",
	47:  ".",
	48:  "Tab",
	49:  "Space",
	50:  "`",
	51:  "Delete",
	53:  "Esc",
	123: "←",
	124: "→",
	125: "↓",
	126: "↑",
}

func getInt(m map[string]interface{}, key string, def int64) int64 {
	if m == nil {
		return def
	}
	if v, ok := m[key]; ok {
		switch t := v.(type) {
		case int64:
			return t
		case int:
			return int64(t)
		case float64:
			return int64(t)
		case string:
			if n, err := strconv.ParseInt(t, 10, 64); err == nil {
				return n
			}
		}
	}
	return def
}

func getFloat(m map[string]interface{}, key string, def float64) float64 {
	if m == nil {
		return def
	}
	if v, ok := m[key]; ok {
		switch t := v.(type) {
		case float64:
			return t
		case int64:
			return float64(t)
		case int:
			return float64(t)
		case string:
			if n, err := strconv.ParseFloat(t, 64); err == nil {
				return n
			}
		}
	}
	return def
}

func actionByID(id int) (Action, bool) {
	for _, a := range actions {
		if a.ID == id {
			return a, true
		}
	}
	return Action{}, false
}
