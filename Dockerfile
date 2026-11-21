# syntax=docker/dockerfile:1
#
# NeuroTUM reBot B601-DM shared ROS 2 image
#   Ubuntu 24.04 · ROS 2 Jazzy · Python 3.12
#   Seeed reBotArmController_ROS2 + reBotArm_control_py (pinned commits)
#   MoveIt 2 · Pinocchio · RViz 2 · ros2_control
#
# Seeed's packages are reused as-is; nothing here reimplements hardware control.
#
# Build from this folder:  docker build -t neuromotion-robotics:jazzy-dev .
# Self-test:               docker run --rm neuromotion-robotics:jazzy-dev rebot-selftest

ARG BASE_IMAGE=ros:jazzy-ros-base-noble
FROM ${BASE_IMAGE}

ARG ROS_DISTRO
ARG USERNAME=ros
ARG USER_UID=1000
ARG USER_GID=1000

# ================= Setting up system ===================== #


# Set ROS distribution
ARG ROS_DISTRO=jazzy

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3-pip python3-setuptools python3-pytest\
      locales ca-certificates curl gnupg2 dirmngr lsb-release \
      software-properties-common git git-lfs nano vim wget

# Install user-added debian packages from 'apt_requirements' file 
COPY ./resources/apt_requirements /tmp
RUN xargs -a /tmp/apt_requirements -r apt-get install -y --no-install-recommends || true
RUN rm /tmp/apt_requirements

# Setup oh-my-bash and robbyrussell theme
RUN bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)"
COPY ./resources/robbyrussell.theme.sh /root/.oh-my-bash/custom/themes/robbyrussell/robbyrussell.theme.sh
RUN sed -i 's/OSH_THEME=".*"/OSH_THEME="robbyrussell"/' /root/.bashrc

# Setup locales package
RUN locale-gen en_US en_US.UTF-8 
RUN update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8


# =================== Building ROS 2 ======================= #


# Enable Ubuntu Universe repo
RUN apt-get install software-properties-common -y
RUN add-apt-repository universe

# Set up keys and ROS2 repos
RUN ROS_APT_SOURCE_VERSION=$(curl -s https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest | grep -oP '"tag_name": "\K[^"]+') && \
    echo "ROS APT source version: ${ROS_APT_SOURCE_VERSION}" && \
    curl -L -o /tmp/ros2-apt-source.deb "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.$(. /etc/os-release && echo $VERSION_CODENAME)_all.deb" && \
    apt-get install -y /tmp/ros2-apt-source.deb && \
    rm -f /tmp/ros2-apt-source.deb

# Refresh apt 
RUN apt-get update
RUN apt-get upgrade -y

# Install ROS2
RUN apt-get install ros-${ROS_DISTRO}-ros-base -y

# Install ROS2 packages from "ros_requirements" file
COPY ./resources/ros_requirements /tmp
RUN cat /tmp/ros_requirements | DEBIAN_FRONTEND=noninteractive xargs -I {} apt-get  install --yes --no-install-recommends ros-${ROS_DISTRO}-{}
RUN rm /tmp/ros_requirements

# Source ROS setup script
RUN echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> /root/.bashrc

# Install recommended ROS2 packages
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends  \
    python3-rosdep \
    python3-colcon-common-extensions 

# Init rosdep and update it
RUN rosdep init && rosdep update


