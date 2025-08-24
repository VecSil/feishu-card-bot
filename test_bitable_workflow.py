#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
飞书多维表格MBTI名片工作流程测试脚本
用于验证webhook服务、图片生成、飞书集成等功能是否正常
"""

import os
import sys
import json
import time
import requests
from datetime import datetime
from typing import Dict, Any, List

# 测试配置
TEST_CONFIG = {
    "webhook_url": "https://2584df5b7dea.ngrok-free.app/hook",
    "test_users": [
        {
            "nickname": "测试用户Alice",
            "gender": "女", 
            "profession": "产品经理",
            "interests": "用户体验设计、数据分析",
            "mbti": "ENFJ",
            "introduction": "热爱创新的理想主义者",
            "wechatQrAttachmentId": ""  # 可以填入真实的attachment_id
        },
        {
            "nickname": "测试用户Bob",
            "gender": "男",
            "profession": "软件工程师", 
            "interests": "机器学习、开源项目",
            "mbti": "INTJ",
            "introduction": "追求完美的架构师",
            "wechatQrAttachmentId": ""
        }
    ]
}

class MBTIWorkflowTester:
    """MBTI名片工作流程测试器"""
    
    def __init__(self, webhook_url: str):
        self.webhook_url = webhook_url
        self.test_results = []
        
    def log(self, message: str, level: str = "INFO"):
        """输出日志"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{timestamp}] [{level}] {message}")
        
    def test_webhook_health(self) -> bool:
        """测试webhook健康状态"""
        try:
            self.log("🔍 测试webhook健康状态...")
            
            response = requests.get(f"{self.webhook_url}/healthz", timeout=10)
            
            if response.status_code == 200:
                self.log("✅ Webhook健康检查通过")
                return True
            else:
                self.log(f"❌ Webhook健康检查失败: HTTP {response.status_code}", "ERROR")
                return False
                
        except requests.exceptions.RequestException as e:
            self.log(f"❌ Webhook连接失败: {e}", "ERROR")
            return False
            
    def test_webhook_info(self) -> Dict[str, Any]:
        """测试webhook基本信息"""
        try:
            self.log("📋 获取webhook服务信息...")
            
            response = requests.get(self.webhook_url, timeout=10)
            
            if response.status_code == 200:
                info = response.json()
                self.log("✅ 服务信息获取成功")
                self.log(f"   版本: {info.get('version', 'Unknown')}")
                self.log(f"   支持的MBTI类型: {info.get('features', {}).get('mbti_types', 'Unknown')}")
                self.log(f"   飞书集成: {info.get('features', {}).get('feishu_integration', 'Unknown')}")
                return info
            else:
                self.log(f"❌ 服务信息获取失败: HTTP {response.status_code}", "ERROR")
                return {}
                
        except Exception as e:
            self.log(f"❌ 服务信息获取异常: {e}", "ERROR")
            return {}
            
    def test_card_generation(self, user_data: Dict[str, Any]) -> Dict[str, Any]:
        """测试名片生成功能"""
        try:
            self.log(f"🎨 测试 {user_data['nickname']} 的名片生成...")
            
            start_time = time.time()
            
            response = requests.post(
                self.webhook_url,
                json=user_data,
                headers={'Content-Type': 'application/json'},
                timeout=30
            )
            
            end_time = time.time()
            duration = round(end_time - start_time, 2)
            
            if response.status_code == 200:
                result = response.json()
                
                if result.get('status') == 'ok':
                    self.log(f"✅ {user_data['nickname']} 名片生成成功 ({duration}秒)")
                    self.log(f"   Image Key: {result.get('image_key', 'None')}")
                    self.log(f"   Image URL: {result.get('image_url', 'None')}")
                    
                    # 验证返回字段
                    required_fields = ['status', 'image_key', 'image_url']
                    for field in required_fields:
                        if field not in result:
                            self.log(f"⚠️  缺少必需字段: {field}", "WARNING")
                    
                    return {
                        'success': True,
                        'result': result,
                        'duration': duration
                    }
                else:
                    self.log(f"❌ 名片生成失败: {result.get('error', 'Unknown error')}", "ERROR")
                    return {'success': False, 'error': result.get('error')}
            else:
                self.log(f"❌ HTTP请求失败: {response.status_code} - {response.text}", "ERROR")
                return {'success': False, 'error': f'HTTP {response.status_code}'}
                
        except requests.exceptions.Timeout:
            self.log("❌ 请求超时（30秒）", "ERROR")
            return {'success': False, 'error': 'Timeout'}
        except Exception as e:
            self.log(f"❌ 名片生成异常: {e}", "ERROR")
            return {'success': False, 'error': str(e)}
            
    def test_image_access(self, image_url: str) -> bool:
        """测试图片访问"""
        try:
            self.log("🖼️  测试图片访问...")
            
            response = requests.get(image_url, timeout=10)
            
            if response.status_code == 200:
                if 'image' in response.headers.get('content-type', ''):
                    self.log(f"✅ 图片访问成功 ({len(response.content)} bytes)")
                    return True
                else:
                    self.log("❌ 返回内容不是图片格式", "ERROR")
                    return False
            else:
                self.log(f"❌ 图片访问失败: HTTP {response.status_code}", "ERROR")
                return False
                
        except Exception as e:
            self.log(f"❌ 图片访问异常: {e}", "ERROR")
            return False
            
    def run_full_test(self) -> Dict[str, Any]:
        """运行完整测试流程"""
        self.log("🚀 开始完整工作流程测试...")
        
        test_summary = {
            'total_tests': 0,
            'passed_tests': 0,
            'failed_tests': 0,
            'results': []
        }
        
        # 1. 健康检查
        self.log("\n=== 第一阶段: 服务健康检查 ===")
        test_summary['total_tests'] += 1
        if self.test_webhook_health():
            test_summary['passed_tests'] += 1
        else:
            test_summary['failed_tests'] += 1
            
        # 2. 服务信息检查
        self.log("\n=== 第二阶段: 服务信息检查 ===")
        webhook_info = self.test_webhook_info()
        
        # 3. 批量名片生成测试
        self.log("\n=== 第三阶段: 批量名片生成测试 ===")
        for i, user_data in enumerate(TEST_CONFIG['test_users']):
            self.log(f"\n--- 测试用户 {i+1}/{len(TEST_CONFIG['test_users'])} ---")
            
            test_summary['total_tests'] += 1
            result = self.test_card_generation(user_data)
            
            if result['success']:
                test_summary['passed_tests'] += 1
                
                # 4. 图片访问测试  
                if result['result'].get('image_url'):
                    self.log("\n--- 图片访问测试 ---")
                    test_summary['total_tests'] += 1
                    if self.test_image_access(result['result']['image_url']):
                        test_summary['passed_tests'] += 1
                    else:
                        test_summary['failed_tests'] += 1
            else:
                test_summary['failed_tests'] += 1
            
            test_summary['results'].append({
                'user': user_data['nickname'],
                'success': result['success'],
                'duration': result.get('duration'),
                'error': result.get('error')
            })
            
            # 避免请求过于频繁
            if i < len(TEST_CONFIG['test_users']) - 1:
                time.sleep(2)
        
        # 输出测试总结
        self.log("\n" + "="*50)
        self.log("🎯 测试总结")
        self.log(f"   总测试数: {test_summary['total_tests']}")
        self.log(f"   通过数: {test_summary['passed_tests']}")
        self.log(f"   失败数: {test_summary['failed_tests']}")
        self.log(f"   成功率: {test_summary['passed_tests']/test_summary['total_tests']*100:.1f}%")
        
        if test_summary['failed_tests'] == 0:
            self.log("🎉 所有测试通过！系统运行正常")
        else:
            self.log("⚠️  部分测试失败，请检查上述错误信息")
            
        return test_summary

