from __future__ import annotations

import queue
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

from PIL import Image, ImageTk

from mysequator.engine import StackOptions, stack_images
from mysequator.engine.io import SUPPORTED_EXTENSIONS, load_image, save_image


class MySequatorApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("MySequator")
        self.geometry("1040x680")
        self.minsize(900, 560)

        self.image_paths: list[Path] = []
        self.dark_paths: list[Path] = []
        self.flat_paths: list[Path] = []
        self.output_path = tk.StringVar(value=str(Path.cwd() / "stacked.tiff"))
        self.mode = tk.StringVar(value="sigma")
        self.auto_brightness = tk.BooleanVar(value=True)
        self.hdr = tk.BooleanVar(value=False)
        self.reduce_lp = tk.BooleanVar(value=False)
        self.enhance_stars = tk.BooleanVar(value=False)
        self.status = tk.StringVar(value="Add star images to begin.")
        self.progress = tk.DoubleVar(value=0)
        self.preview_image: ImageTk.PhotoImage | None = None
        self.messages: queue.Queue[tuple[str, object]] = queue.Queue()

        self._build_ui()
        self.after(100, self._poll_messages)

    def _build_ui(self) -> None:
        root = ttk.Frame(self, padding=12)
        root.pack(fill=tk.BOTH, expand=True)
        root.columnconfigure(0, weight=0)
        root.columnconfigure(1, weight=1)
        root.rowconfigure(0, weight=1)

        sidebar = ttk.Frame(root, width=320)
        sidebar.grid(row=0, column=0, sticky="nsw", padx=(0, 12))
        sidebar.grid_propagate(False)
        sidebar.columnconfigure(0, weight=1)
        sidebar.rowconfigure(2, weight=1)

        ttk.Label(sidebar, text="Star Images").grid(row=0, column=0, sticky="w")
        buttons = ttk.Frame(sidebar)
        buttons.grid(row=1, column=0, sticky="ew", pady=(6, 8))
        buttons.columnconfigure((0, 1, 2), weight=1)
        ttk.Button(buttons, text="Add", command=self._add_images).grid(row=0, column=0, sticky="ew", padx=(0, 4))
        ttk.Button(buttons, text="Remove", command=self._remove_selected).grid(row=0, column=1, sticky="ew", padx=4)
        ttk.Button(buttons, text="Clear", command=self._clear_images).grid(row=0, column=2, sticky="ew", padx=(4, 0))

        self.image_list = tk.Listbox(sidebar, height=12, activestyle="dotbox")
        self.image_list.grid(row=2, column=0, sticky="nsew")
        self.image_list.bind("<<ListboxSelect>>", lambda _event: self._show_selected_preview())

        calibration = ttk.LabelFrame(sidebar, text="Calibration", padding=8)
        calibration.grid(row=3, column=0, sticky="ew", pady=(10, 0))
        calibration.columnconfigure((0, 1), weight=1)
        ttk.Button(calibration, text="Dark Frames", command=self._choose_darks).grid(row=0, column=0, sticky="ew", padx=(0, 4))
        ttk.Button(calibration, text="Flat Frames", command=self._choose_flats).grid(row=0, column=1, sticky="ew", padx=(4, 0))
        self.calibration_label = ttk.Label(calibration, text="0 dark, 0 flat")
        self.calibration_label.grid(row=1, column=0, columnspan=2, sticky="w", pady=(6, 0))

        output = ttk.LabelFrame(sidebar, text="Output", padding=8)
        output.grid(row=4, column=0, sticky="ew", pady=(10, 0))
        output.columnconfigure(0, weight=1)
        ttk.Entry(output, textvariable=self.output_path).grid(row=0, column=0, sticky="ew", padx=(0, 6))
        ttk.Button(output, text="Choose", command=self._choose_output).grid(row=0, column=1)

        options = ttk.LabelFrame(sidebar, text="Stack Options", padding=8)
        options.grid(row=5, column=0, sticky="ew", pady=(10, 0))
        options.columnconfigure(1, weight=1)
        ttk.Label(options, text="Mode").grid(row=0, column=0, sticky="w")
        ttk.Combobox(options, textvariable=self.mode, values=("sigma", "mean", "trails"), state="readonly", width=10).grid(
            row=0, column=1, sticky="ew"
        )
        ttk.Checkbutton(options, text="Auto brightness", variable=self.auto_brightness).grid(row=1, column=0, columnspan=2, sticky="w")
        ttk.Checkbutton(options, text="HDR stretch", variable=self.hdr).grid(row=2, column=0, columnspan=2, sticky="w")
        ttk.Checkbutton(options, text="Reduce light pollution", variable=self.reduce_lp).grid(
            row=3, column=0, columnspan=2, sticky="w"
        )
        ttk.Checkbutton(options, text="Enhance stars", variable=self.enhance_stars).grid(row=4, column=0, columnspan=2, sticky="w")

        ttk.Button(sidebar, text="Stack Images", command=self._start_stack).grid(row=6, column=0, sticky="ew", pady=(12, 0))
        ttk.Progressbar(sidebar, variable=self.progress, maximum=1.0).grid(row=7, column=0, sticky="ew", pady=(8, 0))
        ttk.Label(sidebar, textvariable=self.status, wraplength=300).grid(row=8, column=0, sticky="ew", pady=(6, 0))

        preview = ttk.Frame(root)
        preview.grid(row=0, column=1, sticky="nsew")
        preview.rowconfigure(0, weight=1)
        preview.columnconfigure(0, weight=1)
        self.preview_label = ttk.Label(preview, text="Preview", anchor="center")
        self.preview_label.grid(row=0, column=0, sticky="nsew")

    def _filetypes(self) -> list[tuple[str, str]]:
        patterns = " ".join(f"*{ext}" for ext in sorted(SUPPORTED_EXTENSIONS))
        return [("Images", patterns), ("All files", "*.*")]

    def _add_images(self) -> None:
        files = filedialog.askopenfilenames(title="Choose star images", filetypes=self._filetypes())
        for file in files:
            path = Path(file)
            if path not in self.image_paths:
                self.image_paths.append(path)
                self.image_list.insert(tk.END, path.name)
        if self.image_paths:
            self.image_list.selection_clear(0, tk.END)
            self.image_list.selection_set(len(self.image_paths) - 1)
            self._show_selected_preview()
            self.status.set(f"{len(self.image_paths)} star images ready.")

    def _remove_selected(self) -> None:
        selected = list(self.image_list.curselection())
        for index in reversed(selected):
            del self.image_paths[index]
            self.image_list.delete(index)
        self.status.set(f"{len(self.image_paths)} star images ready.")

    def _clear_images(self) -> None:
        self.image_paths.clear()
        self.image_list.delete(0, tk.END)
        self.preview_label.configure(image="", text="Preview")
        self.preview_image = None
        self.status.set("Add star images to begin.")

    def _choose_darks(self) -> None:
        self.dark_paths = [Path(file) for file in filedialog.askopenfilenames(title="Choose dark frames", filetypes=self._filetypes())]
        self._update_calibration_label()

    def _choose_flats(self) -> None:
        self.flat_paths = [Path(file) for file in filedialog.askopenfilenames(title="Choose flat frames", filetypes=self._filetypes())]
        self._update_calibration_label()

    def _update_calibration_label(self) -> None:
        self.calibration_label.configure(text=f"{len(self.dark_paths)} dark, {len(self.flat_paths)} flat")

    def _choose_output(self) -> None:
        file = filedialog.asksaveasfilename(
            title="Choose output file",
            defaultextension=".tiff",
            filetypes=[("TIFF", "*.tiff *.tif"), ("JPEG", "*.jpg"), ("PNG", "*.png")],
        )
        if file:
            self.output_path.set(file)

    def _show_selected_preview(self) -> None:
        selection = self.image_list.curselection()
        if not selection:
            return
        path = self.image_paths[int(selection[0])]
        try:
            array = load_image(path)
            image = Image.fromarray((array.clip(0, 1) * 255).astype("uint8"), mode="RGB")
            image.thumbnail((680, 620), Image.Resampling.LANCZOS)
            self.preview_image = ImageTk.PhotoImage(image)
            self.preview_label.configure(image=self.preview_image, text="")
        except Exception as exc:
            messagebox.showerror("Preview failed", str(exc))

    def _start_stack(self) -> None:
        if not self.image_paths:
            messagebox.showwarning("No images", "Add at least one star image.")
            return
        output = Path(self.output_path.get()).expanduser()
        options = StackOptions(
            mode=self.mode.get(),
            dark_paths=self.dark_paths,
            flat_paths=self.flat_paths,
            auto_brightness=self.auto_brightness.get(),
            hdr=self.hdr.get(),
            reduce_light_pollution=self.reduce_lp.get(),
            enhance_stars=self.enhance_stars.get(),
        )
        self.progress.set(0)
        self.status.set("Starting stack...")
        thread = threading.Thread(target=self._run_stack, args=(list(self.image_paths), output, options), daemon=True)
        thread.start()

    def _run_stack(self, paths: list[Path], output: Path, options: StackOptions) -> None:
        try:
            def progress(message: str, fraction: float) -> None:
                self.messages.put(("progress", (message, fraction)))

            result = stack_images(paths, options=options, progress=progress)
            save_image(result.image, output)
            self.messages.put(("done", (output, result.alignments)))
        except Exception as exc:
            self.messages.put(("error", str(exc)))

    def _poll_messages(self) -> None:
        while True:
            try:
                kind, payload = self.messages.get_nowait()
            except queue.Empty:
                break

            if kind == "progress":
                message, fraction = payload
                self.progress.set(float(fraction))
                self.status.set(str(message))
            elif kind == "done":
                output, alignments = payload
                self.progress.set(1.0)
                self.status.set(f"Saved {output}")
                details = "\n".join(f"{item.path.name}: dy={item.dy:+d}, dx={item.dx:+d}" for item in alignments[:12])
                if len(alignments) > 12:
                    details += f"\n... {len(alignments) - 12} more"
                messagebox.showinfo("Stack complete", f"Saved:\n{output}\n\nAlignment:\n{details}")
            elif kind == "error":
                self.status.set("Stack failed.")
                messagebox.showerror("Stack failed", str(payload))

        self.after(100, self._poll_messages)


def main() -> None:
    app = MySequatorApp()
    app.mainloop()


if __name__ == "__main__":
    main()
