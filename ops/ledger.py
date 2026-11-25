#!/usr/bin/env python3
"""SQLite ledger for revenue/expenses/actions. Usage:
  ledger.py revenue <amount> <source> <note>   (only VERIFIED, collected money)
  ledger.py expense <amount> <vendor> <note>
  ledger.py action <actor> <text>
  ledger.py summary
"""
import sqlite3, sys, os, datetime
DB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "state", "ledger.db")
def db():
    c = sqlite3.connect(DB)
    c.executescript("""
    CREATE TABLE IF NOT EXISTS money(id INTEGER PRIMARY KEY, ts TEXT, kind TEXT CHECK(kind IN('revenue','expense')), amount REAL, party TEXT, note TEXT);
    CREATE TABLE IF NOT EXISTS actions(id INTEGER PRIMARY KEY, ts TEXT, actor TEXT, text TEXT);""")
    return c
def now(): return datetime.datetime.now().isoformat(timespec="seconds")
def summary(c):
    r = c.execute("SELECT COALESCE(SUM(amount),0) FROM money WHERE kind='revenue'").fetchone()[0]
    e = c.execute("SELECT COALESCE(SUM(amount),0) FROM money WHERE kind='expense'").fetchone()[0]
    return r, e, r - e
if __name__ == "__main__":
    c = db(); a = sys.argv[1:]
    if not a or a[0] == "summary":
        r, e, n = summary(c); print(f"revenue={r:.2f} expenses={e:.2f} net={n:.2f}")
    elif a[0] in ("revenue", "expense"):
        c.execute("INSERT INTO money(ts,kind,amount,party,note) VALUES(?,?,?,?,?)", (now(), a[0], float(a[1]), a[2], " ".join(a[3:]))); c.commit(); print("ok")
    elif a[0] == "action":
        c.execute("INSERT INTO actions(ts,actor,text) VALUES(?,?,?)", (now(), a[1], " ".join(a[2:]))); c.commit(); print("ok")
    else: sys.exit(__doc__)
