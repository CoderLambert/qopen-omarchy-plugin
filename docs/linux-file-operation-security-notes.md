# Linux 文件操作安全：从 Path、inode、FD 到 TOCTOU、Symlink、FIFO 与安全原子写入

> 以 QOpen 的一次安全审查为案例，系统整理 Linux 文件系统安全中最容易被业务开发者忽略的基础概念与工程实践。
>
> 目标不是记住几个 `os.open()` 参数，而是建立一套可复用的文件安全思维模型。

---

## 1. 背景：为什么普通的文件读写代码会变成安全问题

在一般业务开发中，我们很容易把：

```python
Path("config.json").open()
```

理解成：

> “读取 `config.json` 这个文件。”

但在 Linux 文件系统中，更准确的说法是：

> “让内核根据路径字符串重新解析一次文件系统名字空间，并打开当时这个路径所指向的对象。”

这两种理解之间的差异，就是大量文件系统安全问题的来源。

QOpen 最初的实现属于典型的“普通应用代码”模型：

```python
if CONFIG_PATH.exists():
    with CONFIG_PATH.open("r", encoding="utf-8") as file:
        config = json.load(file)
```

从业务逻辑看没有问题：

1. 检查文件是否存在；
2. 打开文件；
3. 解析 JSON；
4. 校验配置。

但从安全角度，这段代码隐含了几个并不成立的假设：

- `CONFIG_PATH.exists()` 和后面的 `CONFIG_PATH.open()` 操作的是同一个文件对象；
- 路径的父目录不会被替换；
- `config.json` 一定是普通文件；
- 文件不是 symlink、FIFO、device、socket 等特殊对象；
- 文件不会在读取过程中被并发修改；
- 文件大小总是合理；
- QML 直接读取文件不会阻塞桌面 Shell；
- subprocess 输出总是有限。

安全审查要求我们把这些隐含假设全部显式化。

---

# 2. Linux 文件系统的核心模型

## 2.1 路径不是文件

例如：

```text
/home/lambert/.config/qopen/config.json
```

只是一个 **path / pathname（路径名）**。

Linux 会逐层解析：

```text
/
└── home
    └── lambert
        └── .config
            └── qopen
                └── config.json
```

目录可以理解成一张：

```text
名字 → inode
```

的映射表。

例如：

```text
qopen/
├── config.json  → inode 91273
├── foo.txt      → inode 91274
└── backup.json  → inode 91275
```

真正代表文件对象的是 inode，而不是文件名。

---

## 2.2 inode

inode 可以粗略理解为：

> Linux 文件对象的身份记录。

它包含：

- 文件类型；
- owner UID；
- permission；
- size；
- hard link 数量；
- 修改时间；
- 数据块位置；
- 其他 metadata。

查看 inode：

```bash
ls -li ~/.config/qopen
```

或者：

```bash
stat ~/.config/qopen/config.json
```

例如：

```text
Inode: 91273
Links: 1
```

需要注意：

```text
路径名 ≠ inode
```

同一个路径名在不同时间完全可以指向不同 inode。

---

# 3. File Descriptor：比路径更重要的对象

Python：

```python
f = open("config.json")
```

底层最终会让 Linux 执行类似：

```c
open(...)
```

成功后，内核返回一个小整数，例如：

```text
3
4
5
```

这就是 **File Descriptor（FD，文件描述符）**。

可以理解为：

> 当前进程持有的、指向一个已经打开文件对象的句柄。

进程可能具有：

```text
fd 0 → stdin
fd 1 → stdout
fd 2 → stderr
fd 3 → /
fd 4 → ~/.config/qopen
fd 5 → config.json
```

可以查看当前 shell 的 FD：

```bash
ls -l /proc/$$/fd
```

---

## 3.1 Path 与 FD 的本质区别

可以记住一句：

> **Path 是名字，FD 是已经打开对象的引用。**

Path：

```text
/home/lambert/.config/qopen/config.json
```

意味着：

> 请重新根据这个名字查找对象。

FD：

```text
fd 5
```

意味着：

> 就是我刚刚已经打开的那个对象。

例如：

```text
config.json → inode A
```

程序：

```python
fd = os.open("config.json", ...)
```

得到：

