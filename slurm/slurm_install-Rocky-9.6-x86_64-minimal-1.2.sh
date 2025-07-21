#!/bin/bash
# Rocky Linux 9.6 Slurm 24.11.5 部署脚本
# 作者: SGHPC
# 版本: 1.3
# 描述: 通过OpenHPC库在Rocky Linux 9.6 minimal上部署Slurm 24.11.5
# 1.2更新：修复mariadb数据库配置逻辑以及配置时意外退出。
# 1.3更新：将数据库配置改为自动


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

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本必须以root用户身份运行"
        exit 1
    fi
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

# 修改软件源到中国科学技术大学源
setup_ustc_repo() {
    log_step "配置中国科学技术大学软件源"
    
    if [ -f "/etc/yum.repos.d/Rocky-ustc.repo" ] && [ -f "/etc/yum.repos.d/epel.repo" ]; then
        log_info "中国科学技术大学软件源及EPEL仓库已配置，跳过"
        return
    fi
    
    # 备份原始源文件
    if [ -d "/etc/yum.repos.d" ]; then
        cp -r /etc/yum.repos.d /etc/yum.repos.d.backup.$(date +%Y%m%d_%H%M%S)
        log_info "已备份原始源文件到 /etc/yum.repos.d.backup.*"
    fi
    
    # 禁用原有源
    sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/*.repo
    
    # 创建中国科学技术大学源配置
    cat > /etc/yum.repos.d/Rocky-ustc.repo << 'EOF'
[baseos]
name=Rocky Linux $releasever - BaseOS - ustc Mirror
baseurl=https://mirrors.ustc.edu.cn/rocky/$releasever/BaseOS/$basearch/os/
gpgcheck=1
enabled=1
countme=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9

[appstream]
name=Rocky Linux $releasever - AppStream - ustc Mirror
baseurl=https://mirrors.ustc.edu.cn/rocky/$releasever/AppStream/$basearch/os/
gpgcheck=1
enabled=1
countme=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9

[extras]
name=Rocky Linux $releasever - Extras - ustc Mirror
baseurl=https://mirrors.ustc.edu.cn/rocky/$releasever/extras/$basearch/os/
gpgcheck=1
enabled=1
countme=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9

[crb]
name=Rocky Linux $releasever - CRB - ustc Mirror
baseurl=https://mirrors.ustc.edu.cn/rocky/$releasever/CRB/$basearch/os/
gpgcheck=1
enabled=1
countme=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9
EOF

    # 配置EPEL仓库（中国科学技术大学镜像）
    cat > /etc/yum.repos.d/epel-ustc.repo << 'EOF'
[epel]
name=Extra Packages for Enterprise Linux $releasever - $basearch (ustc Mirror)
baseurl=https://mirrors.ustc.edu.cn/epel/$releasever/Everything/$basearch/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-9
EOF

    # 清理缓存并更新
    dnf clean all
    dnf makecache
    log_info "中国科学技术大学软件源配置完成"
}

# 主机名配置
setup_hostname() {
    log_step "配置主机名"
    
    current_hostname=$(hostname)
    log_info "当前主机名: $current_hostname"
    
    echo "请选择主机类型:"
    echo "1) 主节点 (master)"
    echo "2) 计算节点 (slave1)"
    echo "3) 计算节点 (slave2)"
    echo "4) 自定义主机名"
    
    while true; do
        read -p "请输入选择 (1-4): " choice
        case $choice in
            1)
                new_hostname="master"
                node_type="master"
                # 询问是否将master也作为计算节点
                if confirm "是否将master节点同时作为计算节点？"; then
                    master_as_compute="yes"
                    log_info "master节点将同时作为计算节点"
                else
                    master_as_compute="no"
                    log_info "master节点仅作为控制节点"
                fi
                break
                ;;
            2)
                new_hostname="slave1"
                node_type="compute"
                master_as_compute="no"
                break
                ;;
            3)
                new_hostname="slave2"
                node_type="compute"
                master_as_compute="no"
                break
                ;;
            4)
                read -p "请输入自定义主机名: " new_hostname
                echo "请选择节点类型:"
                echo "1) 主节点"
                echo "2) 计算节点"
                read -p "请输入选择 (1-2): " type_choice
                case $type_choice in
                    1) 
                        node_type="master"
                        if confirm "是否将master节点同时作为计算节点？"; then
                            master_as_compute="yes"
                            log_info "master节点将同时作为计算节点"
                        else
                            master_as_compute="no"
                            log_info "master节点仅作为控制节点"
                        fi
                        ;;
                    2) 
                        node_type="compute"
                        master_as_compute="no"
                        ;;
                    *) log_error "无效选择"; continue;;
                esac
                break
                ;;
            *)
                log_error "无效选择，请重新输入"
                ;;
        esac
    done
    
    if [[ "$current_hostname" == "$new_hostname" ]]; then
        log_info "主机名已经是 $new_hostname，跳过修改"
        return
    fi
    
    if confirm "确认将主机名修改为: $new_hostname?"; then
        hostnamectl set-hostname $new_hostname
        echo "127.0.0.1 $new_hostname" >> /etc/hosts
        log_info "主机名已修改为: $new_hostname"
        log_info "节点类型: $node_type"
    else
        log_warn "跳过主机名修改"
        node_type="master"  # 默认为master
        master_as_compute="no"  # 默认不作为计算节点
    fi
}


# 配置OpenHPC仓库
setup_openhpc_repo() {
    log_step "配置OpenHPC仓库"
    
    if [ -f "/etc/yum.repos.d/OpenHPC.repo" ]; then
        log_info "OpenHPC仓库已配置，跳过"
        return
    fi
    
    # 安装OpenHPC仓库
    dnf install -y http://repos.openhpc.community/OpenHPC/3/EL_9/x86_64/ohpc-release-3-1.el9.x86_64.rpm
    
    log_info "OpenHPC仓库配置完成"
}

# 安装Slurm相关包
install_slurm_packages() {
    log_step "安装Slurm相关软件包"
    
    if [[ "$node_type" == "master" ]]; then
        if [[ "$master_as_compute" == "yes" ]]; then
            log_info "安装主节点+计算节点Slurm包..."
            slurm_packages=(
                "ohpc-slurm-server"
                "slurm-ohpc"
                "slurm-devel-ohpc"
                "slurm-example-configs-ohpc"
                "slurm-slurmctld-ohpc"
                "slurm-slurmd-ohpc"
                "slurm-slurmdbd-ohpc"
                "mariadb-server"
                "mariadb"
            )
        else
            log_info "安装主节点Slurm包（仅控制节点）..."
            slurm_packages=(
                "ohpc-slurm-server"
                "slurm-ohpc"
                "slurm-devel-ohpc"
                "slurm-example-configs-ohpc"
                "slurm-slurmctld-ohpc"
                "slurm-slurmdbd-ohpc"
                "mariadb-server"
                "mariadb"
            )
        fi
    else
        log_info "安装计算节点Slurm包..."
        slurm_packages=(
            "ohpc-slurm-client"
            "slurm-ohpc"
            "slurm-slurmd-ohpc"
        )
    fi
    
    for pkg in "${slurm_packages[@]}"; do
        if dnf list installed "$pkg" &>/dev/null; then
            log_info "$pkg 已安装，跳过"
        else
            dnf install -y "$pkg"
        fi
    done
    
    log_info "Slurm软件包安装完成"
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
    if [[ "$node_type" != "master" ]]; then
        return 0
    fi
    
    log_step "配置MariaDB数据库"
    
    # 启动并启用MariaDB
    systemctl enable mariadb
    systemctl start mariadb
    
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
    
    # 应用默认安全配置
    mysql -u root << EOF
-- 设置root密码
ALTER USER 'root'@'localhost' IDENTIFIED BY '$mysql_root_pass';
-- 删除匿名用户
DELETE FROM mysql.user WHERE User='';
-- 禁止root远程登录
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
-- 删除test数据库
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
-- 重新加载权限表
FLUSH PRIVILEGES;
EOF
    
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
    
    # 检查数据库是否已存在
    db_exists=$(mysql -u root -p"$mysql_root_pass" -e "SHOW DATABASES LIKE 'slurm_acct_db'" 2>/dev/null | grep -c "slurm_acct_db")
    
    # 检查用户是否已存在
    user_exists=$(mysql -u root -p"$mysql_root_pass" -e "SELECT User FROM mysql.user WHERE User='slurm' AND Host='localhost'" 2>/dev/null | grep -c "slurm")
    
    if [ "$db_exists" -eq 0 ]; then
        mysql -u root -p"$mysql_root_pass" -e "CREATE DATABASE slurm_acct_db;" 2>/dev/null
        if [[ $? -eq 0 ]]; then
            log_info "已创建slurm_acct_db数据库"
        else
            log_error "创建数据库失败"
            exit 1
        fi
    else
        log_info "slurm_acct_db数据库已存在，跳过创建"
    fi
    
    if [ "$user_exists" -eq 0 ]; then
        mysql -u root -p"$mysql_root_pass" -e "CREATE USER 'slurm'@'localhost' IDENTIFIED BY '$slurm_db_pass';" 2>/dev/null
        if [[ $? -eq 0 ]]; then
            log_info "已创建slurm用户"
        else
            log_error "创建用户失败"
            exit 1
        fi
    else
        log_info "slurm用户已存在，跳过创建"
        # 更新现有用户的密码
        mysql -u root -p"$mysql_root_pass" -e "SET PASSWORD FOR 'slurm'@'localhost' = PASSWORD('$slurm_db_pass');" 2>/dev/null
        log_info "已更新slurm用户密码"
    fi
    
    # 无论是否新建，都确保权限正确
    mysql -u root -p"$mysql_root_pass" -e "GRANT ALL PRIVILEGES ON slurm_acct_db.* TO 'slurm'@'localhost';" 2>/dev/null
    mysql -u root -p"$mysql_root_pass" -e "FLUSH PRIVILEGES;" 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        log_info "数据库权限配置完成"
    else
        log_error "权限配置失败"
        exit 1
    fi
}

# 配置Slurm
configure_slurm() {
    log_step "配置Slurm"
    
    # 创建Slurm用户
    if ! id slurm &>/dev/null; then
        useradd -r -s /bin/false -d /var/lib/slurm slurm
        log_info "已创建slurm用户"
    else
        log_info "slurm用户已存在，跳过"
    fi
    
    # 创建必要目录
    mkdir -p /var/spool/slurm/ctld
    mkdir -p /var/spool/slurm/d
    mkdir -p /var/log/slurm
    
    chown slurm:slurm /var/spool/slurm/ctld
    chown slurm:slurm /var/spool/slurm/d
    chown slurm:slurm /var/log/slurm
    
    if [[ "$node_type" == "master" ]]; then
        # 主节点配置
        configure_master_slurm
    else
        # 计算节点配置
        configure_compute_slurm
    fi
}

# 配置主节点Slurm
configure_master_slurm() {
    log_info "配置主节点Slurm..."
    
    # 根据master是否作为计算节点生成不同的配置
    if [[ "$master_as_compute" == "yes" ]]; then
        # master作为计算节点的配置
        cat > /etc/slurm/slurm.conf << 'EOF'
# slurm.conf file generated by configurator.html.
ClusterName=cluster
ControlMachine=master
ControlAddr=master
#BackupController=
#BackupAddr=

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
NodeName=master CPUs=4 Sockets=1 CoresPerSocket=4 ThreadsPerCore=1 RealMemory=4000 State=UNKNOWN
NodeName=slave[1-2] CPUs=4 Sockets=1 CoresPerSocket=4 ThreadsPerCore=1 RealMemory=4000 State=UNKNOWN

# PARTITIONS
PartitionName=compute Nodes=master,slave[1-2] Default=YES MaxTime=INFINITE State=UP
EOF
    else
        # master仅作为控制节点的配置
        cat > /etc/slurm/slurm.conf << 'EOF'
# slurm.conf file generated by configurator.html.
ClusterName=cluster
ControlMachine=master
ControlAddr=master
#BackupController=
#BackupAddr=

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
NodeName=slave[1-2] CPUs=4 Sockets=1 CoresPerSocket=4 ThreadsPerCore=1 RealMemory=4000 State=UNKNOWN

# PARTITIONS
PartitionName=compute Nodes=slave[1-2] Default=YES MaxTime=INFINITE State=UP
EOF
    fi

    # 配置slurmdbd
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
    
    log_info "主节点Slurm配置完成"
}

# 配置计算节点Slurm
configure_compute_slurm() {
    log_info "配置计算节点Slurm..."
    
    log_warn "计算节点需要从主节点复制配置文件"
    echo "请在主节点配置完成后，手动复制以下文件到此节点:"
    echo "  - /etc/slurm/slurm.conf"
    echo "  - /etc/munge/munge.key"
    
    read -p "按回车键继续..."
}

# 配置Munge
setup_munge() {
    log_step "配置Munge认证"
    
    # 安装munge
    if ! dnf list installed munge &>/dev/null; then
        dnf install -y munge munge-libs munge-devel
    else
        log_info "munge 已安装，跳过"
    fi
    
    if [[ "$node_type" == "master" ]]; then
        # 主节点生成密钥
        if [ ! -f /etc/munge/munge.key ]; then
            /usr/sbin/create-munge-key -r
            log_info "已生成Munge密钥"
        else
            log_info "Munge密钥已存在，跳过"
        fi
        
        log_warn "请将 /etc/munge/munge.key 复制到所有计算节点的相同位置"
    else
        log_warn "请从主节点复制 /etc/munge/munge.key 到 /etc/munge/munge.key"
        read -p "复制完成后按回车键继续..."
    fi
    
    # 设置权限
    chown munge:munge /etc/munge/munge.key
    chmod 400 /etc/munge/munge.key
    
    # 启动munge服务
    systemctl enable munge
    systemctl start munge
    
    log_info "Munge配置完成"
}

# 启动Slurm服务
start_slurm_services() {
    log_step "启动Slurm服务"
    
    if [[ "$node_type" == "master" ]]; then
        # 主节点服务
        systemctl enable slurmdbd
        systemctl enable slurmctld
        
        systemctl start slurmdbd
        sleep 5
        systemctl start slurmctld
        
        # 根据配置决定是否启动slurmd
        if [[ "$master_as_compute" == "yes" ]]; then
            systemctl enable slurmd
            systemctl start slurmd
            log_info "主节点Slurm服务已启动（包含计算服务）"
        else
            log_info "主节点Slurm控制服务已启动"
        fi
    else
        # 计算节点服务
        systemctl enable slurmd
        systemctl start slurmd
        
        log_info "计算节点Slurm服务已启动"
    fi
}

# 配置防火墙
setup_firewall() {
    log_step "配置防火墙"
    
    if confirm "是否配置防火墙规则?"; then
        # 启动firewalld
        systemctl enable firewalld
        systemctl start firewalld
        
        # Slurm端口
        firewall-cmd --permanent --add-port=6817/tcp  # slurmctld
        firewall-cmd --permanent --add-port=6818/tcp  # slurmd
        firewall-cmd --permanent --add-port=6819/tcp  # slurmdbd
        
        # SSH端口
        firewall-cmd --permanent --add-service=ssh
        
        # Munge端口
        firewall-cmd --permanent --add-port=6866/tcp
        
        firewall-cmd --reload
        
        log_info "防火墙规则配置完成"
    else
        log_warn "跳过防火墙配置"
    fi
}

# 系统优化
system_optimization() {
    log_step "系统优化"
    
    # 时间同步
    systemctl enable chronyd
    systemctl start chronyd
    
    # 配置系统日志
    systemctl enable rsyslog
    systemctl start rsyslog
    
    # 设置系统限制
    if ! grep -q "Slurm limits" /etc/security/limits.conf; then
        cat >> /etc/security/limits.conf << 'EOF'
# Slurm limits
* soft nofile 65536
* hard nofile 65536
* soft nproc 65536
* hard nproc 65536
EOF
        log_info "系统限制已设置"
    else
        log_info "系统限制已配置，跳过"
    fi
    
    log_info "系统优化完成"
}

# 验证安装
verify_installation() {
    log_step "验证安装"
    
    # 检查服务状态
    echo "=== 服务状态 ==="
    systemctl status munge --no-pager -l
    
    if [[ "$node_type" == "master" ]]; then
        systemctl status slurmdbd --no-pager -l
        systemctl status slurmctld --no-pager -l
        
        if [[ "$master_as_compute" == "yes" ]]; then
            systemctl status slurmd --no-pager -l
        fi
    else
        systemctl status slurmd --no-pager -l
    fi
    
    # 检查Slurm命令
    echo -e "\n=== Slurm版本 ==="
    sinfo --version || log_warn "sinfo命令不可用"
    
    if [[ "$node_type" == "master" ]]; then
        echo -e "\n=== 集群信息 ==="
        sinfo || log_warn "无法获取集群信息，可能需要完成所有节点配置"
        
        echo -e "\n=== 节点信息 ==="
        scontrol show nodes || log_warn "无法获取节点信息"
    fi
    
    log_info "安装验证完成"
}

# 显示后续配置提示
show_post_install_info() {
    log_step "后续配置提示"
    
    echo -e "\n${GREEN}=== Slurm 24.11.5 安装完成 ===${NC}"
    echo
    
    if [[ "$node_type" == "master" ]]; then
        echo "主节点后续操作:"
        echo "1. 将 /etc/munge/munge.key 复制到所有计算节点"
        echo "2. 将 /etc/slurm/slurm.conf 复制到所有计算节点"
        echo "3. 根据实际硬件配置修改 /etc/slurm/slurm.conf 中的节点信息"
        echo "4. 确保所有节点的主机名解析正确 (/etc/hosts)"
        if [[ "$master_as_compute" == "yes" ]]; then
            echo "5. 在所有节点安装完成后运行: scontrol update nodename=ALL state=idle"
            echo "   注意：master节点已配置为计算节点"
        else
            echo "5. 在所有节点安装完成后运行: scontrol update nodename=slave[1-2] state=idle"
            echo "   注意：master节点仅作为控制节点，不参与计算"
        fi
    else
        echo "计算节点后续操作:"
        echo "1. 从主节点复制 /etc/munge/munge.key"
        echo "2. 从主节点复制 /etc/slurm/slurm.conf"
        echo "3. 确保主机名解析正确 (/etc/hosts)"
        echo "4. 重启munge和slurmd服务"
    fi
    
    echo
    echo "常用命令:"
    echo "  sinfo          - 查看集群信息"
    echo "  squeue         - 查看作业队列"
    echo "  sbatch script  - 提交作业脚本"
    echo "  scancel jobid  - 取消作业"
    echo "  scontrol show nodes - 查看节点详情"
    
    echo
    echo "配置文件位置:"
    echo "  /etc/slurm/slurm.conf     - Slurm主配置文件"
    echo "  /etc/slurm/slurmdbd.conf  - 数据库配置文件"
    echo "  /etc/munge/munge.key      - Munge认证密钥"
    
    echo
    echo "日志文件位置:"
    echo "  /var/log/slurm/slurmctld.log - 控制节点日志"
    echo "  /var/log/slurm/slurmd.log    - 计算节点日志"
    echo "  /var/log/slurm/slurmdbd.log  - 数据库日志"
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
    echo "    脚本版本: 1.3"
    echo "    安装教程: https://docs.sg-hpc.com/"
    echo "========================================================"
    echo -e "${NC}"
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
    
    # 初始化变量
    master_as_compute="no"
    
    # 执行安装步骤
    setup_ustc_repo
    setup_hostname
    setup_openhpc_repo
    install_slurm_packages
    setup_munge
    
    if [[ "$node_type" == "master" ]]; then
        setup_mariadb
    fi
    
    configure_slurm
    setup_firewall
    system_optimization
    start_slurm_services
    
    # 等待服务启动
    sleep 10
    
    verify_installation
    show_post_install_info
    
    log_info "Slurm 24.11.5 部署完成!"
}

# 执行主函数
main "$@"