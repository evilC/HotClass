; Proof of concept for replacement for HotClass
#include CInputDetector.ahk

OutputDebug, DBGVIEWCLEAR
;============================================================================================================
; Example user script
;============================================================================================================
#SingleInstance force
mc := new MyClass()
return

GuiClose:
	ExitApp

class MyClass {
	__New(){
		Gui, New, hwndhwnd
		this.hwnd := hwnd
		this.HotClass := new HotClass(hwnd)
		this.HotClass.AddHotkey("hk1", this.hkPressed.Bind(this, "hk1"), "w280 xm")
		Gui, % this.hwnd ":Add", Checkbox, Disabled hwndhwnd1 xp+290 yp+4
		this.HotClass.AddHotkey("hk2", this.hkPressed.Bind(this, "hk2"), "w280 xm")
		Gui, % this.hwnd ":Add", Checkbox, Disabled hwndhwnd2 xp+290 yp+4
		this.HotClass.AddHotkey("hk3", this.hkPressed.Bind(this, "hk3"), "w280 xm")
		Gui, % this.hwnd ":Add", Checkbox, Disabled hwndhwnd3 xp+290 yp+4
		this.hStateChecks := {hk1: hwnd1, hk2: hwnd2, hk3: hwnd3}
		Gui, % this.hwnd ":Show", x0 y0
	}
	
	; called when hk1 goes up or down.
	hkPressed(hk, event){
		GuiControl,,% this.hStateChecks[hk], % event
	}
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
	__New(hwnd, options := 0){
		this.STATES := {IDLE: 0, ACTIVE: 1, BIND: 2}		; State Name constants, for human readibility
		this._HotkeyCache := []								; Length ordered array of keysets
		this._HotkeyStates := {}							; Name indexed list of boolean state values
		this._KeyCache := []								; Associative array of key uids
		this._ActiveHotkeys := []							; Hotkeys currently in down state - for quick ObjHasKey matching
		this._hwnd := hwnd
		this._FuncEscTimer := this._EscTimer.Bind(this)
		
		Gui, New, hwndhwnd -Border
		this._hDialog := hwnd
		Gui, % this._hDialog ":Add", Text, Center, Bind Mode`n`nPress any combination of keys to bind.`n`nBinding finished on an up event.
		;Gui, % this._hDialog ":Show"

		; Set default options
		if (!IsObject(options) || options == 0){
			options := {StartActive: 1}
		}
		
		; Initialize the Library that detects input.
		this.CInputDetector := new CInputDetector(this._ProcessInput.Bind(this))

		; Initialize state
		if (options.StartActive){
			this.ChangeState(this.STATES.ACTIVE)
		} else {
			this.ChangeState(this.STATES.IDLE)
		}
		
	}
	
	; Handles all state transitions
	; Returns 1 if we transitioned to the specified state, 0 if not
	ChangeState(state, args*){
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
			this.CInputDetector.DisableHooks()
			this._State := state
			this._BindName := ""					; The name of the hotkey that is being bound
			this._Hotkeys := {}						; a name indexed array of hotkey objects
			this._HeldKeys := []					; The keys that are currently held
			this._ActiveHotkeys := {}				; Hotkeys which are currently in a down state
			;OutputDebug % "ENTERED IDLE STATE"
			return 1
		} else if (state == this.STATES.ACTIVE ){
			; Enter ACTIVE state, no args required
			out := ""
			if (this._State == this.STATES.BIND){
				; Transition from BIND state
				Gui, % this._hDialog ":Hide"	; Hide Bind Mode dialog
				; Build size-ordered list of hotkeys
				out := ", ADDED " this._HeldKeys.length() " key combo hotkey"
				this._BuildHotkeyCache()
			}
			this.CInputDetector.EnableHooks()
			this._HeldKeys := []
			this._ActiveHotkeys := {}
			this._State := state
			;OutputDebug % "ENTERED ACTIVE STATE" out
			return 1
		} else if (state == this.STATES.BIND ){
			; Enter BIND state.
			Gui, % this._hDialog ":Show"	; Show Bind Mode dialog
			; args[1] = name of hotkey requesting state change
			this.CInputDetector.EnableHooks()
			if (args.length()){
				this._HeldKeys := []
				this._BindName := args[1]
				this._State := state
				;OutputDebug % "ENTERED BINDING STATE FOR HOTKEY NAME: " args[1]
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
				this.ChangeState(this.STATES.ACTIVE)

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
	
	; User command to add a new hotkey
	AddHotkey(name, callback, aParams*){
		; ToDo: Ensure unique name
		this._Hotkeys[name] := new this._Hotkey(this, name, callback, aParams*)
	}
	
	; Called on a Timer to detect timeout of Escape key in Bind Mode
	_EscTimer(){
		this._BindList := {}
		this.ChangeState(this.STATES.ACTIVE)
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
			
			Gui, % this._handler._hwnd ":Add", ComboBox, % "hwndhwnd AltSubmit " aParams[1], % this._MenuText
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
				this._handler.ChangeState(this._handler.STATES.BIND, this.Name)
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