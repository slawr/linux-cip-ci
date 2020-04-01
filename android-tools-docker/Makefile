IMAGE_NAME ?= android_platform_tools
CONTAINER_NAME ?= aptools
CONTAINER_HOSTNAME ?= aptools
EXTERNAL_STORAGE = /optional/host/volume/here

default:
	@echo "make [build|buildnew|run|clean|logs|shell|stop|kill|rm|rmi]"

build:
	docker build --tag=${IMAGE_NAME} . \

buildnew:
	docker build --no-cache --tag=${IMAGE_NAME} .

run:
	docker run -ti -h "${CONTAINER_HOSTNAME}" -d -v "${EXTERNAL_STORAGE}:/tmp/FIXME" --name=${CONTAINER_NAME} ${IMAGE_NAME} /bin/bash

clean: kill rm rmi

logs:
	docker logs -f ${CONTAINER_NAME}

shell:
	docker exec -it ${CONTAINER_NAME} /bin/bash

stop:
	docker stop ${CONTAINER_NAME}

kill:
	@docker kill ${CONTAINER_NAME}
	@docker rm -v ${CONTAINER_NAME} >/dev/null || echo "Container removed already"

rm:
	@docker rm -v ${CONTAINER_NAME} >/dev/null || echo "Container removed already"

rmi:
	@docker rmi ${IMAGE_NAME} 2>/dev/null || echo "Image removed already"