```text
fd 5 → inode A
```

随后另一个进程执行：

```bash
rm config.json
ln -s /tmp/evil config.json
```

此时 pathname 已经变成：

```text
config.json → /tmp/evil → inode B
```

但是：

```text
fd 5
```

仍然指向 inode A。

这就是 descriptor-based programming 在安全代码中的重要价值。

---

# 4. Symlink：路径为什么会“骗人”

Symbolic Link（符号链接）是一个特殊文件：

```bash
ln -s ~/.bashrc config.json
```

结构：

```text
config.json
    │
    │ symlink
    ↓
~/.bashrc
```

普通：

```python
open("config.json")
```

会默认 follow symlink。

于是代码看起来打开：

```text
config.json
```

实际上可能读取：

```text
~/.bashrc
```

---

## 4.1 `O_NOFOLLOW`

Linux 提供：

```python
os.O_NOFOLLOW
```

例如：

```python
fd = os.open(
    "config.json",
    os.O_RDONLY | os.O_NOFOLLOW,
)
```

如果最终路径组件是 symlink，就失败，而不是继续跟随目标。

但这只能解决“最终组件”的 symlink 问题。

---

# 5. 为什么只检查 `config.json` 还不够

考虑：

```text
/home/lambert/.config/qopen/config.json
```

即使：

```text
config.json
```

本身不是 symlink，

父目录：

```text
qopen
```

也可能是：

```text
qopen -> /tmp/evil
```

于是：

```text
/home/lambert/.config/qopen/config.json
```

实际上解析到：

```text
/tmp/evil/config.json
```

因此安全审查中经常会要求：

> complete parent-directory traversal

也就是：

> 整条父目录链都必须受到保护。

---

# 6. descriptor-relative 目录遍历

安全做法不是一次打开整个路径：

```python
open("/home/lambert/.config/qopen/config.json")
```

而是从 `/` 开始，一层一层打开目录：

```python
root_fd = os.open(
    "/",
    os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC,
)
```

然后：

```python
home_fd = os.open(
    "home",
    os.O_RDONLY
    | os.O_DIRECTORY
    | os.O_NOFOLLOW
    | os.O_CLOEXEC,
    dir_fd=root_fd,
)
```

再：

```python
user_fd = os.open(
    "lambert",
    ...,
    dir_fd=home_fd,
)
```

一直到：

```text
qopen_dir_fd
```

最后：

```python
config_fd = os.open(
    "config.json",
    ...,
    dir_fd=qopen_dir_fd,
)
```

---

## 6.1 `dir_fd`

`dir_fd` 的含义可以理解为：

> 不要从全局 pathname 重新开始解析，就从我已经打开的这个目录对象下面找。

普通：

```python
os.open(
    "/home/lambert/.config/qopen/config.json",
    ...,
)
```

是：

```text
name-based lookup
```

而：

```python
os.open(
    "config.json",
    ...,
    dir_fd=qopen_dir_fd,
)
```

是：

```text
descriptor-relative lookup
```

---

# 7. TOCTOU：最典型的路径竞争问题

旧代码：

```python
if path.exists():
    path.open()
```

看起来合理，但存在：

```text
Time Of Check
    ↓
Time Of Use
```

即 TOCTOU。

可能出现：

```text
QOpen                         另一个进程

path.exists()
    ↓
regular file

                              rm path
                              ln -s target path

path.open()
    ↓
打开 target
```

因此：

```python
if path.is_symlink():
    reject()

path.open()
```

也不够安全。

因为：

```text
check
```

和：

```text
use
```

仍然是两个独立 pathname lookup。

---

# 8. 安全顺序：open → fstat

安全敏感代码通常更倾向：

```text
open
↓
得到 fd
↓
fstat(fd)
↓
验证真实对象
```

而不是：

```text
stat(path)
↓
open(path)
```

因为：

```python
os.fstat(fd)
```

询问的是：

> 我已经打开的这个对象到底是什么？

而不是：

> 这个 pathname 此刻又指向什么？

---

# 9. Linux 的“文件”不仅是普通文件

Linux 文件系统对象可能包括：

