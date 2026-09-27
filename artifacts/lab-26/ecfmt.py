import sys, json
d = json.load(sys.stdin)[0]["Status"]
db, use = d["dbSize"], d["dbSizeInUse"]
q = 17 * 1024 * 1024
print("%12s %10s %12s %10s" % ("dbSize", "in use", "not in use", "quota"))
print("%9.1f MB %7.1f MB %11.0f%% %7.1f MB" % (db/1e6, use/1e6, 100*(db-use)/db, q/1e6))
