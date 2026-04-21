PI_VERSION := "3.13"
PI_VERSION_BUILD := "3.13"
IMAGE_NAME := privacyidea-docker:${PI_VERSION}

BUILDER := docker build
CONTAINER_ENGINE := docker

RANDOM_32 = cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1
RANDOM_16 = cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1
RANDOM_50 = cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 50 | head -n 1
RANDOM_ENCKEY = head -c 96 /dev/urandom | base64 -w0

SSL_SUBJECT="/C=DE/ST=SomeState/L=SomeCity/O=privacyIDEA/OU=reverseproxy/CN=localhost"

SERVICE_NAME := privacyidea-docker
SERVICE_USER := privacyidea
SERVICE_WORKDIR := $(shell pwd)
SERVICE_TEMPLATE := templates/privacyidea-docker.service
SERVICE_FILE := /etc/systemd/system/$(SERVICE_NAME).service

REGISTRY := localhost:5000
PORT := 8080
TAG := prod
PROFILE := stack

build:
	${BUILDER} --no-cache -t ${IMAGE_NAME}  --build-arg PI_VERSION_BUILD=${PI_VERSION_BUILD} --build-arg PI_VERSION=${PI_VERSION} .

build-all:
	bash build-images.sh build

push:
	${CONTAINER_ENGINE} tag ${IMAGE_NAME} ${REGISTRY}/${IMAGE_NAME}
	${CONTAINER_ENGINE} push ${REGISTRY}/${IMAGE_NAME}

cert:
	@openssl req -x509 -newkey rsa:4096 -keyout templates/pi.key -out templates/pi.pem -sha256 -days 3650 -nodes -subj "${SSL_SUBJECT}" 2> /dev/null
	@echo Certificate generation done...

secrets:
	$(eval ENV_DIR := environment/$(TAG))
	@test -d $(ENV_DIR) || { echo "ERROR: $(ENV_DIR)/ not found"; exit 1; }
	@echo "Generating secrets for $(ENV_DIR)/ ..."
	@# --- privacyidea.env ---
	@NEW=$$($(RANDOM_32)); sed -i "s|^PI_SECRET=.*|PI_SECRET=$$NEW|" $(ENV_DIR)/privacyidea.env; echo "  PI_SECRET=$$NEW"
	@NEW=$$($(RANDOM_32)); sed -i "s|^PI_PEPPER=.*|PI_PEPPER=$$NEW|" $(ENV_DIR)/privacyidea.env; echo "  PI_PEPPER=$$NEW"
	@NEW=$$($(RANDOM_16)); sed -i "s|^PI_ADMIN_PASS=.*|PI_ADMIN_PASS=$$NEW|" $(ENV_DIR)/privacyidea.env; echo "  PI_ADMIN_PASS=$$NEW"
	@# --- PI_ENCKEY (96 random bytes, base64) ---
	@NEW=$$($(RANDOM_ENCKEY)); \
		if grep -q '^#PI_ENCKEY=' $(ENV_DIR)/privacyidea.env; then \
			sed -i "s|^#PI_ENCKEY=.*|PI_ENCKEY=$$NEW|" $(ENV_DIR)/privacyidea.env; \
		elif grep -q '^PI_ENCKEY=' $(ENV_DIR)/privacyidea.env; then \
			sed -i "s|^PI_ENCKEY=.*|PI_ENCKEY=$$NEW|" $(ENV_DIR)/privacyidea.env; \
		else \
			sed -i '/^PI_SECRET=/a PI_ENCKEY='"$$NEW" $(ENV_DIR)/privacyidea.env; \
		fi; echo "  PI_ENCKEY=$$NEW"
	@# --- db.env + privacyidea.env (DB_PASSWORD must match) ---
	@NEW=$$($(RANDOM_32)); \
		sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$$NEW|" $(ENV_DIR)/db.env; \
		sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=$$NEW|" $(ENV_DIR)/privacyidea.env; \
		echo "  DB_PASSWORD=$$NEW"
	@# --- vpn_pooler.env ---
	@NEW=$$($(RANDOM_50)); sed -i "s|^DJANGO_SECRET_KEY=.*|DJANGO_SECRET_KEY=$$NEW|" $(ENV_DIR)/vpn_pooler.env; echo "  VPN_POOLER_DJANGO_SECRET_KEY=$$NEW"
	@# --- captive.env ---
	@NEW=$$($(RANDOM_50)); sed -i "s|^DJANGO_SECRET_KEY=.*|DJANGO_SECRET_KEY=$$NEW|" $(ENV_DIR)/captive.env; echo "  CAPTIVE_DJANGO_SECRET_KEY=$$NEW"
	@echo "Done. Secrets written to $(ENV_DIR)/"
	
