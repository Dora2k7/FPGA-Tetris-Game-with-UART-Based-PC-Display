#!/usr/bin/env python3
"""
game_viewer.py - Hiển thị game FPGA qua UART lên màn hình laptop
Yêu cầu: pip install pyserial pygame

Chạy: python game_viewer.py --port COM6
       python game_viewer.py --port COM6 --baud 115200
"""

import serial
import pygame
import argparse
import time
import sys

# ── Cấu hình giao thức ──────────────────────────────────────────────
COLS        = 10
ROWS        = 20
FRAME_BYTES = COLS * ROWS        # 200 bytes dữ liệu grid
FRAME_TOTAL = 2 + FRAME_BYTES + 1  # sync(2) + grid(200) + checksum(1) = 203

SYNC1 = 0xAA
SYNC2 = 0x55

# ── Bảng màu Tetris chuẩn (Tetris Guideline) ─────────────────────
#   Index → (R, G, B)
PALETTE = {
    0x00: ( 20,  20,  20),   # Đen  — ô trống
    0x01: (220,  50,  50),   # Đỏ   — Z-piece
    0x02: ( 50, 200,  50),   # Xanh lá — S-piece
    0x03: ( 50,  80, 220),   # Xanh dương — J-piece
    0x04: (240, 210,  40),   # Vàng — O-piece (2×2)
    0x05: ( 50, 210, 230),   # Cyan — I-piece
    0x06: (175,  50, 200),   # Tím  — T-piece
    0x07: (240, 130,  20),   # Cam  — L-piece
}

# ── Cấu hình hiển thị (độ phân giải Tetris cao) ───────────────────
BLOCK_SIZE  = 40            # Pixel mỗi ô game (40px = rõ nét, chuẩn Tetris)
BORDER      = 2             # Viền mỗi ô (pixel)
WIN_W = COLS * BLOCK_SIZE   # Chỉ hiển thị lưới
WIN_H = ROWS * BLOCK_SIZE                 # 800

BG_COLOR     = ( 8,  8, 12)
GRID_COLOR   = (35, 35, 45)
BORDER_COLOR = (55, 55, 70)


