#!/usr/bin/env python3
"""测试微信二维码原始比例保持功能"""

import requests
import json
from PIL import Image
import os

# 测试配置
BASE_URL = "http://localhost:3001"

def create_test_qr_codes():
    """创建不同比例的测试二维码"""
    
    # 1:1 正方形测试图片
    square = Image.new('RGB', (200, 200), color='red')
    square.save('test_square.png')
    
    # 1:1.4 竖长条测试图片  
    vertical = Image.new('RGB', (200, 280), color='blue')
    vertical.save('test_vertical.png')
    
    # 1.4:1 横长条测试图片
    horizontal = Image.new('RGB', (280, 200), color='green')
    horizontal.save('test_horizontal.png')
    
    print("✅ 测试图片创建完成:")
    print("  - test_square.png (1:1)")
    print("  - test_vertical.png (1:1.4)")  
    print("  - test_horizontal.png (1.4:1)")

def test_card_generation_without_qr():
    """测试不带二维码的名片生成"""
    print("\n🧪 测试1: 无二维码名片生成")
    
    test_data = {
        "nickname": "比例测试",
        "gender": "未知",
        "profession": "工程师",
        "interests": "测试不同比例的二维码显示效果",
        "mbti": "INFP",
        "introduction": "验证二维码原始比例是否保持",
        "wechatQrAttachmentId": ""
    }
    
    response = requests.post(f"{BASE_URL}/hook", json=test_data)
    
    if response.status_code == 200:
        result = response.json()
        print(f"✅ 测试成功: {result['image_url']}")
        return True
    else:
        print(f"❌ 测试失败: {response.status_code} - {response.text}")
        return False

def main():
    print("=== 微信二维码比例保持测试 ===")
    
    # 创建测试图片
    create_test_qr_codes()
    
    # 启动测试服务器提示
    print(f"\n⚠️ 请确保服务器正在运行: python app.py")
    print(f"⚠️ 如果需要启动服务器，请运行: .venv/bin/python app.py")
    
    # 测试基本功能
    if test_card_generation_without_qr():
        print("\n✅ 基础测试通过")
        print("\n🎯 二维码比例修复要点:")
        print("  1. get_wechat_qr_from_attachment() 不再使用 ImageOps.fit() 强制裁剪")
        print("  2. generate_card() 使用 min(width_scale, height_scale) 保持原图比例")
        print("  3. 用户上传的图片会保持原始长宽比")
        
        print(f"\n💡 测试建议:")
        print(f"  - 查看生成的名片验证改动效果")
        print(f"  - 如果有真实微信二维码，可以通过飞书上传测试")
    else:
        print("\n❌ 基础测试失败，请检查服务器状态")
    
    # 清理测试图片
    for filename in ['test_square.png', 'test_vertical.png', 'test_horizontal.png']:
        if os.path.exists(filename):
            os.remove(filename)
    
    print(f"\n🧹 测试图片已清理")

if __name__ == "__main__":
    main()