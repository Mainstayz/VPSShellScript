#!/bin/bash

detect_distribution() {
    local supported_distributions=("ubuntu" "debian" "centos" "fedora")
    if [ -f /etc/os-release ]; then
        . /etc/os-release
         if [[ "${ID}" = "ubuntu" || "${ID}" = "debian" || "${ID}" = "centos" || "${ID}" = "fedora" ]]; then
            PM="apt"
            [ "${ID}" = "centos" ] && PM="yum"
            [ "${ID}" = "fedora" ] && PM="dnf"
        else
            echo "Unsupported distribution!"
            exit 1
        fi
    else
        echo "Unsupported distribution!"
        exit 1
    fi
}

check_dependencies() {
    detect_distribution
    local dependencies=("curl" "git" "jq")
    for dep in "${dependencies[@]}"; do
        if ! command -v "${dep}" &> /dev/null; then
            echo "${dep} is not installed. Installing..."
            # ${PM} install -y "${dep}"
        fi
    done
}