stack:
	@TAG=${TAG} PI_BOOTSTRAP="true" \
	${CONTAINER_ENGINE} compose --env-file=environment/${TAG}/compose.env -p ${TAG} --profile=${PROFILE} up -d
	@echo
	@echo Access to privacyIDEA Web-UI: https://localhost:8443

fullstack:
	@TAG=${TAG} PI_BOOTSTRAP="true" \
	${CONTAINER_ENGINE} compose -f docker-compose.yaml -f docker-compose.dev.yaml --env-file=environment/${TAG}/compose.env -p ${TAG} --profile=fullstack up -d
	@echo 
	@echo Access to privacyIDEA Web-UI: https://localhost:8443
	@echo to create resolvers and realm, please run: make resolver

superadmin-policy:
	${CONTAINER_ENGINE} cp templates/superadmin-policy.json ${TAG}-privacyidea-1:/tmp/superadmin-policy.json
	${CONTAINER_ENGINE} exec ${TAG}-privacyidea-1 /privacyidea/venv/bin/pi-manage config import -i /tmp/superadmin-policy.json
	${CONTAINER_ENGINE} exec ${TAG}-privacyidea-1 rm /tmp/superadmin-policy.json
	@echo "superadmin policy imported."

resolver:
	${CONTAINER_ENGINE} cp templates/resolver.json ${TAG}-privacyidea-1:/privacyidea/etc/resolver.json
	${CONTAINER_ENGINE} exec -ti ${TAG}-privacyidea-1 /privacyidea/venv/bin/pi-manage config import -i /privacyidea/etc/resolver.json
	@echo resolvers and realm created.
	@echo "############################################################################"
	@echo "admin login with: admin@admin / admin "
	@echo "helpdesk login with: helpdesk@helpdesk / helpdesk "
	@echo "user login with: HadiPac / hadi "
	@echo "############################################################################"
run:
	@${CONTAINER_ENGINE} run -d --name ${TAG}-privacyidea \
			-e PI_PASSWORD=admin \
			-e PI_ADMIN=admin \
			-e PI_ADMIN_PASS=admin \
			-e DB_PASSWORD=superSecret \
			-e PI_PEPPER=superSecret \
			-e PI_SECRET=superSecret \
			-e PI_PORT=8080 \
			-e PI_LOGLEVEL=INFO \
			-p ${PORT}:${PORT} \
			${IMAGE_NAME} 
	@echo Access to privacyIDEA Web-UI: http://localhost:${PORT}
	@echo Username/Password: admin / admin

clean:
	@${CONTAINER_ENGINE} rm --force ${TAG}-privacyidea-1

distclean:
	@echo -n "Warning! This will remove all related volumes: Are you sure? [y/N] " && read ans && if [ $${ans:-'N'} = 'y' ]; then make make_distclean; fi

make_distclean:
	@echo Remove containers, volumes and data directories
	@${CONTAINER_ENGINE} rm --force ${TAG}-openldap-1 ${TAG}-db-1  ${TAG}-privacyidea-1 ${TAG}-freeradius-1 ${TAG}-reverse_proxy-1 ${TAG}-vpn_pooler-1
	@${CONTAINER_ENGINE} volume rm ${TAG}_pgdata ${TAG}_pidata ${TAG}_vpn_pooler_static ${TAG}_vpn_pooler_data ${TAG}_captive_static ${TAG}_rsyslog_logs 2>/dev/null || true
	@rm -rf data/

install-service:
	@sudo bash setup-service.sh $(SERVICE_USER) $(SERVICE_WORKDIR)

uninstall-service:
	@echo "Removing systemd service: $(SERVICE_NAME)"
	@sudo systemctl stop $(SERVICE_NAME).service 2>/dev/null || true
	@sudo systemctl disable $(SERVICE_NAME).service 2>/dev/null || true
	@sudo rm -f $(SERVICE_FILE)
	@sudo systemctl daemon-reload
	@echo "Service removed."

