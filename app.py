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
    # Try common Chinese fonts on macOS/Linux/Windows; fallback to default
    candidates = [
        "/System/Library/Fonts/PingFang.ttc",  # macOS
        "/System/Library/Fonts/STHeiti Light.ttc",
        "/System/Library/Fonts/Hiragino Sans GB W3.otf",
        "/Library/Fonts/Arial Unicode.ttf",
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/truetype/noto/NotoSansSC-Regular.ttf",
        "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
        os.path.join(ASSETS_DIR, "NotoSansSC-Regular.otf"),
    ]
    for path in candidates:
        if os.path.exists(path):
            try:
                # PIL supports .ttc by specifying index optional (default 0)
                return ImageFont.truetype(path, size=size)
            except Exception:
                continue
    # last resort
    return ImageFont.load_default()

def fetch_image_sq(url: str, size: int) -> Optional[Image.Image]:
    try:
        r = requests.get(url, timeout=10)
        r.raise_for_status()
        im = Image.open(io.BytesIO(r.content)).convert("RGBA")
        # make square thumb
        min_side = min(im.size)
        im = ImageOps.fit(im, (size, size), method=Image.LANCZOS, centering=(0.5, 0.5))
        return im
    except Exception:
        return None

def make_qr(data: str, size: int=280) -> Optional[Image.Image]:
    if not qrcode or not data:
        return None
    qr = qrcode.QRCode(box_size=10, border=1, error_correction=qrcode.constants.ERROR_CORRECT_M)
    qr.add_data(data)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white").convert("RGBA")
    img = img.resize((size, size), Image.LANCZOS)
    return img

# ----------------------- Card generator -----------------------
def generate_card(user: Dict[str, Any]) -> (bytes, str):
    """
    user keys we try to use:
      name/姓名, title/职位, company/公司, phone/电话, email/邮箱, avatar_url, qrcode_url, qrcode_text
    """
    # Load template or create a simple one
    W, H = 1050, 600  # print-quality-ish (3.5x2.0 inch @300dpi)
    if os.path.exists(TEMPLATE_PATH):
        base = Image.open(TEMPLATE_PATH).convert("RGBA").resize((W, H), Image.LANCZOS)
    else:
        # Create a clean gradient background
        base = Image.new("RGBA", (W, H), "#F6F7FB")
        draw_tmp = ImageDraw.Draw(base)
        for y in range(H):
            g = int(246 + (y/H)*6)  # subtle gradient
            draw_tmp.line([(0, y), (W, y)], fill=(g, g, g, 255))

    draw = ImageDraw.Draw(base)
    # Fonts
    name_font = try_load_font(64)
    big_font = try_load_font(36)
    small_font = try_load_font(28)

    # Content
    name = user.get("name") or user.get("姓名") or "未命名"
    title = user.get("title") or user.get("职位") or ""
    company = user.get("company") or user.get("公司") or ""
    phone = user.get("phone") or user.get("电话") or ""
    email = user.get("email") or user.get("邮箱") or ""
    avatar_url = user.get("avatar_url") or user.get("头像") or ""
    qrcode_url = user.get("qrcode_url") or user.get("二维码") or ""
    qrcode_text = user.get("qrcode_text") or ""

    # Layout metrics
    padding = 50
    left_col_x = padding
    right_col_x = W - padding - 280  # space for QR
    center_y = H // 2

    # Avatar (circle) on left
    AVATAR_SIZE = 160
    if avatar_url:
        av = fetch_image_sq(avatar_url, AVATAR_SIZE)
    else:
        av = None
    if av is not None:
        # circular mask
        mask = Image.new("L", (AVATAR_SIZE, AVATAR_SIZE), 0)
        ImageDraw.Draw(mask).ellipse((0, 0, AVATAR_SIZE-1, AVATAR_SIZE-1), fill=255)
        base.paste(av, (left_col_x, padding), mask)

    # Name + title + company
    text_x = left_col_x + (AVATAR_SIZE + 24 if av else 0)
    draw.text((text_x, padding), name, font=name_font, fill="#0F172A")  # slate-900
    y = padding + 80
    if company or title:
        draw.text((text_x, y), " · ".join([x for x in [company, title] if x]), font=big_font, fill="#334155")
        y += 50
    # Contacts
    if phone:
        draw.text((text_x, y), f"📞 {phone}", font=small_font, fill="#475569"); y += 40
    if email:
        draw.text((text_x, y), f"✉️ {email}", font=small_font, fill="#475569"); y += 40

    # QR on right
    qr_img = None
    if qrcode_url:
        qr_img = make_qr(qrcode_url, size=280)
    elif qrcode_text:
        qr_img = make_qr(qrcode_text, size=280)
    if qr_img:
        base.paste(qr_img, (right_col_x, center_y - 140), qr_img)

    # Footer stripe
    footer_h = 60
    footer = Image.new("RGBA", (W, footer_h), "#111827")  # neutral dark
    base.paste(footer, (0, H - footer_h), footer)
    draw = ImageDraw.Draw(base)
    draw.text((padding, H - footer_h + 16), "Auto-generated via Feishu Card Bot", font=small_font, fill="#E5E7EB")

    # Save bytes & file path
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    base_filename = f"{ts}_{safe_filename(name)}.png"
    out_path = os.path.join(OUTPUT_DIR, base_filename)
    base.convert("RGB").save(out_path, "PNG", optimize=True)
    buf = io.BytesIO()
    base.convert("RGB").save(buf, "PNG", optimize=True)
    buf.seek(0)
    return buf.read(), out_path

