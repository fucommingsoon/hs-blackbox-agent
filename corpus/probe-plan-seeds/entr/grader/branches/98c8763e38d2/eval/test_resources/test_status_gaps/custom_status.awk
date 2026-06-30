# Custom status script
/^exit/ { print "CUSTOM:", $3, "exited with", $2; }
/^signal/ { print "CUSTOM:", $3, "killed by", $2; }
