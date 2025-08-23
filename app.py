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

# ----------------------- Feishu helpers -----------------------
def get_tenant_access_token() -> str:
    url = "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal/"
    payload = {"app_id": APP_ID, "app_secret": APP_SECRET}
    r = requests.post(url, json=payload, timeout=10)
    r.raise_for_status()
    data = r.json()
    if data.get("code") != 0:
        raise RuntimeError(f"get_tenant_access_token failed: {data}")
    return data["tenant_access_token"]

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

def get_wechat_qr_from_attachment(token: str, attachment_id: str) -> Optional[Image.Image]:
    """通过飞书附件ID获取微信二维码图片"""
    try:
        url = f"https://open.feishu.cn/open-apis/drive/v1/files/{attachment_id}/content"
        headers = {"Authorization": f"Bearer {token}"}
        r = requests.get(url, headers=headers, timeout=15)
        r.raise_for_status()
        
        # 转换为PIL图片对象
        im = Image.open(io.BytesIO(r.content)).convert("RGBA")
        # 调整为方形，适合放在名片上
        size = 200  # 固定二维码大小
        im = ImageOps.fit(im, (size, size), method=Image.LANCZOS, centering=(0.5, 0.5))
        return im
    except Exception as e:
        print(f"获取微信二维码失败: {e}")
        return None


# ----------------------- Card generator -----------------------
def generate_card(user: Dict[str, Any]) -> (bytes, str):
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
    
    # 加载字体
    name_font = try_load_font(48)
    big_font = try_load_font(32) 
    medium_font = try_load_font(24)
    small_font = try_load_font(20)
    
    # 提取字段信息
    nickname = user.get("nickname", "未命名")
    gender = user.get("gender", "")
    profession = user.get("profession", "")
    interests = user.get("interests", "")
    introduction = user.get("introduction", "")
    wechat_qr = user.get("wechat_qr_image")  # PIL图片对象
    
    # 定义布局位置（基于常见名片尺寸调整）
    padding = 40
    
    # 左上：昵称（大字体）
    draw.text((padding, padding), nickname, font=name_font, fill="#2C3E50", anchor="lt")
    
    # 左中：性别 + 职业
    y_pos = padding + 80
    if gender and profession:
        gender_profession = f"{gender} · {profession}"
    elif gender or profession:
        gender_profession = gender or profession
    else:
        gender_profession = ""
    if gender_profession:
        draw.text((padding, y_pos), gender_profession, font=big_font, fill="#34495E", anchor="lt")
        y_pos += 50
    
    # 左下：兴趣爱好
    if interests:
        # 处理长文本换行
        wrapped_interests = textwrap.fill(interests, width=20)
        draw.text((padding, y_pos), f"兴趣：{wrapped_interests}", font=medium_font, fill="#7F8C8D")
        y_pos += 80
    
    # 右上：MBTI标识
    mbti_x = W - padding - 120
    draw.text((mbti_x, padding), mbti, font=name_font, fill="#E74C3C", anchor="rt")
    
    # 右中：一句话介绍
    if introduction:
        intro_y = padding + 100
        wrapped_intro = textwrap.fill(introduction, width=15)
        # 计算右对齐位置（不使用anchor，因为多行文本不支持）
        lines = wrapped_intro.split('\n')
        for i, line in enumerate(lines):
            line_width = draw.textlength(line, font=medium_font)
            line_x = mbti_x - line_width
            line_y = intro_y + i * 30
            draw.text((line_x, line_y), line, font=medium_font, fill="#2C3E50")
    
    # 右下：微信二维码
    if wechat_qr:
        qr_x = W - padding - 200
        qr_y = H - padding - 200
        base.paste(wechat_qr, (qr_x, qr_y), wechat_qr)
        # 添加"微信"标签
        label_text = "微信"
        label_width = draw.textlength(label_text, font=small_font)
        label_x = qr_x + 100 - label_width // 2
        draw.text((label_x, qr_y + 210), label_text, font=small_font, fill="#95A5A6")
    
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
            wechat_qr_image = get_wechat_qr_from_attachment(token, user["wechatQrAttachmentId"])
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