| 类型 | `ls -l` 首字符 | 说明 |
|---|---:|---|
| Regular file | `-` | 普通文件 |
| Directory | `d` | 目录 |
| Symlink | `l` | 符号链接 |
| FIFO | `p` | Named Pipe |
| Socket | `s` | Unix Socket |
| Character device | `c` | 字符设备 |
| Block device | `b` | 块设备 |

文件扩展名对 Linux 内核没有约束。

例如：

```bash
mkfifo config.json
```

完全合法。

因此：

```text
文件名叫 config.json
```

并不能说明它真的是：

```text
普通 JSON 文件
```

---

# 10. FIFO：为什么普通 `open()` 可能卡住

FIFO 又称：

```text
Named Pipe
```

创建：

```bash
mkfifo /tmp/qopen-learning/config.json
```

确认：

```bash
file /tmp/qopen-learning/config.json
```

输出：

```text
fifo (named pipe)
```

普通：

```python
f = open(
    "/tmp/qopen-learning/config.json",
    "r",
)
```

可能直接阻塞在 `open()`。

原因是 FIFO 的语义是：

```text
Reader
    ↓
open FIFO for read
    ↓
等待 Writer
```

直到另一个进程：

```bash
echo hello > /tmp/qopen-learning/config.json
```

reader 才继续。

对于普通 CLI，这可能只是一个卡住的命令。

但如果发生在：

```text
Quickshell / Desktop Shell
```

就可能拖住整个桌面组件。

---

# 11. `O_NONBLOCK`

因此安全打开未知文件对象时，会考虑：

```python
os.O_NONBLOCK
```

例如：

```python
fd = os.open(
    path,
    os.O_RDONLY | os.O_NONBLOCK,
)
```

对于 FIFO：

```text
不会为了等待 writer 无限阻塞
```

但：

> `O_NONBLOCK` 只解决“不要先卡死”，并不能证明对象是安全文件。

因此必须继续：

```python
info = os.fstat(fd)

if not stat.S_ISREG(info.st_mode):
    reject()
```

---

# 12. `S_ISREG`

```python
stat.S_ISREG(info.st_mode)
```

用于确认：

> 当前 FD 真正指向的是 regular file。

组合：

```text
O_NOFOLLOW
    ↓
拒绝 symlink

O_NONBLOCK
    ↓
避免特殊对象在 open 阶段阻塞

fstat(fd)
    ↓
检查已经打开的对象

S_ISREG
    ↓
只允许普通文件
```

这是安全文件读取中非常重要的一套组合。

---

# 13. Hard Link：为什么 `O_NOFOLLOW` 还不够

Hard Link 与 Symlink 不同。

例如：

```bash
echo hello > a.txt
ln a.txt b.txt
```

可能看到：

```text
12345 a.txt
12345 b.txt
```

两个名字指向同一个 inode：

```text
a.txt ─────┐
           ├── inode 12345
b.txt ─────┘
```

Hard Link 本身不是 symlink，所以：

```text
O_NOFOLLOW
```

无法发现它。

---

## 13.1 `st_nlink`

```python
info = os.fstat(fd)

print(info.st_nlink)
```

可以看到 inode 有多少 hard link。

如果：

```text
st_nlink = 2
```

说明至少有两个路径名指向同一个 inode。

对于像 QOpen state file 这样的私有状态文件，可以采用较保守策略：

```python
if info.st_nlink != 1:
    reject()
```

即：

> QOpen 的 state inode 不允许被其他路径名共享。

---

# 14. Owner 与 Permission

安全文件不仅需要验证类型，还需要验证 owner：

```python
if info.st_uid != os.geteuid():
    reject()
```

其中：

```text
st_uid
```

是文件 owner UID；

```python
os.geteuid()
```

是当前进程的 effective UID。

目录或状态文件也不能允许其他账户写入：

```python
mode = stat.S_IMODE(info.st_mode)

if mode & 0o022:
    reject()
```

`0o022` 代表：

```text
group write
+
other write
```

---

## 14.1 `0600` / `0700`

典型：

```text
0600
```

文件：

```text
owner: rw
group: -
other: -
```

典型：

```text
0700
```

目录：

```text
owner: rwx
group: ---
other: ---
```

但必须明确：

> `0600` 防的是其他 UID，并不能防同一个 UID 下的其他进程。

