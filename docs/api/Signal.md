---
permalink: api/Signal
title: Signal
---

## Methods

### connect()

Connects the given function to a Signal and will be called whenever the Signal is fired.

- #### Type
	
	```lua
	function Signal:connect((...any): ()): ()
	```

---

### disconnect()

Disconnects the given function from a Signal stopping them from being called whenever the signal is fired.

- #### Type
  
	```lua
	function Signal:disconnect((...any): ()): ()
	```

