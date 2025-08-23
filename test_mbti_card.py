#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
测试新的MBTI名片生成功能
"""

import requests
import json
import time

def test_mbti_card_generation():
    """测试MBTI名片生成功能"""
    
    # 测试数据 - 模拟飞书多维表格发送的JSON格式
    test_payload = {
        "nickname": "张三",
        "gender": "男",
        "profession": "产品经理", 
        "interests": "阅读、编程、旅行、摄影",
        "mbti": "INFP",
        "introduction": "热爱技术和产品设计的理想主义者",
        "wechatQrAttachmentId": ""  # 暂时为空，因为需要真实的飞书附件ID
    }
    
    # 本地服务器地址
    url = "http://localhost:3001/hook"
    
    try:
        print("🚀 开始测试MBTI名片生成功能...")
        print(f"📝 测试数据: {json.dumps(test_payload, ensure_ascii=False, indent=2)}")
        
        # 发送POST请求
        response = requests.post(url, json=test_payload, timeout=30)
        
        print(f"📊 响应状态码: {response.status_code}")
        
        if response.status_code == 200:
            result = response.json()
            print("✅ 测试成功!")
            print(f"📸 生成的名片URL: {result.get('image_url')}")
            print(f"💾 本地保存路径: {result.get('saved_path')}")
            
            if result.get('suggestions'):
                suggestions = result['suggestions']
                print(f"💡 查看建议: {suggestions.get('view_image')}")
                print(f"⬇️ 下载建议: {suggestions.get('download_png')}")
        else:
            print(f"❌ 测试失败: {response.status_code}")
            print(f"错误信息: {response.text}")
            
    except requests.exceptions.ConnectionError:
        print("❌ 连接失败：请确保Flask服务器正在运行 (python app.py)")
    except Exception as e:
        print(f"❌ 测试异常: {e}")

def test_different_mbti_types():
    """测试不同MBTI类型的名片生成"""
    
    mbti_types = ["ENFJ", "ENFP", "ENTJ", "ENTP", "ESFJ", "ESFP", "ESTJ", "ESTP",
                  "INFJ", "INFP", "INTJ", "INTP", "ISFJ", "ISFP", "ISTJ", "ISTP"]
    
    base_payload = {
        "nickname": "测试用户",
        "gender": "未知",
        "profession": "测试工程师",
        "interests": "测试各种MBTI类型的名片效果",
        "introduction": "专门测试不同性格类型的名片生成效果",
        "wechatQrAttachmentId": ""
    }
    
    url = "http://localhost:3001/hook"
    
    print("🎨 开始测试16种MBTI类型...")
    
    for mbti in mbti_types[:3]:  # 只测试前3种避免过多输出
        test_data = base_payload.copy()
        test_data["mbti"] = mbti
        test_data["nickname"] = f"MBTI-{mbti}测试者"
        
        try:
            response = requests.post(url, json=test_data, timeout=30)
            if response.status_code == 200:
                result = response.json()
                print(f"✅ {mbti} 类型名片生成成功: {result.get('image_url')}")
            else:
                print(f"❌ {mbti} 类型测试失败: {response.status_code}")
                print(f"   错误详情: {response.text[:200]}")
        except Exception as e:
            print(f"❌ {mbti} 类型测试异常: {e}")
        
        # 添加延迟避免并发问题
        time.sleep(1)

if __name__ == "__main__":
    print("=" * 50)
    print("🧪 MBTI名片生成功能测试")
    print("=" * 50)
    
    # 基本功能测试
    test_mbti_card_generation()
    
    print("\n" + "=" * 50)
    
    # MBTI类型测试
    test_different_mbti_types()
    
    print("=" * 50)
    print("✨ 测试完成!")