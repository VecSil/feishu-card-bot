#!/usr/bin/env python3
"""
本地测试脚本 - 模拟飞书webhook发送请求
"""
import requests
import json

# 模拟飞书多维表格webhook数据
test_data = {
    "name": "李四",
    "title": "高级工程师", 
    "company": "创新科技有限公司",
    "phone": "13900139000",
    "email": "lisi@company.com",
    "qrcode_text": "https://example.com/lisi"
}

# 发送测试请求
try:
    response = requests.post(
        "http://localhost:3000/hook",
        json=test_data,
        timeout=10
    )
    print("状态码:", response.status_code)
    print("响应:", response.json())
    
    # 如果需要获取PNG图片
    png_response = requests.post(
        "http://localhost:3000/hook?format=png",
        json=test_data,
        timeout=10
    )
    if png_response.status_code == 200:
        with open("test_card.png", "wb") as f:
            f.write(png_response.content)
        print("PNG保存为: test_card.png")
        
except Exception as e:
    print("请求失败:", e)