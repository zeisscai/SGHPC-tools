    def compare_energies(self, selected_files):
        """比较能量，找出最小值"""
        print(f"\n开始比较 {len(selected_files)} 个文件的能量...")
        print("=" * 80)
        
        results = []
        min_energy = None
        min_energy_file = None
        
        # 分析所有文件
        for file_path in selected_files:
            result = self.analyze_file(file_path, 1)  # 模式1返回字典
            
            if isinstance(result, dict):
                results.append(result)
                filename = result['filename']
                is_converged = result['is_converged']
                conv_status = result['conv_status']
                energy = result['energy']
                
                # 输出单个文件结果
                output = f"{filename}"
                if is_converged is True:
                    output += " (已收敛)"
                elif is_converged is False:
                    output += f" (未收敛: {conv_status})"
                else:
                    output += f" (收敛状态未知: {conv_status})"
                    
                if energy is not None:
                    output += f", 总能量: {energy:.6f} eV"
                    
                    # 更新最小能量（只考虑收敛的计算）
                    if is_converged is True:
                        if min_energy is None or energy < min_energy:
                            min_energy = energy
                            min_energy_file = filename
                else:
                    output += ", 总能量: 未找到"
                    
                print(output)
            else:
                print(result)  # 错误信息
        
        print("=" * 80)
        
        # 输出比较结果
        if min_energy is not None and min_energy_file is not None:
            print(f"\n最稳定构型(能量最低):")
            print(f"文件名: {min_energy_file}")
            print(f"能量: {min_energy:.6f} eV")
            
            # 计算相对能量
            print(f"\n相对能量 (以最低能量为基准):")
            converged_results = [r for r in results if r['is_converged'] is True and r['energy'] is not None]
            if len(converged_results) > 1:
                for result in converged_results:
                    rel_energy = result['energy'] - min_energy
                    rel_energy_kcal = rel_energy * 23.061  # eV转换为kcal/mol
                    print(f"{result['filename']}: {rel_energy:.6f} eV ({rel_energy_kcal:.3f} kcal/mol)")
        else:
            print("\n未找到有效的能量数据进行比较！")
            print("请检查文件是否正确收敛或包含能量信息。")#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ORCA计算输出文件分析脚本