# ----------------------- Payload parser -----------------------
def extract_user_info(payload: Dict[str, Any]) -> Dict[str, Any]:
    """
    Try to be forgiving about field names and shapes.
    Supports simple flat JSON or Feishu Base event-ish shapes.
    """
    data = {}
    # Direct mapping
    for k in ["name","姓名","title","职位","company","公司","phone","电话","email","邮箱","avatar_url","头像","qrcode_url","二维码","qrcode_text","open_id","user_open_id","user_email","email"]:
        if k in payload:
            data[k] = payload[k]

    # Common wrappers
    if "fields" in payload and isinstance(payload["fields"], dict):
        data.update(payload["fields"])

    # Feishu event style
    event = payload.get("event") or {}
    operator = event.get("operator") or {}
    if operator.get("open_id"):
        data["open_id"] = operator["open_id"]

    # Bitable "after_change" fields
    after_fields = (event.get("after_change") or {}).get("fields") or {}
    if isinstance(after_fields, dict):
        data.update(after_fields)

    # Normalize keys
    normalized = {
        "name": data.get("name") or data.get("姓名"),
        "title": data.get("title") or data.get("职位"),
        "company": data.get("company") or data.get("公司"),
        "phone": data.get("phone") or data.get("电话"),
        "email": data.get("email") or data.get("邮箱") or data.get("user_email"),
        "avatar_url": data.get("avatar_url") or data.get("头像"),
        "qrcode_url": data.get("qrcode_url") or data.get("二维码"),
        "qrcode_text": data.get("qrcode_text"),
        "open_id": data.get("open_id") or data.get("user_open_id"),
    }
    return normalized

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
    """直接访问生成的名片图片"""
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

@app.route("/hook", methods=["POST"])
def hook():
    # 支持多种请求格式：JSON, form-data, form-urlencoded
    payload = {}
    
    try:
        # 尝试解析JSON格式
        if request.content_type and 'application/json' in request.content_type:
            payload = request.get_json(force=True, silent=False) or {}
        # 处理表单数据格式（multipart/form-data 或 application/x-www-form-urlencoded）
        elif request.form:
            payload = dict(request.form)
        # 处理原始数据
        elif request.get_data():
            # 尝试解析为JSON
            try:
                import json
                payload = json.loads(request.get_data().decode('utf-8'))
            except:
                # 如果不是JSON，返回错误信息用于调试
                return jsonify({
                    "error": "unsupported_format", 
                    "detail": f"Content-Type: {request.content_type}",
                    "raw_data": request.get_data().decode('utf-8')[:200]
                }), 400
        else:
            return jsonify({"error": "empty_request", "detail": "No data received"}), 400
            
    except Exception as e:
        return jsonify({
            "error": "parse_failed", 
            "detail": str(e),
            "content_type": request.content_type,
            "form_data": dict(request.form) if request.form else None
        }), 400

    user = extract_user_info(payload)
    # 1) Generate card
    try:
        png_bytes, saved_path = generate_card(user)
    except Exception as e:
        return jsonify({"error": "render_failed", "detail": str(e)}), 500

    # 2) 生成图片访问URL（不依赖飞书上传）
    image_filename = os.path.basename(saved_path)
    # URL编码文件名以支持中文
    encoded_filename = quote(image_filename)
    # 使用ngrok URL（强制HTTPS）
    if 'ngrok' in request.host:
        image_url = f"https://{request.host}/image/{encoded_filename}"
    else:
        base_url = request.url_root.rstrip('/')
        image_url = f"{base_url}/image/{encoded_filename}"

    # 3) 尝试上传到飞书（如果有权限）
    image_key = None
    send_result = None
    feishu_enabled = bool(APP_ID and APP_SECRET)
    
    if feishu_enabled:
        try:
            token = get_tenant_access_token()
            image_key = upload_image_to_feishu(token, png_bytes)

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

    # 4) Support returning PNG directly if client requests it
    if request.args.get("format") == "png":
        return send_file(io.BytesIO(png_bytes), mimetype="image/png", as_attachment=False, download_name="card.png")

    return jsonify({
        "status": "ok",
        "saved_path": os.path.abspath(saved_path),
        "image_url": image_url,  # 新增：本地图片访问URL
        "image_key": image_key,
        "send_result": send_result,
        "suggestions": {
            "view_image": f"访问 {image_url} 查看生成的名片",
            "download_png": f"访问 {image_url}?format=png 下载名片",
            "feishu_setup": get_feishu_setup_suggestions(send_result)
        }
    })

if __name__ == "__main__":
    port = int(os.getenv("PORT", "3000"))
    app.run(host="0.0.0.0", port=port, debug=True)
