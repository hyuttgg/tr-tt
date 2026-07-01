import os
import re

def obfuscate_lua():
    source_path = "core/sender.lua"
    output_path = "core/sender_obfuscated.lua"

    if not os.path.exists(source_path):
        print(f"Lỗi: Không tìm thấy file {source_path}")
        return

    with open(source_path, "r", encoding="utf-8") as f:
        code = f.read()

    # Loại bỏ các block comment dài --[[ ... ]] để giảm dung lượng
    code = re.sub(r'--\[\[.*?\]\]', '', code, flags=re.DOTALL)
    
    # Loại bỏ các comment dòng đơn (giữ lại code)
    lines = code.split("\n")
    cleaned_lines = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("--") and not stripped.startswith("----"):
            continue
        cleaned_lines.append(line)
    code = "\n".join(cleaned_lines)

    # Thuật toán mã hóa: Dịch chuyển Byte (XOR với Key 137)
    key = 137
    encrypted_bytes = []
    for char in code:
        # XOR char code với key và định dạng đúng 3 chữ số để tránh lỗi gộp ký tự trong Lua
        val = ord(char) ^ key
        encrypted_bytes.append(f"{val:03d}")

    # Chuyển đổi thành chuỗi dữ liệu trong Lua: \011\022\033...
    lua_data_string = "\\" + "\\".join(encrypted_bytes)

    # Giao diện đóng gói mã hóa có chữ ký khanh 2007 dev
    obfuscated_template = f"""--[[
    ╔══════════════════════════════════════════════════════════════╗
    ║        OBFUSCATED & PROTECTED BY KHANH 2007 DEV              ║
    ║        Blox Fruits Account Manager — Lua Sender              ║
    ╚══════════════════════════════════════════════════════════════╝
--]]

local _key = {key}
local _cipher = "{lua_data_string}"

local function _decrypt(cipher_str, k)
    local decrypted = {{}}
    for byte_str in string.gmatch(cipher_str, "%d+") do
        local b = tonumber(byte_str)
        table.insert(decrypted, string.char(bit32.bxor(b, k)))
    end
    return table.concat(decrypted)
end

local _decoded = _decrypt(_cipher, _key)
local _exec, _err = loadstring(_decoded)

if _exec then
    task.spawn(_exec)
else
    warn("[khanh 2007 dev - Error]: " .. tostring(_err))
end
"""

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(obfuscated_template)

    print(f"Obfuscation completed -> {output_path}")

if __name__ == "__main__":
    obfuscate_lua()
