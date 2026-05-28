#!/usr/bin/env python3
import os
import signal
import time
import tkinter as tk
from tkinter import ttk, messagebox

import psutil


BG = "#0b0d10"
PANEL = "#15181d"
PANEL_ALT = "#1a1f27"
GOLD = "#d4af37"
TEXT = "#f2e7c9"
MUTED = "#c9b784"
RED = "#c46252"
GREEN = "#8c9f61"


class ChessTaskManager:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("Chess Task Manager")
        self.root.geometry("1040x640")
        self.root.minsize(900, 520)
        self.root.configure(bg=BG)

        # Helps compositors match this app by class/title.
        try:
            self.root.tk.call("wm", "class", self.root._w, "chess-task-manager")
        except tk.TclError:
            pass

        self.sort_column = "cpu"
        self.sort_reverse = True
        self.process_cache = {}

        self._build_style()
        self._build_ui()
        self._bind_events()
        self.refresh_all()

    def _build_style(self):
        style = ttk.Style(self.root)
        style.theme_use("clam")

        style.configure("Root.TFrame", background=BG)
        style.configure("Panel.TFrame", background=PANEL)
        style.configure("PanelAlt.TFrame", background=PANEL_ALT)

        style.configure(
            "Title.TLabel",
            background=BG,
            foreground=GOLD,
            font=("JetBrainsMono Nerd Font", 18, "bold"),
        )
        style.configure(
            "Sub.TLabel",
            background=PANEL,
            foreground=MUTED,
            font=("JetBrainsMono Nerd Font", 10),
        )
        style.configure(
            "Value.TLabel",
            background=PANEL,
            foreground=TEXT,
            font=("JetBrainsMono Nerd Font", 11, "bold"),
        )

        style.configure(
            "Chess.Treeview",
            background=PANEL,
            foreground=TEXT,
            fieldbackground=PANEL,
            rowheight=28,
            borderwidth=0,
            font=("JetBrainsMono Nerd Font", 10),
        )
        style.map(
            "Chess.Treeview",
            background=[("selected", "#3a3529")],
            foreground=[("selected", "#f7ecd0")],
        )
        style.configure(
            "Chess.Treeview.Heading",
            background=PANEL_ALT,
            foreground=GOLD,
            borderwidth=0,
            relief="flat",
            font=("JetBrainsMono Nerd Font", 10, "bold"),
        )

        style.configure(
            "Chess.TButton",
            background=PANEL_ALT,
            foreground=TEXT,
            padding=8,
            borderwidth=1,
            relief="solid",
            font=("JetBrainsMono Nerd Font", 10, "bold"),
        )
        style.map(
            "Chess.TButton",
            background=[("active", "#2a303a")],
            foreground=[("active", "#f7ecd0")],
        )

        style.configure(
            "Danger.TButton",
            background="#3a1f1f",
            foreground="#ffded8",
            padding=8,
            borderwidth=1,
            relief="solid",
            font=("JetBrainsMono Nerd Font", 10, "bold"),
        )
        style.map("Danger.TButton", background=[("active", "#4a2727")])

    def _build_ui(self):
        outer = ttk.Frame(self.root, style="Root.TFrame", padding=14)
        outer.pack(fill="both", expand=True)

        title = ttk.Label(
            outer,
            text="♔ Chess Task Manager",
            style="Title.TLabel",
        )
        title.pack(anchor="w", pady=(0, 10))

        stats = ttk.Frame(outer, style="Panel.TFrame", padding=12)
        stats.pack(fill="x")

        self.cpu_var = tk.StringVar(value="0.0%")
        self.mem_var = tk.StringVar(value="0.0%")
        self.swap_var = tk.StringVar(value="0.0%")
        self.proc_count_var = tk.StringVar(value="0")

        self._add_stat(stats, 0, "♞ CPU", self.cpu_var)
        self._add_stat(stats, 1, "♜ Memory", self.mem_var)
        self._add_stat(stats, 2, "♝ Swap", self.swap_var)
        self._add_stat(stats, 3, "♛ Processes", self.proc_count_var)

        tools = ttk.Frame(outer, style="PanelAlt.TFrame", padding=10)
        tools.pack(fill="x", pady=(10, 10))

        ttk.Label(tools, text="Filter", style="Sub.TLabel").pack(side="left", padx=(0, 8))
        self.filter_var = tk.StringVar()
        self.filter_entry = tk.Entry(
            tools,
            textvariable=self.filter_var,
            bg="#1f232b",
            fg=TEXT,
            insertbackground=GOLD,
            relief="flat",
            font=("JetBrainsMono Nerd Font", 10),
            width=36,
        )
        self.filter_entry.pack(side="left", padx=(0, 10), ipady=6)

        ttk.Button(tools, text="Refresh", style="Chess.TButton", command=self.refresh_all).pack(side="left", padx=4)
        ttk.Button(tools, text="End Task", style="Danger.TButton", command=self.end_selected_task).pack(side="left", padx=4)

        self.status_var = tk.StringVar(value="Ready")
        ttk.Label(tools, textvariable=self.status_var, style="Sub.TLabel").pack(side="right")

        table_wrap = ttk.Frame(outer, style="Panel.TFrame", padding=8)
        table_wrap.pack(fill="both", expand=True)

        columns = ("name", "pid", "cpu", "mem", "status", "user")
        self.tree = ttk.Treeview(table_wrap, columns=columns, show="headings", style="Chess.Treeview")

        labels = {
            "name": "Process",
            "pid": "PID",
            "cpu": "CPU %",
            "mem": "MEM %",
            "status": "State",
            "user": "User",
        }
        widths = {"name": 380, "pid": 80, "cpu": 90, "mem": 90, "status": 120, "user": 160}

        for col in columns:
            self.tree.heading(col, text=labels[col], command=lambda c=col: self.sort_by(c))
            anchor = "w" if col in ("name", "status", "user") else "center"
            self.tree.column(col, width=widths[col], anchor=anchor, stretch=(col == "name"))

        y_scroll = ttk.Scrollbar(table_wrap, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=y_scroll.set)
        self.tree.pack(side="left", fill="both", expand=True)
        y_scroll.pack(side="right", fill="y")

    def _add_stat(self, parent, idx, label, value_var):
        card = ttk.Frame(parent, style="PanelAlt.TFrame", padding=10)
        card.grid(row=0, column=idx, sticky="nsew", padx=6)
        parent.columnconfigure(idx, weight=1)

        ttk.Label(card, text=label, style="Sub.TLabel").pack(anchor="w")
        ttk.Label(card, textvariable=value_var, style="Value.TLabel").pack(anchor="w", pady=(6, 0))

    def _bind_events(self):
        self.filter_var.trace_add("write", lambda *_: self.refresh_process_table())
        self.tree.bind("<Delete>", lambda _e: self.end_selected_task())
        self.root.bind("<Control-r>", lambda _e: self.refresh_all())
        self.root.bind("<Escape>", lambda _e: self.root.destroy())

    def sort_by(self, column):
        if self.sort_column == column:
            self.sort_reverse = not self.sort_reverse
        else:
            self.sort_column = column
            self.sort_reverse = column in {"cpu", "mem", "pid"}
        self.refresh_process_table()

    def refresh_stats(self):
        cpu = psutil.cpu_percent(interval=None)
        mem = psutil.virtual_memory()
        swp = psutil.swap_memory()

        self.cpu_var.set(f"{cpu:.1f}%")
        self.mem_var.set(f"{mem.percent:.1f}%")
        self.swap_var.set(f"{swp.percent:.1f}%")

    def _collect_processes(self):
        rows = []
        for proc in psutil.process_iter(["pid", "name", "username", "memory_percent", "status"]):
            try:
                info = proc.info
                pid = info.get("pid", 0)
                if pid not in self.process_cache:
                    self.process_cache[pid] = proc.cpu_percent(interval=None)
                cpu = proc.cpu_percent(interval=None)
                mem = info.get("memory_percent", 0.0) or 0.0
                rows.append(
                    {
                        "name": info.get("name") or "(unknown)",
                        "pid": pid,
                        "cpu": float(cpu),
                        "mem": float(mem),
                        "status": info.get("status") or "-",
                        "user": (info.get("username") or "-").split("/")[-1],
                    }
                )
            except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                continue
        self.proc_count_var.set(str(len(rows)))
        return rows

    def refresh_process_table(self):
        query = self.filter_var.get().strip().lower()
        rows = self._collect_processes()

        if query:
            rows = [
                r
                for r in rows
                if query in r["name"].lower()
                or query in str(r["pid"])
                or query in r["user"].lower()
            ]

        rows.sort(key=lambda r: r[self.sort_column], reverse=self.sort_reverse)

        for item in self.tree.get_children():
            self.tree.delete(item)

        for r in rows:
            cpu = f"{r['cpu']:.1f}"
            mem = f"{r['mem']:.1f}"
            self.tree.insert("", "end", values=(r["name"], r["pid"], cpu, mem, r["status"], r["user"]))

        self.status_var.set(f"Updated {time.strftime('%H:%M:%S')}  |  {len(rows)} shown")

    def end_selected_task(self):
        selected = self.tree.selection()
        if not selected:
            messagebox.showinfo("Chess Task Manager", "Select a process first.")
            return

        item = self.tree.item(selected[0])
        vals = item.get("values", [])
        if len(vals) < 2:
            return

        name = str(vals[0])
        pid = int(vals[1])

        if pid == os.getpid():
            messagebox.showwarning("Chess Task Manager", "Cannot end Chess Task Manager itself.")
            return

        ok = messagebox.askyesno("End Task", f"End process {name} (PID {pid})?")
        if not ok:
            return

        try:
            proc = psutil.Process(pid)
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except psutil.TimeoutExpired:
                proc.kill()
            self.status_var.set(f"Ended {name} ({pid})")
        except (psutil.NoSuchProcess, psutil.ZombieProcess):
            self.status_var.set("Process already exited")
        except psutil.AccessDenied:
            messagebox.showerror("Permission denied", "You do not have permission to end that process.")

        self.refresh_all()

    def refresh_all(self):
        self.refresh_stats()
        self.refresh_process_table()
        self.root.after(2000, self.refresh_all)

    def run(self):
        self.root.mainloop()


if __name__ == "__main__":
    ChessTaskManager().run()
