package main

import nc "netcode"
import "core:fmt"
import "core:strings"

// Step 3 application handshake. The transport's low-level Connect/Accept is
// deliberately unchanged: an accepted socket gets no World/player/replica
// privileges until the reliable Hello has passed validation.




// Returns empty for a compatible client; caller additionally validates HOST
// ownership. No string from an untrusted packet is used as a format string.





// Returns true when consumed as an application-level control message.
