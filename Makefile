SHELL := /bin/bash
.SHELLFLAGS := -e -O xpg_echo -o errtrace -o functrace -c
MAKEFLAGS += --no-builtin-rules
MAKEFLAGS += --no-builtin-variables
MAKE := $(make)
DATETIME_FORMAT := %(%Y-%m-%d %H:%M:%S)T

.ONESHELL:
.SUFFIXES:
.DELETE_ON_ERROR:

.PHONY: help
help:  ## Prints this usage.
	@printf '== Recipes ==\n' && grep --no-filename -E '^[a-zA-Z0-9-]+:' $(MAKEFILE_LIST) && echo '\n== Images ==' && echo $(SUBDIRS) | tr ' ' '\n' 
# see https://www.gnu.org/software/make/manual/html_node/Origin-Function.html
MAKEFILE_ORIGINS := \
	default \
	environment \
	environment\ override \
	file \
	command\ line \
	override \
	automatic \
	\%

PRINTVARS_MAKEFILE_ORIGINS_TARGETS += \
	$(patsubst %,printvars/%,$(MAKEFILE_ORIGINS)) \

.PHONY: $(PRINTVARS_MAKEFILE_ORIGINS_TARGETS)
$(PRINTVARS_MAKEFILE_ORIGINS_TARGETS):
	@$(foreach V, $(sort $(.VARIABLES)), \
		$(if $(filter $(@:printvars/%=%), $(origin $V)), \
			$(info $V=$($V) ($(value $V)))))

.PHONY: printvars
printvars: printvars/file ## Print all Makefile variables (file origin).

.PHONY: printvar-%
printvar-%: ## Print one Makefile variable.
	@echo '($*)'
	@echo '  origin = $(origin $*)'
	@echo '  flavor = $(flavor $*)'
	@echo '   value = $(value  $*)'


.DEFAULT_GOAL := help


src/build-src/CMakeUserPresets.json: src/build-src/CMakeUserPresets.yaml
	@echo "Generating CMakeUserPresets.json"
	yq -o json $< > $@

.PHONY: cmake-presets

cmake-presets: src/build-src/CMakeUserPresets.json ## Generate CMakePresets.json from CMakePresets.yaml

IMG_VER ?= 0.0.4

.PHONY: img-babypipe
img-babypipe:
	docker build --progress=plain --rm --tag maouw/babypipe:$(IMG_VER) -f maouw/babypipe:latest -f Dockerfile .

.PHONY: img-new-mirtk
img-new-mirtk:
	docker build --progress=plain --rm --build-arg BASE_IMAGE=biomedia/dhcp-structural-pipeline:new-mirtk --tag maouw/babypipe:new-mirtk_$(IMG_VER) -f Dockerfile .

.PHONY: imgs
imgs: img-babypipe img-new-mirtk

