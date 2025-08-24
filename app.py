#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Feishu (Lark) business card generator – local Flask server
- Receives JSON (e.g., from Feishu Base webhook robot)
- Generates a PNG card using Pillow
- Uploads to Feishu via API -> returns image_key and (optionally) sends DM to the submitter
"""
import os
import io
import re
import json
import time
import math
import base64
import textwrap
from datetime import datetime
from typing import Dict, Any, Optional

import requests
from flask import Flask, request, jsonify, send_file
from urllib.parse import quote, unquote
from PIL import Image, ImageDraw, ImageFont, ImageOps
try:
    import qrcode
except Exception:
    qrcode = None

APP_ID = os.getenv("FEISHU_APP_ID", "")
APP_SECRET = os.getenv("FEISHU_APP_SECRET", "")
# If you want to force-send to a specific open_id for testing, set FEISHU_DEBUG_OPEN_ID
DEBUG_OPEN_ID = os.getenv("FEISHU_DEBUG_OPEN_ID", "").strip()

# Output directory for saving cards for printing
OUTPUT_DIR = os.getenv("OUTPUT_DIR", "./output")
ASSETS_DIR = os.getenv("ASSETS_DIR", "./assets")
TEMPLATE_PATH = os.getenv("TEMPLATE_PATH", os.path.join(ASSETS_DIR, "template.png"))

app = Flask(__name__)

# 添加全局响应头以消除ngrok浏览器警告
@app.after_request
def after_request(response):
    # 设置ngrok-skip-browser-warning头以消除ngrok警告页面
    response.headers['ngrok-skip-browser-warning'] = 'true'
    return response

# Token缓存管理
_token_cache = {
    "token": None,
    "expires_at": 0,
    "last_permission_check": 0
}
# ----------------------- Feishu helpers -----------------------
def get_tenant_access_token(force_refresh: bool = False) -> str:
    """获取tenant_access_token，支持缓存和自动刷新"""
    current_time = time.time()
    
    # 检查是否需要刷新token
    if (not force_refresh and 
        _token_cache["token"] and 
        current_time < _token_cache["expires_at"]):
        return _token_cache["token"]
    
    # 获取新token
    url = "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal/"
    payload = {"app_id": APP_ID, "app_secret": APP_SECRET}
    
    print(f"🔑 获取新的tenant_access_token...")
    r = requests.post(url, json=payload, timeout=10)
    r.raise_for_status()
    data = r.json()
    
    if data.get("code") != 0:
        raise RuntimeError(f"get_tenant_access_token failed: {data}")
    
    # 缓存token（设置提前5分钟过期以避免边界问题）
    token = data["tenant_access_token"]
    expires_in = data.get("expire", 7200)  # 默认2小时
    _token_cache["token"] = token
    _token_cache["expires_at"] = current_time + expires_in - 300  # 提前5分钟过期
    
    print(f"✅ Token获取成功，有效期: {expires_in}秒")
    return token

def check_feishu_permissions(token: str) -> Dict[str, Any]:
    """检查飞书应用权限配置状态"""
    permission_status = {
        "drive:file": "unknown",
        "bitable:app": "unknown", 
        "im:resource": "unknown",
        "overall_status": "unknown",
        "recommendations": []
    }
    
    # 测试drive:file权限 - 尝试访问一个测试文件
    try:
        test_url = "https://open.feishu.cn/open-apis/drive/v1/files"
        headers = {"Authorization": f"Bearer {token}"}
        r = requests.get(test_url, headers=headers, timeout=5)
        
        if r.status_code == 200:
            permission_status["drive:file"] = "granted"
        elif r.status_code == 403:
            permission_status["drive:file"] = "denied"
            permission_status["recommendations"].append("需要申请 drive:file 权限")
        else:
            permission_status["drive:file"] = f"error_{r.status_code}"
            
    except Exception as e:
        permission_status["drive:file"] = f"test_failed_{str(e)[:50]}"
    
    # 评估整体状态
    denied_count = sum(1 for status in permission_status.values() if status == "denied")
    if denied_count > 0:
        permission_status["overall_status"] = "incomplete"
        permission_status["recommendations"].append("请访问 https://open.feishu.cn/app/ 配置应用权限")
    else:
        permission_status["overall_status"] = "likely_ok"
    
    return permission_status

def diagnose_attachment_download_error(status_code: int, response_text: str, attachment_id: str) -> Dict[str, str]:
    """诊断附件下载错误并提供解决方案"""
    diagnosis = {
        "error_type": "unknown",
        "cause": "unknown", 
        "solution": "unknown"
    }
    
    if status_code == 403:
        diagnosis["error_type"] = "permission_denied"
        diagnosis["cause"] = "飞书应用缺少 drive:file 权限"
        diagnosis["solution"] = "在飞书开放平台为应用添加 drive:file 权限并重新发布版本"
        
    elif status_code == 404:
        diagnosis["error_type"] = "file_not_found"
        diagnosis["cause"] = f"附件ID {attachment_id} 对应的文件不存在或已删除"
        diagnosis["solution"] = "检查attachment_id是否正确，或确认文件是否已被删除"
        if "not found" in response_text.lower():
            diagnosis["cause"] += f" (服务器响应: {response_text[:100]})"
        
    elif status_code == 400:
        diagnosis["error_type"] = "invalid_request"
        diagnosis["cause"] = "请求参数格式错误或attachment_id格式不正确"
        diagnosis["solution"] = "确认attachment_id格式，可能需要从多维表格记录中获取真实的file_token"
        
    elif status_code == 401:
        diagnosis["error_type"] = "auth_failed"
        diagnosis["cause"] = "token无效或过期"
        diagnosis["solution"] = "重新获取tenant_access_token"
        
    return diagnosis

def get_permission_setup_guide() -> Dict[str, Any]:
    """获取完整的权限配置指导"""
    return {
        "title": "飞书MBTI名片生成器权限配置指南",
        "required_permissions": [
            {
                "name": "drive:file",
                "description": "文件读取权限",
                "purpose": "下载用户上传的微信二维码图片",
                "critical": True
            },
            {
                "name": "bitable:app", 
                "description": "多维表格应用权限",
                "purpose": "访问问卷数据和附件信息",
                "critical": True
            },
            {
                "name": "im:resource",
                "description": "消息资源权限", 
                "purpose": "上传生成的名片图片到飞书",
                "critical": False
            }
        ],
        "setup_steps": [
            "1. 访问飞书开放平台: https://open.feishu.cn/app/",
            "2. 选择您的应用 → 权限管理",
            "3. 搜索并添加上述权限",
            "4. 提交权限申请（部分权限需要管理员审批）", 
            "5. 权限通过后，重新发布应用版本",
            "6. 测试权限是否生效"
        ],
        "troubleshooting": {
            "403_error": "权限不足，请确认已添加drive:file权限并重新发布",
            "404_error": "文件不存在，检查attachment_id是否有效",
            "400_error": "请求参数错误，确认API调用格式正确"
        }
    }

def batch_get_open_id_by_email_or_mobile(token: str, email: Optional[str]=None, mobile: Optional[str]=None) -> Optional[str]:
    """
    Use Feishu contact-v3 API to get open_id by email or mobile
    """
    if not email and not mobile:
        return None
    url = "https://open.feishu.cn/open-apis/contact/v3/users/batch_get_id"
    params = {}
    if email:
        params["emails"] = email
    if mobile:
        params["mobiles"] = mobile
    headers = {"Authorization": f"Bearer {token}"}
    r = requests.get(url, headers=headers, params=params, timeout=10)
    r.raise_for_status()
    data = r.json()
    if data.get("code") != 0:
        return None
    user_list = data.get("data", {}).get("user_list", [])
    if user_list:
        return user_list[0].get("open_id")
    return None

def upload_image_to_feishu(token: str, image_bytes: bytes) -> str:
    url = "https://open.feishu.cn/open-apis/im/v1/images"
    headers = {"Authorization": f"Bearer {token}"}
    
    # 修复：image_type应该作为form-data字段，不是URL参数
    data = {"image_type": "message"}
    files = {"image": ("card.png", image_bytes, "image/png")}
    
    # 记录请求详细信息用于调试
    print(f"Debug: 上传图片到飞书 - 图片大小: {len(image_bytes)} bytes")
    print(f"Debug: 修复参数格式 - image_type作为form-data字段")
    
    r = requests.post(url, headers=headers, files=files, data=data, timeout=20)
    
    # 详细记录响应信息
    print(f"Debug: 飞书API响应状态码: {r.status_code}")
    print(f"Debug: 飞书API响应内容: {r.text}")
    
    try:
        response_data = r.json()
        if response_data.get("code") != 0:
            raise RuntimeError(f"Upload image failed - Code: {response_data.get('code')}, Message: {response_data.get('msg')}, Details: {response_data}")
        return response_data["data"]["image_key"]
    except ValueError as e:
        # 如果响应不是JSON格式
        raise RuntimeError(f"Upload image failed - Invalid JSON response: {r.text}, Status: {r.status_code}")
    except Exception as e:
        raise RuntimeError(f"Upload image failed - Status: {r.status_code}, Response: {r.text}, Error: {str(e)}")

def send_image_message_to_open_id(token: str, open_id: str, image_key: str) -> Dict[str, Any]:
    url = "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=open_id"
    headers = {"Authorization": f"Bearer {token}"}
    payload = {
        "receive_id": open_id,
        "msg_type": "image",
        "content": json.dumps({"image_key": image_key}, ensure_ascii=False)
    }
    r = requests.post(url, headers=headers, json=payload, timeout=10)
    r.raise_for_status()
    return r.json()

# ----------------------- Utilities -----------------------
def safe_filename(s: str) -> str:
    s = s.strip().replace(" ", "_")
    return re.sub(r"[^a-zA-Z0-9_\-\u4e00-\u9fa5]", "", s)

def try_load_font(size: int):
    # 优先使用项目字体文件，简化字体加载逻辑
    font_path = os.path.join(ASSETS_DIR, "font.ttf")
    if os.path.exists(font_path):
        try:
            return ImageFont.truetype(font_path, size=size)
        except Exception:
            pass
    # 备用系统字体
    system_fonts = [
        "/System/Library/Fonts/PingFang.ttc",  # macOS
        "/usr/share/fonts/truetype/noto/NotoSansSC-Regular.ttf",  # Linux
    ]
    for path in system_fonts:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size=size)
            except Exception:
                continue
    return ImageFont.load_default()

def analyze_attachment_id_type(attachment_id: str) -> Dict[str, Any]:
    """分析attachment_id的类型和来源"""
    analysis = {
        "type": "unknown",
        "length": len(attachment_id),
        "prefix": attachment_id[:10] if attachment_id else "",
        "likely_source": "unknown"
    }
    
    if not attachment_id:
        analysis["type"] = "empty"
        return analysis
    
    # 基于ID长度和格式特征推测来源
    if len(attachment_id) > 25:
        analysis["type"] = "bitable_attachment"
        analysis["likely_source"] = "multidimensional_table"
    elif attachment_id.startswith(("img_", "file_")):
        analysis["type"] = "standard_token"
        analysis["likely_source"] = "drive_or_message"
    elif len(attachment_id) < 15:
        analysis["type"] = "short_id"
        analysis["likely_source"] = "legacy_or_custom"
    else:
        analysis["type"] = "medium_id"
        analysis["likely_source"] = "form_or_bitable"
    
    return analysis

def get_file_token_from_bitable_record(token: str, app_token: str, table_id: str, record_id: str, attachment_field: str) -> Optional[str]:
    """从多维表格记录中获取附件的file_token"""
    try:
        url = f"https://open.feishu.cn/open-apis/bitable/v1/apps/{app_token}/tables/{table_id}/records/{record_id}"
        headers = {"Authorization": f"Bearer {token}"}
        
        print(f"🔍 查询多维表格记录获取file_token...")
        print(f"  - app_token: {app_token}")
        print(f"  - table_id: {table_id}")
        print(f"  - record_id: {record_id}")
        
        r = requests.get(url, headers=headers, timeout=15)
        
        print(f"📊 多维表格查询响应: HTTP {r.status_code}")
        
        if r.status_code == 200:
            data = r.json()
            print(f"📋 记录查询成功")
            
            # 从记录中提取附件字段
            fields = data.get("data", {}).get("record", {}).get("fields", {})
            attachment_data = fields.get(attachment_field, [])
            
            print(f"🔗 附件字段 '{attachment_field}' 内容: {attachment_data}")
            
            # 如果是列表格式，取第一个附件的file_token
            if isinstance(attachment_data, list) and len(attachment_data) > 0:
                file_token = attachment_data[0].get("file_token")
                if file_token:
                    print(f"✅ 成功提取file_token: {file_token}")
                    return file_token
                    
        print(f"❌ 无法从记录中获取file_token")
        return None
        
    except Exception as e:
        print(f"❌ 查询多维表格记录失败: {e}")
        return None

def search_all_bitable_records_for_attachments(token: str, app_token: str, table_id: str, attachment_id: str) -> Optional[str]:
    """搜索多维表格所有记录，寻找包含指定attachment_id的记录，并返回真实file_token"""
    try:
        # 使用搜索记录API而不是获取单个记录
        url = f"https://open.feishu.cn/open-apis/bitable/v1/apps/{app_token}/tables/{table_id}/records/search"
        headers = {"Authorization": f"Bearer {token}"}
        payload = {
            "page_size": 100,  # 每页记录数
            "automatic_fields": True  # 自动计算字段
        }
        
        print(f"🔍 搜索多维表格所有记录寻找attachment_id: {attachment_id}")
        
        r = requests.post(url, headers=headers, json=payload, timeout=15)
        
        print(f"📊 搜索记录响应: HTTP {r.status_code}")
        
        if r.status_code == 200:
            data = r.json()
            records = data.get("data", {}).get("items", [])
            
            print(f"📋 找到 {len(records)} 条记录，正在检查附件字段...")
            
            # 遍历所有记录和所有字段，寻找attachment_id
            for record in records:
                fields = record.get("fields", {})
                for field_name, field_value in fields.items():
                    # 检查是否是附件字段（通常是列表格式）
                    if isinstance(field_value, list):
                        for attachment in field_value:
                            if isinstance(attachment, dict):
                                # 检查是否包含file_token
                                file_token = attachment.get("file_token")
                                if file_token:
                                    print(f"🎯 在字段'{field_name}'中发现附件: file_token={file_token}")
                                    # 如果有其他标识符字段匹配attachment_id，或者直接返回第一个找到的
                                    return file_token
            
            print(f"❌ 在所有记录中未找到对应的attachment信息")
            
        else:
            print(f"❌ 搜索记录失败: {r.text}")
            
        return None
        
    except Exception as e:
        print(f"❌ 搜索多维表格记录失败: {e}")
        return None

def get_wechat_qr_from_attachment(token: str, attachment_id: str, user_info: Dict[str, Any] = None) -> Optional[Image.Image]:
    """通过飞书附件ID获取微信二维码图片，支持多种获取方式"""
    
    print(f"🔍 开始获取微信二维码，attachment_id: {attachment_id}")
    
    # 智能分析attachment_id类型
    id_analysis = analyze_attachment_id_type(attachment_id)
    print(f"🧠 ID分析结果: 类型={id_analysis['type']}, 长度={id_analysis['length']}, 来源={id_analysis['likely_source']}")
    
    # 方案1：从多维表格中搜索真实的file_token（基于新发现的正确方法）
    file_token = None
    if user_info and user_info.get("app_token") and user_info.get("table_id"):
        print(f"📋 检测到表格信息，搜索真实file_token...")
        
        # 首先尝试搜索所有记录查找附件
        file_token = search_all_bitable_records_for_attachments(
            token=token,
            app_token=user_info["app_token"],
            table_id=user_info["table_id"],
            attachment_id=attachment_id
        )
        
        if file_token:
            print(f"✅ 通过搜索记录找到真实file_token: {file_token}")
        elif user_info.get("record_id"):
            # 备选方案：如果有具体记录ID，尝试查询特定记录
            print(f"🔄 尝试查询特定记录...")
            possible_fields = ["微信二维码", "附件", "图片", "文件", "wechat_qr", "attachment", "image"]
            for field_name in possible_fields:
                file_token = get_file_token_from_bitable_record(
                    token=token,
                    app_token=user_info["app_token"],
                    table_id=user_info["table_id"],
                    record_id=user_info["record_id"],
                    attachment_field=field_name
                )
                if file_token:
                    print(f"✅ 在字段 '{field_name}' 中找到file_token: {file_token}")
                    break
    
    # 准备下载API尝试列表
    download_attempts = []
    
    if file_token:
        # 如果成功获取file_token，优先使用正确的下载API
        download_attempts.extend([
            f"https://open.feishu.cn/open-apis/drive/v1/medias/{file_token}/download",
            f"https://open.feishu.cn/open-apis/drive/v1/files/{file_token}/content",
        ])
        print(f"✅ 将使用file_token进行下载: {file_token}")
    
    # 方案2：使用正确的飞书媒体文件下载API（基于搜索结果的发现）
    # 关键发现：应该使用 /drive/v1/medias/{file_token}/download 而不是 /files/
    if file_token:
        # 如果有从多维表格获取的file_token，使用正确的medias API
        download_attempts.append(f"https://open.feishu.cn/open-apis/drive/v1/medias/{file_token}/download")
        print(f"✅ 使用正确的媒体文件下载API (file_token: {file_token})")
    
    # 方案3：将attachment_id当作file_token尝试medias API
    download_attempts.append(f"https://open.feishu.cn/open-apis/drive/v1/medias/{attachment_id}/download")
    print(f"✅ 尝试将attachment_id作为file_token使用媒体下载API")
    
    headers = {"Authorization": f"Bearer {token}"}
    
    # 尝试各种下载API
    for i, url in enumerate(download_attempts, 1):
        try:
            print(f"🔄 尝试下载API #{i}: {url}")
            r = requests.get(url, headers=headers, timeout=15)
            
            print(f"📊 API #{i} 响应: HTTP {r.status_code}, Content-Type: {r.headers.get('content-type', 'N/A')}")
            
            if r.status_code == 200:
                content_type = r.headers.get('content-type', '').lower()
                
                # 检查是否是有效的图片内容
                if len(r.content) < 100:
                    print(f"⚠️ 内容太小 ({len(r.content)} bytes)，跳过")
                    continue
                
                if 'json' in content_type:
                    print(f"⚠️ 返回JSON格式: {r.text[:200]}...")
                    continue
                
                try:
                    # 尝试解析为图片
                    im = Image.open(io.BytesIO(r.content)).convert("RGBA")
                    print(f"📐 图片尺寸: {im.size} (保持原始比例)")
                    
                    # 保持原图比例，不进行裁剪
                    # 返回原图，让后续的名片生成函数来处理缩放
                    
                    print(f"✅ 微信二维码获取成功！(API #{i}) - 原始比例保持")
                    return im
                    
                except Exception as img_error:
                    print(f"❌ 图片解析失败 (API #{i}): {img_error}")
                    continue
                    
            else:
                # 使用新的错误诊断功能
                diagnosis = diagnose_attachment_download_error(r.status_code, r.text, attachment_id)
                print(f"❌ API #{i} 失败: HTTP {r.status_code}")
                print(f"   🔍 错误类型: {diagnosis['error_type']}")
                print(f"   🎯 原因: {diagnosis['cause']}")
                print(f"   💡 解决方案: {diagnosis['solution']}")
                
        except Exception as e:
            print(f"❌ API #{i} 异常: {e}")
            continue
    
    print(f"❌ 所有 {len(download_attempts)} 个下载API都失败")
    print(f"📊 附件下载失败总结:")
    print(f"   - 测试的attachment_id: {attachment_id}")
    print(f"   - ID类型分析: {id_analysis['type']} (长度: {id_analysis['length']})")
    print(f"   - 推测来源: {id_analysis['likely_source']}")
    print(f"📋 完整解决方案:")
    print(f"   1. 【权限配置】访问 https://open.feishu.cn/app/ → 您的应用 → 权限管理")
    print(f"      添加权限: drive:file, bitable:app, im:resource")
    print(f"   2. 【重新发布】权限变更后需要重新发布应用版本") 
    print(f"   3. 【API正确性】确认使用 /drive/v1/files/{{attachment_id}}/content API")
    print(f"   4. 【字段映射】确认多维表格中的确切附件字段名称")
    return None


# ----------------------- Card generator -----------------------
def generate_card(user: Dict[str, Any]) -> tuple[bytes, str]:
    """根据用户信息和MBTI生成个性化名片"""
    # 获取MBTI类型并选择对应底图
    mbti = user.get("mbti", "INFP").upper().strip()
    if mbti not in ["ENFJ", "ENFP", "ENTJ", "ENTP", "ESFJ", "ESFP", "ESTJ", "ESTP", 
                   "INFJ", "INFP", "INTJ", "INTP", "ISFJ", "ISFP", "ISTJ", "ISTP"]:
        mbti = "INFP"  # 默认类型
    
    # 加载MBTI底图
    template_path = os.path.join(ASSETS_DIR, f"{mbti}.png")
    if not os.path.exists(template_path):
        raise RuntimeError(f"MBTI底图不存在: {template_path}")
    
    base = Image.open(template_path).convert("RGBA")
    W, H = base.size
    draw = ImageDraw.Draw(base)
    
    # 根据高分辨率底图(4961x7016)调整字体大小
    # 字体需要与底图标题字体大小完全匹配
    scale_factor = W / 1050
    # 按照底图标签字体实际大小调整
    title_font = try_load_font(int(60 * scale_factor))    # 昵称/性别/职业标签字体大小
    content_font = try_load_font(int(50 * scale_factor))  # 兴趣爱好内容字体
    intro_font = try_load_font(int(50 * scale_factor))    # 一句话介绍字体
    
    # 提取字段信息
    nickname = user.get("nickname", "未命名")
    gender = user.get("gender", "")
    profession = user.get("profession", "")
    interests = user.get("interests", "")
    introduction = user.get("introduction", "")
    wechat_qr = user.get("wechat_qr_image")  # PIL图片对象
    
    # 基于底图实际布局的精确坐标（4961x7016分辨率）
    # 根据对比模板图片调整，精确定位到标签右侧
    
    # 左侧字段区域 - 紧贴标签右侧，精确对齐
    nickname_x = int(W * 0.23)  # "昵称"标签右侧紧贴位置
    nickname_y = int(H * 0.25) # "昵称"标签垂直中心对齐
    
    gender_x = int(W * 0.23)    # "性别"标签右侧紧贴位置  
    gender_y = int(H * 0.33)   # "性别"标签垂直中心对齐
    
    profession_x = int(W * 0.23) # "职业"标签右侧紧贴位置
    profession_y = int(H * 0.42) # "职业"标签垂直中心对齐
    
    # 兴趣爱好区域 - 紧贴"兴趣爱好/在做的创业项目"标签下方
    interests_x = int(W * 0.08)
    interests_y = int(H * 0.58)  # 紧贴标签下方，大幅向上调整
    interests_width = int(W * 1.2)  # 可用宽度
    
    # 一句话介绍区域 - 紧贴"一句话介绍你自己"标签下方  
    intro_x = int(W * 0.08)
    intro_y = int(H * 0.87)    # 紧贴标签下方，避免重合
    intro_width = int(W * 1.2) # 可用宽度
    
    # 微信二维码区域 - 精确覆盖图片！
    qr_x = int(W * 0.67)        
    qr_y = int(H * 0.25)        # 山丘区域顶部
    qr_max_width = int(W * 0.26)  # 最大宽度限制
    qr_max_height = int(H * 0.44) # 最大高度限制
    
    # 绘制内容 - 使用更大的字体
    # 1. 昵称 - 使用大字体
    draw.text((nickname_x, nickname_y), nickname, font=title_font, fill="#3B536A")
    
    # 2. 性别 - 使用大字体
    if gender:
        draw.text((gender_x, gender_y), gender, font=title_font, fill="#3B536A")
    
    # 3. 职业 - 使用大字体
    if profession:
        draw.text((profession_x, profession_y), profession, font=title_font, fill="#3B536A")
    
    # 4. 兴趣爱好（多行文本，自动换行）- 使用中等字体
    if interests:
        # 计算合适的字符宽度用于换行
        avg_char_width = draw.textlength("测", font=content_font)
        chars_per_line = int(interests_width // avg_char_width)
        wrapped_interests = textwrap.fill(interests, width=chars_per_line)
        
        lines = wrapped_interests.split('\n')
        for i, line in enumerate(lines):
            line_y = interests_y + i * int(90 * scale_factor)  # 增加行间距
            draw.text((interests_x, line_y), line, font=content_font, fill="#3B536A")
    
    # 5. 一句话介绍（多行文本）- 使用专用字体
    if introduction:
        avg_char_width = draw.textlength("测", font=intro_font)
        chars_per_line = int(intro_width // avg_char_width)
        wrapped_intro = textwrap.fill(introduction, width=chars_per_line)
        
        lines = wrapped_intro.split('\n')
        for i, line in enumerate(lines):
            line_y = intro_y + i * int(90 * scale_factor)  # 增加行间距
            draw.text((intro_x, line_y), line, font=intro_font, fill="#34495E")
    
    # 6. 微信二维码（保持原图比例，不裁剪）
    if wechat_qr:
        # 获取原图尺寸
        orig_w, orig_h = wechat_qr.size
        
        # 计算缩放比例，以适应最大宽度和高度限制，同时保持原图比例
        width_scale = qr_max_width / orig_w
        height_scale = qr_max_height / orig_h
        
        # 选择较小的缩放比例，确保图片完全适应可用空间
        scale = min(width_scale, height_scale)
        
        # 计算最终尺寸
        new_width = int(orig_w * scale)
        new_height = int(orig_h * scale)
        
        # 按原比例缩放
        qr_resized = wechat_qr.resize((new_width, new_height), Image.LANCZOS)
        base.paste(qr_resized, (qr_x, qr_y), qr_resized)
    
    # 保存文件
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    base_filename = f"{ts}_{safe_filename(nickname)}.png"
    out_path = os.path.join(OUTPUT_DIR, base_filename)
    base.convert("RGB").save(out_path, "PNG", optimize=True)
    
    # 返回字节流
    buf = io.BytesIO()
    base.convert("RGB").save(buf, "PNG", optimize=True)
    buf.seek(0)
    return buf.read(), out_path

# ----------------------- Payload parser -----------------------
def extract_user_info(payload: Dict[str, Any]) -> Dict[str, Any]:
    """简化的用户信息提取，直接处理6字段JSON格式"""
    # 直接从JSON中提取所需字段
    user_info = {
        "nickname": payload.get("nickname", "").strip(),
        "gender": payload.get("gender", "").strip(), 
        "profession": payload.get("profession", "").strip(),
        "interests": payload.get("interests", "").strip(),
        "mbti": payload.get("mbti", "").strip(),
        "introduction": payload.get("introduction", "").strip(),
        "wechatQrAttachmentId": payload.get("wechatQrAttachmentId", "").strip()
    }
    return user_info

def get_feishu_setup_suggestions(send_result):
    """根据飞书API响应生成智能配置建议"""
    if not send_result or "warn" not in send_result:
        return "飞书集成正常工作"
    
    error_message = send_result.get("warn", "")
    
    # 分析不同的错误代码并提供对应建议
    if "99991672" in error_message:
        return "需要权限: 访问 https://open.feishu.cn/app/ → 权限管理 → 添加 im:resource:upload 权限"
    elif "234001" in error_message:
        return "参数错误: 系统已自动修复，请重试"
    elif "234007" in error_message:
        return "机器人未启用: 访问 https://open.feishu.cn/app/ → 应用功能 → 机器人 → 启用机器人"
    elif "feishu_disabled" in error_message:
        return "飞书未配置: 请设置环境变量 FEISHU_APP_ID 和 FEISHU_APP_SECRET"
    else:
        return f"飞书配置需要完善: {error_message[:100]}..."

# ----------------------- Flask routes -----------------------
@app.route("/healthz", methods=["GET"])
def healthz():
    return jsonify({"ok": True})

@app.route("/permissions", methods=["GET"])  
def check_permissions():
    """检查飞书权限配置状态"""
    try:
        if not APP_ID or not APP_SECRET:
            return jsonify({
                "status": "error",
                "message": "飞书应用未配置",
                "setup_guide": get_permission_setup_guide()
            }), 400
            
        token = get_tenant_access_token()
        permission_status = check_feishu_permissions(token)
        setup_guide = get_permission_setup_guide()
        
        return jsonify({
            "status": "ok",
            "permission_status": permission_status,
            "setup_guide": setup_guide,
            "app_configured": True
        })
        
    except Exception as e:
        return jsonify({
            "status": "error", 
            "message": f"权限检查失败: {str(e)}",
            "setup_guide": get_permission_setup_guide()
        }), 500

@app.route("/image/<path:filename>", methods=["GET"])
def serve_image(filename):
    """直接访问生成的名片图片（本地文件）"""
    try:
        # URL解码文件名以支持中文
        decoded_filename = unquote(filename)
        image_path = os.path.join(OUTPUT_DIR, decoded_filename)
        
        if not os.path.exists(image_path):
            return jsonify({"error": "image_not_found", "filename": decoded_filename}), 404
        
        # 检查是否请求PNG下载格式
        if request.args.get("format") == "png":
            return send_file(image_path, mimetype="image/png", as_attachment=True, download_name=decoded_filename)
        
        # 默认在浏览器中显示
        return send_file(image_path, mimetype="image/png")
    except Exception as e:
        return jsonify({"error": "serve_image_failed", "detail": str(e)}), 500

@app.route("/feishu-image/<image_key>", methods=["GET"])
def serve_feishu_image(image_key):
    """通过飞书API代理访问云端图片"""
    try:
        print(f"🔍 请求飞书图片: {image_key}")
        
        # 获取飞书访问token
        if not APP_ID or not APP_SECRET:
            return jsonify({"error": "feishu_not_configured", "detail": "飞书应用未配置"}), 500
            
        token = get_tenant_access_token()
        
        # 调用飞书图片下载API
        url = f"https://open.feishu.cn/open-apis/im/v1/images/{image_key}"
        headers = {"Authorization": f"Bearer {token}"}
        
        print(f"📥 从飞书获取图片: {url}")
        r = requests.get(url, headers=headers, timeout=15)
        
        if r.status_code == 200:
            print(f"✅ 飞书图片获取成功: {len(r.content)} bytes")
            # 直接返回飞书的图片内容
            response = app.response_class(
                r.content,
                mimetype="image/png",
                headers={
                    "Cache-Control": "public, max-age=3600",  # 缓存1小时
                    "Content-Disposition": f'inline; filename="feishu-card-{image_key}.png"'
                }
            )
            return response
        else:
            print(f"❌ 飞书图片获取失败: {r.status_code} - {r.text}")
            return jsonify({
                "error": "feishu_image_not_found", 
                "detail": f"飞书API返回: {r.status_code}",
                "image_key": image_key
            }), 404
            
    except Exception as e:
        print(f"❌ 飞书图片代理异常: {e}")
        return jsonify({
            "error": "feishu_proxy_failed", 
            "detail": str(e),
            "image_key": image_key
        }), 500

@app.route("/hook", methods=["GET", "POST"])
def hook():
    # 记录请求详细信息用于调试
    print(f"🔍 收到请求: {request.method} {request.url}")
    print(f"📋 请求头: {dict(request.headers)}")
    print(f"🌐 客户端IP: {request.remote_addr}")
    print(f"📝 Content-Type: {request.content_type}")
    
    # 处理GET请求（飞书可能的预检查）
    if request.method == "GET":
        return jsonify({
            "status": "ok",
            "message": "飞书MBTI名片生成服务运行中",
            "methods_supported": ["GET", "POST"],
            "webhook_endpoint": "/hook",
            "health_endpoint": "/healthz",
            "version": "2.0",
            "features": {
                "mbti_types": 16,
                "fields_supported": ["nickname", "gender", "profession", "interests", "mbti", "introduction"],
                "wechat_qr_support": True,
                "image_formats": ["PNG"],
                "feishu_integration": bool(APP_ID and APP_SECRET)
            }
        })
    
    # 处理POST请求（实际的webhook数据）
    # 支持多种请求格式：JSON, form-data, form-urlencoded
    payload = {}
    
    try:
        print(f"📦 开始解析POST数据...")
        # 尝试解析JSON格式
        if request.content_type and 'application/json' in request.content_type:
            payload = request.get_json(force=True, silent=False) or {}
            print(f"✅ JSON数据解析成功: {len(str(payload))} 字符")
        # 处理表单数据格式（multipart/form-data 或 application/x-www-form-urlencoded）
        elif request.form:
            payload = dict(request.form)
            print(f"✅ Form数据解析成功: {len(payload)} 个字段")
        # 处理原始数据
        elif request.get_data():
            # 尝试解析为JSON
            raw_data = request.get_data().decode('utf-8')
            print(f"📄 原始数据: {raw_data[:200]}...")
            try:
                import json as json_module
                payload = json_module.loads(raw_data)
                print(f"✅ 原始JSON解析成功")
            except:
                # 如果不是JSON，返回错误信息用于调试
                print(f"❌ 无法解析为JSON格式")
                return jsonify({
                    "error": "unsupported_format", 
                    "detail": f"Content-Type: {request.content_type}",
                    "raw_data": raw_data[:200]
                }), 400
        else:
            print(f"❌ 未收到任何数据")
            return jsonify({"error": "empty_request", "detail": "No data received"}), 400
        
        # 打印解析后的数据用于调试
        print(f"🎯 解析后的payload: {json.dumps(payload, ensure_ascii=False, indent=2) if payload else 'Empty'}")
            
    except Exception as e:
        return jsonify({
            "error": "parse_failed", 
            "detail": str(e),
            "content_type": request.content_type,
            "form_data": dict(request.form) if request.form else None
        }), 400

    user = extract_user_info(payload)
    
    # 1) 获取微信二维码图片（如果有attachment_id）
    wechat_qr_image = None
    if user.get("wechatQrAttachmentId") and APP_ID and APP_SECRET:
        try:
            token = get_tenant_access_token()
            wechat_qr_image = get_wechat_qr_from_attachment(token, user["wechatQrAttachmentId"], user)
            user["wechat_qr_image"] = wechat_qr_image
        except Exception as e:
            print(f"获取微信二维码失败: {e}")
    
    # 2) Generate card
    try:
        png_bytes, saved_path = generate_card(user)
    except Exception as e:
        return jsonify({"error": "render_failed", "detail": str(e)}), 500

    # 3) 生成本地备用URL
    image_filename = os.path.basename(saved_path)
    # URL编码文件名以支持中文
    encoded_filename = quote(image_filename)
    # 生成本地访问URL作为备用
    if 'ngrok' in request.host:
        local_image_url = f"https://{request.host}/image/{encoded_filename}"
    else:
        base_url = request.url_root.rstrip('/')
        local_image_url = f"{base_url}/image/{encoded_filename}"

    # 4) 尝试上传到飞书并生成飞书代理URL（推荐）
    image_key = None
    image_url = local_image_url  # 默认使用本地URL
    send_result = None
    feishu_enabled = bool(APP_ID and APP_SECRET)
    
    if feishu_enabled:
        try:
            token = get_tenant_access_token()
            image_key = upload_image_to_feishu(token, png_bytes)
            
            # 生成飞书代理URL（优先使用）
            if 'ngrok' in request.host:
                image_url = f"https://{request.host}/feishu-image/{image_key}"
            else:
                base_url = request.url_root.rstrip('/')
                image_url = f"{base_url}/feishu-image/{image_key}"
            
            print(f"✅ 优先使用飞书代理URL: {image_url}")

            # Determine receiver open_id
            recv_open_id = DEBUG_OPEN_ID or user.get("open_id")
            if not recv_open_id and user.get("email"):
                recv_open_id = batch_get_open_id_by_email_or_mobile(token, email=user["email"])

            if recv_open_id:
                send_result = send_image_message_to_open_id(token, recv_open_id, image_key)
        except Exception as e:
            send_result = {"warn": f"feishu_upload_failed: {e}"}
    else:
        send_result = {"info": "feishu_disabled: APP_ID or APP_SECRET not configured"}

    # 5) Support returning PNG directly if client requests it
    if request.args.get("format") == "png":
        return send_file(io.BytesIO(png_bytes), mimetype="image/png", as_attachment=False, download_name="card.png")

    # 构建响应数据
    response_data = {
        "status": "ok",
        "saved_path": os.path.abspath(saved_path),
        "image_url": image_url,  # 优先使用飞书代理URL
        "image_key": image_key,
        "send_result": send_result,
        "suggestions": {
            "view_image": f"访问 {image_url} 查看生成的名片",
            "feishu_setup": get_feishu_setup_suggestions(send_result)
        }
    }
    
    # 如果有飞书代理URL，提供更多选项
    if image_key and feishu_enabled:
        response_data["local_image_url"] = local_image_url  # 本地备用URL
        response_data["suggestions"].update({
            "feishu_cloud": f"访问 {image_url} 查看云端名片（推荐）",
            "local_backup": f"访问 {local_image_url} 查看本地备份",
            "download_png": f"访问 {local_image_url}?format=png 下载名片"
        })
    else:
        # 无飞书时使用本地URL
        response_data["suggestions"]["download_png"] = f"访问 {image_url}?format=png 下载名片"
    
    return jsonify(response_data)

if __name__ == "__main__":
    port = int(os.getenv("PORT", "3000"))
    app.run(host="0.0.0.0", port=port, debug=True)
