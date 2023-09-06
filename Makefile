setup:
	$ asdf install zig 0.11.0 && asdf local zig 0.11.0
PHONY: setup

build-app:
	$ zig build
PHONY: build-app

run:
	$ zig build run
PHONY: run

build-image:
	# $ docker build -t lucaswilliameufrasio/backend-cockfighting-zig-api --progress=plain .
	$ docker build --no-cache -t lucaswilliameufrasio/backend-cockfighting-zig-api --progress=plain -f ./Dockerfile .
PHONY: build-image

start-database:
	$ docker compose -f docker-compose.dev.yml up -d postgres
PHONY: start-database

stop-all-compose-services:
	$ docker compose -f docker-compose.dev.yml down
	$ docker volume rm backend-cockfighintg-q3-2023-zig_postgres_data
PHONY: stop-all-compose-services

run-container:
	$ docker run --rm --name backend-cockfighting-zig-api --env-file=.env -p 9998:9998 lucaswilliameufrasio/backend-cockfighting-zig-api
PHONY: run-container

stop-container:
	$ docker stop backend-cockfighting-zig-api
PHONY: stop-container

push-image:
	$ docker push lucaswilliameufrasio/backend-cockfighting-zig-api
PHONY: push-image

