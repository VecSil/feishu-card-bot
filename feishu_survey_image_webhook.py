#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
飞书问卷图片自动获取和Webhook转发系统
支持从飞书多维表格获取图片附件并转发到外部数据库
"""

import os
import json
import time
import requests
from typing import Dict, Any, List, Optional
from datetime import datetime
from flask import Flask, request, jsonify

# 配置信息
APP_ID = os.getenv("FEISHU_APP_ID", "")
APP_SECRET = os.getenv("FEISHU_APP_SECRET", "")
TARGET_WEBHOOK_URL = os.getenv("TARGET_WEBHOOK_URL", "")  # 您的数据库webhook地址
IMAGE_DOWNLOAD_DIR = os.getenv("IMAGE_DOWNLOAD_DIR", "./downloaded_images")

app = Flask(__name__)

class FeishuSurveyImageHandler:
    """飞书问卷图片处理器"""
    
    def __init__(self):
        self.app_id = APP_ID
        self.app_secret = APP_SECRET
        self.target_webhook = TARGET_WEBHOOK_URL
        
    def get_tenant_access_token(self) -> str:
        """获取tenant_access_token"""
        url = "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal/"
        payload = {"app_id": self.app_id, "app_secret": self.app_secret}
        
        response = requests.post(url, json=payload, timeout=10)
        response.raise_for_status()
        
        data = response.json()
        if data.get("code") != 0:
            raise RuntimeError(f"获取token失败: {data}")
            
        return data["tenant_access_token"]
    
    def download_attachment(self, token: str, file_token: str, filename: str) -> Optional[str]:
        """下载飞书附件文件"""
        try:
            url = f"https://open.feishu.cn/open-apis/drive/v1/medias/{file_token}/download"
            headers = {"Authorization": f"Bearer {token}"}
            
            response = requests.get(url, headers=headers, timeout=30)
            response.raise_for_status()
            
            # 确保下载目录存在
            os.makedirs(IMAGE_DOWNLOAD_DIR, exist_ok=True)
            
            # 生成唯一文件名
            timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
            safe_filename = f"{timestamp}_{filename}"
            file_path = os.path.join(IMAGE_DOWNLOAD_DIR, safe_filename)
            
            with open(file_path, 'wb') as f:
                f.write(response.content)
                
            print(f"✅ 图片下载成功: {file_path}")
            return file_path
            
        except Exception as e:
            print(f"❌ 图片下载失败: {e}")
            return None
    
    def extract_images_from_record(self, token: str, record_data: Dict[str, Any]) -> List[Dict[str, Any]]:
        """从记录中提取图片信息"""
        images = []
        
        # 遍历记录的所有字段
        for field_name, field_value in record_data.items():
            # 检查是否为附件字段
            if isinstance(field_value, list):
                for item in field_value:
                    if isinstance(item, dict) and "file_token" in item:
                        # 这是一个附件
                        file_info = {
                            "field_name": field_name,
                            "file_token": item.get("file_token"),
                            "file_name": item.get("name", "unknown"),
                            "file_type": item.get("type", "unknown"),
                            "file_size": item.get("size", 0)
                        }
                        
                        # 判断是否为图片类型
                        if self.is_image_file(file_info["file_name"], file_info["file_type"]):
                            # 下载图片
                            local_path = self.download_attachment(
                                token, 
                                file_info["file_token"], 
                                file_info["file_name"]
                            )
                            
                            if local_path:
                                file_info["local_path"] = local_path
                                file_info["download_url"] = self.generate_public_url(local_path)
                                images.append(file_info)
        
        return images
    
    def is_image_file(self, filename: str, file_type: str) -> bool:
        """判断是否为图片文件"""
        image_extensions = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.tiff']
        image_types = ['image/jpeg', 'image/png', 'image/gif', 'image/bmp', 'image/webp']
        
        filename_lower = filename.lower()
        return (any(filename_lower.endswith(ext) for ext in image_extensions) or 
                file_type.lower() in image_types)
    
    def generate_public_url(self, local_path: str) -> str:
        """生成图片的公网访问URL"""
        # 假设您的服务器可以通过HTTP访问下载的图片
        filename = os.path.basename(local_path)
        # 需要根据您的实际服务器配置调整
        base_url = request.url_root if request else "http://your-server.com/"
        return f"{base_url.rstrip('/')}/images/{filename}"
    
    def send_to_target_webhook(self, data: Dict[str, Any]) -> bool:
        """将数据发送到目标webhook"""
        if not self.target_webhook:
            print("⚠️ 目标webhook地址未配置")
            return False
            
        try:
            headers = {
                "Content-Type": "application/json",
                "User-Agent": "Feishu-Survey-Image-Bot/1.0"
            }
            
            response = requests.post(
                self.target_webhook, 
                json=data, 
                headers=headers, 
                timeout=30
            )
            response.raise_for_status()
            
            print(f"✅ Webhook发送成功: {response.status_code}")
            return True
            
        except Exception as e:
            print(f"❌ Webhook发送失败: {e}")
            return False
    
    def process_survey_submission(self, webhook_payload: Dict[str, Any]) -> Dict[str, Any]:
        """处理问卷提交数据"""
        try:
            # 获取token
            token = self.get_tenant_access_token()
            
            # 从webhook载荷中提取记录信息
            event_data = webhook_payload.get("event", {})
            record_data = {}
            
            # 支持多种webhook格式
            if "after_change" in event_data:
                # 多维表格记录变更事件
                record_data = event_data["after_change"].get("fields", {})
            elif "fields" in webhook_payload:
                # 直接字段数据
                record_data = webhook_payload["fields"]
            else:
                # 其他格式
                record_data = webhook_payload
            
            # 提取图片信息
            images = self.extract_images_from_record(token, record_data)
            
            # 构建发送到数据库的数据
            database_payload = {
                "timestamp": datetime.now().isoformat(),
                "source": "feishu_survey",
                "submission_data": record_data,
                "images": images,
                "total_images": len(images),
                "webhook_metadata": {
                    "app_id": self.app_id,
                    "processed_at": datetime.now().isoformat()
                }
            }
            
            # 发送到目标webhook
            success = self.send_to_target_webhook(database_payload)
            
            return {
                "status": "success" if success else "partial_success",
                "images_processed": len(images),
                "images": [
                    {
                        "field": img["field_name"],
                        "filename": img["file_name"],
                        "local_path": img.get("local_path"),
                        "download_url": img.get("download_url")
                    } for img in images
                ],
                "webhook_sent": success
            }
            
        except Exception as e:
            return {
                "status": "error",
                "error": str(e),
                "images_processed": 0
            }

# 全局处理器实例
handler = FeishuSurveyImageHandler()

@app.route("/healthz", methods=["GET"])
def healthz():
    """健康检查"""
    return jsonify({"status": "ok", "service": "feishu-survey-image-webhook"})

@app.route("/webhook", methods=["POST"])
def survey_webhook():
    """接收飞书多维表格webhook"""
    try:
        payload = request.get_json()
        if not payload:
            return jsonify({"error": "empty_payload"}), 400
        
        print(f"📨 收到Webhook: {json.dumps(payload, ensure_ascii=False, indent=2)}")
        
        # 处理问卷提交
        result = handler.process_survey_submission(payload)
        
        return jsonify({
            "status": "ok",
            "processed": True,
            "result": result
        })
        
    except Exception as e:
        print(f"❌ Webhook处理错误: {e}")
        return jsonify({
            "status": "error",
            "error": str(e)
        }), 500

@app.route("/images/<filename>", methods=["GET"])
def serve_image(filename):
    """提供下载的图片文件访问"""
    try:
        from flask import send_file
        file_path = os.path.join(IMAGE_DOWNLOAD_DIR, filename)
        
        if not os.path.exists(file_path):
            return jsonify({"error": "file_not_found"}), 404
            
        return send_file(file_path)
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/test", methods=["POST"])  
def test_webhook():
    """测试webhook功能"""
    test_payload = {
        "event": {
            "after_change": {
                "fields": {
                    "姓名": "测试用户",
                    "头像": [
                        {
                            "file_token": "test_file_token",
                            "name": "avatar.jpg",
                            "type": "image/jpeg",
                            "size": 102400
                        }
                    ]
                }
            }
        }
    }
    
    result = handler.process_survey_submission(test_payload)
    return jsonify({"test_result": result})

if __name__ == "__main__":
    print("🚀 启动飞书问卷图片Webhook服务...")
    print(f"📁 图片下载目录: {IMAGE_DOWNLOAD_DIR}")
    print(f"🔗 目标Webhook: {TARGET_WEBHOOK_URL if TARGET_WEBHOOK_URL else '未配置'}")
    
    port = int(os.getenv("PORT", "3000"))
    app.run(host="0.0.0.0", port=port, debug=True)