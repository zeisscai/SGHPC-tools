#!/bin/bash
#SBATCH --partition=amd  ###集群分区
#SBATCH -N 1 ###请求节点数量,只能为1
#SBATCH --ntasks=96 ###申请CPU数量
#SBATCH --mem=110G ###申请内存
#SBATCH --nodelist=AMD ###指定节点

###自定义部分
#SBATCH --job-name=chn  ###你的名字
#SBATCH --mail-user=2004@njupt.edu.cn ###接受通知的邮箱
#SBATCH --mail-type=END  ###接受通知类型

###文件目录
#SBATCH --chdir=/home/user0/xsj1023/b3lyp/ ###指定工作目录


file_array=()
### 遍历所有的gjf文件，并且处理gjf的第一行
for file in *.gjf; do
  file_name=$(basename "$file")
  file_dir=$(dirname "$file")
  new_dir="${file_dir}/${file_name%.*}.chk"
  sed "1s|%chk=.*|%chk=${new_dir}|" "$file" > "${file}.tmp"
  mv "${file}.tmp" "$file"
  file_name=$(basename "$file" .gjf)
  file_array+=("$file_name")
done

### 计算该目录下没有算过的gjf文件
for name in "${file_array[@]}"; do
  second_line=$(sed -n '2p' "$file")
  if [ -f "${name}.fchk" ]; then
    echo "Skipping ${name}.gjf"
  else
    g16 <${name}.gjf> ${name}.out
    formchk ${name}.chk
  fi
done