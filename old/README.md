# HotClass
A class that enhances AutoHotkey's input detection (ie hotkeys) capabilities

####Limitations of vanilla AHK that this class seeks to overcome:
* Maximum of 100 hotkeys  
This is not normally a problem, but in certain cases can be.
* Cannot fully remove hotkeys  
Only really an issue with the 1000 limit.
* Only down events supported for joystick buttons  
No up events for buttons, `GetKeyState()` must normally be used.
* No event-based mechanism for Joystick axis change.  
Again, endless `GetKeyState` loops must be used.
* No way of easily providing a "Bind" box that facilitates visually choosing of a hotkey, *that supports all input methods*.  
The `Hotkey` Gui item only supports certain keyboard keys.  
The `Input` command has limited support (No Joystick) and requires hacky `#if` statements to fully support some keys and combos.  

####How it works
Keyboard / mouse input is read via `SetWindowsHookEx` callbacks.  Blocking of Keyboard / mouse input can be achieved through this call.
