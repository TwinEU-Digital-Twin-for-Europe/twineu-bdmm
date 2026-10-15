.PHONY: help up up-minio up-aimic up-minio-aimic down down-volumes logs

COMPOSE_FILE = docker-compose.prod.yaml

help:
	@echo "TwinEU Big Data Management Module - Deployment Menu"
	@echo "  up                    Start stack (Local Storage Mode)"
	@echo "  up-minio         Start stack WITH Local MinIO"
	@echo "  up-aimic              Start stack WITH Bundled Publisher (AIMIC)"
	@echo "  up-minio-aimic   Start stack WITH MinIO and AIMIC"
	@echo "  down                  Stop stack and remove containers"
	@echo "  down-volumes          Stop stack and wipe all data volumes"
	@echo "  logs                  Tail system logs"

up:
	docker compose -f $(COMPOSE_FILE) up -d

up-minio:
	docker compose -f $(COMPOSE_FILE) --profile include_minio up -d

up-aimic:
	docker compose -f $(COMPOSE_FILE) --profile include_aimic up -d

up-minio-aimic:
	docker compose -f $(COMPOSE_FILE) --profile include_minio --profile include_aimic up -d

down:
	docker compose -f $(COMPOSE_FILE) --profile include_minio --profile include_aimic down

down-volumes:
	docker compose -f $(COMPOSE_FILE) --profile include_minio --profile include_aimic down -v

logs:
	docker compose -f $(COMPOSE_FILE) --profile include_minio --profile include_aimic logs -f