同 UID 进程理论上仍能直接修改用户自己的文件。

---

# 15. Same-user attack 到底在防什么

审查中常见：

> A same-user process can race or pre-place these paths.

这里并不是说：

> 我们能够完全阻止同 UID 程序修改 QOpen 配置。

这是做不到的。

真正要防的是：

> 不要让另一个进程把 QOpen 骗去操作“本来不应该操作的其他对象”。

例如：

```text
config.json.bak -> ~/.bashrc
```

QOpen 以为：

```text
我在写 backup
```

实际：

```text
我在写 ~/.bashrc
```

这种问题属于：

```text
Confused Deputy
```

即：

> 一个本来合法的程序，被攻击者利用成为错误操作其他资源的代理。

---

# 16. 读取大小为什么必须有限

旧代码：

```python
json.load(file)
```

最终需要将输入读入内存并解析。

如果输入：

```text
1 MB
100 MB
1 GB
```

程序就可能消耗大量资源。

正确思路不是：

```text
读完
↓
发现太大
↓
reject
```

而是：

```text
边读
↓
边计数
↓
超过 limit
↓
立即停止
```

---

## 16.1 metadata size + actual byte count

可以先检查：

```python
if info.st_size > MAX_BYTES:
    reject()
```

这是低成本快速 gate。

但还应该实际读取时累计：

```python
total = 0

while True:
    chunk = os.read(fd, 65536)

    if not chunk:
        break

    total += len(chunk)

    if total > MAX_BYTES:
        reject()
```

形成：

```text
metadata bound
+
runtime streamed-byte bound
```

---

# 17. 为什么读取前后还要 `fstat`

即使已经拿到 FD：

```text
fd → inode A
```

另一个同 UID 进程仍可能直接修改：

```text
inode A
```

因此可能出现：

```text
开始读取
↓
另一个进程修改文件
↓
继续读取
```

得到一个不一致的数据快照。

可以：

```python
before = os.fstat(fd)

read(...)

after = os.fstat(fd)
```

比较：

```text
st_dev
st_ino
st_size
st_mtime_ns
st_ctime_ns
```

如果变化：

```text
reject and retry
```

属于典型：

```text
fail closed
```

策略。

---

# 18. Fail Closed

Fail Open：

```text
发生异常或无法确认
↓
继续执行
```

Fail Closed：

```text
发生异常或无法确认
↓
停止操作
```

安全敏感文件操作通常倾向：

```text
symlink?
→ reject

special file?
→ reject

wrong owner?
→ reject

hard link?
→ reject

too large?
→ reject

changed while reading?
→ reject
```

安全工程中：

> “不确定”通常不应该自动等于“可以继续”。

---

# 19. 安全写文件为什么比安全读文件更复杂

最简单的写法：

```python
with open("config.json", "w") as f:
    json.dump(config, f)
```

会先：

```text
truncate existing file
```

然后逐步写入。

如果：

```text
写到一半进程 crash
```

原文件可能只剩：

```json
{
  "version": 1,
  "items": [
    {
      "id":
```

即半截 JSON。

因此配置文件通常应该采用：

```text
temporary file
↓
完整写入
↓
fsync
↓
atomic replace
```

---

# 20. 目录应该理解成“名字 → inode”的映射表

例如：

```text
qopen directory

config.json      → inode 100
```

创建 temp：

```text
config.json      → inode 100
.qopen-abc.tmp   → inode 200
```

完成写入后：

```text
rename / replace
```

变成：

```text
config.json      → inode 200
```

这比“文件夹里装着文件”的模型更适合理解 rename、hard link 与原子写入。

---

# 21. Atomic Replace

在同一 filesystem 中：

```text
rename
```

通常可以提供原子的目录项切换。

其他进程看到：

```text
before:
config.json → inode A
```

或者：

```text
after:
config.json → inode B
```

而不是看到：

```text
一半 A + 一半 B
```

因此常见配置保存流程：

```text
write temp
↓
fsync temp
↓
rename temp → config
```

---

# 22. Atomic ≠ Durable

两个概念必须区分。

## Atomic

回答：

> 其他进程观察到的是不是完整切换？

## Durable

回答：

