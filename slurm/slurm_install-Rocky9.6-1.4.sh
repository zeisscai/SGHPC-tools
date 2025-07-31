#!/bin/bash
# Rocky Linux 9.6 Slurm 24.11.5 部署脚本
# 作者: SGHPC
# 版本: 1.4
# 描述: 通过OpenHPC库在Rocky Linux 9.6 minimal上部署Slurm 24.11.5
# 1.2更新：修复mariadb数据库配置逻辑以及配置时意外退出。
# 1.3更新：将数据库配置改为自动
# 1.4更新：自动化配置，最多5台节点


# -----------------------------------------------------------------
#set -e  # 遇到错误立即退出-修改

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

show_logo(){
    echo -e "${BLUE}"
    echo "========================================================"
    echo " ____   ____       _   _ ____   ____   _              _ "
    echo "/ ___| / ___|     | | | |  _ \ / ___| | |_ ___   ___ | |"
    echo "\___ \| |  _ _____| |_| | |_) | |     | __/ _ \ / _ \| |"
    echo " ___) | |_| |_____|  _  |  __/| |___  | || (_) | (_) | |"
    echo "|____/ \____|     |_| |_|_|    \____|  \__\___/ \___/|_|"   
    echo "    Rocky Linux 9.6 Slurm 24.11.5 部署脚本"
    echo "    脚本版本: 1.4"
    echo "    安装教程: https://docs.sg-hpc.com/"
    echo "========================================================"
    echo -e "${NC}"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本必须以root用户身份运行"
        exit 1
    fi
}

# 检查并安装sshpass
check_sshpass() {
    log_step "检查sshpass安装"
    
    if ! command -v sshpass &> /dev/null; then
        log_info "sshpass未安装，正在安装..."
        
        # 在本地安装sshpass
        dnf install -y epel-release
        dnf install -y sshpass
        
        if command -v sshpass &> /dev/null; then
            log_info "sshpass安装成功"
        else
            log_error "sshpass安装失败"
            exit 1
        fi
    else
        log_info "sshpass已安装"
    fi
}

install_base_packages(){
    log_step "安装基础软件包"

    for i in "${!nodes[@]}"; do
        node="${nodes[$i]}"
        ip="${node_ips[$i]}"
        
        ssh root@"$ip" "
        if ! dnf list installed epel-release &>/dev/null; then
            rpm --import https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-9
            dnf install -y https://mirrors.ustc.edu.cn/epel/epel-release-latest-9.noarch.rpm
        else 
            echo 'epel-release已安装'
        fi

        dnf config-manager --set-enabled crb
        packages=(
        "libjwt"
        "libjwt-devel"
        )
        for pkg in "${packages[@]}"; do
            if ! rpm -q "$pkg" &> /dev/null; then
                echo "正在安装 $pkg..."
                dnf install -y "$pkg"
            else
                echo "$pkg 已安装"
            fi
        done
        echo '基础依赖包安装完成'
        "
    done
}

# 确认函数
confirm() {
    while true; do
        read -p "$1 (y/n): " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "请输入 y 或 n";;
        esac
    done
}

