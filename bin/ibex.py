low = 120

for len in range(1, 9):
    span = 1 << (len * 8)
    high = low + span - 1
    print(f".{{ .bytes = &.{{ 0x{len + 0xF7:02x}{', 0x00' * len} }}, .want = {low} }},")
    print(
        f".{{ .bytes = &.{{ 0x{len + 0xF7:02x}{', 0xff' * len} }}, .want = {high} }},"
    )
    low += span

high = -121
for len in range(1, 9):
    span = 1 << (len * 8)
    low = high - span + 1
    print(f".{{ .bytes = &.{{ 0x{8 - len:02x}{', 0xff' * len} }}, .want = {high} }},")
    print(f".{{ .bytes = &.{{ 0x{8 - len:02x}{', 0x00' * len} }}, .want = {low} }},")
    high -= span

# .{ .bytes = &.{ 0xf8, 0x00 }, .want = 120 },
# .{ .bytes = &.{0xf7}, .want = 119 },
# .{ .bytes = &.{0x81}, .want = 1 },
# .{ .bytes = &.{0x80}, .want = 0 },
# .{ .bytes = &.{0x7f}, .want = -1 },
# .{ .bytes = &.{0x08}, .want = -120 },
