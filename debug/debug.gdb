set mem inaccessible-by-default off
set print pretty on

target remote localhost:3333

monitor reset halt

load

break main

continue
