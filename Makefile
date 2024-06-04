IMG_VER ?= 0.0.4

.PHONY: img-babypipe
img-babypipe:
	docker build --progress=plain --rm --tag maouw/babypipe:$(IMG_VER) -f maouw/babypipe:latest -f Dockerfile .

.PHONY: img-new-mirtk
img-new-mirtk:
	docker build --progress=plain --rm --build-arg BASE_IMAGE=biomedia/dhcp-structural-pipeline:new-mirtk --tag maouw/babypipe:new-mirtk_$(IMG_VER) -f Dockerfile .

.PHONY: imgs
imgs: img-babypipe img-new-mirtk

