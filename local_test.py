#!/usr/bin/env python3
"""
本地测试飞书webhook - 完全模拟飞书的请求行为
无需外网隧道，直接测试localhost:3000上的服务
"""
import requests
import json
import time
import os
from datetime import datetime

class FeishuWebhookSimulator:
    def __init__(self, base_url="http://localhost:3000"):
        self.base_url = base_url
        
    def test_health(self):
        """测试服务健康状态"""
        print("🔍 检查服务健康状态...")
        try:
            response = requests.get(f"{self.base_url}/healthz", timeout=5)
            if response.status_code == 200:
                print("✅ 服务健康检查通过")
                return True
            else:
                print(f"❌ 健康检查失败，状态码: {response.status_code}")
                return False
        except requests.exceptions.ConnectionError:
            print("❌ 无法连接到服务，请确保Flask应用正在运行")
            return False
        except Exception as e:
            print(f"❌ 健康检查异常: {e}")
            return False
    
    def generate_card(self, user_data, get_png=False):
        """生成名片"""
        url = f"{self.base_url}/hook"
        if get_png:
            url += "?format=png"
            
        try:
            response = requests.post(url, json=user_data, timeout=30)
            
            if get_png:
                if response.status_code == 200:
                    return response.content  # 返回PNG二进制数据
                else:
                    return {"error": f"HTTP {response.status_code}: {response.text}"}
            else:
                if response.status_code == 200:
                    return response.json()   # 返回JSON响应
                else:
                    return {"error": f"HTTP {response.status_code}: {response.text}"}
                
        except requests.exceptions.RequestException as e:
            return {"error": str(e)}
    
    def run_test_suite(self):
        """运行完整测试套件"""
        print("🧪 开始飞书名片生成器本地测试套件")
        print("=" * 50)
        
        # 1. 健康检查
        if not self.test_health():
            print("\n🚨 服务未启动或不可用")
            print("请执行以下步骤:")
            print("1. 运行: ./start.sh")
            print("2. 选择选项2 - 仅本地运行")
            print("3. 等待服务启动后重新运行测试")
            return False
        
        # 2. 测试数据准备
        test_users = [
            {
                "name": "张三",
                "title": "产品经理", 
                "company": "创新科技有限公司",
                "phone": "13800138000",
                "email": "zhangsan@company.com",
                "qrcode_text": "https://company.com/zhangsan"
            },
            {
                "name": "李四",
                "title": "高级工程师",
                "company": "智能科技股份",
                "phone": "13900139000", 
                "email": "lisi@tech.com",
                "avatar_url": "https://avatars.githubusercontent.com/u/1?v=4"
            },
            {
                "姓名": "王五",  # 测试中文字段
                "职位": "设计总监",
                "公司": "创意设计工作室",
                "电话": "13700137000",
                "邮箱": "wangwu@design.com"
            },
            {
                "name": "赵六"  # 最小化数据测试
            },
            {
                "name": "钱七",
                "company": "Test Company with Very Long Name That Might Cause Layout Issues",
                "title": "Senior Software Development Engineer with Extended Title",
                "email": "very.long.email.address.for.testing@extremely-long-domain-name.com"
            }
        ]
        
        print(f"\n📋 准备了 {len(test_users)} 个测试用例")
        
        # 3. 批量测试
        print("\n🔬 开始执行名片生成测试...")
        success_count = 0
        png_count = 0
        
        for i, user in enumerate(test_users, 1):
            user_name = user.get('name', user.get('姓名', f'用户{i}'))
            print(f"\n--- 测试用例 {i}: {user_name} ---")
            
            # JSON响应测试
            print("🔄 测试JSON响应...")
            result = self.generate_card(user)
            
            if "error" in result:
                print(f"❌ JSON生成失败: {result['error']}")
                continue
            
            if result.get('status') == 'ok':
                success_count += 1
                print(f"✅ JSON响应成功")
                
                if result.get('saved_path'):
                    saved_path = result['saved_path']
                    if os.path.exists(saved_path):
                        file_size = os.path.getsize(saved_path) / 1024  # KB
                        print(f"📁 文件已保存: {os.path.basename(saved_path)} ({file_size:.1f} KB)")
                    else:
                        print(f"⚠️ 保存路径不存在: {saved_path}")
                
                if result.get('image_key'):
                    print(f"🔑 飞书图片Key: {result['image_key']}")
                
                if result.get('send_result'):
                    send_result = result['send_result']
                    if 'warn' in send_result:
                        print(f"⚠️ 发送警告: {send_result['warn']}")
                    else:
                        print("📤 飞书消息发送成功")
            else:
                print(f"❌ 响应状态异常: {result}")
                continue
            
            # PNG图片测试
            print("🔄 测试PNG直接获取...")
            png_data = self.generate_card(user, get_png=True)
            
            if isinstance(png_data, bytes) and len(png_data) > 0:
                png_count += 1
                filename = f"test_card_{i}_{user_name}.png"
                try:
                    with open(filename, "wb") as f:
                        f.write(png_data)
                    file_size = len(png_data) / 1024  # KB
                    print(f"🖼️ PNG保存成功: {filename} ({file_size:.1f} KB)")
                except Exception as e:
                    print(f"❌ PNG保存失败: {e}")
            elif isinstance(png_data, dict) and "error" in png_data:
                print(f"❌ PNG生成失败: {png_data['error']}")
            else:
                print("❌ PNG数据异常")
            
            time.sleep(0.5)  # 避免并发问题
        
        # 4. 测试结果汇总
        print("\n" + "=" * 50)
        print("📊 测试结果汇总")
        print(f"总测试用例: {len(test_users)}")
        print(f"JSON成功: {success_count}")
        print(f"PNG成功: {png_count}")
        print(f"成功率: {success_count/len(test_users)*100:.1f}%")
        
        # 5. 检查输出目录
        output_dir = "./output"
        if os.path.exists(output_dir):
            output_files = [f for f in os.listdir(output_dir) if f.endswith('.png')]
            print(f"\n📂 输出目录包含 {len(output_files)} 个PNG文件")
            if output_files:
                latest_file = max([os.path.join(output_dir, f) for f in output_files], 
                                key=os.path.getmtime)
                print(f"最新文件: {os.path.basename(latest_file)}")
        
        # 6. 性能测试
        print("\n⚡ 快速性能测试...")
        start_time = time.time()
        perf_result = self.generate_card({"name": "性能测试", "email": "perf@test.com"})
        end_time = time.time()
        response_time = (end_time - start_time) * 1000  # 毫秒
        
        if perf_result.get('status') == 'ok':
            print(f"✅ 单次请求响应时间: {response_time:.1f}ms")
            if response_time < 3000:
                print("🚀 响应速度优秀 (< 3秒)")
            elif response_time < 10000:
                print("🙂 响应速度良好 (< 10秒)")
            else:
                print("🐌 响应速度较慢 (> 10秒)")
        
        print("\n🎉 本地测试套件执行完成！")
        
        # 7. 后续建议
        if success_count == len(test_users):
            print("\n✨ 所有测试通过，系统运行正常！")
            print("建议下一步操作:")
            print("1. 打开生成的PNG文件检查视觉效果")
            print("2. 运行 open test_page.html 进行可视化测试")
            print("3. 准备配置真实的飞书应用凭据")
        else:
            print(f"\n⚠️ 有 {len(test_users)-success_count} 个测试用例失败")
            print("建议检查:")
            print("1. 查看错误信息和日志")
            print("2. 确认所有依赖已正确安装")
            print("3. 检查.env配置文件")
        
        return success_count == len(test_users)

if __name__ == "__main__":
    print("🏠 飞书名片生成器 - 本地测试工具")
    print("版本: 1.0 | 无需外网隧道")
    print()
    
    simulator = FeishuWebhookSimulator()
    simulator.run_test_suite()