run-server:
	(cd server && zig build run)

run-client:
	(cd client && zig build run)

run-all:
	make run-server
	make run-client
