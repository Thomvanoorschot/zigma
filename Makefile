run-server:
	(cd server && zig build run)

run-client:
	(cd client && zig build -Dtarget=wasm32-emscripten -Doptimize=ReleaseFast run)