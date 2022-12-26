#!/bin/bash

set -eo pipefail

DOCKER_REGISTRY=${1}
DOCKER_USERNAME=${2}
DOCKER_PASSWORD=${3}
POSTGRES_VERSION=${4}
POSTGRES_DATABASE=${5}
POSTGRES_USERNAME=${6}
POSTGRES_PASSWORD=${7}
REPOSITORY=${8}
TAG=${9}

RDS_DB_HOST=${RDS_DB_HOST}
RDS_DB_NAME=${RDS_DB_NAME}
RDS_DB_USER=${RDS_DB_USER}
RDS_DB_PASS=${RDS_DB_PASS}

DEV_DB_IMAGE_REPO=some-repo-name
DEV_DB_IMAGE_TAG=$(date +"%Y-%m-%d")
AWS_REGISTRY_URL=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGISTRY_REGION}.amazonaws.com

if [[ -z ${POSTGRES_PASSWORD} ]]; then
  echo "POSTGRES_PASSWORD must be defined as an environment variable"
  exit 1
fi

echo -n "Fetching schema..."
PGPASSWORD=${POSTGRES_PASSWORD:-} pg_dump \
    --host="${RDS_DB_HOST}" \
    --dbname="${RDS_DB_NAME}" \
    --username="${RDS_DB_USER}" \
    --no-owner \
    --no-privileges \
    --schema-only \
    --file=schema.sql &>/dev/null
echo "done."

# Login to private docker registry
echo -n "Logging into private docker registry..."
aws ecr get-login-password --region ${AWS_REGISTRY_REGION} | docker login --username AWS --password-stdin ${AWS_REGISTRY_URL} &>/dev/null
echo "done."

# Build platform-specific images. Apple M1 chips will require linux/arm64 while most others will require linux/amd64
ARCHITECTURES=("amd64" "arm64")
image_list=()
for arch in "${ARCHITECTURES[@]}"; do
  platform="linux/${arch}"
  image=${AWS_REGISTRY_URL}/${DEV_DB_IMAGE_REPO}:${DEV_DB_IMAGE_TAG}-${arch}
  image_list+=("${image}")
  echo -n "Building image for ${platform}..."
  docker build --platform "${platform}" -t "${image}" . &>/dev/null
  echo "done."
  echo -n "Pushing image for ${platform}..."
  docker push "${image}" &>/dev/null
  echo "done."
done

# Create docker manifest to avoid having to manually specify a platform when pulling
echo -n "Creating multi-platform manifest..."
manifest_name="${AWS_REGISTRY_URL}/${DEV_DB_IMAGE_REPO}:${DEV_DB_IMAGE_TAG}"
docker manifest create --amend "${manifest_name}" ${image_list[*]} &>/dev/null

for arch in "${ARCHITECTURES[@]}"; do
  image=${AWS_REGISTRY_URL}/${DEV_DB_IMAGE_REPO}:${DEV_DB_IMAGE_TAG}-${arch}
  docker manifest annotate --arch "${arch}" "${manifest_name}" "${image}" &>/dev/null
done
echo "done."

echo -n "Pushing manifest..."
docker manifest push "$manifest_name" &>/dev/null
echo "done."

echo -e "\nYou can now pull this image on any platform with the following:"
echo -e "\n  docker pull ${AWS_REGISTRY_URL}/${DEV_DB_IMAGE_REPO}:${DEV_DB_IMAGE_TAG}"