def draw_block(surface, x, y, color_idx):
    """Vẽ 1 ô game với hiệu ứng 3D bevel."""
    color = PALETTE.get(color_idx, (120, 0, 120))
    bx = x + BORDER
    by = y + BORDER
    bw = BLOCK_SIZE - BORDER * 2
    bh = BLOCK_SIZE - BORDER * 2

    # Nền ô
    pygame.draw.rect(surface, color, (bx, by, bw, bh))

    if color_idx != 0x00:
        # Highlight sáng (trên + trái)
        hi = tuple(min(c + 70, 255) for c in color)
        pygame.draw.line(surface, hi, (bx, by), (bx + bw - 1, by), 3)
        pygame.draw.line(surface, hi, (bx, by), (bx, by + bh - 1), 3)
        # Shadow tối (dưới + phải)
        sh = tuple(max(c - 70, 0) for c in color)
        pygame.draw.line(surface, sh, (bx, by + bh - 1), (bx + bw - 1, by + bh - 1), 3)
        pygame.draw.line(surface, sh, (bx + bw - 1, by), (bx + bw - 1, by + bh - 1), 3)
        # Inner fill (middle tone)
        mid = tuple((c + color[i]) // 2 for i, c in enumerate(color))
        pygame.draw.rect(surface, color, (bx + 3, by + 3, bw - 6, bh - 6))


def draw_grid(surface, frame_data):
    """Vẽ grid 10x20 từ frame_data (200 bytes, column-major)."""
    for c in range(COLS):
        for r in range(ROWS):
            color_idx = frame_data[c * ROWS + r]
            x = c * BLOCK_SIZE
            y = r * BLOCK_SIZE
            draw_block(surface, x, y, color_idx)


def parse_frame(buf):
    """Parse 203-byte frame. Trả về mảng 200 byte dữ liệu hoặc None nếu lỗi."""
    if len(buf) < FRAME_TOTAL:
        return None
    if buf[0] != SYNC1 or buf[1] != SYNC2:
        return None

    grid = buf[2:2 + FRAME_BYTES]
    chk_expected = 0
    for b in grid:
        chk_expected ^= b
    
    # Kiểm tra Checksum
    if chk_expected != buf[2 + FRAME_BYTES]:
        return None 

    return grid


def main():
    parser = argparse.ArgumentParser(description="FPGA UART Game Viewer")
    parser.add_argument("--port",  default="COM3", help="Tên cổng COM (vd: COM3)")
    parser.add_argument("--baud",  type=int, default=115200, help="Tốc độ Baudrate")
    args = parser.parse_args()

    # ── Mở UART ──────────────────────────────────────────────────
    try:
        ser = serial.Serial(args.port, args.baud, timeout=0.05)
        print(f"[OK] Đã mở cổng {args.port} với tốc độ {args.baud} baud")
    except Exception as e:
        print(f"[ERROR] Không thể mở cổng Serial: {e}")
        sys.exit(1)

    # ── Pygame init ───────────────────────────────────────────────
    pygame.init()
    screen = pygame.display.set_mode((WIN_W, WIN_H))
    pygame.display.set_caption(f"FPGA Tetris Viewer")
    clock = pygame.time.Clock()

    # Buffer chứa dữ liệu thô từ UART và Grid màn hình hiện tại
    rx_buf = bytearray()
    frame_data = [0] * FRAME_BYTES   

    print(f"Đang chờ dữ liệu từ mạch FPGA... (Nhấn ESC để thoát)")

    running = True
    while running:
        # Xử lý sự kiện bàn phím/chuột
        for event in pygame.event.get():
            if event.type == pygame.QUIT or (event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE):
                running = False

        # Đọc dữ liệu từ mạch FPGA đẩy lên
        try:
            data = ser.read(512)
            if data:
                rx_buf.extend(data)
        except Exception:
            pass

        # Tìm và bóc tách từng Khung hình (Frame)
        while len(rx_buf) >= FRAME_TOTAL:
            # Tìm Header (0xAA 0x55)
            idx = -1
            for i in range(len(rx_buf) - 1):
                if rx_buf[i] == SYNC1 and rx_buf[i + 1] == SYNC2:
                    idx = i
                    break

            if idx < 0:
                rx_buf = rx_buf[-1:]  # Giữ lại 1 byte cuối phòng khi bị cắt nửa chừng
                break
            
            if idx > 0:
                rx_buf = rx_buf[idx:]  # Xóa bỏ các byte rác nằm trước Header

            if len(rx_buf) < FRAME_TOTAL:
                break

            # Đã có đủ 203 byte của 1 Frame
            frame_raw = rx_buf[:FRAME_TOTAL]
            rx_buf    = rx_buf[FRAME_TOTAL:]

            # Phân tích Frame, nếu dữ liệu chuẩn xác thì cập nhật lên màn hình
            grid = parse_frame(frame_raw)
            if grid:
                frame_data = list(grid)

        # ── Render Đồ Họa ─────────────────────────────────────────
        screen.fill(BG_COLOR)

        # Vẽ các đường kẻ lưới (Grid lines)
        for c in range(COLS + 1):
            pygame.draw.line(screen, GRID_COLOR, (c * BLOCK_SIZE, 0), (c * BLOCK_SIZE, WIN_H))
        for r in range(ROWS + 1):
            pygame.draw.line(screen, GRID_COLOR, (0, r * BLOCK_SIZE), (WIN_W, r * BLOCK_SIZE))

        # Vẽ các khối gạch Tetris
        draw_grid(screen, frame_data)

        pygame.display.flip()
        clock.tick(60)  # Cố định tốc độ quét của cửa sổ là 60 FPS

    ser.close()
    pygame.quit()


if __name__ == "__main__":
    main()