# --- Pinned upstream sources (update deliberately, then rebuild) -------------
# Seeed ROS 2 workspace (v0.3.0, main @ 2026-11-06)
ARG REBOT_ROS2_REPO=https://github.com/Seeed-Projects/reBotArmController_ROS2.git
ARG REBOT_ROS2_COMMIT=87780c6a5c2fb43b55ddebda5eac375ceb9c5a40
# Seeed low-level Python SDK (main @ 2026-11-06)
ARG REBOT_SDK_REPO=https://github.com/Seeed-Projects/reBotArm_control_py.git
ARG REBOT_SDK_COMMIT=3524ebc5316985d6d74fe30269ae771fea715507
# Damiao/Robstride motor bridge used by the SDK (PyPI, cp312 wheels)
ARG MOTORBRIDGE_VERSION=0.6.0

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    REBOT_WS=/opt/rebotarm_ros2

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# --- System + ROS packages (Seeed's documented list + MoveIt set) ------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        git ca-certificates sudo bash-completion less nano \
        python3-pip python3-colcon-common-extensions python3-rosdep \
        python3-numpy python3-yaml python3-matplotlib python3-scipy \
        # X11 / OpenGL client libraries for RViz (Mesa: Intel iGPU + software fallback)
        libgl1 libglx-mesa0 libgl1-mesa-dri libegl1 mesa-utils x11-apps \
        # Seeed Step 2
        ros-${ROS_DISTRO}-control-msgs \
        ros-${ROS_DISTRO}-trajectory-msgs \
        ros-${ROS_DISTRO}-tf-transformations \
        ros-${ROS_DISTRO}-robot-state-publisher \
        ros-${ROS_DISTRO}-rviz2 \
        ros-${ROS_DISTRO}-pinocchio \
        # Seeed MoveIt section
        ros-${ROS_DISTRO}-moveit \
        ros-${ROS_DISTRO}-moveit-configs-utils \
        ros-${ROS_DISTRO}-moveit-kinematics \
        ros-${ROS_DISTRO}-moveit-planners-ompl \
        ros-${ROS_DISTRO}-moveit-simple-controller-manager \
        ros-${ROS_DISTRO}-ros2-control \
        ros-${ROS_DISTRO}-ros2-controllers \
        ros-${ROS_DISTRO}-xacro \
        # Used by rebotarm_bringup (declared in its package.xml)
        ros-${ROS_DISTRO}-rosbridge-server \
    && rm -rf /var/lib/apt/lists/*

# motorbridge into the system Python 3.12, matching Seeed's instructions.
RUN python3 -m pip install --no-cache-dir --break-system-packages \
        --index-url https://pypi.org/simple "motorbridge==${MOTORBRIDGE_VERSION}"

# --- Seeed sources at pinned commits -----------------------------------------
# The ROS package finds the SDK by walking up to <workspace>/third_party/reBotArm_control_py.
RUN git clone "${REBOT_ROS2_REPO}" "${REBOT_WS}" \
    && git -C "${REBOT_WS}" checkout --detach "${REBOT_ROS2_COMMIT}" \
    && git clone "${REBOT_SDK_REPO}" "${REBOT_WS}/third_party/reBotArm_control_py" \
    && git -C "${REBOT_WS}/third_party/reBotArm_control_py" checkout --detach "${REBOT_SDK_COMMIT}" \
    && rm -rf "${REBOT_WS}/.git" "${REBOT_WS}/third_party/reBotArm_control_py/.git"

# Resolve any remaining package.xml dependencies, then build the Seeed workspace.
# "ament_python" is a build type (buildtool_depend in Seeed's Python packages), not a
# rosdep key; skipping exactly that key keeps every other missing dependency fatal.
RUN rosdep init 2>/dev/null || true \
    && apt-get update \
    && rosdep update --rosdistro "${ROS_DISTRO}" \
    && rosdep install --from-paths "${REBOT_WS}/src" --ignore-src -y --rosdistro "${ROS_DISTRO}" \
        --skip-keys "ament_python" \
    && rm -rf /var/lib/apt/lists/*

RUN source "/opt/ros/${ROS_DISTRO}/setup.bash" \
    && cd "${REBOT_WS}" \
    && colcon build --event-handlers console_direct- \
    && rm -rf build log

# --- Non-root user matching the host user (UID 1000 by default) --------------
# Ubuntu 24.04 images ship a default "ubuntu" user with UID 1000; replace it.
RUN if [ "${USER_UID}" = 0 ] || [ "${USER_GID}" = 0 ]; then echo "USER_UID/USER_GID must not be 0" >&2; exit 1; fi \
    && if id -u ubuntu >/dev/null 2>&1; then userdel -r ubuntu; fi \
    && groupadd --gid "${USER_GID}" "${USERNAME}" \
    && useradd --uid "${USER_UID}" --gid "${USER_GID}" -m -s /bin/bash "${USERNAME}" \
    && usermod -aG dialout,video "${USERNAME}" \
    && echo "${USERNAME} ALL=(root) NOPASSWD:ALL" > "/etc/sudoers.d/${USERNAME}" \
    && chmod 0440 "/etc/sudoers.d/${USERNAME}"

# ROS 2: default domain 0, traffic kept inside the container; Seeed's Fast DDS workaround.
ENV ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST \
    FASTDDS_BUILTIN_TRANSPORTS=UDPv4

USER ${USERNAME}
WORKDIR /workspaces/neuromotion-robotics

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
