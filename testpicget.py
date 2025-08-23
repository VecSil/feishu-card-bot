import requests

# 1. 先获取 tenant_access_token
def get_tenant_access_token(app_id, app_secret):
    url = "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal"
    headers = {"Content-Type": "application/json"}
    data = {
        "app_id": app_id,
        "app_secret": app_secret
    }
    resp = requests.post(url, json=data, headers=headers)
    resp.raise_for_status()
    token = resp.json()["tenant_access_token"]
    print(f"✅ {token}")
    return token

# 2. 下载问卷里用户上传的图片
def download_file(file_token, tenant_access_token, save_path):
    url = f"https://open.feishu.cn/open-apis/drive/v1/medias/{file_token}/download"
    headers = {
        "Authorization": f"Bearer {tenant_access_token}",
        "Content-Type": "application/json; charset=utf-8"
    }
    resp = requests.get(url, headers=headers, stream=True)
    resp.raise_for_status()
    with open(save_path, "wb") as f:
        for chunk in resp.iter_content(1024):
            f.write(chunk)
    print(f"✅ 文件已保存到 {save_path}")

if __name__ == "__main__":
    # 你应用的 app_id 和 app_secret
    APP_ID = "cli_a823ed89dd3d1013"
    APP_SECRET = "WNo78z4fjOcEZilR1DYEihYC8HCRJlXp"

    # 问卷答案返回的 file_token（附件id）
    FILE_TOKEN = "N7Aibhtm0opQdgxXoNccIwvDnwh"

    # 保存到本地的路径
    SAVE_PATH = "user_upload.png"

    # 执行
    token = get_tenant_access_token(APP_ID, APP_SECRET)
    download_file(FILE_TOKEN, token, SAVE_PATH)