> 系统掉电以后，修改是不是仍然存在？

Linux 写入通常先进入：

```text
kernel page cache
```

因此：

```python
os.write(...)
```

成功并不等于 SSD 已经持久化。

---

# 23. `fsync(file_fd)`

```python
os.fsync(temp_fd)
```

用于要求：

> 把这个文件的内容及必要 metadata 推进到持久存储。

所以：

```text
write
↓
fsync(file)
```

用于保护新 inode 的内容。

---

# 24. 为什么还要 `fsync(directory_fd)`

文件内容和目录项不是同一个东西。

例如：

```text
config.json → inode A
```

切换成：

```text
config.json → inode B
```

属于目录 metadata 的变化。

因此完整流程：

```text
write new inode
↓
fsync(new file)
↓
rename
↓
fsync(directory)
```

可以理解为：

```text
保证新文件内容落盘
+
保证“名字 → inode”的新映射也落盘
```

---

# 25. Backup、Lock、Temp 都属于同一个安全边界

一个常见错误是只保护：

```text
config.json
```

但忘记：

```text
config.json.bak
config.json.lock
temporary file
recovery snapshot
```

例如：

```python
shutil.copy2(
    CONFIG_PATH,
    BACKUP_PATH,
)
```

如果 backup pathname 被攻击者预先构造成危险对象，就可能形成新的攻击入口。

所以安全要求通常不是：

> “把 config.json 修安全。”

而是：

> “整个 state lifecycle 都必须使用一致的安全模型。”

即：

```text
read
lock
backup
temporary
replace
recovery
permission repair
```

全部落在同一个 trust boundary 内。

---

# 26. 为什么 `chmod(path)` 也有风险

普通：

```python
os.chmod(BACKUP_PATH, 0o600)
```

仍然是 pathname operation。

安全敏感环境更喜欢：

```python
fd = safe_open(...)
os.fchmod(fd, 0o600)
```

区别：

```text
chmod(path)
→ 再次解析路径名

fchmod(fd)
→ 直接操作已经验证过的 inode
```

---

# 27. Temp File 为什么要 `O_EXCL`

创建安全临时文件：

```python
fd = os.open(
    temp_name,
    os.O_WRONLY
    | os.O_CREAT
    | os.O_EXCL
    | os.O_NOFOLLOW
    | os.O_CLOEXEC,
    0o600,
    dir_fd=trusted_dir_fd,
)
```

`O_EXCL` 意味着：

```text
不存在
→ 创建

已经存在
→ 失败
```

避免：

```text
攻击者提前创建同名对象
```

配合高随机度名称：

```text
.qopen-<random>.tmp
```

可以显著减少 pathname pre-placement 风险。

---

# 28. 为什么 temp 应放在同一目录

推荐：

```text
qopen/
├── config.json
└── .qopen-random.tmp
```

而不是：

```text
/tmp/qopen-random.tmp
```

再移动到：

```text
~/.config/qopen/config.json
```

原因：

- 同目录通常保证同 filesystem；
- rename / replace 的原子语义更可靠；
- descriptor-relative 操作更容易建立一致边界；
- 不需要额外信任 `/tmp`。

---

# 29. Descriptor-relative `os.replace`

普通：

```python
os.replace(
    temp_path,
    CONFIG_PATH,
)
```

需要再次解析完整 pathname。

更安全：

```python
os.replace(
    temp_name,
    config_name,
    src_dir_fd=trusted_dir_fd,
    dst_dir_fd=trusted_dir_fd,
)
```

意思是：

> 就在“我已经打开并验证过的这个目录 inode”里做名字替换。

避免重新依赖：

```text
/home/lambert/.config/qopen
```

整个字符串路径。

---

# 30. Lock 的作用

如果两个正常 QOpen 进程同时：

```text
A:
read
modify
write

B:
read
modify
write
```

可能导致 lost update：

```text
B 覆盖 A
```

因此需要 lock。

旧模型：

```text
config.json.lock
```

本身又引入了一个 pathname。

新版可以：

```python
fcntl.flock(
    trusted_directory_fd,
    ...
)
```

避免创建新的 lock file pathname。

---

## 30.1 Advisory Lock

必须注意：

```text
flock
```

