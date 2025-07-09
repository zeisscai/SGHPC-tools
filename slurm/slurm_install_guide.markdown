# Rocky Linux 9.6 Slurm 24.11.5 安装指南

本指南详细说明如何在 Rocky Linux 9.6 最小化安装环境上部署 Slurm 24.11.5 集群管理系统。脚本通过 OpenHPC 仓库安装 Slurm，并优化了依赖配置，适用于主节点和计算节点。

## 前提条件

- **操作系统**：Rocky Linux 9.6 最小化安装（x86_64 架构）
- **权限**：需要 root 权限运行脚本
- **网络**：确保系统可以访问互联网以下载软件包
- **硬件**：至少一台主节点（master）和一台或多台计算节点（slave）

## 安装步骤

### 1. 安装 wget（若未安装）
脚本需要使用 `wget` 下载文件。如果系统未安装 `wget`，请先安装：

```bash
dnf install -y wget
```

### 2. 下载并运行安装脚本
执行以下命令下载并运行 Slurm 安装脚本：

```bash
wget https://github.com/zeisscai/SGHPC-tools/raw/refs/heads/main/slurm/slurm_install-Rocky-9.6-x86_64-minimal-2025_2.sh
chmod a+x slurm_install-Rocky-9.6-x86_64-minimal-2025_2.sh
sudo ./slurm_install-Rocky-9.6-x86_64-minimal-2025_2.sh
```

**注意**：
- 必须以 root 权限运行脚本（使用 `sudo` 或切换到 root 用户）。
- 如果网络不稳定，可多次尝试 `wget` 命令，或检查网络连接。

### 3. 脚本运行过程中的交互输入
脚本执行过程中会提示用户进行以下交互操作，请根据实际需求输入：

#### 3.1 确认开始部署
脚本开始时会询问是否继续部署：
```
确认开始Slurm部署? (y/n):
```
- 输入 `y` 确认开始，输入 `n` 将退出脚本。

#### 3.2 主机名配置
脚本会提示选择主机类型：
```
请选择主机类型:
1) 主节点 (master)
2) 计算节点 (slave1)
3) 计算节点 (slave2)
4) 自定义主机名
请输入选择 (1-4):
```
- 选择 `1`（主节点）、`2`（slave1）、`3`（slave2）或 `4`（自定义主机名）。
- 如果选择 `4`，需要进一步输入：
  - 自定义主机名，例如：`myhost`
  - 节点类型（1 为主节点，2 为计算节点）：
    ```
    请输入自定义主机名: myhost
    请选择节点类型:
    1) 主节点
    2) 计算节点
    请输入选择 (1-2): 1
    ```
- 确认主机名修改：
  ```
  确认将主机名修改为: myhost? (y/n):
  ```
  - 输入 `y` 确认修改，`n` 跳过。

#### 3.3 配置 MariaDB（仅主节点）
如果选择主节点，脚本会配置 MariaDB 数据库，并提示设置密码：
```
请为MariaDB root用户设置密码
```
- 按提示设置 MariaDB root 用户密码，按照 `mysql_secure_installation` 的交互式提示操作：
  - 输入当前 root 密码（初始为空，直接回车）。
  - 设置新 root 密码并确认。
  - 按需选择是否移除匿名用户、禁止远程 root 登录等（建议全选 `y`）。
- 随后输入 MariaDB root 密码和 Slurm 数据库用户密码：
  ```
  请输入MariaDB root密码: [输入之前设置的 root 密码]
  请设置slurm数据库用户密码: [输入 Slurm 用户密码]
  ```

#### 3.4 配置 Munge（计算节点）
对于计算节点，脚本会提示从主节点复制 Munge 密钥：
```
请从主节点复制 /etc/munge/munge.key 到 /etc/munge/munge.key
复制完成后按回车键继续...
```
- 在主节点上，复制密钥文件：
  ```bash
  scp /etc/munge/munge.key user@computenode:/etc/munge/munge.key
  ```
  - 替换 `user` 为计算节点的用户名，`computenode` 为计算节点的主机名或 IP。
- 在计算节点上，设置正确权限：
  ```bash
  chown munge:munge /etc/munge/munge.key
  chmod 400 /etc/munge/munge.key
  ```
- 按回车继续脚本执行。

