; Proof of concept for replacement for HotClass
#include hotclass.ahk

OutputDebug, DBGVIEWCLEAR
/*
============================================================================================================
Test script for Hotclass
Performs automated tests, plus loads a bunch of bindings for manual testing

Automated tests send fake input objects to _ProcessInput and assert that the callbacks were fired correctly.
Only matching logic is tested by the automated tests.
============================================================================================================
*/
#SingleInstance force
th := new TestHarness()
return

GuiClose:
	ExitApp

class TestHarness {
	__New(){
		this.HotkeyStates := []
		this.HotClass := new HotClass()
		this.HotClass.EnforceOrder := 0
		Loop % 12 {
			this.HotkeyStates[A_Index] := 0
			name := "hk" A_Index
			this.HotClass.AddHotkey(name, this.hkPressed.Bind(this, A_Index), "w280 xm")
			Gui, Add, Checkbox, Disabled hwndhwnd xp+290 yp+4
			this.hStateChecks[name] := hwnd
		}
		Gui, Show, x0 y0
		
		; Build a list of keys. UIDs would not normally be needed, but seeing as we will be simulating input, we will need them.
		keys := {}
		keys.a := {type: "k", code: 30, uid: "k30"}
		keys.ctrl := {type: "k", code: 29, uid: "k29"}
		keys.shift := {type: "k", code: 42, uid: "k42"}
		keys.alt := {type: "k", code: 56, uid: "k56"}
		keys.s := {type: "k", code: 31, uid: "k31"}
		keys.lbutton := {type: "m", code: 1, uid: "m1"}
		
		; Load bindings
		this.HotClass.DisableHotkeys()
		this.HotClass.SetHotkey("hk1", [keys.a])
		this.HotClass.SetHotkey("hk2", [keys.ctrl,keys.a])
		this.HotClass.SetHotkey("hk3", [keys.shift,keys.a])
		this.HotClass.SetHotkey("hk4", [keys.ctrl,keys.shift,keys.a])
		this.HotClass.SetHotkey("hk5", [keys.s])
		this.HotClass.SetHotkey("hk6", [keys.ctrl,keys.s])
		;this.HotClass.SetHotkey("hk7", [keys.shift,keys.s])
		this.HotClass.SetHotkey("hk8", [keys.ctrl,keys.shift,keys.s])
		this.HotClass.SetHotkey("hk9", [keys.ctrl,keys.shift])
		this.HotClass.SetHotkey("hk10", [keys.alt,keys.ctrl,keys.shift,keys.a])
		this.HotClass.SetHotkey("hk11", [keys.ctrl,keys.lbutton])
		this.HotClass.SetHotkey("hk12", [{type: "m", code: 4},{type: "h", joyid: 2, code: 1}])
		this.HotClass.EnableHotkeys()
		
		/*
		; Perform Automated Tests
		this.TestInput(keys.a,1).TestInput(keys.s,1)
		this.Assert(1, true, "TEST 1 FAIL: hk1 not pressed")
		this.TestInput(keys.ctrl,1)
		this.Assert(1, false, "TEST 2 FAIL: hk1 Not released")
		this.Assert(2, true, "TEST 3 FAIL: hk2 not pressed")
		this.Assert(6, true, "TEST 4 FAIL: hk6 not pressed")

		this.TestInput(keys.shift,1)
		this.Assert(2, false, "TEST 5 FAIL: hk2 Not released")
		;this.TestInput(keys.ctrl,0).TestInput(keys.a,0)
		;this.Assert(1, false, "TEST 5 FAIL: hk1 not released")
		;this.Assert(2, false, "TEST 6 FAIL: hk2 not released")
		*/
	}
	
	; called when hk1 goes up or down.
	hkPressed(hk, event){
		name := "hk" hk
		GuiControl,,% this.hStateChecks[name], % event
		this.HotkeyStates[hk] := event
	}
	
	Assert(hk, state, description){
		if (this.HotkeyStates[hk] = state){
			return 1
		} else {
			msgbox % description
		return 0
		}
	}
	
	; Simulate input
	TestInput(keys, event){
		this.HotClass._ProcessInput(event(keys,event))
		return this
	}
}

event(obj, event){
	obj.event := event
	return obj
}
