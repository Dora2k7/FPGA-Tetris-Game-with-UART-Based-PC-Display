#!/usr/bin/env python3
"""
game_viewer.py - Hiển thị game FPGA qua UART lên màn hình laptop
Yêu cầu: pip install pyserial pygame

Chạy: python game_viewer.py --port COM3
       python game_viewer.py --port COM3 --baud 115200
"""

import serial
import pygame
import argparse
import time
import sys

# ── Cấu hình giao thức ──────────────────────────────────────────────
COLS   = 10
ROWS   = 20
FRAME_BYTES = COLS * ROWS   # 200 bytes dữ liệu grid
FRAME_TOTAL = 2 + FRAME_BYTES + 1  # sync(2) + grid(200) + checksum(1) = 203

SYNC1 = 0xAA
SYNC2 = 0x55

# ── Bảng màu (index → RGB) ─────────────────────────────────────────
PALETTE = {
    0x00: (15,  15,  15),   # Đen (ô trống)
    0x01: (220,  50,  50),  # Đỏ
    0x02: (50,  220,  50),  # Xanh lá
    0x03: (50,   80, 220),  # Xanh dương
    0x04: (220, 200,  50),  # Vàng
    0x05: (50,  220, 220),  # Cyan
    0x06: (200,  50, 200),  # Magenta
    0x07: (255, 140,   0),  # Cam
}

# ── Cấu hình hiển thị ──────────────────────────────────────────────
BLOCK_SIZE  = 30            # Pixel mỗi ô game
BORDER      = 2             # Viền mỗi ô (pixel)
PANEL_WIDTH = 200           # Panel thông tin bên phải
WIN_W = COLS * BLOCK_SIZE + PANEL_WIDTH
WIN_H = ROWS * BLOCK_SIZE

BG_COLOR     = (10, 10, 10)
GRID_COLOR   = (40, 40, 40)
BORDER_COLOR = (60, 60, 60)


def draw_grid(surface, frame_data):
    """Vẽ grid 10x20 từ frame_data (200 bytes, column-major)."""
    for c in range(COLS):
        for r in range(ROWS):
            color_idx = frame_data[c * ROWS + r]
            color = PALETTE.get(color_idx, (100, 0, 100))  # Magenta nếu lỗi

            x = c * BLOCK_SIZE
            y = r * BLOCK_SIZE

            # Ô nền
            pygame.draw.rect(surface, color,
                             (x + BORDER, y + BORDER,
                              BLOCK_SIZE - BORDER * 2,
                              BLOCK_SIZE - BORDER * 2))

            # Highlight (3D effect) nếu ô không đen
            if color_idx != 0:
                # Viền sáng trên/trái
                pygame.draw.line(surface, tuple(min(c + 60, 255) for c in color),
                                 (x + BORDER, y + BORDER),
                                 (x + BLOCK_SIZE - BORDER - 1, y + BORDER), 2)
                pygame.draw.line(surface, tuple(min(c + 60, 255) for c in color),
                                 (x + BORDER, y + BORDER),
                                 (x + BORDER, y + BLOCK_SIZE - BORDER - 1), 2)
                # Viền tối dưới/phải
                pygame.draw.line(surface, tuple(max(c - 60, 0) for c in color),
                                 (x + BORDER, y + BLOCK_SIZE - BORDER - 1),
                                 (x + BLOCK_SIZE - BORDER - 1, y + BLOCK_SIZE - BORDER - 1), 2)


def draw_panel(surface, font, fps, frame_count, error_count, total_frames):
    """Vẽ panel thông tin bên phải."""
    x0 = COLS * BLOCK_SIZE + 10

    surface.fill((20, 20, 30), (COLS * BLOCK_SIZE, 0, PANEL_WIDTH, WIN_H))

    def txt(text, y, color=(200, 200, 200)):
        s = font.render(text, True, color)
        surface.blit(s, (x0, y))

    txt("FPGA UART GAME", 10, (100, 200, 255))
    txt(f"FPS: {fps:.1f}", 50, (100, 255, 100))
    txt(f"Frames: {frame_count}", 75)
    txt(f"Errors: {error_count}", 100, (255, 100, 100) if error_count > 0 else (200, 200, 200))

    err_rate = error_count / max(total_frames, 1) * 100
    txt(f"Err rate: {err_rate:.1f}%", 125, (255, 150, 50) if err_rate > 1 else (200, 200, 200))

    txt("─" * 18, 155)
    txt("Controls:", 175, (200, 200, 100))
    txt("KEY0 = Up", 200)
    txt("KEY1 = Down", 220)
    txt("KEY2 = Reset", 240)
    txt("─" * 18, 265)
    txt("Grid: 10 x 20", 285)
    txt("Protocol:", 310)
    txt("AA 55 [200B] CHK", 330, (150, 150, 150))
    txt("115200 baud", 355, (150, 150, 150))