#### 3.5 配置 Slurm（计算节点）
计算节点需要从主节点复制 Slurm 配置文件：
```
请在主节点配置完成后，手动复制以下文件到此节点:
  - /etc/slurm/slurm.conf
  - /etc/munge/munge.key
按回车键继续...
```
- 在主节点上，复制配置文件：
  ```bash
  scp /etc/slurm/slurm.conf user@computenode:/etc/slurm/slurm.conf
  scp /etc/munge/munge.key user@computenode:/etc/munge/munge.key
  ```
- 在计算节点上，设置正确权限：
  ```bash
  chown slurm:slurm /etc/slurm/slurm.conf
  chown munge:munge /etc/munge/munge.key
  chmod 400 /etc/munge/munge.key
  ```
- 按回车继续脚本执行。

#### 3.6 配置防火墙
脚本会询问是否配置防火墙规则：
```
是否配置防火墙规则? (y/n):
```
- 输入 `y` 配置 Slurm 和 Munge 所需的端口（6817/tcp, 6818/tcp, 6819/tcp, 6866/tcp 及 SSH）。
- 输入 `n` 跳过防火墙配置（如果手动管理防火墙或禁用）。

### 4. 后续配置
脚本完成后，会显示后续操作提示，确保集群正常运行：

#### 4.1 主节点后续操作
- **复制文件到计算节点**：
  ```bash
  scp /etc/munge/munge.key user@slave1:/etc/munge/munge.key
  scp /etc/munge/munge.key user@slave2:/etc/munge/munge.key
  scp /etc/slurm/slurm.conf user@slave1:/etc/slurm/slurm.conf
  scp /etc/slurm/slurm.conf user@slave2:/etc/slurm/slurm.conf
  ```
- **修改节点信息**：
  - 编辑 `/etc/slurm/slurm.conf`，根据实际硬件配置调整节点信息（例如 CPU 数量、内存等）。
  - 示例：`NodeName=slave1 CPUs=8 RealMemory=8000`
- **配置主机名解析**：
  - 编辑 `/etc/hosts`，添加所有节点的主机名和 IP，例如：
    ```
    192.168.1.10 master
    192.168.1.11 slave1
    192.168.1.12 slave2
    ```
- **设置节点状态**：
  - 所有节点配置完成后，在主节点运行：
    ```bash
    scontrol update nodename=ALL state=idle
    ```

#### 4.2 计算节点后续操作
- **确保文件已复制**：
  - 确认 `/etc/munge/munge.key` 和 `/etc/slurm/slurm.conf` 已从主节点复制。
- **配置主机名解析**：
  - 编辑 `/etc/hosts`，添加主节点和计算节点的主机名和 IP。
- **重启服务**：
  ```bash
  systemctl restart munge
  systemctl restart slurmd
  ```

### 5. 验证安装
脚本会自动验证安装，检查服务状态和 Slurm 命令：
- 查看服务状态：
  ```bash
  systemctl status munge
  systemctl status slurmd
  ```
  - 主节点额外检查：
    ```bash
    systemctl status slurmdbd
    systemctl status slurmctld
    ```
- 检查 Slurm 版本和集群信息：
  ```bash
  sinfo --version
  sinfo
  scontrol show nodes
  ```

### 6. 常用命令
- 查看集群信息：`sinfo`
- 查看作业队列：`squeue`
- 提交作业脚本：`sbatch script.sh`
- 取消作业：`scancel jobid`
- 查看节点详情：`scontrol show nodes`

### 7. 配置文件和日志
- **配置文件**：
  - `/etc/slurm/slurm.conf`：Slurm 主配置文件
  - `/etc/slurm/slurmdbd.conf`：数据库配置文件（主节点）
  - `/etc/munge/munge.key`：Munge 认证密钥
- **日志文件**：
  - `/var/log/slurm/slurmctld.log`：主节点控制日志
  - `/var/log/slurm/slurmd.log`：计算节点日志
  - `/var/log/slurm/slurmdbd.log`：数据库日志（主节点）

## 注意事项
- 确保所有节点时间同步（脚本已启用 `chronyd`）。
- 如果遇到依赖问题，检查网络连接或尝试重新运行 `dnf makecache`。
- 主节点和计算节点需在同一网络内，主机名解析需正确配置。
- 定期检查日志文件以排查问题。

通过以上步骤，您可以在 Rocky Linux 9.6 上成功部署 Slurm 24.11.5 集群。