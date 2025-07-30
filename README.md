
``` 
     ____   ____       _   _ ____   ____   _              _ 
    / ___| / ___|     | | | |  _ \ / ___| | |_ ___   ___ | |
    \___ \| |  _ _____| |_| | |_) | |     | __/ _ \ / _ \| |
     ___) | |_| |_____|  _  |  __/| |___  | || (_) | (_) | |
    |____/ \____|     |_| |_|_|    \____|  \__\___/ \___/|_|
```

<p align="left">
  <a href="https://www.gnu.org/licenses/gpl-3.0.html"><img src="https://shields.io/github/license/1Panel-dev/1Panel?color=%231890FF" alt="License: GPL v3"></a>
  <a href="https://github.com/zeisscai/SGHPC-tools"><img src="https://img.shields.io/badge/Version-1.4_beta-blue" alt="GitHub release"></a>
  <a href="https://docs.sg-hpc.com"><img src="https://img.shields.io/badge/%E4%BD%BF%E7%94%A8%E6%8C%87%E5%8D%97-8A2BE2" alt="SG-HPC docs"></a>
</p>


SG-HPC Tool 是一个专为高性能计算（HPC）领域设计的集群管理工具，基于 OpenHPC 仓库开发，旨在为用户提供高效、便捷的集群管理与计算体验。

> 本项目还处于早期开发阶段，目前可用功能：slurm集群部署（Rocky Linux 9.6）；


## 功能特性
- Slurm 集群部署：支持快速部署和配置 Slurm 工作负载管理器，简化高性能计算集群的搭建过程。
- 集群运行查询：提供实时集群状态监控与查询功能，帮助用户掌握计算资源的使用情况。
- 集群管理：集成强大的管理工具，支持节点管理、任务调度和资源分配，优化集群运行效率。
- 计算软件编译与安装：支持常用高性能计算软件的自动化编译与安装，降低环境配置的复杂性。

## slurm集群部署快速使用

配置 deploy.conf 文件，并修改成自己的配置，目前脚本最多5台节点，默认使用root账户:

```shell
[master]
ip = 192.168.11.201
password = password
hostname = master

[node1]
ip = 192.168.11.150
password = password
hostname = node1

[node2]
ip = 192.168.11.204
password = password
hostname = node2

```


在 root 用户或者 sudo 下使用：
```shell
    dnf install -y wget
    wget https://github.com/zeisscai/SGHPC-tools/raw/refs/heads/main/slurm/slurm_install-Rocky-9.6-1.4sh

    chmod a+x slurm_install-Rocky-9.6-1.2.sh
    # root
    sh slurm_install-Rocky-9.6-1.2.sh
```

在安装过程中，更换ustc软件源为可选，如果已经更换过，注意不要再次更换以免报错。如果脚本在一次运行无法完成，最好的办法是重新安装 Rocky Linux 9.6 系统后再运行脚本。


## 联系我们
如果有问题或建议，可发送邮件至

<a href="mailto:info@sg-hpc.com.cn"><img src="https://img.shields.io/badge/info%40sg--hpc.com.cn-blue" alt="email"></a>

