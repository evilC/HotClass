; Proof of concept for replacement for HotClass
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
		this.HotClass.AddHotkey("hk1")
		this.HotClass.AddHotkey("hk2")
		Gui, Show, x0 y0
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
			OutputDebug % "ENTERED IDLE STATE"
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
				this._HotkeyCache := []
				for name, hk in this._Hotkeys {
					count++
					if (hk.length() > currentlength){
						currentlength := hk.length()
					}
				}
				hotkeys := this._Hotkeys.clone()
				while (Count){
					for name, hotkey in hotkeys {
						if (hotkey.length() = currentlength){
							;this._HotkeyCache.push({name: name, hotkey: hotkey})
							this._HotkeyCache.push(hotkey)
							hotkeys.Remove(name)
							Count--
						}
					}
				}
				OutputDebug % "Hotkey Type: " this._HotkeyCache[1].Value[1].Type
			}
			this.CInputDetector.EnableHooks()
			this._HeldKeys := []
			this._ActiveHotkeys := {}
			this._State := state
			OutputDebug % "ENTERED ACTIVE STATE" out
			return 1
		} else if (state == this.STATES.BIND ){
			; Enter BIND state.
			; args[1] = name of hotkey requesting state change
			this.CInputDetector.EnableHooks()
			if (args.length()){
				this._HeldKeys := []
				this._BindName := args[1]
				this._State := state
				OutputDebug % "ENTERED BINDING STATE FOR HOTKEY NAME: " args[1]
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
	Bug: Superfluous keys cause repeat of hotkey trigger
	Repro:
	Binding of A. Hold A (A Triggers), Hit B (A Triggers).
	A should not trigger again, it is already in the down state.
	
	Bug: Hotkey triggers when longer hotkey triggers
	Repro:
	Bindings of A and A+B. Hold B, then hit A. A triggers as well as A+B
	A should not trigger as it is "shorter" than A+B
	*/
	_ProcessInput(keyevent){
		static state := {0: "U", 1: "D"}
		; Update list of held keys, filter repeat events
		if (keyevent.event){
			; down event
			if (this._CompareHotkeys([keyevent], this._HeldKeys)){
				; repeat down event
				return 0
			}
			this._HeldKeys.push(keyevent)
		} else if (this._State != this.STATES.BIND) {
			; up event, but not in bind state
			pos := this._CompareHotkeys([keyevent], this._HeldKeys)
			if (pos){
				this._HeldKeys.Remove(pos)
			}
		}
		OutputDebug % "EVENT: " this._RenderHotkey(keyevent) " " state[keyevent.event]
		if (this._State == this.STATES.BIND){
			; Bind mode - block all input and build up a list of held keys
			if (keyevent.event = 1){
				if (keyevent.Type = "k" && keyevent.Code == 1){
					; Escape down - start timer to detect hold of escape to quit
					fn := this._FuncEscTimer
					SetTimer, % fn, -1000
				}
				; Down event - add pressed key to list of held keys
				;this._HeldKeys.push(keyevent)
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
				; As each key goes down, add it to the list of held keys
			
				; Check the bound hotkeys (longest to shortest) to check if there is a match
			
				; down event
				;this._HeldKeys.push(keyevent)
				;OutputDebug % "Adding to list of held keys: " keyevent.joyid keyevent.type keyevent.Code ". Now " this._HeldKeys.length() " held keys"

				; Check list of bound hotkeys for matches.
				Loop % this._HotkeyCache.length(){
					hk := A_Index
					; Supress Repeats - eg if A is bound, and A is held, do not fire A again if B is pressed.
					match := this._CompareHotkeys(this._HotkeyCache[hk].Value, this._HeldKeys)
					if (match){
						name := this._HotkeyCache[hk].name
						;SoundBeep, 1000, 150
						tt .= "`n" name " DOWN"
						;OutputDebug % "TRIGGER DOWN: " name
						;this._ActiveHotkeys[name] := 1
						this._ActiveHotkeys[name] := this._HotkeyCache[hk].Value
					}
				}
				; List must be indexed LONGEST (most keys in combination) to SHORTEST (least keys in combination) to ensure correct behavior
				; ie if CTRL+A and A are both bound, pressing CTRL+A should match CTRL+A before A.
			} else {
				;OutputDebug % "Release: comparing " keyevent.joyid keyevent.type keyevent.Code " against " this._HeldKeys.length() " held keys."
				;pos := this._CompareHotkeys([keyevent], this._HeldKeys)
				;if (pos){
				;	this._HeldKeys.Remove(pos)
				;	;OutputDebug % "Removing item " pos " from list: " keyevent.joyid keyevent.type keyevent.Code ". Now " this._HeldKeys.length() " held keys"
				;}
				;OutputDebug % "Checking " this._ActiveHotkeys.length() " active hotkeys..."
				for name, hotkey in this._ActiveHotkeys {
					match := 0
					;OutputDebug % "Checking if active hotkey " name " should be released"
					if (!this._CompareHotkeys(this._Hotkeys[name].Value, this._HeldKeys)){
						match := 1
					}
					if (match){
						;OutputDebug % "TRIGGER UP: " name
						this._ActiveHotkeys.Remove(name)
						;SoundBeep, 500, 150
						tt .= "`n" name " UP"
					}
				}
			}
			;out .=  " Now " this._HeldKeys.length() " keys"
		}
		OutputDebug % "HELD: " this._RenderHotkeys(this._HeldKeys) " - ACTIVE: " this._RenderNamedHotkeys(this._ActiveHotkeys)
		ToolTip % tt
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
	AddHotkey(name){
		; ToDo: Ensure unique name
		this._Hotkeys[name] := new this._Hotkey(this, name)
	}
	
	; Called on a Timer to detect timeout of Escape key in Bind Mode
	_EscTimer(){
		this._BindList := {}
		this.ChangeState(this.STATES.ACTIVE)
	}
	
	; Each hotkey is an instance of this class.
	; Handles the Gui control and routing of callbacks when the hotkey triggers
	class _Hotkey {
		__New(handler, name){
			this._handler := handler
			this.name := name
			this.BindList := {}
			this.Value := {}		; Holds the current binding
			
			Gui, Add, Edit, hwndhwnd w200 xm Disabled
			this.hEdit := hwnd
			Gui, Add, Button, hwndhwnd xp+210, Bind
			this.hBind := hwnd
			fn := this._handler.ChangeState.Bind(handler, this._handler.STATES.BIND, name)
			GuiControl +g, % hwnd, % fn
		}
		
		SetBinding(BindList){
			this.BindList := BindList
			GuiControl,, % this.hEdit, % this.BuildHumanReadable(BindList)
			this.Value := BindList
		}
		
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
		for name, obj in hk {
			ct := 1
			out .= name ": "
			if (ct > 1){
				out .= " | "
			}
			out .= this._RenderHotkeys(obj)
			ct++
		}
		return out
	}
}

;------------------------------------------------------------------------------------------------------------
; Sets up the hooks etc to watch for input
;------------------------------------------------------------------------------------------------------------
class CInputDetector {
	__New(callback){
		this._HooksEnabled := 0
		this._Callback := callback
		
		this.EnableHooks()
	}
	
	EnableHooks(){
		static WH_KEYBOARD_LL := 13, WH_MOUSE_LL := 14
		
		if (this._HooksEnabled){
			return 1
		}
		
		this._HooksEnabled := 1

		; Hook Input
		this._hHookKeybd := this._SetWindowsHookEx(WH_KEYBOARD_LL, RegisterCallback(this._ProcessKHook,"Fast",,&this))
		this._hHookMouse := this._SetWindowsHookEx(WH_MOUSE_LL, RegisterCallback(this._ProcessMHook,"Fast",,&this))
		
		this._JoysticksWithHats := []
		Loop 8 {
			joyid := A_Index
			joyinfo := GetKeyState(joyid "JoyInfo")
			if (joyinfo){
				; watch buttons
				Loop % 32 {
					fn := this._ProcessJHook.Bind(this, joyid, A_Index)
					hotkey, % joyid "Joy" A_Index, % fn
					hotkey, % joyid "Joy" A_Index, On
				}
				; Watch POVs
				if (instr(joyinfo, "p")){
					this._JoysticksWithHats.push(joyid)
				}
			}
		}
		fn := this._WatchJoystickPOV.Bind(this)
		SetTimer, % fn, 10
		return 1
	}
	
	DisableHooks(){
		if (!this._HooksEnabled){
			return 1
		}
		
		this._HooksEnabled := 0

		this._UnhookWindowsHookEx(this._hHookKeybd)
		this._UnhookWindowsHookEx(this._hHookMouse)

		this._JoysticksWithHats := []
		Loop 8 {
			joyid := A_Index
			joyinfo := GetKeyState(joyid "JoyInfo")
			if (joyinfo){
				; stop watching buttons
				Loop % 32 {
					hotkey, % joyid "Joy" A_Index, Off
				}
			}
		}
		fn := this._WatchJoystickPOV.Bind(this)
		SetTimer, % fn, Off
		return 1
	}
	
	; Process Joystick button down events
	_ProcessJHook(joyid, btn){
		;ToolTip % "Joy " joyid " Btn " btn
		this._Callback.({Type: "j", Code: btn, joyid: joyid, event: 1})
		fn := this._WaitForJoyUp.Bind(this, joyid, btn)
		SetTimer, % fn, -0
	}
	
	; Emulate up events for joystick buttons
	_WaitForJoyUp(joyid, btn){
		str := joyid "Joy" btn
		while (GetKeyState(str)){
			sleep 10
		}
		this._Callback.({Type: "j", Code: btn, joyid: joyid, event: 0})
	}
	
	; A constantly running timer to emulate "button events" for Joystick POV directions (eg 2JoyPOVU, 2JoyPOVD...)
	_WatchJoystickPOV(){
		static pov_states := [-1, -1, -1, -1, -1, -1, -1, -1]
		static pov_strings := ["1JoyPOV", "2JoyPOV", "3JoyPOV", "4JoyPOV", "5JoyPOV", "6JoyPOV" ,"7JoyPOV" ,"8JoyPOV"]
		static pov_direction_map := [[0,0,0,0], [1,0,0,0], [1,1,0,0] , [0,1,0,0], [0,1,1,0], [0,0,1,0], [0,0,1,1], [0,0,0,1], [1,0,0,1]]
		static pov_direction_states := [[0,0,0,0], [0,0,0,0], [0,0,0,0], [0,0,0,0], [0,0,0,0], [0,0,0,0], [0,0,0,0], [0,0,0,0]]
		Loop % this._JoysticksWithHats.length() {
			joyid := this._JoysticksWithHats[A_Index]
			pov := GetKeyState(pov_strings[joyid])
			if (pov = pov_states[joyid]){
				; do not process stick if nothing changed
				continue
			}
			if (pov = -1){
				state := 1
			} else {
				state := round(pov / 4500) + 2
			}
			
			Loop 4 {
				if (pov_direction_states[joyid, A_Index] != pov_direction_map[state, A_Index]){
					this._Callback.({Type: "h", Code: A_Index, joyid: joyid, event: pov_direction_map[state, A_Index]})
				}
			}
			pov_states[joyid] := pov
			pov_direction_states[joyid] := pov_direction_map[state]
		}
	}
	
	; Process Keyboard Hook messages
	_ProcessKHook(wParam, lParam){
		; KBDLLHOOKSTRUCT structure: https://msdn.microsoft.com/en-us/library/windows/desktop/ms644967%28v=vs.85%29.aspx
		; KeyboardProc function: https://msdn.microsoft.com/en-us/library/windows/desktop/ms644984(v=vs.85).aspx
		static WM_KEYDOWN := 0x100, WM_KEYUP := 0x101, WM_SYSKEYDOWN := 0x104
		Critical
		
		if (this<0){
			Return DllCall("CallNextHookEx", "Uint", Object(A_EventInfo)._hHookKeybd, "int", this, "Uint", wParam, "Uint", lParam)
		}
		this:=Object(A_EventInfo)
		
		vk := NumGet(lParam+0, "UInt")
		Extended := NumGet(lParam+0, 8, "UInt") & 1
		sc := (Extended<<8)|NumGet(lParam+0, 4, "UInt")
		sc := sc = 0x136 ? 0x36 : sc
        ;key:=GetKeyName(Format("vk{1:x}sc{2:x}", vk,sc))
		event := wParam = WM_SYSKEYDOWN || wParam = WM_KEYDOWN
		
        if ( sc != 541 ){		; ignore non L/R Control. This key never happens except eg with RALT
			block := this._Callback.({ Type: "k", Code: sc, event: event})
			if (block){
				return 1
			}
		}
		Return DllCall("CallNextHookEx", "Uint", Object(A_EventInfo)._hHookKeybd, "int", this, "Uint", wParam, "Uint", lParam)

	}
	
	; Process Mouse Hook messages
	_ProcessMHook(wParam, lParam){
		; MSLLHOOKSTRUCT structure: https://msdn.microsoft.com/en-us/library/windows/desktop/ms644970(v=vs.85).aspx
		static WM_LBUTTONDOWN := 0x0201, WM_LBUTTONUP := 0x0202 , WM_RBUTTONDOWN := 0x0204, WM_RBUTTONUP := 0x0205, WM_MBUTTONDOWN := 0x0207, WM_MBUTTONUP := 0x0208, WM_MOUSEHWHEEL := 0x20E, WM_MOUSEWHEEL := 0x020A, WM_XBUTTONDOWN := 0x020B, WM_XBUTTONUP := 0x020C
		static button_map := {0x0201: 1, 0x0202: 1 , 0x0204: 2, 0x0205: 2, 0x0207: 3, 0x208: 3}
		static button_event := {0x0201: 1, 0x0202: 0 , 0x0204: 1, 0x0205: 0, 0x0207: 1, 0x208: 0}
		Critical
		
		if (this<0 || wParam = 0x200){
			Return DllCall("CallNextHookEx", "Uint", Object(A_EventInfo)._hHookMouse, "int", this, "Uint", wParam, "Uint", lParam)
		}
		this:=Object(A_EventInfo)
		out := "Mouse: " wParam " "
		
		keyname := ""
		event := 0
		button := 0
		
		;if (IsObject(this._MouseLookup[wParam])){
		if (ObjHasKey(button_map, wParam)){
			; L / R / M  buttons
			button := button_map[wParam]
			event := button_event[wParam]
		} else {
			; Wheel / XButtons
			; Find HiWord of mouseData from Struct
			mouseData := NumGet(lParam+0, 10, "Short")
			
			if (wParam = WM_MOUSEHWHEEL || wParam = WM_MOUSEWHEEL){
				; Mouse Wheel - mouseData indicate direction (up/down)
				event := 1	; wheel has no up event, only down
				if (wParam = WM_MOUSEWHEEL){
					if (mouseData > 1){
						button := 6
					} else {
						button := 7
					}
				} else {
					if (mouseData < 1){
						button := 8
					} else {
						button := 9
					}
				}
			} else if (wParam = WM_XBUTTONDOWN || wParam = WM_XBUTTONUP){
				; X Buttons - mouseData indicates Xbutton 1 or Xbutton2
				if (wParam = WM_XBUTTONDOWN){
					event := 1
				} else {
					event := 0
				}
				button := 3 + mouseData
			}
		}

		block := this._Callback.({Type: "m", Code: button, event: event})
		if (wParam = WM_MOUSEHWHEEL || wParam = WM_MOUSEWHEEL){
			; Mouse wheel does not generate up event, simulate it.
			this._Callback.({Type: "m", Code: button, event: 0})
		}
		if (block){
			return 1
		}
		Return DllCall("CallNextHookEx", "Uint", Object(A_EventInfo)._hHookMouse, "int", this, "Uint", wParam, "Uint", lParam)
	}
	
	; ============= HOOK HANDLING =================
	_SetWindowsHookEx(idHook, pfn){
		Return DllCall("SetWindowsHookEx", "Ptr", idHook, "Ptr", pfn, "Uint", DllCall("GetModuleHandle", "Uint", 0, "Ptr"), "Uint", 0, "Ptr")
	}
	
	_UnhookWindowsHookEx(idHook){
		Return DllCall("UnhookWindowsHookEx", "Ptr", idHook)
	}

}