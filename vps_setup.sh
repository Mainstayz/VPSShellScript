#!/bin/bash
set -e

# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

detect_distribution() {
    local supported_distributions=("ubuntu" "debian" "centos" "fedora")
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "${ID}" = "ubuntu" || "${ID}" = "debian" || "${ID}" = "centos" || "${ID}" = "fedora" ]]; then
            PM="apt"
            [ "${ID}" = "centos" ] && PM="yum"
            [ "${ID}" = "fedora" ] && PM="dnf"
            log_info "检测到系统: ${ID} (包管理器: ${PM})"
        else
            log_error "不支持的系统类型: ${ID}"
            exit 1
        fi
    else
        log_error "无法检测系统类型: /etc/os-release 文件不存在"
        exit 1
    fi
}

# 更新组件，包管理
update_system() {
    log_info "开始更新系统..."
    if [ "${PM}" = "apt" ]; then
        sudo apt update
        sudo apt upgrade --only-upgrade -y
    elif [ "${PM}" = "yum" ]; then
        sudo yum update -y
    fi
    log_info "系统更新完成"
}

# 新增询问函数
ask_user() {
    local tool_name=$1
    local description=$2
    echo -e "${YELLOW}是否安装 ${tool_name}?${NC}"
    [ ! -z "$description" ] && echo -e "${YELLOW}描述: ${description}${NC}"
    read -p "请输入 [Y/n]: " choice
    case "$choice" in
    [nN][oO] | [nN])
        return 1
        ;;
    *)
        return 0
        ;;
    esac
}

install_tool() {
    local name=$1
    local description=$2

    # 如果工具已安装，显示版本信息
    if command -v "${name}" &>/dev/null; then
        log_info "${name} 已安装"
        return 0
    fi

    # 询问用户是否安装
    if ask_user "${name}" "${description}"; then
        log_warn "${name} 未安装，正在安装..."
        sudo ${PM} install -y "${name}"
        if [ $? -eq 0 ]; then
            log_info "${name} 安装成功"
        else
            log_error "${name} 安装失败"
            exit 1
        fi
    else
        log_info "跳过安装 ${name}"
    fi
}

install_tool_no_ask() {
    local name=$1
    if command -v "${name}" &>/dev/null; then
        log_info "${name} ���安装"
        return 0
    fi
    log_warn "${name} 未安装，正在安装..."
    sudo ${PM} install -y "${name}"
    if [ $? -eq 0 ]; then
        log_info "${name} 安装成功"
    else
        log_error "${name} 安装失败"
        exit 1
    fi
}

config_zsh() {
    log_info "配置 zsh 主题"
    # choose oh-my-zsh theme
    # 替换 zshrc 文件中的 ZSH_THEME 为 ys
    sed -i "s/^ZSH_THEME=.*/ZSH_THEME=\"ys\"/g" ~/.zshrc

    install_tool_no_ask "git"

    log_info "安装 oh-my-zsh 插件, zsh-autosuggestions, zsh-syntax-highlighting ....."
    git clone https://github.com/zsh-users/zsh-autosuggestions.git ~/.oh-my-zsh/plugins/zsh-autosuggestions
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ~/.oh-my-zsh/plugins/zsh-syntax-highlighting

    log_info "配置 zshrc 文件"
    sed -i "s/^plugins=.*/plugins=(git z wd extract zsh-autosuggestions zsh-syntax-highlighting command-not-found)/g" ~/.zshrc

    if ! grep -q "/usr/bin/zsh" /etc/shells; then
        echo "/usr/bin/zsh" >>/etc/shells
    fi
    log_info "设置 zsh 为默认 shell"
    chsh -s $(which zsh)

    log_info "zsh 配置完成"
}

install_oh_my_zsh() {
    log_info "开始安装 oh-my-zsh..."

    # 清理旧文件
    if [ -d ~/.oh-my-zsh ]; then
        log_warn "检测到已存在的 oh-my-zsh 安装，正在删除..."
        rm -rf ~/.oh-my-zsh
    fi

    # 备份已存在的 .zshrc
    [ -f ~/.zshrc ] && mv ~/.zshrc ~/.zshrc.backup

    # 克隆 oh-my-zsh 仓库
    git clone https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh

    # 复制默认配置文件
    cp ~/.oh-my-zsh/templates/zshrc.zsh-template ~/.zshrc

    # 配置 zsh
    config_zsh

    log_info "oh-my-zsh 安装完成"
}

