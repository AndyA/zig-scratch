import os

MIN_SIZE = 1431655677
MAX_SIZE = 1431655680


def step_size(size: int) -> int:
    return size + 1


def make_file(path: str, size: int) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.truncate(size)


size = MIN_SIZE
for i in range(100):
    print(size)
    make_file(f"tmp/f{i:02}.bin", size)
    if size > MAX_SIZE:
        break
    size = step_size(size)
