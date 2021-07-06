#
# Dockerfile for Firebase CI testing
#
# Provides:
#   - 'firebase' CLI, with some emulators pre-installed
#   - node.js and npm >=7.7.0
#   - bash, curl
#   - a user 'user' created (can be activated manually)
#
# Note:
#   Cloud Build requires that the builder image has 'root' rights; not a dedicated user.
#   Otherwise, one gets all kinds of access right errors with '/builders/home/.npm' and related files.
#
#   This is fine. There is no damage or risk, leaving the builder image with root so the user/home related lines have
#   been permanently disabled by '#|' prefix.
#
# Manual user land:
#   It's sometimes good to debug things as a user, a 'user' is added. Jump there with 'passwd user' and 'login user'.
#
# Note:
#   Use of 'FIREBASE_EMULATORS_PATH' env.var. seems legit, but it's not mentioned in 'firebase-tools' documentation.
#
# References:
#   - Best practices for writing Dockerfiles
#       -> https://docs.docker.com/develop/develop-images/dockerfile_best-practices/
#

# Node images
#   -> https://hub.docker.com/_/node
#
# As of May'21:
#   "current-alpine": 16.2.0
#   "16-alpine": 16.2.0 (npm 7.13.0)
#
# As of Mar'21:
#   "current-alpine": 15.12.0
#   "lts-alpine": 14.16.0 (npm 6.14.11)

# Note: IF YOU CHANGE THIS, change the '-nodeXX' suffix within 'build' script.
FROM node:16-alpine

# Version of 'firebase-tools' is also our version
#
ARG FIREBASE_VERSION

#|# It should not matter where the home is, but based on an error received with Cloud Build (beta 2021.03.19),
#|# the commands it excercises seem to expect to be able to 'mkdir' a folder within '/builder/home'.
#|#
#|ENV HOME /builder/home
ENV USER user
ENV GROUP mygroup

# Add 'npm' 7 (was needed with node 14). KEEP?
#RUN npm install -g npm

RUN apk --no-cache add openjdk11-jre-headless

# Auxiliary tools; The '-alpine' base image is based on 'busybox' and doesn't have these.
#
RUN apk --no-cache add bash curl

RUN yarn global add firebase-tools@${FIREBASE_VERSION} \
  && yarn cache clean

# Alternative:
#
# Note: With this approach (from Firebase docs), we are not in charge of the version (which we.. like to be :).
#
#RUN curl -sL https://firebase.tools | bash

# Products that have 'setup:emulators:...' (only some of these are cached into the image, but you can tune the set):
#
#   - Realtime database
#   - Firestore
#   - Storage
#   - Pub/Sub
#   - Emulator UI   (not needed in CI; include this for Docker-based development)
#
# NOTE: The caching goes to '/root/.cache', under the home of this image.
#   Cloud Build (as of 27-Mar-21) does NOT respect the image's home, but places one in '/builder/home', instead.
#   More importantly, it seems to overwrite existing '/builder/home' contents, not allowing us to prepopulate.
#
# @Firebase:
#   - [ ] Can we trust on 'FIREBASE_EMULATORS_PATH' env.var. to be a feature? (it's not documented; Jun 2021)
#
# Note: Adding as separate layers, with the least changing mentioned first.
#
RUN firebase setup:emulators:database
RUN firebase setup:emulators:firestore
#RUN firebase setup:emulators:storage
#RUN firebase setup:emulators:pubsub \
#  && rm /root/.cache/firebase/emulators/pubsub-emulator*.zip

# Note: We also bring in the emulator UI, though it's not needed in CI. This helps in using the same image also in dev.
#
RUN firebase setup:emulators:ui \
  && rm -rf /root/.cache/firebase/emulators/ui-v*.zip

  # $ ls .cache/firebase/emulators/
  #   cloud-firestore-emulator-v1.12.0.jar    (57,5 MB)
  #   cloud-storage-rules-runtime-v1.0.0.jar  (31,7 MB)   ; NOT PRE-FETCHED (people can use it; will get downloaded if they do)
  #   firebase-database-emulator-v4.7.2.jar   (27,6 MB)
  #   pubsub-emulator-0.1.0                   (37,9 MB)   ; NOT PRE-FETCHED (-''-)
  #   pubsub-emulator-0.1.0.zip               (34,9 MB)   ; removed
  #   ui-v1.5.0                               (24 MB)
  #   ui-v1.5.0.zip                           (6 MB)      ; removed

# Setting the env.var so 'firebase-tools' finds the images.
#
# Without this, the using CI script would first need to do a 'mv /root/.cache ~/' command. It's weird; the other approaches
# considered were:
#   - use our user and home                   (Cloud Build doesn't resepect them)
#   - place the files under '/builder/home'   (Cloud Build wipes that folder, before announcing it the new home)
#   - have an 'ONBUILD' step handle the move  (Cloud Build doesn't call the triggers)
#
# Note: 'FIREBASE_EMULATORS_PATH' looks legit (from the sources), but is not mentioned in Firebase documentation (May 2021)
#   so it might seize to work, one day... #good-enough
#
ENV FIREBASE_EMULATORS_PATH '/root/.cache/firebase/emulators'

# Allow manual user invocation.
#
#ENV USER_HOME /home/${USER}

RUN addgroup -S ${GROUP} && \
  adduser --disabled-password \
    --ingroup ${GROUP} \
    ${USER}

  # Note: npm needs the user to have a home directory ('/home/user')
  #mkdir -p ${USER_HOME} && \
  #chown -R ${USER}:${GROUP} ${USER_HOME}

#|WORKDIR ${HOME}

#|# Now changing to user (no more root)
#|USER ${USER}
#|   # $ whoami
#|   # user

# Don't define an 'ENTRYPOINT' since we provide multiple ('firebase', 'npm'). Cloud Build scripts can choose one.
