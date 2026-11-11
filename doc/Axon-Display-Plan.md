# Display plan: sending drawings, not pictures

Status: steps 1 and 2 done (November 11, 2026), with most of step 3; the rest of step 3 and step 4 to come.

## Decision

Axon programs describe pictures; they do not make them. A program that shows a figure, a drawing or an animation frame sends the IDE the **scene**, the list of lines, shapes, text and images that `graphics` already uses, and the IDE draws it with Skia into the plot pane. No image files are written to show anything. Files are made only when a program asks for one (`graphics.save`, `plot.save`, `draw.save`).

Today `graphics.show` renders a PNG into a temporary folder and writes a marker line on stderr; the IDE loads the PNG, and for `plot` figures also a JSON file beside it. That costs a PNG encode and decode per figure or frame, leaves files on disk, and mixes control lines into the error stream.

ZeroMQ, as Jupyter front ends use it, is not needed: the IDE starts `axon` itself, on the same machine, and already talks to it through pipes. A Jupyter kernel for Axon would be a separate project that needs ZeroMQ by its protocol.

## Design

### One drawing code for both sides

A new unit, `src/Axon.Scene.pas`, used by both `axon` and the IDE, holds:

- the scene model: plain Delphi records and arrays (items with their kind, points, colours, stroke, text, image pixels, groups with transforms and clips), with no dependency on `Axon.Values` or the interpreter;
- the drawing code, moved from `Axon.Graphics`: `DrawScene(Canvas: sk_canvas_t; Scene)` through Skia's flat API, and `SavePng`/`SaveSvg`/`SavePdf`;
- a compact binary encoding of a scene (`EncodeScene`/`DecodeScene`): little-endian numbers, UTF-8 strings, coordinate vectors as raw doubles (or singles), image pixels as raw RGBA bytes.

`Axon.Graphics` keeps the checking of Axon scene records, with the same error messages, and converts a valid record into the scene model; `save`, `show` and `frame` then use `Axon.Scene`. Files saved by `graphics.save` stay as they are now.

### The display channel

The IDE gives each `axon` it starts (programs and the REPL) one more pipe, the display channel, and tells it where through the environment variable `AXON_DISPLAY`:

- Windows: an inheritable pipe handle, its number in `AXON_DISPLAY`;
- macOS: file descriptor 3 (`dup2` before `exec`), and `AXON_DISPLAY=3`.

`axon` writes length-prefixed binary messages to it (`Axon.Platform` holds the platform code):

| Message | Payload |
| --- | --- |
| `show` | an encoded scene |
| `frame` | an encoded scene: replaces the previous frame, no history entry |
| `figure` | an encoded scene and a `plot` figure record as JSON, for the interactive chart |

The IDE's process runner reads the channel on its own thread. For frames it keeps only the newest unshown one, as now.

### The IDE

- The plot pane draws scenes in a Skia paint box, so pictures are sharp at any pane size and screen resolution and redraw on resize; `plot` figures still go to the interactive charts.
- The figure history keeps scenes (and figure records) in memory, not file paths. Copy and Save render the scene with `Axon.Scene` (PNG, SVG, PDF), as they render charts now.
- The temporary figure folder and `AXON_SHOW_DIR` are no longer used by the IDE.

### Outside the IDE

Without `AXON_DISPLAY`, `show` renders the scene and opens it in the system's image viewer, as now (one file per `show`, in the temporary folder); `frame` does nothing. `AXON_SHOW_DIR` stays as a fallback that the test runner uses: with it set and no display channel, `show` and `frame` write PNGs there and the marker lines on stderr, as today, so tests keep a place for their figures.

## Steps

1. **Scene unit.** `Axon.Scene` with the model, drawing, saving and encoding; `Axon.Graphics` converts records to it. Every saved file and every test unchanged. *Done:* a script saving every item kind and option, `plot` figures (lines, bars, histogram, surface, subplots) and `draw` output as PNG and SVG gave byte-identical files before and after, and again with `AXON_SCENE_ROUNDTRIP=1`, which makes `axon` encode and decode every scene before drawing it (a check of the encoding; it can go once the display channel exercises the encoding). Coordinates are encoded as doubles. Images reach the scene as pixels: colour maps are applied in `Axon.Graphics`, so the IDE needs none.
2. **Display channel.** The pipe in the IDE's process runner (Windows and macOS), the writer in `axon`, the three messages. The IDE still accepts the old marker lines meanwhile. *Done,* together with the IDE drawing of step 3: the IDE starts programs and the REPL with the channel; the plot pane draws scenes in a `TSkPaintBox` (scaled to fit, centred, redrawn on resize); the history holds `TFigureEntry` objects (a scene, a figure record as JSON, or a file path) in memory; frames replace the animation's one entry and only the newest is decoded and drawn; Copy and Save render scenes through `Axon.Scene` (PNG at 2 pixels per point, PDF, SVG); the chart loaders take JSON text (`LoadFigureText`, `LoadFigure3DText`, `LoadFigureGridText`). Checked with a console program that runs `axon` through the IDE's `TProcessRunner` and decodes every message: a show, frames and a figure; the Mandelbrot example's 2.3 MB scene as one message; the pendulum's 300 frames in 10 s of real time, about 330 bytes a frame; no files written; `AXON_DISPLAY` not left in the IDE's environment. The macOS code compiles (dccosxarm64) but has not been run. Added afterwards: `DisplayAdd`, a frame carrying only the items added since the previous frame (`graphics.frame(scene, sent)`; `draw.frame` uses it when the canvas was not restarted), for pictures built up gradually. A program filling 256 columns of 256 boxes with a frame after each column sent 806 MB and took 18.6 s; with `DisplayAdd` it sends 12.5 MB and takes 8.6 s, of which 8.5 s is the pacing of 256 frames at 30 a second (1.4 s at `fps = 1000`). The shape functions of `draw` also became cheaper (about 14.5 µs a call instead of 26.6 µs), by working out page coordinates inline.
3. **IDE drawing.** The plot pane draws scenes; history in memory; Copy and Save from scenes; `plot` figures through `figure` messages; the IDE stops setting `AXON_SHOW_DIR`. *Left:* the IDE stops setting `AXON_SHOW_DIR` and creating its temporary figure folder, and its handling of the `#3show`/`#3frame` marker lines goes (only the test runner uses that path now); try it on the Mac.
4. **Documents.** Reference (`graphics.show`, `frame`, the display channel), CLAUDE.md, the manual's sections on showing figures and on animation.

Each step leaves everything working, with the suite passing in all three JIT modes.

## Questions to settle on the way

- Coordinates as doubles or singles in the encoding (Skia draws in singles; doubles keep the encoder trivial).
- Whether a figure from `plot` also carries its scene (for Copy and Save as drawn) or the IDE always redraws charts from the record.
- The largest message to accept (an image of 4000×4000 pixels is 64 MB of RGBA).