def create_test_feishu_script() -> str:
    """生成飞书自动化测试脚本代码"""
    return '''
// 飞书多维表格测试脚本
// 复制此代码到飞书多维表格的自动化流程中运行

async function testMBTIWorkflow() {
    console.log('🧪 开始飞书多维表格工作流程测试...');
    
    try {
        // 1. 测试基础API
        const user = await bitable.bridge.getUserInfo();
        console.log('✅ 用户信息获取成功:', user.name);
        
        const table = await bitable.base.getActiveTable();
        console.log('✅ 表格信息获取成功');
        
        // 2. 测试webhook连接
        const testData = {
            nickname: '测试用户',
            gender: '未知',
            profession: '测试工程师',
            interests: '自动化测试',
            mbti: 'ENFP',
            introduction: '测试专用用户',
            wechatQrAttachmentId: '',
            open_id: user.open_id
        };
        
        console.log('📤 发送测试请求...');
        const response = await fetch('https://your-domain.com/hook', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify(testData)
        });
        
        const result = await response.json();
        console.log('📥 收到响应:', result);
        
        if (result.status === 'ok') {
            console.log('✅ 工作流程测试成功！');
            
            bitable.ui.showToast({
                toastType: 'success',
                message: '✅ 工作流程测试通过'
            });
            
            return true;
        } else {
            console.error('❌ 工作流程测试失败:', result.error);
            
            bitable.ui.showToast({
                toastType: 'error', 
                message: '❌ 工作流程测试失败'
            });
            
            return false;
        }
        
    } catch (error) {
        console.error('❌ 测试过程异常:', error);
        
        bitable.ui.showToast({
            toastType: 'error',
            message: '❌ 测试异常: ' + error.message
        });
        
        return false;
    }
}

// 执行测试
testMBTIWorkflow();
'''

def main():
    """主函数"""
    print("🎯 飞书多维表格MBTI名片工作流程测试器")
    print("="*50)
    
    # 检查配置
    webhook_url = TEST_CONFIG.get('webhook_url')
    if not webhook_url:
        print("❌ 请先配置webhook_url")
        return
    
    print(f"📍 测试目标: {webhook_url}")
    print(f"👥 测试用户数: {len(TEST_CONFIG['test_users'])}")
    print("")
    
    # 创建测试器并运行
    tester = MBTIWorkflowTester(webhook_url)
    summary = tester.run_full_test()
    
    # 保存测试结果
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    report_file = f"test_report_{timestamp}.json"
    
    with open(report_file, 'w', encoding='utf-8') as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)
    
    print(f"\n📄 详细测试报告已保存到: {report_file}")
    
    # 生成飞书测试脚本
    feishu_script = create_test_feishu_script()
    script_file = f"feishu_test_script_{timestamp}.js"
    
    with open(script_file, 'w', encoding='utf-8') as f:
        f.write(feishu_script)
    
    print(f"📄 飞书测试脚本已生成: {script_file}")
    
    return summary['failed_tests'] == 0

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)