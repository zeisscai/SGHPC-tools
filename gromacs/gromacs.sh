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

# 检查是否存在gromacs开头的tar.gz压缩包
if ls gromacs*.tar.gz 1> /dev/null 2>&1; then
  # 解压缩压缩包
  tar xfz gromacs*.tar.gz
  cd gromacs-*/ || exit

  # 创建build目录并进入
  mkdir build
  cd build || exit

  # 使用cmake进行配置
  cmake .. -DGMX_BUILD_OWN_FFTW=ON -DREGRESSIONTEST_DOWNLOAD=ON

  # 编译
  make

  # 运行测试
  make check

  # 安装
  sudo make install

  # 设置环境变量
  source /usr/local/gromacs/bin/GMXRC

  # 打印安装输出
  echo "Gromacs已成功安装"
else
  echo "未找到gromacs开头的tar.gz压缩包"
fi
