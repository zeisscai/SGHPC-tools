
``` 
     ____   ____       _   _ ____   ____   _              _ 
    / ___| / ___|     | | | |  _ \ / ___| | |_ ___   ___ | |
    \___ \| |  _ _____| |_| | |_) | |     | __/ _ \ / _ \| |
     ___) | |_| |_____|  _  |  __/| |___  | || (_) | (_) | |
    |____/ \____|     |_| |_|_|    \____|  \__\___/ \___/|_|
```

<p align="center">
  <a href="https://www.gnu.org/licenses/gpl-3.0.html"><img src="https://shields.io/github/license/1Panel-dev/1Panel?color=%231890FF" alt="License: GPL v3"></a>
  <a href="https://github.com/zeisscai/SGHPC-tools"><img src="https://img.shields.io/badge/Version-1.3_beta-blue
  " alt="GitHub release"></a>
  <a href="https://docs.sg-hpc.com
  "><img src="https://img.shields.io/badge/%E4%BD%BF%E7%94%A8%E6%8C%87%E5%8D%97-8A2BE2
  " alt="SG-HPC docs"></a>
</p>


SG-HPC Tool 是一个专为高性能计算（HPC）领域设计的集群管理工具，基于 OpenHPC 仓库开发，旨在为用户提供高效、便捷的集群管理与计算体验。

> 本项目还处于早期开发阶段，目前可用功能：slurm集群部署（Rocky Linux 9.6）；


## 功能特性
- Slurm 集群部署：支持快速部署和配置 Slurm 工作负载管理器，简化高性能计算集群的搭建过程。
- 集群运行查询：提供实时集群状态监控与查询功能，帮助用户掌握计算资源的使用情况。
- 集群管理：集成强大的管理工具，支持节点管理、任务调度和资源分配，优化集群运行效率。
- 计算软件编译与安装：支持常用高性能计算软件的自动化编译与安装，降低环境配置的复杂性。

## slurm集群部署快速使用

在 root 用户或者 sudo 下使用：
```shell
    dnf install -y wget
    wget https://github.com/zeisscai/SGHPC-tools/raw/refs/heads/main/slurm/slurm_install-Rocky-9.6-x86_64-minimal-1.2.sh
    chmod a+x slurm_install-Rocky-9.6-x86_64-minimal-1.2.sh
    # sudo
    sudo ./slurm_install-Rocky-9.6-x86_64-minimal-1.2.sh
    # root
    sh slurm_install-Rocky-9.6-x86_64-minimal-1.2.sh
```
安装完成后需要自行复制munge.key，修改slurm.conf，修改hosts文件。