通常属于 advisory lock。

也就是说：

> 只有合作的进程才会遵守它。

恶意程序可以完全不理这个锁。

所以：

```text
lock
```

主要解决：

```text
正常并发一致性
```

而不是：

```text
对抗恶意进程
```

---

# 31. QML 直接读取文件为什么有问题

旧设计：

```text
QML
↓
FileView
↓
config.json
```

意味着未经验证的 filesystem object 直接进入长期运行的 desktop shell。

如果 pathname 最终是：

```text
FIFO
device
symlink
超大文件
```

可能导致：

```text
阻塞
内存增长
桌面 Shell 不稳定
```

更合理的边界：

```text
QML
↓
bounded backend process
↓
filesystem
↓
类型/owner/size/encoding/schema 验证
↓
有界 JSON response
↓
QML
```

---

# 32. 为什么 `StdioCollector` / `capture_output=True` 也可能危险

简单 subprocess：

```python
subprocess.run(
    command,
    capture_output=True,
)
```

通常会完整收集：

```text
stdout
stderr
```

如果 producer 异常输出：

```text
100 MB
1 GB
...
```

父进程会持续保存这些数据。

即使最终：

```text
发现 response 太大
↓
reject
```

也已经太晚：

```text
内存已经消耗
```

安全原则应该是：

```text
producer output
↓
chunked read
↓
byte counter
↓
超过 limit
↓
terminate producer
```

也就是：

> producer-side byte limit

而不是：

> consumer 收完之后再检查。

---

# 33. 真正的 Process Deadline

仅仅 UI 层：

```text
3 秒后显示 timeout
```

不代表后台进程真的停止。

真正 deadline 应该：

```text
start
↓
deadline
↓
超时
↓
SIGTERM
↓
短暂等待
↓
仍未退出
↓
SIGKILL
```

即：

```text
TERM → KILL
```

这样才能真正释放：

- CPU；
- pipe；
- memory；
- subprocess；
- helper resource。

---

# 34. Defense in Depth

QOpen 新设计使用多层保护：

```text
Python producer
├── filesystem type checks
├── byte limit
├── helper stdout/stderr limit
├── helper deadline
└── API response limit

QML consumer
├── response-size secondary limit
├── one-response protocol
├── request serial
└── process deadline
```

这属于：

```text
Defense in Depth
纵深防御
```

即：

> 不把整个安全性依赖在单一层。

---

# 35. QOpen 案例：旧模型与新模型

## 旧模型

```text
Path.exists()
↓
Path.open()
↓
json.load()
↓
Path.stat()
↓
shutil.copy2()
↓
chmod(path)
↓
tempfile
↓
os.replace(path, path)
```

核心问题：

```text
长期依赖 pathname
```

---

## 新模型

```text
absolute state path
↓
逐层 parent traversal
├── O_DIRECTORY
├── O_NOFOLLOW
└── dir_fd
↓
trusted state-directory fd
↓
open config relative to fd
├── O_NOFOLLOW
├── O_NONBLOCK
└── O_CLOEXEC
↓
fstat(fd)
├── S_ISREG
├── owner
├── nlink
└── mode
↓
bounded read
↓
before/after metadata
↓
UTF-8
↓
JSON
↓
schema
```

写入：

```text
trusted dir fd
↓
random temp
↓
O_CREAT | O_EXCL | O_NOFOLLOW
↓
write
↓
fchmod(fd)
↓
fsync(file)
↓
fd-relative replace
↓
fsync(directory)
```

这已经形成一个完整的安全边界。

---

# 36. 可复用的文件安全检查清单

以后看到安全敏感文件读写，可以先问：

### Path

- 这个路径是否来自用户输入？
- pathname 是否可能被其他进程替换？
- 是否存在 `check(path) → use(path)`？
- 父目录是否可能包含 symlink？

### File Object

- 是否使用 `O_NOFOLLOW`？
- 特殊文件是否可能在 open 阶段阻塞？
- 是否使用 `O_NONBLOCK`？
- 是否 `fstat(fd)`？
- 是否验证 `S_ISREG`？
- owner 是否正确？
- permission 是否合理？
- hard link 是否允许？

### Input

