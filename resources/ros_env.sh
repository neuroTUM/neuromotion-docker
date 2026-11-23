# ROS 2 environment, loaded for every new shell of the image's users.
# Installed as /etc/profile.d/ros_env.sh (read by login shells via /etc/profile)
# and sourced from /etc/bash.bashrc (read by interactive non-login shells).

# Sourcing setup.bash twice stacks duplicate paths, so load it once per shell tree.
if [ -z "${ROS_ENV_LOADED:-}" ]; then
    ROS_DISTRO="${ROS_DISTRO:-jazzy}"
    REBOT_WS="${REBOT_WS:-/opt/rebotarm_ros2}"

    if [ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]; then
        . "/opt/ros/${ROS_DISTRO}/setup.bash"
    fi

    # Seeed's packages overlay the ROS underlay, so this must come second.
    if [ -f "${REBOT_WS}/install/setup.bash" ]; then
        . "${REBOT_WS}/install/setup.bash"
    fi

    export ROS_ENV_LOADED=1
fi