# 添加清理函数，用于清除之前的安装残留
cleanup_previous_install() {
    log_step "清理之前的安装残留"
    
    master_ip="${node_ips[0]}"
    
    log_info "停止可能正在运行的Slurm服务"
    for i in "${!nodes[@]}"; do
        node="${nodes[$i]}"
        ip="${node_ips[$i]}"
        
        ssh root@"$ip" "
        # 停止Slurm服务
        systemctl stop slurmd 2>/dev/null
        systemctl disable slurmd 2>/dev/null
        
        if [ \"$node\" == \"master\" ]; then
            systemctl stop slurmctld slurmdbd 2>/dev/null
            systemctl disable slurmctld slurmdbd 2>/dev/null
        fi
        
        # 删除Slurm相关文件和目录
        rm -rf /var/spool/slurm
        rm -rf /var/log/slurm
        rm -f /etc/slurm/slurm.conf
        rm -f /etc/slurm/slurmdbd.conf
        rm -f /etc/slurm/cgroup.conf
        
        # 删除Slurm用户（如果存在）
        if id slurm &>/dev/null; then
            userdel -r slurm 2>/dev/null
        fi
        
        echo '已清理 $node 节点的Slurm残留'
        "
    done
    
    log_info "清理MariaDB残留"
    ssh root@"$master_ip" "
    # 停止MariaDB服务
    systemctl stop mariadb 2>/dev/null
    systemctl disable mariadb 2>/dev/null
    
    # 删除MariaDB数据目录
    rm -rf /var/lib/mysql/*
    
    # 重新初始化MariaDB
    mysql_install_db --user=mysql --datadir=/var/lib/mysql 2>/dev/null
    
    # 启动MariaDB服务
    systemctl start mariadb
    
    echo '已清理MariaDB残留'
    "
    
    # 等待MariaDB启动
    sleep 5
    
    log_info "清理Munge残留"
    for i in "${!nodes[@]}"; do
        node="${nodes[$i]}"
        ip="${node_ips[$i]}"
        
        ssh root@"$ip" "
        # 停止Munge服务
        systemctl stop munge 2>/dev/null
        systemctl disable munge 2>/dev/null
        
        # 删除Munge密钥
        rm -f /etc/munge/munge.key
        
        # 删除Munge用户（如果需要重新创建）
        if id munge &>/dev/null; then
            userdel -r munge 2>/dev/null
        fi
        
        echo '已清理 $node 节点的Munge残留'
        "
    done
    
    log_info "之前的安装残留清理完成"
}

# 解析配置文件
parse_config() {
    log_step "解析配置文件"
    
    local config_file="$(dirname "$(readlink -f "$0")")/deploy.conf"
    
    if [ ! -f "$config_file" ]; then
        log_error "配置文件 $config_file 不存在"
        exit 1
    fi
    
    # 初始化数组
    nodes=()
    node_ips=()
    node_passwords=()
    node_hostnames=()
    
    # 读取配置文件
    current_section=""
    master_ip=""
    master_password=""
    master_hostname=""
    
    while IFS= read -r line; do
        # 跳过空行和注释
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # 检查是否是节标题
        if [[ "$line" =~ ^\[(.+)\]$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            
            # 检查节标题是否有效
            if [[ "$current_section" != "master" ]] && [[ ! "$current_section" =~ ^node[0-9]+$ ]]; then
                log_error "无效的节标题: $current_section"
                exit 1
            fi
            
            # 检查节点数量
            if [[ "$current_section" =~ ^node[0-9]+$ ]]; then
                node_num=${current_section#node}
                if [ "$node_num" -gt 4 ]; then
                    log_error "节点编号不能超过4 (当前: $node_num)"
                    exit 1
                fi
            fi
            
            # 初始化节点信息
            declare "${current_section}_ip="
            declare "${current_section}_password="
            declare "${current_section}_hostname="
        elif [[ -n "$current_section" ]] && [[ "$line" =~ ^[[:space:]]*([^=]+)[[:space:]]*=[[:space:]]*(.*)[[:space:]]*$ ]]; then
            key="${BASH_REMATCH[1]// /}"
            value="${BASH_REMATCH[2]// /}"
            
            case "$key" in
                "ip") 
                    declare "${current_section}_ip=$value"
                    ;;
                "password") 
                    declare "${current_section}_password=$value"
                    ;;
                "hostname") 
                    declare "${current_section}_hostname=$value"
                    ;;
            esac
        fi
    done < "$config_file"
    
    # 验证配置
    if [ -z "${master_ip}" ]; then
        log_error "master节点的IP地址未配置"
        exit 1
    fi
    
    # 检查节点顺序
    for i in {1..4}; do
        prev_node_var="node$((i-1))_ip"
        curr_node_var="node${i}_ip"
        if [ -n "${!curr_node_var}" ] && [ -z "${!prev_node_var}" ] && [ $i -gt 1 ]; then
            log_error "节点配置顺序错误: node$((i-1)) 未配置但 node$i 已配置"
            exit 1
        fi
    done
    
    # 构建节点列表
    nodes=("master")
    node_ips=("$master_ip")
    node_passwords=("$master_password")
    node_hostnames=("$master_hostname")
    
    for i in {1..4}; do
        node_ip_var="node${i}_ip"
        node_password_var="node${i}_password"
        node_hostname_var="node${i}_hostname"
        
        if [ -n "${!node_ip_var}" ]; then
            nodes+=("node$i")
            node_ips+=("${!node_ip_var}")
            
            # 如果密码为空，使用master密码
            if [ -z "${!node_password_var}" ]; then
                node_passwords+=("$master_password")
            else
                node_passwords+=("${!node_password_var}")
            fi
            
            # 如果主机名为空，使用默认主机名
            if [ -z "${!node_hostname_var}" ]; then
                node_hostnames+=("node$i")
            else
                node_hostnames+=("${!node_hostname_var}")
            fi
        fi
    done
    
    # 检查节点总数
    if [ ${#nodes[@]} -gt 5 ]; then
        log_error "节点总数不能超过5台"
        exit 1
    fi
    
    log_info "配置文件解析完成，共发现 ${#nodes[@]} 个节点"
    for i in "${!nodes[@]}"; do
        log_info "  ${nodes[$i]}: ${node_ips[$i]} (${node_hostnames[$i]})"
    done
}

# 配置所有节点的hosts文件
configure_hosts() {
    log_step "配置所有节点的hosts文件"
    
    # 在所有节点上添加hosts条目
    for i in "${!nodes[@]}"; do
        node="${nodes[$i]}"
        ip="${node_ips[$i]}"
        hostname="${node_hostnames[$i]}"
        
        log_info "在 $node ($ip) 上配置hosts文件"
        
        # 构建hosts条目
        hosts_entries=""
        for j in "${!nodes[@]}"; do
            hosts_entries+="${node_ips[$j]} ${node_hostnames[$j]}\n"
        done
        
        # 更新hosts文件
        ssh root@"$ip" "
        # 备份原始hosts文件
        cp /etc/hosts /etc/hosts.backup
        
        # 删除之前可能添加的条目（如果有标记）
        sed -i '/# Added by Slurm installation script/d' /etc/hosts
        
        # 添加新的条目
        echo -e '$hosts_entries# Added by Slurm installation script' >> /etc/hosts
        
        echo '已更新 $node 节点的hosts文件'
        "
    done
    
    log_info "所有节点的hosts文件配置完成"
}

# SSH基础配置
setup_ssh() {
    log_step "配置SSH免密登录"
    
    # 生成SSH密钥对（如不存在）
    if [ ! -f ~/.ssh/id_rsa ]; then
        ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
        log_info "已生成SSH密钥对"
    else
        log_info "SSH密钥对已存在，跳过生成"
    fi
    
    # 配置所有节点免密登录
    for i in "${!nodes[@]}"; do
        node="${nodes[$i]}"
        ip="${node_ips[$i]}"
        password="${node_passwords[$i]}"
        
        log_info "配置 $node ($ip) 的SSH免密登录"
        
        # 使用sshpass配置免密登录
        sshpass -p "$password" ssh-copy-id -o StrictHostKeyChecking=no root@"$ip"
        
        if [ $? -eq 0 ]; then
            log_info "已配置 $node 的SSH免密登录"
        else
            log_error "配置 $node 的SSH免密登录失败"
            exit 1
        fi
    done
}

# 设置主机名
setup_hostnames() {
    log_step "设置主机名"
    
    for i in "${!nodes[@]}"; do
        node="${nodes[$i]}"
        ip="${node_ips[$i]}"
        hostname="${node_hostnames[$i]}"
        
        log_info "设置 $node ($ip) 的主机名为 $hostname"
        
        ssh root@"$ip" "hostnamectl set-hostname $hostname"
        
        if [ $? -eq 0 ]; then
            log_info "已设置 $node 的主机名为 $hostname"
        else
            log_error "设置 $node 的主机名失败"
            exit 1
        fi
    done
}

# 修改软件源到中国科学技术大学源
setup_ustc_repo() {
    log_step "配置中国科学技术大学软件源"
    
    for i in "${!nodes[@]}"; do
        node="${nodes[$i]}"
        ip="${node_ips[$i]}"
        
        log_info "在 $node ($ip) 上配置中国科学技术大学软件源"
        
        ssh root@"$ip" "
        # 检查是否已经配置过USTC源
        if [ -f "/etc/yum.repos.d/Rocky-ustc.repo" ] && [ -f "/etc/yum.repos.d/epel-ustc.repo" ]; then
            echo '中国科学技术大学软件源及EPEL仓库已配置，跳过'
            exit 0
        fi
        
        # 备份原始源文件
        if [ -d "/etc/yum.repos.d" ]; then
            # 创建备份目录（如果不存在）
            mkdir -p /etc/yum.repos.d.backup
            # 备份所有repo文件
            if ls /etc/yum.repos.d/*.repo 1> /dev/null 2>&1; then
                cp /etc/yum.repos.d/*.repo /etc/yum.repos.d.backup/ 2>/dev/null || true
            fi
            echo '已备份原始源文件到 /etc/yum.repos.d.backup/'
        fi
        
        # 删除现有的repo文件以避免重复
        rm -f /etc/yum.repos.d/Rocky-*.repo
        rm -f /etc/yum.repos.d/epel*.repo
        rm -f /etc/yum.repos.d/CentOS-*.repo
        
        # 创建中国科学技术大学源配置
        cat > /etc/yum.repos.d/Rocky-ustc.repo << 'EOF_REPO'
[baseos]
name=Rocky Linux \$releasever - BaseOS - ustc Mirror
baseurl=https://mirrors.ustc.edu.cn/rocky/\$releasever/BaseOS/\$basearch/os/
gpgcheck=1
enabled=1
countme=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9

[appstream]
name=Rocky Linux \$releasever - AppStream - ustc Mirror
baseurl=https://mirrors.ustc.edu.cn/rocky/\$releasever/AppStream/\$basearch/os/
gpgcheck=1
enabled=1
countme=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9

[extras]
name=Rocky Linux \$releasever - Extras - ustc Mirror
baseurl=https://mirrors.ustc.edu.cn/rocky/\$releasever/extras/\$basearch/os/
gpgcheck=1
enabled=1
countme=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9

[crb]
name=Rocky Linux \$releasever - CRB - ustc Mirror
baseurl=https://mirrors.ustc.edu.cn/rocky/\$releasever/CRB/\$basearch/os/
gpgcheck=1
enabled=1
countme=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9
EOF_REPO

        # 配置EPEL仓库（中国科学技术大学镜像）
        cat > /etc/yum.repos.d/epel-ustc.repo << 'EOF_EPEL'
[epel]
name=Extra Packages for Enterprise Linux \$releasever - \$basearch (ustc Mirror)
baseurl=https://mirrors.ustc.edu.cn/epel/\$releasever/Everything/\$basearch/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-9
EOF_EPEL

        # 清理缓存并更新
        dnf clean all
        dnf makecache
        echo '中国科学技术大学软件源配置完成'
        "
    done
}

# 配置OpenHPC仓库
setup_openhpc_repo() {
    log_step "配置OpenHPC仓库"
    
    for i in "${!nodes[@]}"; do
        node="${nodes[$i]}"
        ip="${node_ips[$i]}"
        
        log_info "在 $node ($ip) 上配置OpenHPC仓库"
        
        ssh root@"$ip" "
        if [ -f "/etc/yum.repos.d/OpenHPC.repo" ]; then
            echo 'OpenHPC仓库已配置，跳过'
            exit 0
        fi
        
        # 安装OpenHPC仓库
        dnf install -y http://repos.openhpc.community/OpenHPC/3/EL_9/x86_64/ohpc-release-3-1.el9.x86_64.rpm
        
        echo 'OpenHPC仓库配置完成'
        "
    done
}

# 安装Slurm相关包
install_slurm_packages() {
    log_step "安装Slurm相关软件包"
    
    for i in "${!nodes[@]}"; do
        node="${nodes[$i]}"
        ip="${node_ips[$i]}"
        
        if [ "$node" == "master" ]; then
            log_info "在 $node ($ip) 上安装主节点Slurm包..."
            ssh root@"$ip" "
            # 先尝试安装依赖
            dnf install -y libjwt || true
            
            dnf install -y ohpc-slurm-server slurm-ohpc slurm-devel-ohpc slurm-example-configs-ohpc slurm-slurmctld-ohpc slurm-slurmdbd-ohpc slurm-slurmd-ohpc mariadb-server mariadb
            echo '主节点Slurm包安装完成'
            "
        else
            log_info "在 $node ($ip) 上安装计算节点Slurm包..."
            ssh root@"$ip" "
            # 先尝试安装依赖
            dnf install -y libjwt || true
            
            dnf install -y ohpc-slurm-client slurm-ohpc slurm-slurmd-ohpc
            echo '计算节点Slurm包安装完成'
            "
        fi
    done
}

# 生成随机密码函数
generate_random_password() {
    local length=${1:-16}
    # 生成包含大小写字母、数字和特殊字符的随机密码
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-${length}
}

# 保存密码到文件
save_passwords_to_file() {
    local script_dir=$(dirname "$(readlink -f "$0")")
    local password_file="${script_dir}/slurm_passwords.txt"
    
    cat > "$password_file" << EOF
# Slurm数据库密码文件
# 生成时间: $(date)
# 主机名: $(hostname)

MYSQL_ROOT_PASSWORD=${mysql_root_pass}
SLURM_DB_PASSWORD=${slurm_db_pass}
EOF

    chmod 600 "$password_file"
    log_info "密码已保存到文件: $password_file"
}

# 配置MariaDB (仅主节点) - 修改版
setup_mariadb() {
    log_step "配置MariaDB数据库"
    
    # 获取master节点IP
    master_ip="${node_ips[0]}"
    
    # 启动并启用MariaDB
    ssh root@"$master_ip" "
    systemctl enable mariadb
    systemctl start mariadb
    "
    
    # 等待MariaDB服务启动
    sleep 5
    
    # 检查MariaDB是否正确安装和运行
    ssh root@"$master_ip" "
    if ! command -v mysql &> /dev/null; then
        echo 'MySQL命令未找到，尝试重新安装mariadb-server'
        dnf install -y mariadb-server mariadb
        systemctl start mariadb
        sleep 5
    fi
    
    # 再次检查mysql命令是否存在
    if ! command -v mysql &> /dev/null; then
        echo '错误：MySQL命令仍未找到，安装可能失败'
        exit 1
    fi
    
    # 检查服务状态
    if ! systemctl is-active --quiet mariadb; then
        echo '错误：MariaDB服务未运行'
        exit 1
    fi
    "
    
    # 自动生成密码
    mysql_root_pass=$(generate_random_password 20)
    slurm_db_pass=$(generate_random_password 20)
    
    log_info "已生成MariaDB root密码: $mysql_root_pass"
    log_info "已生成Slurm数据库用户密码: $slurm_db_pass"
    
    # 应用默认安全配置
    setup_mariadb_default
    
    # 创建Slurm数据库和用户
    create_slurm_database
    
    # 保存密码到文件
    save_passwords_to_file
    
    log_info "MariaDB配置完成"
}

# 默认MariaDB配置 - 修改版
setup_mariadb_default() {
    log_info "使用自动生成的安全配置..."
    
    master_ip="${node_ips[0]}"
    
    # 应用默认安全配置
    ssh root@"$master_ip" "
    mysql -u root << EOF
-- 设置root密码
ALTER USER 'root'@'localhost' IDENTIFIED BY '$mysql_root_pass';
-- 删除匿名用户
DELETE FROM mysql.user WHERE User='';
-- 禁止root远程登录
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
-- 删除test数据库
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\\\_%';
-- 重新加载权限表
FLUSH PRIVILEGES;
EOF
    "
    
    if [[ $? -eq 0 ]]; then
        log_info "MariaDB默认安全配置完成"
        log_info "- 已设置root密码"
        log_info "- 已删除匿名用户"
        log_info "- 已禁止root远程登录"
        log_info "- 已删除test数据库"
        log_info "- 已重新加载权限表"
    else
        log_error "MariaDB默认配置失败"
        exit 1
    fi
}

# 创建Slurm数据库和用户 - 修改版
create_slurm_database() {
    log_info "创建Slurm数据库和用户..."
    
    master_ip="${node_ips[0]}"
    
    ssh root@"$master_ip" "
    # 检查数据库是否已存在
    db_exists=\$(mysql -u root -p\"$mysql_root_pass\" -e \"SHOW DATABASES LIKE 'slurm_acct_db'\" 2>/dev/null | grep -c \"slurm_acct_db\")
    
    # 检查用户是否已存在
    user_exists=\$(mysql -u root -p\"$mysql_root_pass\" -e \"SELECT User FROM mysql.user WHERE User='slurm' AND Host='localhost'\" 2>/dev/null | grep -c \"slurm\")
    
    if [ \"\$db_exists\" -eq 0 ]; then
        mysql -u root -p\"$mysql_root_pass\" -e \"CREATE DATABASE slurm_acct_db;\" 2>/dev/null
        if [[ \$? -eq 0 ]]; then
            echo '已创建slurm_acct_db数据库'
        else
            echo '创建数据库失败'
            exit 1
        fi
    else
        echo 'slurm_acct_db数据库已存在，跳过创建'
    fi
    
    if [ \"\$user_exists\" -eq 0 ]; then
        mysql -u root -p\"$mysql_root_pass\" -e \"CREATE USER 'slurm'@'localhost' IDENTIFIED BY '$slurm_db_pass';\" 2>/dev/null
        if [[ \$? -eq 0 ]]; then
            echo '已创建slurm用户'
        else
            echo '创建用户失败'
            exit 1
        fi
    else
        echo 'slurm用户已存在，跳过创建'
        # 更新现有用户的密码
        mysql -u root -p\"$mysql_root_pass\" -e \"SET PASSWORD FOR 'slurm'@'localhost' = PASSWORD('$slurm_db_pass');\" 2>/dev/null
        echo '已更新slurm用户密码'
    fi
    
    # 无论是否新建，都确保权限正确
    mysql -u root -p\"$mysql_root_pass\" -e \"GRANT ALL PRIVILEGES ON slurm_acct_db.* TO 'slurm'@'localhost';\" 2>/dev/null
    mysql -u root -p\"$mysql_root_pass\" -e \"FLUSH PRIVILEGES;\" 2>/dev/null
    
    if [[ \$? -eq 0 ]]; then
        echo '数据库权限配置完成'
    else
        echo '权限配置失败'
        exit 1
    fi
    "
}

# 配置Munge
setup_munge() {
    log_step "配置Munge认证"
    
    # 在所有节点安装munge
    for i in "${!nodes[@]}"; do
        node="${nodes[$i]}"
        ip="${node_ips[$i]}"
        
        ssh root@"$ip" "
        if ! dnf list installed munge &>/dev/null; then
            dnf install -y munge munge-libs munge-devel
            echo 'munge 已安装'
        else
            echo 'munge 已安装，跳过'
        fi
        
        # 确保munge用户存在
        if ! id munge &>/dev/null; then
            useradd -r -s /usr/sbin/nologin munge
            echo '已创建munge用户'
        fi
        "
    done
    
    # 在master节点生成密钥
    master_ip="${node_ips[0]}"
    ssh root@"$master_ip" "
    if [ ! -f /etc/munge/munge.key ]; then
        /usr/sbin/create-munge-key -r
        echo '已生成Munge密钥'
    else
        echo 'Munge密钥已存在，跳过'
    fi
    "
    
    # 将密钥分发到所有节点
    log_info "分发Munge密钥到所有节点"
    for i in "${!nodes[@]}"; do
        node="${nodes[$i]}"
        ip="${node_ips[$i]}"
        
        if [ "$node" != "master" ]; then
            scp root@"$master_ip":/etc/munge/munge.key root@"$ip":/etc/munge/munge.key
            ssh root@"$ip" "chown munge:munge /etc/munge/munge.key && chmod 400 /etc/munge/munge.key"
            log_info "已将Munge密钥分发到 $node"
        else
            ssh root@"$ip" "chown munge:munge /etc/munge/munge.key && chmod 400 /etc/munge/munge.key"
            log_info "已设置 $node 上的Munge密钥权限"
        fi
    done
    
    # 启动munge服务
    for i in "${!nodes[@]}"; do
        node="${nodes[$i]}"
        ip="${node_ips[$i]}"
        
        ssh root@"$ip" "
        # 确保munge用户存在后再启动服务
        if ! id munge &>/dev/null; then
            useradd -r -s /usr/sbin/nologin munge
        fi
        
        systemctl enable munge
        systemctl start munge
        echo 'Munge服务已启动'
        "
    done
    
    log_info "Munge配置完成"
}

# 获取节点硬件信息
get_node_hardware_info() {
    log_step "获取节点硬件信息"
    
    # 初始化硬件信息数组
    node_cpus=()
    node_memory=()
    
    for i in "${!nodes[@]}"; do
        node="${nodes[$i]}"
        ip="${node_ips[$i]}"
        
        # 获取CPU核心数
        cpu_count=$(ssh root@"$ip" "nproc")
        
        # 获取内存大小(MB)
        memory_mb=$(ssh root@"$ip" "free -m | grep '^Mem:' | awk '{print \$2}'")
        
        node_cpus+=("$cpu_count")
        node_memory+=("$memory_mb")
        
        log_info "$node: $cpu_count CPU核心, ${memory_mb}MB 内存"
    done
}

# 配置Slurm
configure_slurm() {
    log_step "配置Slurm"
    
    # 获取硬件信息
    get_node_hardware_info
    
    # 在所有节点创建Slurm用户和目录
    for i in "${!nodes[@]}"; do
        node="${nodes[$i]}"
        ip="${node_ips[$i]}"
        
        ssh root@"$ip" "
        # 创建Slurm用户
        if ! id slurm &>/dev/null; then
            useradd -r -s /bin/false -d /var/lib/slurm slurm
            echo '已创建slurm用户'
        else
            echo 'slurm用户已存在，跳过'
        fi
        
        # 创建必要目录
        mkdir -p /var/spool/slurm/ctld
        mkdir -p /var/spool/slurm/d
        mkdir -p /var/log/slurm
        mkdir -p /etc/slurm  # 添加这行确保配置目录存在
        
        chown slurm:slurm /var/spool/slurm/ctld
        chown slurm:slurm /var/spool/slurm/d
        chown slurm:slurm /var/log/slurm
        "
    done
    
    # 在master节点生成配置文件
    master_ip="${node_ips[0]}"
    master_hostname="${node_hostnames[0]}"
    
    # 构建节点配置部分
    node_configs=""
    partition_nodes=""
    
    for i in "${!nodes[@]}"; do
        node="${nodes[$i]}"
        hostname="${node_hostnames[$i]}"
        cpus="${node_cpus[$i]}"
        memory="${node_memory[$i]}"
        
        # 保留90%的内存给Slurm使用
        slurm_memory=$((memory * 90 / 100))
        
        node_configs+="NodeName=$hostname CPUs=$cpus RealMemory=$slurm_memory State=UNKNOWN\n"
        if [ -n "$partition_nodes" ]; then
            partition_nodes+=",$hostname"
        else
            partition_nodes="$hostname"
        fi
    done
    
    # 生成slurm.conf
    ssh root@"$master_ip" "
    cat > /etc/slurm/slurm.conf << 'EOF'
# slurm.conf file generated by automated script
ClusterName=cluster
ControlMachine=$master_hostname
ControlAddr=$master_hostname

SlurmUser=slurm
SlurmdUser=root
SlurmctldPort=6817
SlurmdPort=6818
AuthType=auth/munge
StateSaveLocation=/var/spool/slurm/ctld
SlurmdSpoolDir=/var/spool/slurm/d
SwitchType=switch/none
MpiDefault=none
SlurmctldPidFile=/var/run/slurm/slurmctld.pid
SlurmdPidFile=/var/run/slurm/slurmd.pid
ProctrackType=proctrack/pgid
ReturnToService=1
SlurmctldTimeout=120
SlurmdTimeout=300
InactiveLimit=0
MinJobAge=300
KillWait=30
MaxJobCount=10000
Waittime=0

# SCHEDULING
SchedulerType=sched/backfill
SelectType=select/cons_tres
SelectTypeParameters=CR_Core

# LOGGING AND ACCOUNTING
AccountingStorageType=accounting_storage/slurmdbd
AccountingStoreFlags=job_comment
JobCompType=jobcomp/none
JobAcctGatherFrequency=30
JobAcctGatherType=jobacct_gather/linux
SlurmctldDebug=info
SlurmctldLogFile=/var/log/slurm/slurmctld.log
SlurmdDebug=info
SlurmdLogFile=/var/log/slurm/slurmd.log

# NODES
$(echo -e "$node_configs")

# PARTITIONS
PartitionName=compute Nodes=$partition_nodes Default=YES MaxTime=INFINITE State=UP
EOF
    "
    
    # 生成slurmdbd.conf
    ssh root@"$master_ip" "
    cat > /etc/slurm/slurmdbd.conf << EOF
AuthType=auth/munge
AuthInfo=/var/run/munge/munge.socket.2
DbdAddr=localhost
DbdHost=localhost
SlurmUser=slurm
DebugLevel=verbose
LogFile=/var/log/slurm/slurmdbd.log
PidFile=/var/run/slurm/slurmdbd.pid
StorageType=accounting_storage/mysql
StorageHost=localhost
StoragePass=$slurm_db_pass
StorageUser=slurm
StorageLoc=slurm_acct_db
EOF
    
    chmod 600 /etc/slurm/slurmdbd.conf
    chown slurm:slurm /etc/slurm/slurmdbd.conf
    "
    
    # 将配置文件分发到所有计算节点
    for i in "${!nodes[@]}"; do
        node="${nodes[$i]}"
        ip="${node_ips[$i]}"
        hostname="${node_hostnames[$i]}"
        
        if [ "$node" != "master" ]; then
            # 确保目标节点上的目录存在后再分发配置文件
            ssh root@"$ip" "mkdir -p /etc/slurm"
            scp root@"$master_ip":/etc/slurm/slurm.conf root@"$ip":/etc/slurm/slurm.conf
            log_info "已将slurm.conf分发到 $node"
        fi
    done
    
    log_info "Slurm配置完成"
}

# 启动Slurm服务
start_slurm_services() {
    log_step "启动Slurm服务"
    
    # 在master节点启动服务
    master_ip="${node_ips[0]}"
    ssh root@"$master_ip" "
    systemctl enable slurmdbd
    systemctl enable slurmctld
    
    systemctl start slurmdbd
    sleep 5
    systemctl start slurmctld
    
    echo '主节点Slurm服务已启动'
    "
    
    # 在所有节点启动slurmd服务
    for i in "${!nodes[@]}"; do
        node="${nodes[$i]}"
        ip="${node_ips[$i]}"
        
        ssh root@"$ip" "
        systemctl enable slurmd
        systemctl start slurmd
        echo '$node 节点Slurm服务已启动'
        "
    done
    
    log_info "所有Slurm服务已启动"
}

# 验证安装
verify_installation() {
    log_step "验证安装"
    
    master_ip="${node_ips[0]}"
    
    # 检查slurm命令是否存在
    log_info "检查Slurm命令是否存在"
    ssh root@"$master_ip" "
    if ! command -v sinfo &> /dev/null; then
        # 尝试安装slurm包来修复命令
        dnf install -y slurm-ohpc --skip-broken || true
    fi
    
    if ! command -v sinfo &> /dev/null; then
        echo '错误: sinfo命令未找到'
        exit 1
    fi
    
    if ! command -v sbatch &> /dev/null; then
        echo '错误: sbatch命令未找到'
        exit 1
    fi
    
    if ! command -v squeue &> /dev/null; then
        echo '错误: squeue命令未找到'
        exit 1
    fi
    
    if ! command -v scontrol &> /dev/null; then
        echo '错误: scontrol命令未找到'
        exit 1
    fi
    "
    
    if [ $? -ne 0 ]; then
        log_error "Slurm命令未正确安装"
        exit 1
    fi
    
    # 检查服务状态
    log_info "检查Slurm服务状态"
    ssh root@"$master_ip" "
    if ! systemctl is-active --quiet slurmctld-ohpc; then
        echo '错误: slurmctld服务未运行'
        exit 1
    fi
    
    if ! systemctl is-active --quiet slurmdbd-ohpc; then
        echo '错误: slurmdbd服务未运行'
        exit 1
    fi
    "
    
    if [ $? -ne 0 ]; then
        log_error "Slurm服务未正确运行"
        exit 1
    fi
    
    # 在所有节点检查slurmd服务
    for i in "${!nodes[@]}"; do
        node="${nodes[$i]}"
        ip="${node_ips[$i]}"
        
        ssh root@"$ip" "
        if ! systemctl is-active --quiet slurmd-ohpc; then
            echo '错误: slurmd服务在 $node 节点未运行'
            # 尝试启动服务
            systemctl start slurmd-ohpc 2>/dev/null || true
            if ! systemctl is-active --quiet slurmd-ohpc; then
                exit 1
            fi
        fi
        "
    done
    
    # 等待服务完全启动
    log_info "等待服务启动"
    sleep 15
    
    # 检查节点状态
    log_info "检查集群节点状态"
    ssh root@"$master_ip" "
    node_status=\$(sinfo -h -o '%T' | head -1)
    if [[ -z \"\$node_status\" ]]; then
        echo '错误: 无法获取节点状态'
        exit 1
    fi
    echo '集群节点状态: \$node_status'
    "
    
    if [ $? -ne 0 ]; then
        log_error "无法获取集群节点状态"
        exit 1
    fi
    
    # 测试作业提交
    log_info "测试作业提交"
    ssh root@"$master_ip" "
    echo '#!/bin/bash' > test_job.sh
    echo '#SBATCH --job-name=test' >> test_job.sh
    echo '#SBATCH --output=test.out' >> test_job.sh
    echo '#SBATCH --error=test.err' >> test_job.sh
    echo '#SBATCH --ntasks=1' >> test_job.sh
    echo 'srun hostname' >> test_job.sh
    
    job_id=\$(sbatch test_job.sh 2>&1 | grep -o '[0-9]*')
    
    if [[ -z \"\$job_id\" ]]; then
        echo '错误: 作业提交失败'
        exit 1
    fi
    
    echo '作业提交成功，作业ID: \$job_id'
    
    # 等待作业完成
    sleep 10
    
    # 检查作业状态
    job_state=\$(squeue -j \$job_id -h -o '%T' 2>/dev/null)
    if [[ -n \"\$job_state\" ]]; then
        echo '作业仍在队列中，状态: \$job_state'
    else
        echo '作业已完成或不存在于队列中'
    fi
    
    # 显示节点详情
    echo '=== 节点详情 ==='
    scontrol show nodes || echo '警告: 无法获取节点详情'
    "
    
    if [ $? -ne 0 ]; then
        log_error "验证测试失败"
        exit 1
    fi
    
    log_info "安装验证完成"
}



# 主函数
main() {
    
    show_logo
    # 检查root权限
    check_root
    
    # 确认开始安装
    if ! confirm "确认开始Slurm部署?"; then
        log_info "部署已取消"
        exit 0
    fi
    
    # 检查sshpass安装
    check_sshpass
    
    # 解析配置文件
    parse_config
    
    # 询问是否清理之前的安装
    if confirm "是否清理之前的安装残留? (推荐用于重复安装)"; then
        cleanup_previous_install
    fi
    
    # 询问是否配置USTC软件源
    if confirm "是否配置USTC软件源? (推荐用于国内网络环境)"; then
        setup_ustc_repo
    else
        log_info "跳过USTC软件源配置"
    fi
    
    # 配置OpenHPC仓库
    setup_openhpc_repo
    
    # 安装基础软件包
    install_base_packages
    
    # 安装Slurm相关包
    install_slurm_packages
    
    # 配置Munge
    setup_munge
    
    # 配置所有节点的hosts文件
    configure_hosts
    
    # 配置MariaDB
    setup_mariadb
    
    # 配置Slurm
    configure_slurm
    
    # 启动Slurm服务
    start_slurm_services
    
    # 验证安装
    verify_installation
    
    log_info "Slurm 24.11.5 部署完成!"
}

# 执行主函数
main "$@"