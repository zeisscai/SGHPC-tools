#!/bin/bash

# 解压Gaussian压缩包到/home/user0/目录下
tar -xvf /home/user0/G16-A03-AVX2.tbz -C /home/user0/

# 建立临时文件夹/home/user0/g16/scratch
mkdir -p /home/user0/g16/scratch

# 在/home/user0/.bashrc中添加环境变量
echo "export g16root=/home/user0" >> /home/user0/.bashrc
echo "export GAUSS_SCRDIR=/home/user0/g16/scratch" >> /home/user0/.bashrc
echo "source /home/user0/g16/bsd/g16.profile" >> /home/user0/.bashrc

# 重新加载.bashrc文件
source /home/user0/.bashrc

# 创建Default.Route文件并设置默认计算资源
echo "-M- 60GB" > /home/user0/g16/Default.Route
echo "-P- 36" >> /home/user0/g16/Default.Route

# 修改权限
chmod 750 -R /home/user0/g16/