change_ssh_port() {

    # 检查 /etc/ssh/sshd_config 文件是否存在
    if [ ! -f /etc/ssh/sshd_config ]; then
        log_error "/etc/ssh/sshd_config 文件不存在"
        exit 1
    fi

    if ask_user "修改 ssh 端口号" "修改 ssh 端口号"; then
        read -p "请输入新的 ssh 端口号（1024-65535）: " SSH_PORT
        if [[ ! "${SSH_PORT}" =~ ^[0-9]+$ ]] || [ "${SSH_PORT}" -lt 1024 ] || [ "${SSH_PORT}" -gt 65535 ]; then
            log_error "输入的端口号不在 1024-65535 范围内"
            exit 1
        fi

        local backup_file="/etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "备份配置文件到 ${backup_file}"
        cp /etc/ssh/sshd_config "${backup_file}"

        log_info "修改 ssh 端口号为 ${SSH_PORT}"
        sed -i "s/^#Port.*/Port ${SSH_PORT}/g" /etc/ssh/sshd_config
        sed -i "s/^Port.*/Port ${SSH_PORT}/g" /etc/ssh/sshd_config

        if ! sshd -t; then
            log_error "SSH 配置文件语法检查失败，正在还原配置..."
            cp "${backup_file}" /etc/ssh/sshd_config
            exit 1
        fi

        # 重启 ssh 服务
        log_info "重启 ssh 服务"
        if ! sudo systemctl restart sshd; then
            log_error "SSH 服务重启失败，正在还原配置..."
            cp "${backup_file}" /etc/ssh/sshd_config
            sudo systemctl restart sshd
            exit 1
        fi

        log_info "SSH 端口修改成功，请确保使用新端口 ${SSH_PORT} 连接"
        log_warn "建议保持当前连接，新开一个终端验证新端口是否可用"
    fi
}

# 新增防火墙配置函数
configure_firewall() {
    local port=$1

    case "${ID}" in
    "ubuntu" | "debian")
        # 检查 ufw 是否安装
        if ! command -v ufw >/dev/null; then
            log_warn "未检测到 ufw，正在安装..."
            sudo ${PM} install -y ufw
        fi
        sudo ufw allow "${port}"/tcp
        sudo ufw --force enable
        ;;
    "centos" | "fedora")
        # 检查 firewalld 是否安装
        if ! command -v firewall-cmd >/dev/null; then
            log_warn "未检测到 firewalld，正在安装..."
            sudo ${PM} install -y firewalld
            sudo systemctl enable firewalld
            sudo systemctl start firewalld
        fi
        sudo firewall-cmd --permanent --add-port="${port}"/tcp
        sudo firewall-cmd --reload
        ;;
    *)
        log_warn "未知的系统类型，请手动配置防火墙规则"
        ;;
    esac

    log_info "防火墙规则已添加"
}

run_script() {
    log_info "开始运行脚本..."
    detect_distribution

    # 更新系统
    update_system

    # VIM
    install_tool "vim" "强大的文本编辑器"
    [ -x "$(command -v vim)" ] && log_info "VIM 版本: $(vim --version | head -n 1)"

    # command-not-found
    install_tool "command-not-found" "当运行未安装的命令时，提供安装建议"

    # curl
    install_tool "curl" "命令行文件传输工具"
    [ -x "$(command -v curl)" ] && log_info "curl 版本: $(curl --version | head -n 1)"

    # git
    install_tool "git" "分布式版本控制系统"
    [ -x "$(command -v git)" ] && log_info "git 版本: $(git --version)"

    # zsh
    if install_tool "zsh" "功能强大的shell"; then
        if ask_user "oh-my-zsh" "zsh的配置框架，提供主题和插件支持"; then
            log_info "开始安装 oh-my-zsh..."
            install_oh_my_zsh
            log_info "oh-my-zsh 安装和配置完成"
        fi
    fi

    # 修改 ssh 端口号
    change_ssh_port
}

run_script