用于分析ORCA量子化学计算软件的输出文件
"""

import os
import re
import glob
from pathlib import Path

class ORCAAnalyzer:
    def __init__(self):
        self.hartree_to_ev = 27.211386245988  # Hartree到eV的转换因子
    
    def get_folder_path(self):
        """获取用户指定的文件夹路径"""
        while True:
            folder_path = input("请输入需要分析的文件夹路径(输入exit退出程序): ").strip()
            if folder_path.lower() == 'exit':
                print("程序退出！")
                exit(0)
            if os.path.exists(folder_path) and os.path.isdir(folder_path):
                return folder_path
            else:
                print("文件夹不存在，请重新输入！")
    
    def list_out_files(self, folder_path):
        """列出文件夹中的所有.out文件"""
        pattern = os.path.join(folder_path, "*.out")
        out_files = glob.glob(pattern)
        out_files.sort()  # 按文件名排序
        
        if not out_files:
            print("该文件夹中没有找到.out文件！")
            return []
        
        print("\n找到以下.out文件:")
        for i, file_path in enumerate(out_files, 1):
            filename = os.path.basename(file_path)
            print(f"{i:2d}. {filename}")
        
        return out_files
    
    def select_files(self, inp_files):
        """让用户选择要分析的文件"""
        while True:
            user_input = input("\n请输入文件序号(数字 空格 数字)，直接回车选择全部，输入exit退出: ").strip()
            
            if user_input.lower() == 'exit':
                return None
            
            if not user_input:  # 直接回车，选择全部
                return inp_files
            
            try:
                # 解析用户输入的序号
                indices = list(map(int, user_input.split()))
                selected_files = []
                for idx in indices:
                    if 1 <= idx <= len(inp_files):
                        selected_files.append(inp_files[idx-1])
                    else:
                        print(f"序号 {idx} 超出范围！")
                        break
                else:
                    return selected_files
            except ValueError:
                print("输入格式不正确，请输入数字序号，用空格分隔！")
    
    def select_analysis_mode(self):
        """选择分析模式"""
        print("\n请选择分析模式:")
        print("1. 比较能量，找出最小值(最稳定构型)")
        print("2. 输出HOMO/LUMO能级")
        print("3. 输出总能量")
        
        while True:
            choice = input("请输入选择(1、2或3): ").strip()
            if choice in ['1', '2', '3']:
                return int(choice)
            else:
                print("请输入1、2或3！")
    
    def check_convergence(self, content):
        """检查计算是否收敛"""
        # 查找收敛信息
        if "****ORCA TERMINATED NORMALLY****" in content:
            return True, "计算正常结束"
        elif "SCF CONVERGED" in content:
            return True, "SCF收敛"
        elif "SCF NOT CONVERGED" in content:
            return False, "SCF未收敛"
        elif "ERROR" in content.upper():
            return False, "计算出现错误"
        else:
            return None, "收敛状态未知"
    
    def extract_homo_lumo(self, content):
        """提取HOMO/LUMO能级"""
        homo_energy = None
        lumo_energy = None
        
        # 查找轨道能级信息
        orbital_pattern = r'(\d+)\s+(-?\d+\.\d+)\s+(\d+\.\d+)\s*$'
        lines = content.split('\n')
        
        for i, line in enumerate(lines):
            if "ORBITAL ENERGIES" in line:
                # 找到轨道能级部分，继续查找HOMO/LUMO
                for j in range(i, min(i+100, len(lines))):
                    if "NO   OCC          E(Eh)" in lines[j]:
                        # 开始解析轨道能级
                        for k in range(j+2, min(j+200, len(lines))):
                            match = re.search(r'(\d+)\s+(\d+\.\d+)\s+(-?\d+\.\d+)', lines[k])
                            if match:
                                orbital_num = int(match.group(1))
                                occupation = float(match.group(2))
                                energy = float(match.group(3))
                                
                                if occupation > 1.0:  # 占据轨道
                                    homo_energy = energy
                                elif occupation < 1.0 and lumo_energy is None:  # 第一个空轨道
                                    lumo_energy = energy
                            else:
                                break
                        break
                break
        
        # 转换为eV
        if homo_energy is not None:
            homo_energy_ev = homo_energy * self.hartree_to_ev
        else:
            homo_energy_ev = None
            
        if lumo_energy is not None:
            lumo_energy_ev = lumo_energy * self.hartree_to_ev
        else:
            lumo_energy_ev = None
            
        return homo_energy_ev, lumo_energy_ev
    
    def extract_total_energy(self, content):
        """提取总能量"""
        # 查找最终的SCF能量
        patterns = [
            r'FINAL SINGLE POINT ENERGY\s+(-?\d+\.\d+)',
            r'Total Energy\s*:\s*(-?\d+\.\d+)\s*Eh',
            r'SCF Energy\s*:\s*(-?\d+\.\d+)'
        ]
        
        for pattern in patterns:
            matches = re.findall(pattern, content)
            if matches:
                # 取最后一个匹配的能量值
                energy_hartree = float(matches[-1])
                energy_ev = energy_hartree * self.hartree_to_ev
                return energy_ev
        
        return None
    
    def analyze_file(self, file_path, mode):
        """分析单个文件"""
        filename = os.path.basename(file_path)
        
        try:
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
        except Exception as e:
            return f"{filename}: 读取文件失败 - {str(e)}"
        
        # 检查收敛性
        is_converged, conv_status = self.check_convergence(content)
        
        if mode == 1:  # 能量比较模式，返回字典格式
            total_energy = self.extract_total_energy(content)
            return {
                'filename': filename,
                'is_converged': is_converged,
                'conv_status': conv_status,
                'energy': total_energy
            }
            
        elif mode == 2:  # HOMO/LUMO模式
            homo, lumo = self.extract_homo_lumo(content)
            
            result = f"{filename}"
            # 先输出收敛状态
            if is_converged is True:
                result += " (已收敛)"
            elif is_converged is False:
                result += f" (未收敛: {conv_status})"
            else:
                result += f" (收敛状态未知: {conv_status})"
            
            if homo is not None:
                result += f", HOMO: {homo:.6f} eV"
            else:
                result += ", HOMO: 未找到"
                
            if lumo is not None:
                result += f", LUMO: {lumo:.6f} eV"
            else:
                result += ", LUMO: 未找到"
                
            return result
            
        elif mode == 3:  # 总能量模式
            total_energy = self.extract_total_energy(content)
            
            result = f"{filename}"
            # 先输出收敛状态
            if is_converged is True:
                result += " (已收敛)"
            elif is_converged is False:
                result += f" (未收敛: {conv_status})"
            else:
                result += f" (收敛状态未知: {conv_status})"
                
            if total_energy is not None:
                result += f", 总能量: {total_energy:.6f} eV"
            else:
                result += ", 总能量: 未找到"
                
            return result
    
    def run(self):
        """主运行函数"""
        print("=== ORCA输出文件分析工具 ===")
        
        while True:
            # 1. 获取文件夹路径
            folder_path = self.get_folder_path()
            
            # 2. 列出out文件
            out_files = self.list_out_files(folder_path)
            if not out_files:
                continue
            
            # 3. 选择文件
            selected_files = self.select_files(out_files)
            if selected_files is None:  # 用户选择退出
                continue
            
            # 4. 选择分析模式
            mode = self.select_analysis_mode()
            
            # 5. 执行分析
            if mode == 1:  # 能量比较模式
                self.compare_energies(selected_files)
            else:  # HOMO/LUMO或总能量模式
                print(f"\n开始分析 {len(selected_files)} 个文件...")
                print("=" * 80)
                
                for file_path in selected_files:
                    result = self.analyze_file(file_path, mode)
                    print(result)
                
                print("=" * 80)
                print("分析完成！\n")

if __name__ == "__main__":
    analyzer = ORCAAnalyzer()
    analyzer.run()
