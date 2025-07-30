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
            
            dnf install -y ohpc-slurm-server slurm-ohpc slurm-devel-ohpc slurm-example-configs-ohpc slurm-slurmctld-ohpc slurm-slurmdbd-ohpc slurm-slurmd-ohpc mariadb-server mariadb --skip-broken
            echo '主节点Slurm包安装完成'
            "
        else
            log_info "在 $node ($ip) 上安装计算节点Slurm包..."
            ssh root@"$ip" "
            # 先尝试安装依赖
            dnf install -y libjwt || true
            
            dnf install -y ohpc-slurm-client slurm-ohpc slurm-slurmd-ohpc --skip-broken
            echo '计算节点Slurm包安装完成'
            "
        fi
    done
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
    if ! systemctl is-active --quiet slurmctld; then
        echo '错误: slurmctld服务未运行'
        # 尝试启动服务
        systemctl start slurmctld 2>/dev/null || true
        if ! systemctl is-active --quiet slurmctld; then
            exit 1
        fi
    fi
    
    if ! systemctl is-active --quiet slurmdbd; then
        echo '错误: slurmdbd服务未运行'
        # 尝试启动服务
        systemctl start slurmdbd 2>/dev/null || true
        if ! systemctl is-active --quiet slurmdbd; then
            exit 1
        fi
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
        if ! systemctl is-active --quiet slurmd; then
            echo '错误: slurmd服务在 $node 节点未运行'
            # 尝试启动服务
            systemctl start slurmd 2>/dev/null || true
            if ! systemctl is-active --quiet slurmd; then
                # 再次尝试安装并启动
                dnf install -y slurm-slurmd-ohpc --skip-broken || true
                systemctl daemon-reload
                systemctl start slurmd 2>/dev/null || true
                if ! systemctl is-active --quiet slurmd; then
                    exit 1
                fi
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