- 是否有最大 byte limit？
- limit 是否在读取过程中执行？
- 是否只在“全部读完后”才检查？
- 文件读取过程中变化怎么办？

### Write

- 是否直接 truncate 正式文件？
- 是否使用同目录 temp file？
- temp 是否 `O_EXCL`？
- temp 是否 random？
- 是否 `fsync(file)`？
- replace 是否原子？
- 是否 `fsync(directory)`？
- destination / backup / recovery 是否全部使用相同安全边界？

### Concurrency

- 是否存在两个正常实例同时修改？
- lock 是 advisory 还是 mandatory？
- lock 是否被误认为安全隔离？

### Subprocess

- stdout 是否有 byte limit？
- stderr 是否有 byte limit？
- stdout/stderr 是否同时消费？
- process 是否有真正 deadline？
- 超时后是否 TERM → KILL？

### UI / Long-running Process

- UI 是否直接处理未经验证的文件系统对象？
- 是否应该将 untrusted I/O 下沉到 backend process？
- consumer 是否还有 secondary limit？

---

# 37. 最值得记住的 10 条原则

1. **Path 不是文件，Path 只是名字。**
2. **每次 pathname operation 都可能重新解析路径。**
3. **FD 是已经打开对象的稳定引用。**
4. **避免 `check(path) → use(path)` 型 TOCTOU。**
5. **安全顺序通常是 `open → fstat → operate by fd`。**
6. **文件扩展名不能证明文件类型。**
7. **特殊文件可能在 open/read 阶段阻塞。**
8. **输入必须在消费过程中有界，而不是读完再判断。**
9. **安全写入需要考虑 atomicity 与 durability 两个维度。**
10. **真正安全的是完整生命周期的一致边界，而不是给某一行 API 打补丁。**

---

# 38. 常用实验命令

## 查看 inode

```bash
ls -li file
stat file
```

## 查看文件类型

```bash
file file
/usr/bin/ls -l file
```

## 创建 symlink

```bash
ln -s target link
```

## 创建 hard link

```bash
ln source hardlink
```

## 创建 FIFO

```bash
mkfifo pipe
```

## 查看当前 shell FD

```bash
ls -l /proc/$$/fd
```

## 查看 UID

```bash
id -u
```

## 查看权限

```bash
stat -c '%A %a %U %G %n' file
```

---

# 39. 建议的学习方向

这部分知识继续往下，可以按以下顺序扩展：

```text
Linux VFS
↓
inode / dentry
↓
openat / dirfd
↓
openat2
↓
rename / renameat
↓
fsync durability
↓
POSIX file locking
↓
pipes / sockets / devices
↓
process signals
↓
privilege boundary
```

其中最值得继续深入的是：

- `openat()` / `dir_fd`
- Linux VFS 中 pathname resolution 的实际过程
- inode 与 dentry 的区别
- `rename()` 原子语义
- `fsync()` 与 crash consistency
- `openat2()` 的 `RESOLVE_*` 安全能力
- `/proc/<pid>/fd`
- `flock()` / `fcntl()` lock 的区别
- symlink / hard link 的攻击模型

---

# 40. 总结

这次 QOpen 的安全问题，本质上不是：

```text
“Python 文件 API 用错了”
```

而是：

```text
从普通应用文件模型
升级到
安全敏感系统文件模型
```

普通应用关注：

```text
文件能不能读
JSON 能不能解析
配置能不能保存
```

安全模型还必须关注：

```text
这个路径现在到底指向什么？
父目录是否可信？
打开的是不是同一个对象？
它是不是普通文件？
会不会阻塞？
会不会无限输出？
能不能被 race？
写入是否原子？
断电后是否持久？
整个 state lifecycle 是否都遵守同一个边界？
```

真正值得积累的能力不是记住：

```text
O_NOFOLLOW
O_NONBLOCK
O_EXCL
```

这些参数本身，而是形成下面这套思维：

```text
Name
↓
Resolve
↓
Open
↓
Verify Object
↓
Bound Resource
↓
Operate by Descriptor
↓
Fail Closed
```

一旦这套模型建立起来，再看到文件系统、安全审查、daemon、桌面插件、系统服务等代码，就会知道应该从哪里开始寻找风险。