def parse_frame(buf):
    """Parse 203-byte frame. Returns (grid_bytes, ok) hoặc (None, False)."""
    if len(buf) < FRAME_TOTAL:
        return None, False
    if buf[0] != SYNC1 or buf[1] != SYNC2:
        return None, False

    grid = buf[2:2 + FRAME_BYTES]
    chk_expected = 0
    for b in grid:
        chk_expected ^= b
    chk_got = buf[2 + FRAME_BYTES]

    if chk_expected != chk_got:
        return grid, False  # Data có nhưng checksum lỗi

    return grid, True


def main():
    parser = argparse.ArgumentParser(description="FPGA UART Game Viewer")
    parser.add_argument("--port", default="COM3", help="COM port (e.g. COM3 or /dev/ttyUSB0)")
    parser.add_argument("--baud", type=int, default=115200)
    args = parser.parse_args()

    # ── Mở UART ──────────────────────────────────────────────────
    try:
        ser = serial.Serial(args.port, args.baud, timeout=0.05)
        print(f"[OK] Opened {args.port} @ {args.baud} baud")
    except Exception as e:
        print(f"[ERROR] Cannot open serial port: {e}")
        print(f"Tip: Try --port COM4 hoặc COM5 (kiểm tra Device Manager)")
        sys.exit(1)

    # ── Pygame init ───────────────────────────────────────────────
    pygame.init()
    screen = pygame.display.set_mode((WIN_W, WIN_H))
    pygame.display.set_caption(f"FPGA Game Viewer — {args.port} @ {args.baud}")
    font = pygame.font.SysFont("monospace", 14)
    clock = pygame.time.Clock()

    # Trạng thái
    rx_buf      = bytearray()
    frame_data  = [0] * FRAME_BYTES   # Grid hiện tại
    frame_count = 0
    error_count = 0
    total_frames = 0

    fps_timer   = time.time()
    fps_frames  = 0
    fps_display = 0.0

    print("Đang chờ dữ liệu từ FPGA...")
    print("Nhấn Ctrl+C hoặc đóng cửa sổ để thoát.")

    running = True
    while running:
        # ── Xử lý events ────────────────────────────────────────
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
            if event.type == pygame.KEYDOWN:
                if event.key == pygame.K_ESCAPE:
                    running = False

        # ── Đọc UART ────────────────────────────────────────────
        try:
            data = ser.read(512)
            if data:
                rx_buf.extend(data)
        except Exception:
            pass

        # ── Parse frame ─────────────────────────────────────────
        while len(rx_buf) >= FRAME_TOTAL:
            # Tìm sync header
            idx = -1
            for i in range(len(rx_buf) - 1):
                if rx_buf[i] == SYNC1 and rx_buf[i + 1] == SYNC2:
                    idx = i
                    break

            if idx < 0:
                rx_buf = rx_buf[-1:]  # Giữ lại byte cuối phòng partial sync
                break

            if idx > 0:
                rx_buf = rx_buf[idx:]  # Bỏ rác trước sync

            if len(rx_buf) < FRAME_TOTAL:
                break

            frame_raw = rx_buf[:FRAME_TOTAL]
            rx_buf    = rx_buf[FRAME_TOTAL:]

            grid, ok = parse_frame(frame_raw)
            total_frames += 1
            if ok:
                frame_data  = list(grid)
                frame_count += 1
                fps_frames  += 1
            else:
                error_count += 1

        # ── Tính FPS mỗi giây ───────────────────────────────────
        now = time.time()
        if now - fps_timer >= 1.0:
            fps_display = fps_frames / (now - fps_timer)
            fps_frames  = 0
            fps_timer   = now

        # ── Vẽ ──────────────────────────────────────────────────
        screen.fill(BG_COLOR)

        # Vẽ ô grid (đường kẻ nền)
        for c in range(COLS + 1):
            pygame.draw.line(screen, GRID_COLOR,
                             (c * BLOCK_SIZE, 0),
                             (c * BLOCK_SIZE, WIN_H))
        for r in range(ROWS + 1):
            pygame.draw.line(screen, GRID_COLOR,
                             (0, r * BLOCK_SIZE),
                             (COLS * BLOCK_SIZE, r * BLOCK_SIZE))

        draw_grid(screen, frame_data)
        draw_panel(screen, font, fps_display, frame_count, error_count, total_frames)

        pygame.display.flip()
        clock.tick(60)  # Render 60 FPS ở phía laptop

    ser.close()
    pygame.quit()
    print(f"\nKết quả: {frame_count} frames OK, {error_count} lỗi")
    print(f"FPS cuối: {fps_display:.1f}")


if __name__ == "__main__":
    main()
