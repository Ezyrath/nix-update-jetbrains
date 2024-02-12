#!/usr/bin/env bash

# this script update the default.nix file for jetbrains-toolbox
# nix-prefetch-url --unpack not generate the good hash
# this script use the method of (fake hash) hash not set
# to force nix to generate the hash
# and apply this to the default.nix of jetbrains-toolbox

VERSION=$1
PATH_NIX_PKGS="pkgs/applications/misc/jetbrains-toolbox/default.nix"
PKGS_NAME="jetbrains-toolbox"

# verify version set
if [ -z "$VERSION" ]; then
    echo "Error : Parameter VERSION is not set !"
    echo "launch.sh [VERSION]"
    exit
fi

# get nixos pkgs
echo "Clone nixpkgs git..."
git clone --depth=1 -b "update/jetbrains" https://github.com/Ezyrath/nixpkgs.git

# get old version
OLD_VERSION=$(< "nixpkgs/pkgs/applications/misc/jetbrains-toolbox/default.nix" \
  sed -En "s|version = \"(.*)\";|\1|p" | xargs echo)

# updating jetbrains-toolbox with fake sha256
echo "Change version in the nix file..."
sed -i "s|version = .*|version = \"$VERSION\";|g" nixpkgs/$PATH_NIX_PKGS # change version
sed -i "s|sha256 = .*|sha256 = \"\";|g" nixpkgs/$PATH_NIX_PKGS # use fake sha256 to generate the good hash

# zip
echo "Compress nixpkgs..."
tar -zcf nixpkgs.tar.gz nixpkgs
mkdir html
mv nixpkgs.tar.gz html

# deliver the nixpkgs by http
echo "Start nginx for serve nixpkgs..."
docker run --rm --name nginx-temp-for-updating-nix \
  -v "$(pwd)/html":/usr/share/nginx/html:ro \
  -d nginx

# wait nginx
echo "Wait nginx..."
sleep 4

NGINX_DELIVER_IP=$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
  nginx-temp-for-updating-nix)

# start nixos container for generate true hash
echo "Start nixos for generate hash..."
docker run --rm --name nixos-temp-for-updating-nix \
  -e NIXPKGS_ALLOW_UNFREE="1" \
  -it nixos/nix bash -c " \
    nix-channel --remove nixpkgs &&\
    nix-channel --add http://${NGINX_DELIVER_IP}/nixpkgs.tar.gz nixpkgs &&\
    nix-channel --update &&\
    nix-shell -p $PKGS_NAME \
  " > out.txt 2>&1
# get true hash
TRUE_HASH=$(< out.txt tail | grep -o "sha256.*=" | tail -n1)
echo "HASH GENERATED : $TRUE_HASH"

# apply the true hash
echo "Apply the hash in the nix file..."
sed -i "s|sha256 = .*|sha256 = \"${TRUE_HASH}\";|g" nixpkgs/$PATH_NIX_PKGS

# generate commit
echo "Generate commit..."
cd nixpkgs || exit
git add $PATH_NIX_PKGS
git commit -m "${PKGS_NAME}: $OLD_VERSION -> $VERSION"
echo "Manual git push before confirm clean !"

# Wait user for clean
echo "!! CONFIRM FOR CLEAN !!"
read CONFIRM

# cleaning
echo "--- CLEANING UP ---"
echo "Stop and clean container..."
docker stop nginx-temp-for-updating-nix > /dev/null 2>&1
docker stop nixos-temp-for-updating-nix > /dev/null 2>&1
docker rm -Rf nginx-temp-for-updating-nix > /dev/null 2>&1
docker rm -Rf nixos-temp-for-updating-nix > /dev/null 2>&1
echo "Clean file..."
rm -Rf nixpkgs
rm -Rf html
rm -Rf out.txt