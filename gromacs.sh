#!/bin/bash

# 检查操作系统版本和内核版本
os_version=$(cat /etc/os-release | grep "PRETTY_NAME" | cut -d "=" -f 2)
kernel_version=$(uname -r)
echo "----checking the operating system version and kernel version----"
echo "Operating System Version: $os_version"
echo "Kernel Version: $kernel_version"

# 检查依赖项是否安装
dependencies=("tar" "wget" "bzip2" "gcc" "g++" "perl" "cmake")
echo ""
echo "----Checking if dependencies are installed----"
for dependency in ${dependencies[@]}
do
    if command -v $dependency &> /dev/null
    then
        version=$(command -V $dependency | head -n 1 | cut -d " " -f 3)
        echo -e "$dependency:OK;"
    else
        echo -e "$dependency:NO"
    fi
done

# 判断操作系统是否为Rocky Linux
if [[ $os_version == *"Rocky Linux"* ]]; then
    echo ""
    echo "----Installing missing dependencies using yum----"
    for dependency in ${dependencies[@]}
    do
        if ! command -v $dependency &> /dev/null; then
            sudo yum install -y $dependency
        fi
    done
else
  echo "This script only supports Rocky Linux. Exiting..."
  exit 1
fi