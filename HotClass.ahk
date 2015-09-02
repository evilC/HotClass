; Proof of concept for replacement for HotClass
#include CInputDetector.ahk

OutputDebug, DBGVIEWCLEAR
;============================================================================================================
; Test script
;============================================================================================================
#SingleInstance force
mc := new MyClass()
return

GuiClose:
	ExitApp

class MyClass {
	__New(){
		this.HotkeyStates := []
		this.HotClass := new HotClass()
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
		keys.q := {type: "k", code: 31, uid: "k31"}
		keys.lbutton := {type: "m", code: 1, uid: "m1"}
		
		this.HotClass.DisableHotkeys()
		this.HotClass.SetHotkey("hk1", [keys.a])
		this.HotClass.SetHotkey("hk2", [keys.ctrl,keys.a])
		this.HotClass.SetHotkey("hk3", [keys.shift,keys.a])
		this.HotClass.SetHotkey("hk4", [keys.ctrl,keys.shift,keys.a])
		this.HotClass.SetHotkey("hk5", [keys.q])
		this.HotClass.SetHotkey("hk6", [keys.ctrl,keys.q])
		this.HotClass.SetHotkey("hk7", [keys.shift,keys.q])
		this.HotClass.SetHotkey("hk8", [keys.ctrl,keys.shift,keys.q])
		this.HotClass.SetHotkey("hk9", [keys.ctrl,keys.shift])
		this.HotClass.SetHotkey("hk10", [keys.alt,keys.ctrl,keys.shift,keys.a])
		this.HotClass.SetHotkey("hk11", [keys.ctrl,keys.lbutton])
		this.HotClass.SetHotkey("hk12", [{type: "m", code: 4},{type: "h", joyid: 2, code: 1}])
		this.HotClass.EnableHotkeys()
		
		this.TestInput(keys.a,1)
		this.Assert(1, true, "FAIL: hk1 not pressed")
		this.TestInput(keys.ctrl,1)
		this.Assert(1, false, "FAIL: hk Not released")
		this.Assert(2, true, "FAIL: hk2 not pressed")
		this.TestInput(keys.ctrl,0).TestInput(keys.a,0)
		this.Assert(1, false, "FAIL: hk1 not released")
		this.Assert(2, false, "FAIL: hk2 not released")
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

;============================================================================================================
; Libraries
;============================================================================================================

;------------------------------------------------------------------------------------------------------------
; Class that manages ALL hotkeys for the script
;------------------------------------------------------------------------------------------------------------
class HotClass{
	#MaxThreadsPerHotkey 256	; required for joystick input as (8 * 32) hotkeys are declared to watch for button down events.
	
	; Constructor
	; startactive param decides 
	__New(options := 0){
		this.STATES := {IDLE: 0, ACTIVE: 1, BIND: 2}		; State Name constants, for human readibility
		this._HotkeyCache := []								; Length ordered array of keysets
		this._HotkeyStates := {}							; Name indexed list of boolean state values
		this._KeyCache := []								; Associative array of key uids
		this._ActiveHotkeys := []							; Hotkeys currently in down state - for quick ObjHasKey matching
		this._Hotkeys := {}									; A name indexed array of hotkey objects

		this._FuncEscTimer := this._EscTimer.Bind(this)
		
		Gui, +HwndOldDefaultHwnd	; store default gui
		Gui, New, hwndhwnd -Border
		this._hDialog := hwnd
		Gui, % this._hDialog ":Add", Text, Center, Bind Mode`n`nPress any combination of keys to bind.`n`nBinding finished on an up event.
		;Gui, % this._hDialog ":Show"
		Gui, % OldDefaultHwnd ":Default"	; restore default Gui
		; Set default options
		if (!IsObject(options) || options == 0){
			options := {StartActive: 1}
		}
		
		; Initialize the Library that detects input.
		this.CInputDetector := new CInputDetector(this._ProcessInput.Bind(this))

		; Initialize state
		if (options.StartActive){
			this._ChangeState(this.STATES.ACTIVE)
		} else {
			this._ChangeState(this.STATES.IDLE)
		}
		
	}
	
	; User command to add a new hotkey
	AddHotkey(name, callback, aParams*){
		; ToDo: Ensure unique name
		this._Hotkeys[name] := new this._Hotkey(this, name, callback, aParams*)
	}

	EnableHotkeys(){
		; set state of hotkey class
		;this._Hotkeys[this._BindName].SetBinding(this._HeldKeys)
		
		; Trigger state change
		this._ChangeState(this.STATES.ACTIVE)
	}
	
	DisableHotkeys(){
		;this._handler._ChangeState(this._handler.STATES.IDLE, this.Name)
		this._ChangeState(this.STATES.IDLE, this.Name)
	}

	SetHotkey(name, value){
		Loop % value.length(){
			if (!ObjHasKey(value[A_Index], "uid")){
				value[A_Index].uid := value[A_Index].joyid value[A_Index].type value[A_Index].code
			}
		}
		this._Hotkeys[name].SetBinding(value)
	}
	
	; Handles all state transitions
	; Returns 1 if we transitioned to the specified state, 0 if not
	_ChangeState(state, args*){
		if (state == this._State){
			return 1
		}
		if (!ObjHasKey(this, "_State")){
			; Initialize state
			this._State := this.STATES.IDLE			; Set state to IDLE
		}
		
		; Decide what to do, based upon state we wish to transition to
		if (state == this.STATES.IDLE){
			; Go idle / initialize, no args required
			OutputDebug % "ENTERED IDLE STATE"
			this.CInputDetector.DisableHooks()
			this._State := state
			this._BindName := ""					; The name of the hotkey that is being bound
			this._HeldKeys := []					; The keys that are currently held
			this._ActiveHotkeys := {}				; Hotkeys which are currently in a down state
			return 1
		} else if (state == this.STATES.ACTIVE ){
			; Enter ACTIVE state, no args required
			OutputDebug % "ENTERED ACTIVE STATE" out
			if (this._State == this.STATES.BIND){
				; Transition from BIND state
				Gui, % this._hDialog ":Hide"	; Hide Bind Mode dialog
			}
			; Build size-ordered list of hotkeys
			this._BuildHotkeyCache()
			; Reset Vars
			this._HeldKeys := []
			this._ActiveHotkeys := {}
			this._State := state
			this.CInputDetector.EnableHooks()
			return 1
		} else if (state == this.STATES.BIND ){
			; Enter BIND state.
			Gui, % this._hDialog ":Show"	; Show Bind Mode dialog
			; args[1] = name of hotkey requesting state change
			this.CInputDetector.EnableHooks()
			if (args.length()){
				OutputDebug % "ENTERED BINDING STATE FOR HOTKEY NAME: " args[1]
				this._HeldKeys := []
				this._BindName := args[1]
				this._State := state
				return 1
			}
		}
		; Default to Fail
		return 0
	}

	; Builds the quick lookup cache for _ProcessInput's ACTIVE state
	_BuildHotkeyCache(){
		OutputDebug % "Building hotkey cache"
		this._KeyCache := {}
		this._HotkeyStates := {}
		currentlength := 0
		count := 0
		; find longest hotkey length, build key cache, initialize subset / superset arrays
		for name, hotkey in this._Hotkeys {
			count++							; count holds number of hotkeys
			hotkey._IsSubSetOf := []		; Array that holds other hotkeys that this hotkey is a subset of
			hotkey._IsSuperSetOf := []		; Array that holds other hotkeys that this hotkey is a superset of
			this._HotkeyStates[name] := 0	; Initialize state
			if (hotkey.Value.length() > currentlength){
				currentlength := hotkey.Value.length()
			}
			Loop % hotkey.Value.length() {
				this._KeyCache[hotkey.Value[A_Index].uid] := 1
			}
		}
		
		; currentlength should now hold length of longest hotkey
		this._HotkeyCache := []
		hotkeys := this._Hotkeys.clone()
		; Build length (as in number of keys in each hotkey) ordered list of hotkeys
		t := A_TickCount
		while (Count && A_TickCount - t < 2000){	; insurance against dumb code inside)
		;while (Count){
			; Iterate through clone of hotkey list, decrementing currentlength each time
			new_hotkeys := hotkeys.clone()
			for name, hotkey in hotkeys {
				; check if length matches currentlength
				if (hotkey.Value.length() = currentlength){
					; Find out if any of the previously added hotkeys are a superset of this one.
					Loop % this._HotkeyCache.length(){
						; Check this hotkey against the one in the cache
						if (this._CompareHotkeys(hotkey.Value,this._HotkeyCache[A_Index].Value)){
							hotkey._IsSubSetOf.push(this._HotkeyCache[A_Index])
							this._HotkeyCache[A_Index]._IsSuperSetOf.push(hotkey)
						}
					}
					; Add hotkey to the cache
					this._HotkeyCache.push(hotkey)
					; remove this hotkey from the loop
					;hotkeys.Remove(name)
					new_hotkeys.Remove(name)
					Count--
				}
			}
			; Replace hotkeys with shorter version for next run.
			hotkeys := new_hotkeys
			currentlength--
		}
		if (Count){
			OutputDebug % "Aborted Building hotkey cache"
			return
		}
		dbg := "me"
		OutputDebug % "hotkey cache built"
	}
	
	; All Input Events flow through here - ie an input device changes state
	; Encompasses keyboard keys, mouse buttons / wheel and joystick buttons or hat directions
	_ProcessInput(keyevent){
		; Update list of held keys, filter repeat events
		if (keyevent.event){
			; Down event - add keys.
			if (this._CompareHotkeys([keyevent], this._HeldKeys)){
				; repeat down event
				return 0
			}
			this._HeldKeys.push(keyevent)
		} else if (this._State != this.STATES.BIND) {
			; Up Event - remove keys
			; In Bind mode, an up event triggers the end of binding.
			; Therefore, do not remove the key from _HeldKeys that triggered the end (it's one of the bound keys).
			pos := this._CompareHotkeys([keyevent], this._HeldKeys)
			if (pos){
				this._HeldKeys.Remove(pos)
			}
		}
		OutputDebug % keyevent.uid " " keyevent.event
		
		;OutputDebug % "EVENT: " this._RenderHotkey(keyevent) " " state[keyevent.event]
		if (this._State == this.STATES.BIND){
			; Bind mode - block all input and build up a list of held keys
			if (keyevent.event = 1){
				if (keyevent.Type = "k" && keyevent.Code == 1){
					; Escape down - start timer to detect hold of escape to quit
					fn := this._FuncEscTimer
					SetTimer, % fn, -1000
				}
			} else {
				; Up event in bind mode - state change from bind mode to normal mode
				if (keyevent.Type = "k" && keyevent.Code == 1){
					; Escape up - stop timer to detect hold of escape to quit
					fn := this._FuncEscTimer
					SetTimer, % fn, Off
				}
				
				;ToDo: Check if hotkey is duplicate, and if so, reject.
				
				; set state of hotkey class
				this._Hotkeys[this._BindName].SetBinding(this._HeldKeys)
				
				; Trigger state change
				;this._ChangeState(this.STATES.ACTIVE)
				
				this.EnableHotkeys()

			}
			return 1 ; block input
		} else if (this._State == this.STATES.ACTIVE){
			; ACTIVE state - aka "Normal Operation". Trigger hotkey callbacks as appropriate
			; Ignore events for keys not involved in hotkeys
			if (!ObjHasKey(this._KeyCache, keyevent.uid)){
				return 0
			}
			
			hotkey_delta := {}
			; Loop through hotkeys, longest to shortest.
			Loop % this._HotkeyCache.length(){
				main_name := this._HotkeyCache[A_Index].name
				if (this._CompareHotkeys(this._Hotkeys[main_name].Value, this._HeldKeys)){
					; hotkey matches
					; check if hotkey is overridden
					brk := 0
					Loop % this._Hotkeys[main_name]._IsSubSetOf.length(){
						superset_name := this._Hotkeys[main_name]._IsSubSetOf[A_Index].name
						; is this key a subset of an active superset?
						if (ObjHasKey(this._ActiveHotkeys, superset_name)){
							; ignore
							brk := 1
							break
						}
					}
					if (!brk){
						;OutputDebug % "MATCH: " main_name
						hotkey_delta[main_name] := 1
						this._ActiveHotkeys[main_name] := this._Hotkeys[main_name].Value
						
					} else {
						; does not match.
						;OutputDebug % "IGNORE: " main_name
						hotkey_delta[main_name] := 0
						this._ActiveHotkeys.Remove(main_name)
					}
					
				} else {
					;OutputDebug % "DOES NOT MATCH: " main_name
					hotkey_delta[main_name] := 0
					this._ActiveHotkeys.Remove(main_name)
				}
			}
			
			; Fire all up event callbacks, then all down event callbacks.
			Loop 2 {
				idx := A_Index - 1
				For delta_name, state in hotkey_delta {
					; Release all hotkeys that want to go up
					if (state = idx){
						if (this._HotkeyStates[delta_name] != state){
							OutputDebug % "CALLBACK " delta_name ": " state
							this._Hotkeys[delta_name]._Callback.(state)
							this._HotkeyStates[delta_name] := state
						}
					}
				}
			}
			; Default to not blocking input
		}
		
		return 0 ; don't block input
	}
	
	; All of needle must be in haystack
	_CompareHotkeys(needle, haystack){
		length := needle.length()
		Count := 0
		; Loop through elements of the needle
		Loop % length {
			ni := A_Index
			; Loop through the haystack to see if this item is present
			Loop % haystack.length() {
				hi := A_Index
				if (needle[ni].uid == haystack[hi].uid){
					;OutputDebug % out "YES"
					count++
					if (Count = length){
						break
					}
				}
			}
		}
		
		if (Count && (Count = length)){
			return hi
		}
		return 0
	}
	
	; Called on a Timer to detect timeout of Escape key in Bind Mode
	_EscTimer(){
		this._BindList := {}
		this._ChangeState(this.STATES.ACTIVE)
	}
	
	; ============================================================================================================================
	;                                         HOTKEY CLASS
	; ============================================================================================================================
	; Each hotkey is an instance of this class.
	; Handles the Gui control and routing of callbacks when the hotkey triggers
	class _Hotkey {
		static _MenuText := "Select new Binding|Toggle Wild (*) |Toggle PassThrough (~)|Remove Binding"
		__New(handler, name, callback, aParams*){
			this._handler := handler
			this._Callback := callback
			this.Name := name
			this.BindList := {}
			this.Value := {}						; Holds the current binding
			
			Gui, Add, ComboBox, % "hwndhwnd AltSubmit " aParams[1], % this._MenuText
			this._hwnd := hwnd
			this._hEdit := DllCall("GetWindow","PTR",this._hwnd,"Uint",5) ;GW_CHILD = 5
			fn := this.OptionSelected.Bind(this)
			GuiControl +g, % hwnd, % fn
		}
		
		; An option was selected in the drop-down list
		OptionSelected(){
			GuiControlGet, option,, % this._hwnd
			GuiControl, Choose, % this._hwnd, 0
			if (option = 1){
				this._handler._ChangeState(this._handler.STATES.BIND, this.Name)
			} else if (option = 2){
				;ToolTip Wild Option Changed
				this.Wild := !this.Wild
			} else if (option = 3){
				;ToolTip PassThrough Option Changed
				this.PassThrough := !this.PassThrough
			} else if (option = 4){
				;ToolTip Remove Binding
				
			}
		}

		; Setter
		SetBinding(BindList){
			static EM_SETCUEBANNER:=0x1501
			this.BindList := BindList
			this.Value := BindList
			DllCall("User32.dll\SendMessageW", "Ptr", this._hEdit, "Uint", EM_SETCUEBANNER, "Ptr", True, "WStr", this.BuildHumanReadable(BindList))
		}
		
		; Builds a human readable string from a hotkey object
		BuildHumanReadable(BindList){
			static mouse_lookup := ["LButton", "RButton", "MButton", "XButton1", "XButton2", "WheelU", "WheelD", "WheelL", "WheelR"]
			static pov_directions := ["U", "R", "D", "L"]
			static event_lookup := {0: "Release", 1: "Press"}
			
			out := ""
			Loop % BindList.length(){
				if (A_Index > 1){
					out .= " + "
				}
				obj := BindList[A_Index]
				if (obj.Type = "m"){
					; Mouse button
					key := mouse_lookup[obj.Code]
				} else if (obj.Type = "k") {
					; Keyboard Key
					key := GetKeyName(Format("sc{:x}", obj.Code))
					if (StrLen(key) = 1){
						StringUpper, key, key
					}
				} else if (obj.Type = "j") {
					; Joystick button
					key := obj.joyid "Joy" obj.Code
				} else if (obj.Type = "h") {
					; Joystick hat
					key := obj.joyid "JoyPOV" pov_directions[obj.Code]
				}
				out .= key
			}
			return out
		}
	}
	
	; Debugging Renderer
	_RenderHotkey(hk){
		return hk.joyid hk.type hk.Code
	}
	
	; Debugging Renderer
	_RenderHotkeys(hk){
		out := ""
		Loop % hk.length(){
			if (A_Index > 1){
				out .= ","
			}
			out .= this._RenderHotkey(hk[A_Index])
		}
		return out
	}
	
	; Debugging Renderer
	_RenderNamedHotkeys(hk){
		out := ""
		ct := 1
		for name, obj in hk {
			if (ct > 1){
				out .= " | "
			}
			out .= name ": "
			out .= this._RenderHotkeys(obj)
			ct++
		}
		return out
	}
}