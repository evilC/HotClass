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
		this.HotClass := new HotClass()
		this.HotClass.AddHotkey("hk1", this.hk1Pressed.Bind(this), "w300 xm")
		this.HotClass.AddHotkey("hk2", this.hk2Pressed.Bind(this), "w300 xm")
		Gui, Show, x0 y0
	}
	
	; called when hk1 goes up or down.
	hk1Pressed(event){
		ToolTip % "HK1 " event, 0,200, 1
	}
	
	; called when hk2 goes up or down.
	hk2Pressed(event){
		ToolTip % "HK2 " event, 0,220, 2
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
	__New(options := 0){
		this.STATES := {IDLE: 0, ACTIVE: 1, BIND: 2}		; State Name constants, for human readibility
		this._HotkeyCache := []
		this._ActiveHotkeys := []
		this._FuncEscTimer := this._EscTimer.Bind(this)

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
			this._ActiveHotkeys := []				; Hotkeys which are currently in a down state
			;OutputDebug % "ENTERED IDLE STATE"
			return 1
		} else if (state == this.STATES.ACTIVE ){
			; Enter ACTIVE state, no args required
			out := ""
			if (this._State == this.STATES.BIND){
				; Transition from BIND state
				; Build size-ordered list of hotkeys
				out := ", ADDED " this._HeldKeys.length() " key combo hotkey"
				currentlength := 0
				count := 0
				
				; find longest hotkey length
				for name, hk in this._Hotkeys {
					count++
					if (hk.Value.length() > currentlength){
						currentlength := hk.Value.length()
					}
				}
				this._HotkeyCache := []
				; Sort backwards
				while (Count){
					for name, hotkey in this._Hotkeys {
						if (hotkey.Value.length() = currentlength){
							this._HotkeyCache.push(hotkey)
							Count--
						}
					}
					currentlength--
				}
				;OutputDebug % "Hotkey Type: " this._HotkeyCache[1].Value[1].Type
			}
			this.CInputDetector.EnableHooks()
			this._HeldKeys := []
			this._ActiveHotkeys := {}
			this._State := state
			;OutputDebug % "ENTERED ACTIVE STATE" out
			return 1
		} else if (state == this.STATES.BIND ){
			; Enter BIND state.
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

	; All Input Events flow through here - ie an input device changes state
	; Encompasses keyboard keys, mouse buttons / wheel and joystick buttons or hat directions
	
	/*
	ToDo: 
	Bug: Hotkey triggers when longer hotkey triggers
	Repro:
	Bindings of A and A+B. Hold B, then hit A. A triggers as well as A+B
	A should not trigger as it is "shorter" than A+B
	*/
	_ProcessInput(keyevent){
		static state := {0: "U", 1: "D"}
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
			tt := ""
			if (keyevent.event = 1){
				; Down event in ACTIVE state
				; Check list of bound hotkeys for matches.
				; List must be indexed LONGEST (most keys in combination) to SHORTEST (least keys in combination) to ensure correct behavior
				; ie if CTRL+A and A are both bound, pressing CTRL+A should match CTRL+A before A.
				Loop % this._HotkeyCache.length(){
					hk := A_Index
					name := this._HotkeyCache[hk].name
					; Supress Repeats - eg if A is bound, and A is held, do not fire A again if B is pressed.
					if ((!ObjHasKey(this._ActiveHotkeys, name)) && this._CompareHotkeys(this._HotkeyCache[hk].Value, this._HeldKeys)){
						OutputDebug % "TRIGGER DOWN: " name
						;SoundBeep, 1000, 150
						tt .= "`n" name " DOWN"
						this._ActiveHotkeys[name] := this._HotkeyCache[hk].Value
						this._HotkeyCache[hk]._Callback.(1)
						break
					}
				}
			} else {
				; Up event in ACTIVE state - check active hotkeys for release
				newhotkeys := this._ActiveHotkeys.clone()
				for name, hotkey in this._ActiveHotkeys {
					if (!this._CompareHotkeys(this._ActiveHotkeys[name], this._HeldKeys)){
						OutputDebug % "TRIGGER UP: " name
						newhotkeys.Remove(name)
						;SoundBeep, 500, 150
						tt .= "`n" name " UP"
						this._Hotkeys[name]._Callback.(0)
					}
				}
				this._ActiveHotkeys := newhotkeys
			}
			;out .=  " Now " this._HeldKeys.length() " keys"
		}
		OutputDebug % "HELD: " this._RenderHotkeys(this._HeldKeys) " - ACTIVE: " this._RenderNamedHotkeys(this._ActiveHotkeys)
		;ToolTip % tt
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
				n := needle[ni].joyid needle[ni].type needle[ni].Code
				h := haystack[hi].joyid haystack[hi].type haystack[hi].Code
				;out := n " = " h " ? "
				if (n = h){
					;OutputDebug % out "YES"
					count++
					if (Count = length){
						break
					}
				} else {
					;OutputDebug % out "NO"
				}
			}
		}
		
		if (Count = length){
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
			this.Value := {}		; Holds the current binding
			
			Gui, % "Add", ComboBox, % "hwndhwnd AltSubmit " aParams[1], % this._MenuText
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