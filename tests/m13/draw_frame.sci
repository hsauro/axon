# draw.frame: frames of an animation, paced to fps, and saved as numbered
# files when asked.
import draw
import graphics
import io
import time

t0 = time.clock()
for k in 1:5
  draw.canvas(width = 100, height = 100)
  draw.circle(50, 50, 8 * k)
  draw.frame(fps = 50, save = "_tmp_anim")
end
# Five frames at 50 a second: at least four intervals of 0.02 s.
println(time.clock() - t0 >= 0.079)
ok = true
for k in 1:5
  f = "_tmp_anim_0000" + string(k) + ".png"
  ok = ok and io.file_exists(f) and io.delete_file(f)
end
println(ok, io.file_exists("_tmp_anim_00006.png"))

# Under the IDE (and the test runner) a frame is one of a few files reused
# in turn, named frame-<process>-<n>.png.
p = graphics.frame({width: 10, height: 10, items: {}})
println(endswith(p, ".png"), contains(p, "frame-"))

# With a count of items already sent (the picture grew since the last frame)
# only the new items go to the IDE; under the test runner the frame is still
# rendered whole.
p2 = graphics.frame({width: 10, height: 10, items: {{kind: "circle", x: 5, y: 5, r: 2}}}, 1)
println(endswith(p2, ".png"))
