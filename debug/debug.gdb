set mem inaccessible-by-default off
set print pretty on

target remote localhost:3333

monitor reset halt

load

break main

continue

dashboard -layout assembly source registers variables !memory !breakpoints !expressions !history !stack !threads
dashboard source -style height 11
dashboard assembly -style height 10
dashboard -style syntax_highlighting 'dracula'
dashboard register -style column-major True
dashboard assembly -style opcodes True
