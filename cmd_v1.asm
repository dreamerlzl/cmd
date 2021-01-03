org 100h 		; 可编译成COM文件
; ===================================================================
; 命令行主程序开始
;--------------------------------------------------------------------	
[section .bss]
cmdaddr: ; 内部命令例程入口地址数组
	resw N
sbuf: resb dn ; 用于存放十进制数字串的缓冲区，大小 = 常量dn（=5）
buf resb buflen ; 命令行缓冲区
Sector:
	resb 512

[section .data]
dn equ 5 ; 最大位数
drvno db 0 ; 磁盘驱动器号：0=软盘A、1=软盘B、80h=硬盘C
i dw 0 ; 循环变量
n dw 0 ; 命令串长度

N equ 10	; 内部命令总数
cslen equ 8 ; 命令串最大长度

txtn dw 0		; txt文件名串长度
txtlen equ 8	; txt文件名串最大长度

cmdstr: ; 内部命令串数组（统一串长为8，不足补空格符）
	db 'VER     '
	db 'CLS     '
	db 'A:      '
	db 'B:      '
	db 'C:      '
	db 'DIR     '
	db 'LS      '
	db 'SHOWTIME'
	db 'KIND    '
	db 'TYPE    '

fnbuf: ; COM文件名串（8+3=11字符）
	db '12345678COM'

buflen equ 80 ; 缓冲区长度=80

txtbuf:		; TXT文件名串（8+3=11字符）
	db '        TXT'
 
str1: ; 字符串1（版权信息串）
	db 'MyOS 1.0  (C) 2017 Li Caiwei'
str1len equ $ - str1 ; 版权串长

str2: ; 字符串2数组（命令行提示串）
	db 'A:/$'
str2len equ $ - str2 ; 提示串长

str3: ; 字符串3（出错信息串）
	db 'Wrong command!'
str3len equ $ - str3 ; 错误命令串长

str4: ; 字符串4（串太长信息串）
	db 'Too long!'
str4len equ $ - str4 ; 太长串长
str5: ; 字符串5（磁盘不存在信息串）
	db 'Disk not exist!'
str5len equ $ - str5 ; 磁盘不存在串长
str6: ; 字符串6（文件不存在信息串）
	db 'File not exist!'
str6len equ $ - str6 ; 文件不存在串长

builtin db "built-in"
builtinlen equ $ - builtin 
comfile  db "file in root directory"
comfilelen equ $ - comfile
nocmdstr db "no such command"
nocmdlen equ $ - nocmdstr
noparam db "no parameter!"
noparamlen equ $ - noparam

BaseOfLoader	equ	4000h	; COM文件被加载到的位置 ----  段地址
OffsetOfLoader	equ	100h	; COM文件被加载到的位置 ---- 偏移地址
RootDirSectors	equ	14		; 根目录占用的扇区数
SectorNoOfRootDirectory	equ	19	; 根目录区的首扇区号
SectorNoOfFAT1	equ	1		; FAT#1的首扇区号 = BPB_RsvdSecCnt
DeltaSectorNo	equ	17		; DeltaSectorNo = BPB_RsvdSecCnt + 
							; (BPB_NumFATs * FATSz) - 2 = 1 + (2*9) -2 = 17
							; 文件的开始扇区号 = 目录条目中的开始扇区号 
							; + 根目录占用扇区数目 + DeltaSectorNo

pkinstr db 'Press any key to continue!' ; 提示用户键入的串
pkinstrlen equ $ - pkinstr ; 串长

isec dw 0	; 当前扇区号
nsec dw 0	; 剩余扇区数
lns dw 0	; 定义行数，初值为0
secspt dw 0	; 每磁道扇区数
heads dw 0	; 磁头数

fsbuf db '0,987,654,321' ; 文件大小串
fsbuflen equ $ - fsbuf ; 串长
dsbuf db '            <DIR>          ' ; 子目录标识串
;dsbuflen equ $ - dsbuf ; 串长
volbuf db '            <VOL>          ' ; 卷标标识串
;volbuflen equ $ - volbuf
btbuf db 'Byte' ; 字节字符串
btbuflen equ $ - btbuf ; 串长

[section .text]
	; 通过AX中转，将CS的值赋给DS、ES和SS
	mov ax, cs
	mov ds, ax
	mov es, ax
	mov ss, ax
	mov sp, 100h - 4	; 置栈顶指针SP=100h-4
	
	; 初始化内部命令例程入口地址
	mov word [cmdaddr], ver		; VER 显示版权信息
	mov word [cmdaddr + 2], cls	; CLS 清屏
	mov word [cmdaddr + 4], toa	; A:  切换到A盘
	mov word [cmdaddr + 6], tob	; B:  切换到B盘
	mov word [cmdaddr + 8], toc	; C:  切换到C盘
	mov word [cmdaddr + 10], dir; DIR 显示文件目录列表
	mov word [cmdaddr + 12], dir; LS  显示文件目录列表
	mov word [cmdaddr + 14], showtime; showtime 显示系统日期和时间
	mov word [cmdaddr + 16], kind; 显示命令类型
	mov word [cmdaddr + 18], typ	; TYPE	显示文本文件内容

	; 设置中断向量（21h）showtisho
	xor ax, ax		; AX = 0
	mov fs, ax		; FS = 0
	mov word[fs:21h*4], int21h ; 设置21h号中断向量的偏移地址
	mov ax,cs 
	mov [fs:21h*4+2], ax ; 设置21h号中断向量的段地址=CS

	call getdiskparam	; 获取磁盘参数H&S（用于ReadSec和ls例程）
	
	call cls		; 清屏
	call ver		; 显示版权信息
	
again: ; 命令行循环
	call prompt		; 显示提示串
	call getstrln	; 获取键盘输入的命令串行
	call dtlen		; 确定命令串长度
	call tocap		; 转换成大写字母
	call newstr		; 构造新串
	call iscmd		; 判断是否为内部命令，如果是，则执行之，否则：
	call newline	; 回车换行
	call exec		; 执行外部命令（COM文件）
	jmp again		; 继续循环
	


; -------------------------------------------------------------------
; 命令行主程序结束
; ===================================================================


; ===================================================================
; 小型辅助例程开始
;--------------------------------------------------------------------
int21h: ; int 21h中断处理例程
	mov al, 20h		; AL = EOI
	out 20h, al		; 发送EOI到主8529A
	out 0A0h, al	; 发送EOI到从8529A
	
	; 初始化段寄存器和栈指针
	mov ax, cs 		; 通过AX中转,  将CS的值传送给DS、ES和SS
	mov ds, ax
	mov es, ax
	mov ss, ax
	mov sp, 100h - 4; 置栈顶指针SP=100h-4
	
	jmp again		; 重新开始命令行循环

; -------------------------------------------------------------------
getdiskparam: ; 获取磁盘参数H/S
	call ReadPBootSec		; 调用读入磁盘分区引导扇区例程
	mov ax, [Sector + 18h]	; AX = 每磁道扇区数
	mov [secspt], ax		; secspt = AX = 每磁道扇区数
	mov ax, [Sector + 1Ah]	; AX = 磁头数
	mov [heads], ax			; heads = AX = 磁头数
	ret						; 从例程返回
	
; -------------------------------------------------------------------
newline: ; 换行（显示回车符和换行符）
	; 显示回车符CR（置当前列号=0）
	mov ah, 0Eh 	; 功能号
	mov al, 0Dh 	; 设置AL为回车符CR（ASCII码为0DH）
	mov bl, 0 		; 对文本方式置0
	int 10h 		; 调用10H号显示中断
	; 显示换行符（当前行号++）
	mov ah, 0Eh 	; 功能号
	mov al, 0Ah 	; 设置AL为换行符LF（ASCII码为0AH）
	mov bl, 0 		; 对文本方式置0
	int 10h 		; 调用10H号显示中断
	ret				; 从例程返回

; -------------------------------------------------------------------
space: ; 显示空格符
	mov ah, 0Eh 	; 功能号
	mov al, 20h 	; 设置AL为空格符SP（ASCII码为20H）
	mov bl, 0 	; 对文本方式置0
	int 10h 		; 调用10H号显示中断
	ret			; 从例程返回
	
; -------------------------------------------------------------------
showwrong: ; 显示出错信息
	call newline 	; 回车换行
	; 获取当前光标位置（返回的行列号分别在DH和DL中）
	mov ah, 3		; 功能号
	mov bh, 0		; 第0页
	int 10h 		; 调用10H号显示中断
	; 显示出错信息串
	mov ah, 13h 	; 功能号
	mov al, 1 		; 光标放到串尾
	mov bl, 0fh 	; 亮白
	mov bh, 0 		; 第0页
	mov dl, 0 		; 第0列
	mov bp, str3 	; BP=串地址
	mov cx, str3len	; 串长
	int 10h 		; 调用10H号显示中断
	ret				; 从例程返回
	
; -------------------------------------------------------------------
showtoolong: ; 显示太长信息
	call newline 	; 回车换行
	; 获取当前光标位置（返回的行列号分别在DH和DL中）
	mov ah, 3		; 功能号
	mov bh, 0		; 第0页
	int 10h 		; 调用10H号显示中断
	; 显示太长信息串
	mov ah, 13h 	; 功能号
	mov al, 1 		; 光标放到串尾
	mov bl, 0fh 	; 亮白
	mov bh, 0 		; 第0页
	mov dl, 0 		; 第0列
	mov bp, str4 	; BP=串地址
	mov cx, str4len	; 串长
	int 10h 		; 调用10H号显示中断
	ret				; 从例程返回
	
backspace: ;处理回退符, [buf + si]为最后一个有效字符的后一个位置
	push ax        	;
	push bx        	;
	push cx
	push dx         ;
	mov ah, 03h     ;
	mov bh, 0       ;
	int 10h         ; dh是行号，dl是列号
	mov cx, 0
	add cl, dl
	cmp cl, str2len	;
	je  cannot
	dec dl          ;
	mov ah, 02h     ;
	int 10h         ; 将光标设置到前一个位置
	mov al, 20h     ; 打印一个空格符取代前一个字符
	mov ah, 0eh     ;
	int 10h         ;
	mov ah, 02h     ;
	int 10h         ;
	dec  si         ;
	mov byte[buf+si],20h; 将缓冲区的最后一个有效字符置为空格符
cannot:
	pop  dx         ;
	pop  cx
	pop  bx         ;
	pop  ax       	;
	ret             ;	
	
;--------------------------------------------------------------------
; 小型辅助例程结束
; ===================================================================

	
; ===================================================================
; 内部命令例程开始
; -------------------------------------------------------------------
ver: ; 显示版权信息
	; 获取当前光标位置（返回的行列号分别在DH和DL中）
	mov ah, 3		; 功能号
	mov bh, 0		; 第0页
	int 10h 		; 调用10H号显示中断
	; 显示版权字符串 "MyOS 1.0 (C) 2015  Li Caiwei"
	mov ah, 13h 	; 功能号
	mov al, 1 		; 光标放到串尾
	mov bl, 0fh 	; 亮白
	mov bh, 0 		; 第0页
	mov dl, 0 		; 第0列
	mov bp, str1 	; BP=串地址
	mov cx, str1len	; 串长
	int 10h 		; 调用10H号显示中断
	ret				; 从例程返回

; -------------------------------------------------------------------
cls: ; 清屏
	mov	ah, 6		; 功能号
	mov	al, 0		; 滚动的文本行数（0=整个窗口）
	mov bh, 0fh		; 设置插入空行的字符颜色为黑底亮白字
	mov cx, 0		; 窗口左上角的行号=CH、列号=CL
	mov dh, 24		; 窗口右下角的行号
	mov dl, 79		; 窗口右下角的列号
	int 10h 		; 调用10H号显示中断
	; 设置光标位置
	mov ah, 2		; 功能号
	mov bh, 0		; 第0页
	mov dh, 0		; 行号
	mov dl, 0		; 列号
	int 10h			; 显示中断
	ret				; 从例程返回
	
; -------------------------------------------------------------------
diskok: ; 判断切换到的目标磁盘是否存在（输入参数为DL=磁盘的驱动器号）
	; 利用磁盘的0号中断判断磁盘是否存在
	mov ah, 0		; 功能号=0：磁盘复位（出错置CF标志位）
	int 13h			; 调用13H号磁盘中断
	jc .1			; CF=1 磁盘不存在，切换磁盘失败
	; 磁盘存在时，返回切换磁盘例程
	ret				; 从例程返回
	
.1: ; 磁盘不存在时，显示出错信息后，退出循环，重新开始
	; 获取当前光标位置（返回的行列号分别在DH和DL中）
	mov ah, 3		; 功能号
	mov bh, 0		; 第0页
	int 10h 		; 调用10H号显示中断
	; 显示磁盘不存在的信息 "Disk not exist!"
	mov ah, 13h 	; 功能号
	mov al, 1 		; 光标放到串尾
	mov bl, 0fh 	; 亮白
	mov bh, 0 		; 第0页
	mov dl, 0 		; 第0列
	mov bp, str5 	; BP=串地址
	mov cx, str5len	; 串长
	int 10h 		; 调用10H号显示中断
	; 退出循环，重新开始
	add sp, 4		; 弹出两次call的返回地址
	jmp again		; 重新开始
	

; -------------------------------------------------------------------
toa: ; 改为A盘
	mov dl, 0		; 软盘A的驱动器号=0
	call diskok		; 如果磁盘不存在，就不切换磁盘，否则继续：
	mov byte [str2], 'A' ; 修改提示串首字母为A
	mov byte [drvno], 0 ; 设置驱动器号为0
	call getdiskparam	; 获取磁盘参数H&S（用于ReadSec和ls例程）
	add sp, 2		; 弹出call的返回地址
	jmp again		; 重新开始
	
; -------------------------------------------------------------------
tob: ; 改为B盘
	mov dl, 1		; 软盘B的驱动器号=1
	call diskok		; 如果磁盘不存在，就不切换磁盘，否则继续：
	mov byte [str2], 'B' ; 修改提示串首字母为B
	mov byte [drvno], 1 ; 设置驱动器号为1
	call getdiskparam	; 获取磁盘参数H&S（用于ReadSec和ls例程）
	add sp, 2		; 弹出call的返回地址
	jmp again		; 重新开始

; -------------------------------------------------------------------
toc: ; 改为C盘
	mov dl, 80h		; 硬盘C的驱动器号=80h
	call diskok		; 如果磁盘不存在，就不切换磁盘，否则继续：
	mov byte [str2], 'C' ; 修改提示串首字母为C
	mov byte [drvno], 80h ; 设置驱动器号为80h
	call getdiskparam	; 获取磁盘参数H&S（用于ReadSec和ls例程）
	add sp, 2		; 弹出call的返回地址
	jmp again		; 重新开始
	
;--------------------------------------------------------------------
dir: ; 显示根目录文件
	call showbpb	; 显示磁盘信息
	call ls			; 显示磁盘文件信息列表
	ret				; 从例程返回
	
; -------------------------------------------------------------------
showtime: ;显示系统日期和时间
	;call ver;
	call newline;
	mov ah, 3		; 功能号
	mov bh, 0		; 第0页
	int 10h 		; 调用10H号显示中断
	mov ah,0eh;
	mov bl,0;
	mov al,032h;
	int 10h;
	mov ah,0eh;
	mov bl,0;
	mov al,030h;
	int 10h;
	mov ah,04h;
	int 1ah;
	mov ah,0Fh;
	int 10h;
	mov ah,0eh;
	mov bl,0;
	mov al,cl;
	shr al,4;
	add al,30h;
	int 10h;
	mov al,cl;
	and al,0Fh;
	add al,30h;
	int 10h;
	mov al,02fh;
	int 10h;
	mov al,dh;
	shr al,4;
	add al,30h;
	int 10h;
	mov al,dh;
	and al,0Fh;
	add al,30h;
	int 10h;
	mov al,02fh;
	int 10h;
	mov al,dl;
	shr al,4;
	add al,30h;
	int 10h;
	mov al,dl;
	and al,0Fh;
	add al,30h;
	int 10h;
	mov al,020h;
	int 10h;
	int 10h;
	int 10h;
	
	mov ah,02h;
	int 1ah;
	mov ah,0Fh;
	int 10h;
	mov ah,0eh;
	mov bl,0;
	mov al,ch;
	shr al,4;
	add al,30h;
	int 10h;
	mov al,ch;
	and al,0Fh;
	add al,30h;
	int 10h;
	mov al,03ah;
	int 10h;
	mov al,cl;
	shr al,4;
	add al,30h;
	int 10h;
	mov al,cl;
	and al,0Fh;
	add al,30h;
	int 10h;
	mov al,03ah;
	int 10h;
	mov al,dh;
	shr al,4;
	add al,30h;
	int 10h;
	mov al,dh;
	and al,0Fh;
	add al,30h;
	int 10h;
	mov al,03ah;
	call newline;
	jmp again;

; -------------------------------------------------------------------
kind: ;显示命令的类型
	push ax;
	push bx;
	;call newline;
	;mov ax,buf;
	;mov ah,0eh;
	;int 10h;测试
	mov di,buf;
	add di,5;
	mov cx,buflen;
	sub cx,5;
	mov al,20h;
	repe scasb;当遇到第一个非空格字符时跳出循环,此时di指向第二个非空格字符
	cmp cx,0;
	jnz nothing;
	mov ah,3;
	mov bh,0;
	int 10h;
	mov ah,13h;
	mov al,1;
	mov bl,0fh;
	mov bh,0;
	mov dl,0;
	mov bp,noparam;
	mov cx,noparamlen;
	int 10h;
	jmp again;
nothing:
	mov bx,di           ;
	dec bx              ;
	;mov al,bl           ;
	;mov ah,0eh;
	;int 10h;
	mov si,bx           ;si和bx指向参数的第一个字符
	;repne scasb         ;当遇到第一个空格字符时跳出循环;di指向第一个空格字符的下一个
	;dec di              ;	
	;mov ax,di           ;
	;push ax;
	;mov ah,0eh          ;
	;int 10h             ;
	;pop ax;
	;sub ax,bx           ;ax = 参数的字符个数
	mov word [n],4     ;n = 参数的字符个数, 即参数长度
	mov di,si;
	add di,4;
	;dec di              ;di指向参数的最后一个字符
	;mov ah,0eh          ;
	;add al,'0'          ;
	;int 10h             ;
	cmp word [n],cslen  ; n > 8?
	ja toolong          ; 
;将参数转化为大写字符
	mov cx,word [n]          ;
caploop:
	cmp byte[bx],61h;
	jb notlc			  ;
	cmp byte[bx],7ah;
	ja notlc			  ;
	sub byte[bx],20h      ;
notlc:;不是小写字母
	inc bx      ;
	loop caploop;
;构造参数文件名串
	mov di,fnbuf;
	mov cx,word [n]  ;
	cld         ;
	rep movsb   ;移动完成
;开始看这个参数是否是内置命令
	mov word [i], 0	; 外循环变量/内部命令的序号i=0（初值为0）
	mov dx, cmdstr	; 命令串的初始起始地址
isbuiltin:; 外循环
	mov si, fnbuf	; 源串起始地址
	mov di, dx		; 目的串起始地址
	mov cx, cslen 	; 内循环次数
	; 重复比较两字符串中的字符，CX--，直到不相等或CX=0
	repe cmpsb		; CX>0 && [DS:SI]==[ES:DI]时,CX--、SI++、DI++，继续循环
	jcxz isin		; CX=0，表示两串相等，为第BX个内部命令串，跳转执行该命令
	inc word [i]	; CX≠0，表示两串不等，i++
	cmp word [i], N	; i=N（内部命令总数）？
	je iisout		; 不是内部命令，退出循环
	add dx, cslen	; DX + 8 =下一命令串的起始地址
	jmp isbuiltin	; 继续外循环
isin:;是内置命令
	mov ah,3            ;
	mov bh,0            ;
	int 10h             ;获取光标位置
	mov ah,0eh          ;
	mov al,0dh          ;
	int 10h             ;
	mov ah,13h          ;
	mov al,1            ;
	mov bl,0fh          ;
	mov bh,0            ;
	mov dl,0            ;
	mov bp,builtin      ;
	mov cx,builtinlen   ;
	int 10h             ;
	jmp typexit         ;
iisout: ; 查看是否为根目录的命令
	call isout          ;
	cmp al,0            ;
	jz  nocmd           ;
	mov ah,3            ;
	mov bh,0            ;
	int 10h             ;获取光标位置
	mov ah,0eh          ;
	mov al,0dh          ;
	int 10h             ;
	mov ah,13h          ;
	mov al,1            ;
	mov bl,0fh          ;
	mov bh,0            ;
	mov dl,0            ;
	mov bp,comfile      ;
	mov cx,comfilelen   ;
	int 10h             ;
	jmp typexit         ;
nocmd:
	mov ah,3            ;
	mov bh,0            ;
	int 10h             ;获取光标位置
	mov ah,0eh          ;
	mov al,0dh          ;
	int 10h             ;
	mov ah,13h          ;
	mov al,1            ;
	mov bl,0fh          ;
	mov bh,0            ;
	mov dl,0            ;
	mov bp,nocmdstr     ;
	mov cx,nocmdlen     ;
	int 10h             ;
typexit:                ;
	pop bx              ;
	pop ax              ;
	jmp again           ;
	
; ----------------------------------------------------------
isout:;判断命令是否为根目录下的.com文件;如果是,则al为1;如果找不到(不是),则al为0
push bx     ;
push cx     ;
push dx     ;
push es		; 保护ES

; 软驱复位
	xor	ah, ah	; 功能号ah=0（复位磁盘驱动器）
	xor	dl, dl	; dl=0（软驱A，软驱B为1、硬盘和U盘为80h）
	int	13h		; 磁盘中断
	
; 下面在磁盘根目录中寻找 COM文件
	mov	word [wSectorNo], SectorNoOfRootDirectory 	; 给表示当前扇区号的
						; 变量wSectorNo赋初值为根目录区的首扇区号
	mov word [wRootDirSizeForLoop], RootDirSectors	; 根目录区剩余扇区数
										; 初始化为32，在循环中会递减至零
SEARCH_IN_ROOT_DIR_BEGIN:
	cmp	word [wRootDirSizeForLoop], 0 ; 判断根目录区是否已读完
	jz	NOT_FOUND	; 若读完则表示未找到COM文件
	dec	word [wRootDirSizeForLoop]	; 递减变量wRootDirSizeForLoop的值
	; 调用读扇区函数读入一个根目录扇区到装载区
	mov	ax, BaseOfLoader
	mov	es, ax			; ES <- BaseOfLoader（6000h）
	mov	bx, OffsetOfLoader	; BX <- OffsetOfLoader（100h）
	mov	ax, [wSectorNo]	; AX <- 根目录中的当前扇区号
	mov	cl, 1			; 只读一个扇区
	call ReadSec		; 调用读扇区函数

	mov	si, fnbuf		; DS:SI -> COM文件
	mov	di, OffsetOfLoader ; ES:DI -> BaseOfLoader:0100
	cld					; 清除DF标志位
						; 置比较字符串时的方向为左/上[索引增加]
	mov	dx, 10h			; 循环次数=16（每个扇区有16个文件条目：512/32=16）
SEARCH_FOR_COM_FILE:
	cmp	dx, 0			; 循环次数控制
	jz GOTO_NEXT_SECTOR_IN_ROOT_DIR ; 若已读完一扇区
	dec	dx				; 递减循环次数值			  就跳到下一扇区
	mov	cx, 11			; 初始循环次数为11
CMP_FILENAME:
	repe cmpsb			; 重复比较字符串中的字符，CX--，直到不相等或CX=0
	cmp	cx, 0
	jz	FILENAME_FOUND ; 如果比较了11个字符都相等，表示找到
DIFFERENT:
	and	di, 0FFE0h		; DI &= E0为了让它指向本条目开头（低5位清零）
						; FFE0h = 1111111111100000（低5位=32=目录条目大小）
	add	di, 20h			; DI += 20h 下一个目录条目
	mov	si, fnbuf		; SI指向装载文件名串的起始地址
	jmp	SEARCH_FOR_COM_FILE; 转到循环开始处

GOTO_NEXT_SECTOR_IN_ROOT_DIR:
	add	word [wSectorNo], 1 ; 递增当前扇区号
	jmp	SEARCH_IN_ROOT_DIR_BEGIN;
NOT_FOUND:
	mov al,0;
	jmp cexit;
FILENAME_FOUND:
	mov al,1;
cexit:
	pop es;
	pop dx;
	pop cx;
	pop bx;
	ret;

; -------------------------------------------------------------------
typ: ; 显示文本文件内容
; 获取文件名
	; 读输入缓冲区第二个参数（第一个是命令串）
	mov word [txtn], buflen
	mov cx, [n]
	sub word [txtn], cx
	sub word [txtn], 1
	mov di, buf
	add di, [n]
	inc di
	mov cx, buflen
	sub cx, [n]
	dec cx
	mov al, 20h
	repne scasb
	jcxz longname
	; 计算 txtn = 文件名串长度（buflen - [n] - 1 - CX - 1）
	sub [txtn], cx
	dec word [txtn]
	je wrongformat	; 格式错误，没有第二个参数
	cmp word [txtn], txtlen
	ja longname		; 文件名太长
	jmp txtstr
longname:
	call showtoolong
	add sp, 2
	jmp again
wrongformat:
	call showwrong
	add sp, 2
	jmp again
; 构造文件名串
txtstr:
	mov si, buf
	add si, [n]
	inc si
	mov di, txtbuf
	mov cx, [txtn]
	rep movsb
; 转大写
	mov cx, [txtn]
	mov bx, 0
tocaploop:
	cmp byte [txtbuf + bx], 61h	; 字符与字母a（61h）比较
	jb notll2					; 字符 < 61h 跳转
	cmp byte [txtbuf + bx], 7ah	; 字符与字母z（7Ah）比较
	ja notll2					; 字符 > 7Ah 跳转
	sub byte [txtbuf + bx], 20h	; 小写字母 - 20h = 大写字母
notll2: ; 不是小写字母
	inc bx			; 递增偏移值
	loop tocaploop	; 继续循环
; 搜索文件并显示
	call Find1stFATEntry
	; mov ax, cx
	; call GetDigStr
	; call DispStr
	call PrintTXT
	ret
	
; 内部命令例程结束
; ===================================================================


; ===================================================================
; 命令行主循环例程开始
; -------------------------------------------------------------------
prompt: ; 显示命令行系统提示串例程
	call newline	; 回车换行
	; 获取当前光标位置（返回的行列号分别在DH和DL中）
	mov ah, 3		; 功能号
	mov bh, 0		; 第0页
	int 10h 		; 调用10H号中断
	; 显示提示串
	mov ah, 13h 	; 功能号
	mov al, 1 		; 光标放到串尾
	mov bl, 0fh 	; 亮白
	mov bh, 0 		; 第0页
	mov dl, 0 		; 第0列
	mov bp, str2 	; BP=串地址
	mov cx, str2len	; 串长
	int 10h 		; 调用10H号中断
	ret				; 从例程返回

; -------------------------------------------------------------------
getstrln: ; 获取键盘输入的命令串行
	cld				; 清除方向标志位（使扫描字符串方向为从串首到串尾）
	
	; 用空格符（20h）填充buf
	mov cx, buflen	; 循环次数CX=命令行缓冲区buf的长度（buflen=80）
	mov al, 20h		; AL=要填充的空格符ASCII码
	mov di, buf		; ES:DI=字符串的起始地址
	rep stosb		; CX>0时将AL存储到[ES:DI]，CX--、DI++
	
	; 用空格符（20h）填充fnbuf的前8个字节
	mov cx, cslen	; 循环次数CX=命令串最大的长度（cslen=8）
	mov al, 20h		; AL=要填充的空格符ASCII码
	mov di, fnbuf	; ES:DI=字符串的起始地址
	rep stosb		; CX>0时将AL存储到[ES:DI]，CX--、DI++
	
	mov si, 0		; 当前字符偏移位置 SI = 0
keyin: ; 接受键盘输入
	; 读按键（返回的按键ASCII码在AL中）
	mov ah, 0 		; 功能号
	int 16h 		; 调用16H号中断
	; 对回车符（0DH）结束输入
	cmp al, 0dh 	; 比较AL中的键入字符与回车符（ASCII码为0DH）
	je return 		; 相等跳转到从例程返回
	cmp al,08h		; 与回退符相比较     
	jne notbackspace; 不等则正常输入
	call backspace  ; 否则处理回退符
	jmp keyin		; 继续输入
	
notbackspace:
	; 保存按键字符到buf
	mov [buf + si], al; buf[SI]=AL
	inc si			; SI++
	; 太长时跳出
	cmp si, buflen	; SI >= 80 ?
	jae goout		; >= 时跳转
	; 显示AL中的键入字符
	mov ah, 0eh 	; 功能号
	mov bl, 0 		; 对文本方式置0
	int 10h 		; 调用10H号中断
	jmp keyin		; 循环读存显按键
return:
	ret 			; 从例程返回

goout: ; 键入的字符数超过缓冲区长度时跳转到此
	call showtoolong; 显示串太长出错信息
	add sp, 2		; 弹出CALL时压栈的返回地址
	jmp again		; 重新开始主循环
	
; -------------------------------------------------------------------
dtlen: ; 确定命令串长度
	mov cx, buflen	; CX = 输入缓冲区长度（80）
	mov al, 20h		; AL = 空格符
	mov di, buf		; DI指向buf
	; 在buf中找到第一个空格符后停止：
	repne scasb		; CX>0 && [di]≠AL 时DI++继续扫描，否则退出循环
	jcxz toolong	; CX=0则没找到空格符，串长n = buflen >> cslen (= 8)
	; 计算 n = 输入缓冲区长度 - CX - 1
	mov word [n], buflen ; n = buflen
	sub [n], cx		; n - CX
	dec word [n]	; n--
	je zlen 		; n=0：重新开始命令行循环
	cmp word [n], cslen ; n > 8 ?
	ja toolong		; 命令串长超过8时跳转
	ret 			; 从例程返回

toolong: ; 命令串太长（报错退出）
	call showwrong	; 显示出错信息
zlen: ; n=0时重新开始
	add sp, 2		; 弹出call压栈的返回地址
	jmp again		; 重新开始

; -------------------------------------------------------------------
tocap: ; 转换成大写字母
	mov cx, [n]		; 循环次数 CX = n
	mov bx, 0		; 字符偏移值 BX = 0（初值为0）
next: ; 循环开始
	cmp byte [buf + bx], 61h	; 字符与字母a（61h）比较
	jb notll					; 字符 < 61h 跳转
	cmp byte [buf + bx], 7ah	; 字符与字母z（7Ah）比较
	ja notll					; 字符 > 7Ah 跳转
	sub byte [buf + bx], 20h	; 小写字母 - 20h = 大写字母
notll: ; 不是小写字母
	inc bx			; 递增偏移值
	loop next		; 继续循环
	ret 			; 从例程返回

; -------------------------------------------------------------------
newstr:	; 构造新串（命令串 --> COM文件名）
	mov si, buf		; 源串起始地址
	mov di, fnbuf	; 目的串起始地址
	mov cx, [n]		; 循环次数 CX = n
	; 将输入缓冲区buf中的命令串复制到文件名缓冲区fnbuf：
	rep movsb		; CX > 0时 [ES:DI] = [DS:SI]、CX--，CX = 0时退出循环
	ret 			; 从例程返回

; -------------------------------------------------------------------
iscmd: ; 判断是否为内部命令
	mov word [i], 0	; 外循环变量/内部命令的序号i=0（初值为0）
	mov dx, cmdstr	; 命令串的初始起始地址
	
.1: ; 外循环
	mov si, fnbuf	; 源串起始地址
	mov di, dx		; 目的串起始地址
	mov cx, cslen 	; 内循环次数
	; 重复比较两字符串中的字符，CX--，直到不相等或CX=0
	repe cmpsb		; CX>0 && [DS:SI]==[ES:DI]时，CX--、SI++、DI++，继续循环；否则退出
	jcxz docmd		; CX=0，表示两串相等，为第BX个内部命令串，跳转执行该命令
	inc word [i]	; CX≠0，表示两串不等，i++
	cmp word [i], N	; i=N（内部命令总数）？
	je .2			; 不是内部命令，退出循环
	add dx, cslen	; DX + 8 =下一命令串的起始地址
	jmp .1			; 继续外循环
.2: ; 返回
	;call showwrong	; 显示出错信息
	ret 			; 从例程返回
	
docmd: ; 执行内部命令
	add sp, 2		; 弹出call iscmd时压栈的返回地址
	call newline	; 回车换行
	mov bx, [i]		; BX = 内部命令的序号i
	shl bx, 1		; 偏移地址 = 内部命令的序号*2
	call near [cmdaddr + bx] ; 调用第i个内部命令
	jmp again		; 跳转到命令行循环
	
;--------------------------------------------------------------------

; -------------------------------------------------------------------
showwrong2: ; 显示出错信息
	call newline 	; 回车换行
	; 获取当前光标位置（返回的行列号分别在DH和DL中）
	mov ah, 3		; 功能号
	mov bh, 0		; 第0页
	int 10h 		; 调用10H号显示中断
	; 显示出错信息串
	mov ah, 13h 	; 功能号
	mov al, 1 		; 光标放到串尾
	mov bl, 0fh 	; 亮白
	mov bh, 0 		; 第0页
	mov dl, 0 		; 第0列
	mov bp, str6 	; BP=串地址
	mov cx, str6len	; 串长
	int 10h 		; 调用10H号显示中断
	ret				; 从例程返回
	
;--------------------------------------------------------------------

exec: ; 执行外部命令（COM文件）

; 定义常量（COM文件加载位置和磁盘参数）


	
	push es		; 保护ES

; 软驱复位
	xor	ah, ah	; 功能号ah=0（复位磁盘驱动器）
	xor	dl, dl	; dl=0（软驱A，软驱B为1、硬盘和U盘为80h）
	int	13h		; 磁盘中断
	
; 下面在磁盘根目录中寻找 COM文件
	mov	word [wSectorNo], SectorNoOfRootDirectory 	; 给表示当前扇区号的
						; 变量wSectorNo赋初值为根目录区的首扇区号（=19）
	mov word [wRootDirSizeForLoop], RootDirSectors	; 根目录区剩余扇区数
										; 初始化为14，在循环中会递减至零
LABEL_SEARCH_IN_ROOT_DIR_BEGIN:
	cmp	word [wRootDirSizeForLoop], 0 ; 判断根目录区是否已读完
	jz	LABEL_NOT_FOUND	; 若读完则表示未找到COM文件
	dec	word [wRootDirSizeForLoop]	; 递减变量wRootDirSizeForLoop的值
	; 调用读扇区函数读入一个根目录扇区到装载区
	mov	ax, BaseOfLoader
	mov	es, ax			; ES <- BaseOfLoader（4000h）
	mov	bx, OffsetOfLoader	; BX <- OffsetOfLoader（100h）
	mov	ax, [wSectorNo]	; AX <- 根目录中的当前扇区号
	mov	cl, 1			; 只读一个扇区
	call ReadSec		; 调用读扇区函数

	mov	si, fnbuf		; DS:SI -> COM文件
	mov	di, OffsetOfLoader ; ES:DI -> BaseOfLoader:0100
	cld					; 清除DF标志位
						; 置比较字符串时的方向为左/上[索引增加]
	mov	dx, 10h			; 循环次数=16（每个扇区有16个文件条目：512/32=16）
LABEL_SEARCH_FOR_COM_FILE:
	cmp	dx, 0			; 循环次数控制
	jz LABEL_GOTO_NEXT_SECTOR_IN_ROOT_DIR ; 若已读完一扇区
	dec	dx				; 递减循环次数值			  就跳到下一扇区
	mov	cx, 11			; 初始循环次数为11
LABEL_CMP_FILENAME:
	repe cmpsb			; 重复比较字符串中的字符，CX--，直到不相等或CX=0
	cmp	cx, 0
	jz	LABEL_FILENAME_FOUND ; 如果比较了11个字符都相等，表示找到
LABEL_DIFFERENT:
	and	di, 0FFE0h		; DI &= E0为了让它指向本条目开头（低5位清零）
						; FFE0h = 1111111111100000（低5位=32=目录条目大小）
	add	di, 20h			; DI += 20h 下一个目录条目
	mov	si, fnbuf		; SI指向装载文件名串的起始地址
	jmp	LABEL_SEARCH_FOR_COM_FILE; 转到循环开始处

LABEL_GOTO_NEXT_SECTOR_IN_ROOT_DIR:
	add	word [wSectorNo], 1 ; 递增当前扇区号
	jmp	LABEL_SEARCH_IN_ROOT_DIR_BEGIN

LABEL_NOT_FOUND:
	pop es			; 恢复ES
	call showwrong	; 显示字符串
	ret

; 下面将COM文件加载到内存
LABEL_FILENAME_FOUND:	; 找到 COM文件后便来到这里继续
	; 计算文件的起始扇区号
	mov	ax, RootDirSectors	; AX=根目录占用的扇区数
	and	di, 0FFE0h		; DI -> 当前条目的开始地址
	add	di, 1Ah			; DI -> 文件的首扇区号在条目中的偏移地址
	mov cx, word [es:di] ; CX=文件的首扇区号
	push cx				; 保存此扇区在FAT中的序号
	add	cx, ax			; CX=文件的相对起始扇区号+根目录占用的扇区数
	add	cx, DeltaSectorNo ; CL <- COM文件的起始扇区号(0-based)
	mov	ax, BaseOfLoader
	mov	es, ax			; ES <- BaseOfLoader（COM程序基址=4000h）
	mov	bx, OffsetOfLoader ; BX <- OffsetOfLoader（COM程序偏移地址=100h）
	mov	ax, cx			; AX <- 起始扇区号

LABEL_GOON_LOADING_FILE:
	push bx				; 保存COM程序偏移地址
	mov	cl, 1			; 1个扇区
	call ReadSec		; 读扇区

	; 计算文件的下一扇区号
	pop bx				; 取出COM程序偏移地址
	pop	ax				; 取出此扇区在FAT中的序号
	call GetFATEntry	; 获取FAT项中的下一簇号
	cmp	ax, 0FF8h		; 是否是文件最后簇
	jae	LABEL_FILE_LOADED ; ≥FF8h时跳转，否则读下一个簇
	push ax				; 保存扇区在FAT中的序号
	mov	dx, RootDirSectors ; DX = 根目录扇区数 = 14
	add	ax, dx			; 扇区序号 + 根目录扇区数
	add	ax, DeltaSectorNo ; AX = 要读的数据扇区地址
	add	bx, [BPB_BytsPerSec] ; BX+512指向COM程序区的下一个扇区地址
	jmp	LABEL_GOON_LOADING_FILE

; 下面跳转执行COM程序
LABEL_FILE_LOADED:
	add sp, 4			; 弹出call指令压栈的返回地址和保存的ES
	jmp	BaseOfLoader:OffsetOfLoader	; 这一句跳转到已加载到内存中的
						; COM文件的开始处，开始执行 COM文件的代码。
						; （COM程序通过调用21h中断返回命令行程序）

; 变量
BPB_BytsPerSec	DW 512	; 每扇区字节数
BPB_SecPerTrk	DW 18	; 每磁道扇区数

wRootDirSizeForLoop	dw	RootDirSectors	; 根目录区剩余扇区数
										; 初始化为14，在循环中会递减至零
wSectorNo		dw	0	; 当前扇区号，初始化为0，在循环中会递增
bOdd			db	0	; 奇数还是偶数FAT项
; -------------------------------------------------------------------
; 命令行主循环例程结束
; ===================================================================


; ===================================================================
; 大型辅助例程开始
;--------------------------------------------------------------------

;--------------------------------------------------------------------
; 例程名：Find1stFATEntry
;--------------------------------------------------------------------
; 作用：找到 TXT文件的首簇号，返回到CX
Find1stFATEntry:
; 定义常量

	push es		; 保护ES
; 软驱复位
	xor	ah, ah	; 功能号ah=0（复位磁盘驱动器）
	xor	dl, dl	; dl=0（软驱A，软驱B为1、硬盘和U盘为80h）
	int	13h		; 磁盘中断
; 下面在磁盘根目录中寻找 TXT文件
	mov	word [twSectorNo], SectorNoOfRootDirectory 	; 给表示当前扇区号的
													; 变量wSectorNo赋初值为根目录区的首扇区号（=19）
	mov word [twRootDirSizeForLoop], RootDirSectors	; 根目录区剩余扇区数
													; 初始化为14，在循环中会递减至零
tLABEL_SEARCH_IN_ROOT_DIR_BEGIN:
	cmp	word [twRootDirSizeForLoop], 0 ; 判断根目录区是否已读完
	jz	tLABEL_NOT_FOUND	; 若读完则表示未找到TXT文件
	dec	word [twRootDirSizeForLoop]	; 递减变量wRootDirSizeForLoop的值
	; 调用读扇区函数读入一个根目录扇区到装载区
	mov	ax, BaseOfLoader
	mov	es, ax			; ES <- BaseOfLoader（4000h）
	mov	bx, OffsetOfLoader	; BX <- OffsetOfLoader（100h）
	mov	ax, [twSectorNo]	; AX <- 根目录中的当前扇区号
	mov	cl, 1			; 只读一个扇区
	call ReadSec		; 调用读扇区函数
	mov	si, txtbuf		; DS:SI -> TXT文件名
	mov	di, OffsetOfLoader ; ES:DI -> BaseOfLoader:0100
	cld					; 清除DF标志位
						; 置比较字符串时的方向为左/上[索引增加]
	mov	dx, 10h			; 循环次数=16（每个扇区有16个文件条目：512/32=16）
tLABEL_SEARCH_FOR_COM_FILE:
	cmp	dx, 0			; 循环次数控制
	jz tLABEL_GOTO_NEXT_SECTOR_IN_ROOT_DIR ; 若已读完一扇区
	dec	dx				; 递减循环次数值	 就跳到下一扇区
	mov	cx, 11			; 初始循环次数为11
tLABEL_CMP_FILENAME:
	repe cmpsb			; 重复比较字符串中的字符，CX--，直到不相等或CX=0
	cmp	cx, 0
	jz	tLABEL_FILENAME_FOUND ; 如果比较了11个字符都相等，表示找到
tLABEL_DIFFERENT:
	and	di, 0FFE0h		; DI &= E0为了让它指向本条目开头（低5位清零）
						; FFE0h = 1111111111100000（低5位=32=目录条目大小）
	add	di, 20h			; DI += 20h 下一个目录条目
	mov	si, txtbuf		; SI指向文件名串的起始地址
	jmp	tLABEL_SEARCH_FOR_COM_FILE; 转到循环开始处
tLABEL_GOTO_NEXT_SECTOR_IN_ROOT_DIR:
	add	word [twSectorNo], 1 ; 递增当前扇区号
	jmp	tLABEL_SEARCH_IN_ROOT_DIR_BEGIN
tLABEL_NOT_FOUND:
	pop es				; 恢复ES
	call showwrong2		; 显示字符串
	ret
; 下面返回 TXT文件的首簇号
tLABEL_FILENAME_FOUND:	; 找到 TXT文件后便来到这里继续
	and	di, 0FFE0h		; DI -> 当前条目的开始地址
	add	di, 1Ah			; DI -> 文件的首簇号在条目中的偏移地址
	mov cx, word [es:di] ; CX=文件的首簇号
	pop es
	ret
; 变量
tBPB_BytsPerSec			DW 512				; 每扇区字节数
tBPB_SecPerTrk			DW 18				; 每磁道扇区数
twRootDirSizeForLoop	dw RootDirSectors	; 根目录区剩余扇区数
											; 初始化为14，在循环中会递减至零
twSectorNo				dw 0				; 当前扇区号，初始化为0，在循环中会递增	
tbOdd					db 0				; 奇数还是偶数FAT项
;--------------------------------------------------------------------

;--------------------------------------------------------------------
; 例程名：PrintTXT
;--------------------------------------------------------------------
; 功能：看名字
PrintTXT:
	push es
	mov ax, BaseOfLoader
	mov es, ax
	mov ax, RootDirSectors
	push cx
	add cx, ax
	add	cx, DeltaSectorNo ; CL <- COM文件的起始扇区号(0-based)
	mov	ax, BaseOfLoader
	mov	es, ax			; ES <- BaseOfLoader（COM程序基址=6000h）
	mov	bx, OffsetOfLoader ; BX <- OffsetOfLoader（COM程序偏移地址=100h）
	mov	ax, cx			; AX <- 起始扇区号
GO_ON_PRINTING:
	push bx
	mov cl, 1
	call ReadSec
	mov di, bx
	mov cx, 512
printAscii:
	cmp cx, 0
	je empty
	mov ah, 0eh
	mov al, [es:di]
	cmp al, 0
	je empty
	mov bl, 0
	int 10h
	inc di
	dec cx
	jmp printAscii
empty:
	; 计算文件的下一扇区号
	pop bx				; 取出COM程序偏移地址
	pop	ax				; 取出此扇区在FAT中的序号
	call GetFATEntry	; 获取FAT项中的下一簇号
	cmp	ax, 0FF8h		; 是否是文件最后簇
	jae	printfinished ; ≥FF8h时跳转，否则读下一个簇
	push ax				; 保存扇区在FAT中的序号
	mov	dx, RootDirSectors ; DX = 根目录扇区数 = 14
	add	ax, dx			; 扇区序号 + 根目录扇区数
	add	ax, DeltaSectorNo ; AX = 要读的数据扇区地址
	jmp	GO_ON_PRINTING
printfinished:
	pop es
	ret
;--------------------------------------------------------------------



;--------------------------------------------------------------------
; 例程名：GetFATEntry
;--------------------------------------------------------------------
; 作用：找到序号为AX的扇区在FAT中的条目，结果放在AX中。需要注意的
;     是，中间需要读FAT的扇区到ES:BX处，所以函数一开始保存了ES和BX
GetFATEntry:
	push es			; 保存ES、BX和AX（入栈）
	push bx
	push ax
; 设置读入的FAT扇区写入的基地址
	mov ax, BaseOfLoader	; AX=4000h
	sub	ax, 100h	; 在BaseOfLoader后面留出4K空间用于存放FAT
	mov	es, ax		; ES=8F00h
; 判断FAT项的奇偶
	pop	ax			; 取出FAT项序号（出栈）
	mov	byte [bOdd], 0; 初始化奇偶变量值为0（偶）
	mov	bx, 3		; AX*1.5 = (AX*3)/2
	mul	bx			; DX:AX = AX * 3（AX*BX 的结果值放入DX:AX中）
	mov	bx, 2		; BX = 2（除数）
	xor	dx, dx		; DX=0	
	div	bx			; DX:AX / 2 => AX <- 商、DX <- 余数
	cmp	dx, 0		; 余数 = 0（偶数）？
	jz LABEL_EVEN	; 偶数跳转
	mov	byte [bOdd], 1	; 奇数
LABEL_EVEN:		; 偶数
	; 现在AX中是FAT项在FAT中的偏移量，下面来
	; 计算FAT项在哪个扇区中(FAT占用不止一个扇区)
	xor	dx, dx		; DX=0	
	mov	bx, [BPB_BytsPerSec]	; BX=512
	div	bx			; DX:AX / 512
		  			; AX <- 商 (FAT项所在的扇区相对于FAT的扇区号)
		  			; DX <- 余数 (FAT项在扇区内的偏移)
	push dx			; 保存余数（入栈）
	mov bx, 0 		; BX <- 0 于是，ES:BX = 8F00h:0
	add	ax, SectorNoOfFAT1 ; 此句之后的AX就是FAT项所在的扇区号
	mov	cl, 2			; 读取FAT项所在的扇区，一次读两个，避免在边界
	call	ReadSec	; 发生错误, 因为一个 FAT项可能跨越两个扇区
	pop	dx			; DX= FAT项在扇区内的偏移（出栈）
	add	bx, dx		; BX= FAT项在扇区内的偏移
	mov	ax, [es:bx]	; AX= FAT项值
	cmp	byte [bOdd], 1	; 是否为奇数项？
	jnz	LABEL_EVEN_2	; 偶数跳转
	shr	ax, 4			; 奇数：右移4位（取高12位）
LABEL_EVEN_2:		; 偶数
	and	ax, 0FFFh	; 取低12位
LABEL_GET_FAT_ENRY_OK:
	pop	bx			; 恢复ES、BX（出栈）
	pop	es
	ret
;--------------------------------------------------------------------

;--------------------------------------------------------------------
; 例程名：showbpb
;--------------------------------------------------------------------
; 作用：; 显示磁盘的BPB信息
showbpb:
	call ReadPBootSec	; 调用读入磁盘分区引导扇区例程

	mov word [lns], 0	; 当前已显示行数，初始化为0
	
	; 显示OEM串---------------------------------------------
	mov cx, OEMMsgLen	; CX=串长
	mov bp, OEMMsg		; BP="OEM:"
	call DispStr		; 调用显示字符串例程
	call space			; 插入空格符
	mov cx, 8			; CX=串长=8
	mov bp, Sector + 3	; BP=BPB中的OEM串
	call DispStr		; 调用显示字符串例程
	call newline		; 回车换行
	inc word [lns]		; lns++ 已显示行数+1

	; 显示介质串---------------------------------------------
	mov cx, MediaMsgLen	; CX=串长
	mov bp, MediaMsg	; BP="Media:"
	call DispStr		; 调用显示字符串例程
	call space			; 插入空格符
	cmp byte [Sector + 15h], 0F0h ; 介质描述符 > F0h ?
	jg HD				; > 为硬盘
	; 软盘
	mov cx, FDMsgLen	; CX=软盘的串长
	mov bp, FDMsg		; BP="Floppy Disk"
	jmp DStr			; 跳转到显示串
HD: ; 硬盘
	mov cx, HDMsgLen	; 硬盘的串长=9
	mov bp, HDMsg		; BP="Hard Disk"
DStr: ; 显示串
	call DispStr		; 调用显示字符串例程
	call newline		; 回车换行
	inc word [lns]		; lns++ 已显示行数+1
	
	; 显示磁盘容量 --------------------------------------------------------
	; 显示“Size:”串
	mov cx, SizeMsgLen	; CX=串长
	mov bp, SizeMsg		; BP="Size:"
	call DispStr		; 调用显示字符串例程
	call space			; 插入空格符

	; 获取十进制数字串
	mov ax, [Sector + 13h] ; AX=总扇区数
	shr ax, 1			; 扇区数/2 = KB值
	call GetDigStr		; 以AX为传递参数，BP(串地址)和CX(字符个数)为返回值
	; 显示数字串
	call DispStr		; 调用显示字符串例程
	
	; 显示“KB”串
	add dl, cl			; 列号DL += 十进制数字串的字符个数
	inc dl				; DL++（空一格）
	mov cx, KBMsgLen	; CX=串长
	mov bp, KBMsg		; BP="KB"
	call DispStr		; 调用显示字符串例程
	call newline		; 回车换行
	inc word [lns]		; lns++ 已显示行数+1
	
	; 显示文件系统类型串---------------------------------------------
	mov cx, FSMsgLen	; CX=串长
	mov bp, FSMsg		; BP="File System:"
	call DispStr		; 调用显示字符串例程
	call space			; 插入空格符
	mov cx, 8			; CX=串长=8
	mov bp, Sector + 36h ; BP=EBPB中的文件系统类型串
	call DispStr		; 调用显示字符串例程
	call newline		; 回车换行
	inc word [lns]		; lns++ 已显示行数+1
	
	; 显示BPB中的卷标串---------------------------------------------
	mov cx, VolMsgLen	; CX=串长
	mov bp, VolMsg		; BP="Vol:"
	call DispStr		; 调用显示字符串例程
	call space			; 插入空格符
	mov cx, 11			; CX=串长=11
	mov bp, Sector + 2Bh ; BP=EBPB中的文件系统类型串
	call DispStr		; 调用显示字符串例程
	call newline		; 回车换行
	inc word [lns]		; lns++ 已显示行数+1
	
	; 显示ID（序列号）---------------------------------------------
	mov cx, IDMsgLen	; CX=串长
	mov bp, IDMsg		; BP="Vol:"
	call DispStr		; 调用显示字符串例程
	call space			; 插入空格符
	call showid			; 显示ID串
	call newline		; 回车换行	
	inc word [lns]		; lns++ 已显示行数+1

	call newline		; 回车换行
	inc word [lns]		; lns++ 已显示行数+1

	ret					; 终止程序，返回
	
; 定义字符串常量及其长度值符号常量：	
OEMMsg db "OEM:"
OEMMsgLen equ $ - OEMMsg
MediaMsg db "Media:"
MediaMsgLen equ $ - MediaMsg
FDMsg db "Floppy Disk"
FDMsgLen equ $ - FDMsg
HDMsg db "Hard Disk"
HDMsgLen equ $ - HDMsg
SizeMsg db "Size:"
SizeMsgLen equ $ - SizeMsg
KBMsg db "KB"
KBMsgLen equ $ - KBMsg
FSMsg db "File System:"
FSMsgLen equ $ - FSMsg
VolMsg db "Vol:"
VolMsgLen equ $ - VolMsg
IDMsg db "ID:"
IDMsgLen equ $ - IDMsg

; -------------------------------------------------------------------	
showid: ; 显示4B整数ID值的十六进制串

	mov edx, [Sector + 27h] ; EDX = ID
	bswap edx		; 字节反序

	mov cx, 4		; 循环次数
.1: ; 显示单个字节
	; 显示高4位
	mov al, dl		; AL=ID高位字节
	and al, 0F0h	; 取出高4位
	shr al, 4		; AL >> 4
	call ShowChar	; 调用显示字符函数
	; 显示低4位
	mov al, dl		; AL=ID高位字节
	and al, 0Fh		; 取出低4位
	call ShowChar	; 调用显示字符函数
	; 下一个字节
	shr edx, 8		; EDX >> 8
	cmp cx, 3		; CX = 3 ?
	jne .2			; ！= 继续循环
	; 显示减号符'-'
	mov al,'-'		; AL = 空格符
	mov ah,0Eh 		; 功能号（以电传方式显示单个字符）
	mov bl,0 		; 对文本方式置0
	int 10h 		; 调用10H号中断
.2:
	loop .1			; 循环

	ret				; 从例程返回
; -------------------------------------------------------------------	

; -------------------------------------------------------------------	
; 显示单个十六进制字符函数
ShowChar: ; 显示一个十六进制数字符：0~9、A~F（以AL为传递参数）
	cmp al, 10		; AL < 10 ?
	jl .1			; AL < 10：跳转到.1
	add al, 7		; AL >= 10：显示字母（ = 数值 += 37h）
.1: ; 数字
	add al, 30h		; 数字字符 = 数值+=30h
	mov ah, 0Eh		; 功能号（以电传方式显示单个字符）
	mov bl, 0 		; 对文本方式置0
	int 10h 		; 调用10H号中断
	ret				; 从例程返回
; -------------------------------------------------------------------	

; --------------------------------------------------------------------
ReadPBootSec: ; 读入磁盘的分区引导扇区到Sector处
	mov bx, Sector 	; ES:BX=读入数据到内存中的存储地址
	mov ah, 2 		; 功能号
	mov al, 1 		; 要读入的扇区数
	mov dl, [drvno]	; 磁盘驱动器号：0=软盘A、1=软盘B、80h=硬盘C、81h=硬盘D
	mov dh, 0 		; 磁头号
	mov ch, 0 		; 柱面号（软盘=0、硬盘=1）
	cmp byte[drvno], 1 ; 驱动器号 > 1 ? 
	jbe	.1			; <= 1 时为软盘，柱面号CH=0
	mov ch, 1		; > 1 时为硬盘，柱面号CH=1
.1:
	mov cl, 1 		; 起始扇区号（编号从1开始）
	int 13H 		; 调用13H号中断
	ret 			; 从例程返回
; 定义缓冲区，用于存放从磁盘读入的扇区

; --------------------------------------------------------------------
DispStr: ; 显示字符串例程（需先置串长CX和串地址BP）
	; 获取当前光标位置（返回的行列号分别在DH和DL中）
	push cx			; 保护CX（进栈）
	mov ah, 3		; 功能号
	mov bh, 0		; 第0页
	int 10h 		; 调用10H号显示中断
	pop cx			; 恢复CX（出栈）

	; 在当前位置显示字符串（串长CX和串地址BP已预先设置好了）
	mov ah, 13h		; BIOS中断的功能号（显示字符串）
	mov al, 1 		; 光标放到串尾
	mov bh, 0 		; 页号=0
	mov bl, 0fh		; 字符颜色=不闪（0）黑底（000）亮白字（1111）
	int 10h 		; 调用10H号显示中断
	ret				; 从例程返回
	
; --------------------------------------------------------------------
; 获取字数据值十进制串例程
GetDigStr: ; 以AX为传递参数，[串地址]BP和[字符个数]CX为返回值
	mov cx, 1		; 位数=1（初值）
	mov bp, sbuf	; BP = sbuf + dn - 1 = sbuf的当前位置
	add bp, dn - 1
	mov bx,10		; 除数=10
DLoop: ; 循环开始处
	mov dx, 0		; DX=0, DX:AX / BX -> 商AX、余DX
	div bx
	add dl, 30h		; 余数 + 30h = 对应的数字符ASCII码
	mov [bp], dl	; sbuf[BP] = DL
	cmp ax, 0		; 商AX = 0 ?
	je OutLoop		; = 0 跳出循环
	inc cx			; 位数CX++
	dec bp			; 数字符的当前位置BP--
	jmp DLoop		; 继续循环
OutLoop: ; 退出循环
	ret				; 从例程返回



;--------------------------------------------------------------------
; 例程名：ReadSec
;--------------------------------------------------------------------
; 作用：从第 AX个扇区开始，将CL个扇区读入ES:BX中
; 需使用磁盘参数secspt(每磁道扇区数）和heads(磁头数）
ReadSec:
	; ---------------------------------------------------------------
	; 怎样由扇区号求扇区在磁盘中的位置 (扇区号->柱面号、起始扇区、磁头号)
	; ---------------------------------------------------------------
	; 设扇区号为 x（= AX）
	;                             ┌ 柱面号C = y / 磁头数
	;         x            ┌ 商 y ┤
	;   -------------- 	=> ┤      └ 磁头号H = y % 磁头数
	;    每磁道扇区数      │
	;                      └ 余 z => 起始扇区号S = z + 1
	push cx			; 保存要读的扇区数CL
	push bx			; 保存BX
	mov	bl, [secspt]; BL(= 磁道扇区数）为除数
	div	bl			; AX/BL，商y在AL中、余数z在AH中
	inc	ah			; z ++（因磁盘的起始扇区号为1），AH = 起始扇区号
	mov	cl, ah		; CL <- 起始扇区号S
	mov	ah, 0		; AX <- y
	mov bl, [heads]	; BL(= 磁头数）为除数
	div	bl			; AX/BL，商在AL中、余数在AH中
	mov	ch, al		; CH <- 柱面号C
	mov	dh, ah		; DH <- 磁头号H
	; 至此，"柱面号、起始扇区、磁头号"已全部得到
	pop	bx			; 恢复BX
	pop ax			; AL = 恢复的要读的扇区数CL
	mov	dl, [drvno]	; 驱动器号
.1: ; 使用磁盘中断读入扇区
	mov	ah, 2		; 功能号（读扇区）
	int	13h			; 磁盘中断
	jc .1			; 如果读取错误，CF会被置为1，这时就不停地读，直到正确为止
	ret
;--------------------------------------------------------------------

;--------------------------------------------------------------------
; 例程名：ls
;--------------------------------------------------------------------
; 作用：; 显示磁盘根目录文件信息列表
; 需使用磁盘参数secspt(每磁道扇区数）和heads(磁头数）
ls: 
	; nsec为根目录区剩余扇区数，初始化为根目录扇区数，在循环中会递减至零
	; 计算根目录扇区数（ = 最大根目录项数 / 32）
	mov ax, [Sector + 11h]	; AX = 最大根目录项数
	shr ax, 4				; AX右移4位（~ /32） = 根目录扇区数
	mov word [nsec], ax		; nsec = AX = 根目录扇区数

	; isec为当前扇区号，赋初值为根目录区的首扇区号，在循环中会逐个增加
	; 计算根目录首扇区号（= 保留扇区数 + FAT数 * FAT占扇区数）
	movzx ax, byte [Sector + 10h] ; AX = FAT数
	mul word [Sector + 16h]	; AX *= FAT占扇区数
	add ax, [Sector + 0Eh]	; AX += 保留扇区数
	mov [isec], ax			; isec = AX = 根目录首扇区号
	
	;call getdiskparam	; 获取磁盘参数H&S
	; 获取磁盘参数H/S
	;mov ax, [Sector + 18h]	; AX = 每磁道扇区数
	;mov [secspt], ax		; secspt = AX = 每磁道扇区数
	;mov ax, [Sector + 1Ah]	; AX = 磁头数
	;mov [heads], ax			; heads = AX = 磁头数
	; 对硬盘isec需加第1个柱面的扇区数
	cmp byte [drvno], 80h	; 驱动器号=80h（硬盘C）？
	je hdc					; = 80h 跳转
	jmp begain				; 软盘
hdc: ; 硬盘C
	; 计算分区前的扇区数（假设 = 1个柱面扇区数）= 每磁道扇区数 * 磁头数
	mov ax, [secspt] 		; AX = 每磁道扇区数
	mul word [heads]		; AX *= 磁头数 = 1个柱面扇区数
	add [isec], ax			; isec += 1个柱面扇区数 = 硬盘根目录首扇区号

begain: 
	; 下面在磁盘根目录中寻找文件目录条目
searchrdir: ; 搜索根目录循环（逐个读入根目录扇区）
	cmp	word [nsec], 0	; 判断根目录区是否已读完
	jz	exit			; 若读完则退出
	dec	word [nsec]		; nsec--
	; 调用读扇区函数读入一个根目录扇区到缓冲区
	mov	bx, Sector		; BX = Sector
	mov	ax, [isec]		; AX <- 根目录中的当前扇区号
	mov cl, 1			; 读一个扇区到缓冲区
	call ReadSec		; 调用读扇区函数
	
	mov	di, Sector		; ES:DI -> Sector	
	mov	word [i], 10h	; 循环次数=16（每个扇区有16个文件条目：512/32=16）
searchfi: ; 搜索文件项循环（在当前扇区中逐个检查文件目录项）
	cmp	word [i], 0		; 循环次数控制
	jz nextsec 			; 若已读完一扇区，跳到下一扇区
	dec	word [i]		; 递减循环次数值
	; 判断是否为文件条目（0开始的为空项、E5h开始的为已删项、属性低4位全1的
	; 为长文件名项或系统占用项、卷标项的属性3号位为1）
	cmp	byte [di], 0	; 文件名的首字母=0？
	jz	notfi			; 为空目录项
	cmp	byte [di], 0E5h	; 文件名的首字母=E5？
	jz	notfi 			; 为已删除目录项
	cmp	byte [di + 11], 0Fh; 文件属性=0Fh？
	jz	notfi 			; 为长文件名目录项

	; 显示文件名串
	inc word [lns]		; 当前屏幕上的文件条目数lns++
	; 判断是否到了屏幕底部
	cmp word [lns], 24	; 行数 = 24 ？
	jb .1				; < 24 继续
	mov word [lns], 1	; 重新设已显示行数为1
	call waitforkey		; 按任意键继续
.1: ; 继续
	; 显示文件条目信息（文件名、大小、时间）
	; 显示文件名串
	mov bp, di			; BP=文件名字符串的起始地址
	mov cx, 11			; 文件名串长8+3=11
	call DispStr		; 调用显示字符串例程
	call space			; 插入空格符

	; 对卷标项，不显示文件大小，显示标识串"<VOL>"
	mov al, [di + 0Bh]	; AL=文件属性
	and al, 8h			; AL & 8（卷标位）
	jz .2	 			; 不为卷标
	; 为卷标，显示字符串"<VOL>"
	mov bp, volbuf		; 串地址
	mov cx, fsbuflen + btbuflen + 1	; 串长=文件大小的串长
	call DispStr		; 显示字符串
	jmp .3				; 跳过显示文件大小串
	
	; 对子目录项，不显示文件大小，显示标识串"<DIR>"
	cmp byte [di + 0Bh], 10h ; 为子目录？
	jne .2				; 显示文件大小
	; 显示字符串"<DIR>"
	mov bp, dsbuf		; 串地址
	mov cx, fsbuflen + btbuflen + 1	; 串长=文件大小的串长
	call DispStr		; 显示字符串
	jmp .3				; 跳过显示文件大小串
	
.2: ; 计算并显示文件大小十进制串
	call getsizestr		; 获取文件大小十进制串
	mov bp, fsbuf		; 串地址
	mov cx, fsbuflen	; 串长
	; 显示文件大小字符串
	call DispStr		; 显示字符串
	call space			; 插入空格符
	; 显示字节字符串（文件大小单位）"Byte"
	mov bp, btbuf		; 串地址
	mov cx, btbuflen	; 串长
	call DispStr		; 显示字符串

.3: ; 插入若干空格分隔符
	call space			; 插入空格符
	call space			; 插入空格符
	call space			; 插入空格符
	
	; 显示时间（年月日时分秒，格式为：yyyy.mm.dd  hh:mm:ss）
	; 显示日期（年.月.日）
	mov ax, [di + 18h]	; AX = 日期（低5位为日、中4位为月、高7位为年-1980）
	push ax				; 保存AX进栈
	; 显示年（高7位为年-1980）
	shr ax, 9			; AX >> 9，AX = 年 - 1980
	add ax, 1980		; AX + 1980 = 年
	call GetDigStr 		; 以AX为传递参数，[串地址]BP和[字符个数]CX为返回值
	call DispStr		; 显示年字符串
	; 显示月（中4位为月）
	pop ax				; 弹出AX = 日期
	push ax				; 保存AX进栈
	shr ax, 5			; AX >> 5
	and ax, 0Fh			; AX & 1111 b = 月
	call GetDigStr 		; 以AX为传递参数，[串地址]BP和[字符个数]CX为返回值
	cmp cx, 1			; 串长 > 1 ？
	ja .4				; > 1：跳转
	; = 1：补充字符'0'
	dec bp				; BP--
	mov byte [bp], '0'	; 加前导'0'
	inc cx				; 串长CX++
.4: ; 添加句点分隔符'.'
	dec bp				; BP--
	mov byte [bp], '.'	; 加句点符'.'
	inc cx				; 串长CX++
	call DispStr		; 显示月字符串
	; 显示日（低5位为日）
	pop ax				; 弹出AX = 日期
	and ax, 1Fh			; AX & 1 1111 b = 日
	call GetDigStr 		; 以AX为传递参数，[串地址]BP和[字符个数]CX为返回值
	cmp cx, 1			; 串长 > 1 ？
	ja .5				; > 1：跳转
	; = 1：补充字符'0'
	dec bp				; BP--
	mov byte [bp], '0'	; 加前导'0'
	inc cx				; 串长CX++
.5: ; 添加句点分隔符'.'
	dec bp				; BP--
	mov byte [bp], '.'	; 加句点符'.'
	inc cx				; 串长CX++
	call DispStr		; 显示日字符串
	call space			; 插入空格符
	call space			; 插入空格符

	; 显示时间（时:分:秒）	
	mov ax, [di + 16h]	; AX = 时间（低5位为秒/2、中6位为分、高5位为时）
	push ax				; 保存AX进栈
	; 显示时（高5位为时）
	shr ax, 11			; AX >> 11，AX = 时
	call GetDigStr 		; 以AX为传递参数，[串地址]BP和[字符个数]CX为返回值
	cmp cx, 1			; 串长 > 1 ？
	ja .6				; > 1：跳转
	; = 1：补充字符'0'
	dec bp				; BP--
	mov byte [bp], '0'	; 加前导'0'
	inc cx				; 串长CX++
.6:	
	call DispStr		; 显示时字符串
	; 显示分（中6位为分）
	pop ax				; 弹出AX = 时间
	push ax				; 保存AX进栈
	shr ax, 5			; AX >> 5
	and ax, 3Fh			; AX & 11 1111 b = 分
	call GetDigStr 		; 以AX为传递参数，[串地址]BP和[字符个数]CX为返回值
	cmp cx, 1			; 串长 > 1 ？
	ja .7				; > 1：跳转
	; = 1：补充字符'0'
	dec bp				; BP--
	mov byte [bp], '0'	; 加前导'0'
	inc cx				; 串长CX++
.7: ; 添加冒号分隔符':'
	dec bp				; BP--
	mov byte [bp], ':'	; 加前导':'
	inc cx				; 串长CX++
	call DispStr		; 显示月字符串
	; 显示秒（低5位为秒/2）
	pop ax				; 弹出AX = 时间
	and ax, 1Fh			; AX & 1 1111 b = 秒/2
	shl ax, 1			; AX << 1，AX*2 = 秒
	call GetDigStr 		; 以AX为传递参数，[串地址]BP和[字符个数]CX为返回值
	cmp cx, 1			; 串长 > 1 ？
	ja .8				; > 1：跳转
	; = 1：补充字符'0'
	dec bp				; BP--
	mov byte [bp], '0'	; 加前导'0'
	inc cx				; 串长CX++
.8: ; 添加冒号分隔符':'
	dec bp				; BP--
	mov byte [bp], ':'	; 加前导':'
	inc cx				; 串长CX++
	call DispStr		; 显示日字符串
	
	call newline		; 回车换行
	
notfi:
	add	di, 20h			; DI += 20h 指向下一个目录条目开始处
	jmp	searchfi		; 转到循环开始处

nextsec:
	inc	word [isec] 	; 递增当前扇区号
	jmp	searchrdir		; 继续搜索根目录循环

exit: ; 终止程序，返回
	ret
	

;--------------------------------------------------------------------
getsizestr: ; 获取文件大小十进制串
	; 用空格符（20h）填充fsbuf
	push di			; 保存DI到栈
	mov cx, fsbuflen; 循环次数CX=命令行缓冲区fsbuf的长度
	mov al, 20h		; AL=要填充的空格符ASCII码
	mov di, fsbuf	; ES:DI=字符串的起始地址
	rep stosb		; CX>0时将AL存储到[ES:DI]，CX--、DI++
	pop di			; 从栈恢复DI

	; 计算文件大小十进制串
	mov cx, 0		; 当前分段数字个数（初始化为0）
	mov bp, fsbuf	; BP = fsbuf + fsbuflen - 1 = fsbuf的当前位置
	add bp, fsbuflen - 1 ; BP = 串尾
	mov ebx,10		; 除数=10
	mov eax, [di + 1Ch]; EAX = 文件大小
.1: ; 循环开始处
	mov edx, 0		; EDX = 0
	div ebx			; EDX:EAX / EBX -> 商EAX、余EDX
	add dl, 30h		; 余数 + 30h = 对应的数字符ASCII码
	mov [bp], dl	; fsbuf[BP] = DL
	cmp eax, 0		; 商EAX = 0 ?
	je .2			; = 0 跳出循环
	dec bp			; 数字符的当前位置BP--
	inc cx			; 当前分段数字个数++
	cmp cx, 3		; CX == 3 ？
	jne .1			; ≠ 继续循环
	; 添加逗号分隔符
	mov byte [bp], ',' ; 插入逗号分隔符“,”
	dec bp			; 数字符的当前位置BP--
	mov cx, 0		; 重新置CX=0
	jmp .1			; 继续循环
.2: ; 退出循环
	ret				; 从例程返回

;--------------------------------------------------------------------
waitforkey: ; 按任意键继续
	; 获取当前光标位置（返回的行列号分别在DH和DL中）
	mov ah, 3		; 功能号
	mov bh, 0		; 第0页
	int 10h 		; 调用10H号显示中断
	; 显示提示串
	mov ah, 13h 	; BIOS中断的功能号（显示字符串）
	mov al, 1 		; 光标放到串尾
	mov bh, 0 		; 页号=0
	mov bl, 0fh 	; 字符颜色=不闪（0）黑底（000）亮白字（1111）
	mov bp, pkinstr	; BP=串地址
	mov cx, pkinstrlen; CX=串长
	mov dl, 0		; 列号=0
	int 10h 		; 调用10H号显示中断
	; 等待用户按键
	mov ah, 0		; 功能号（接受键盘字符输入）
	int 16h			; 调用16h键盘中断
	
	call newline	; 回车换行
	ret				; 从例程返回

;--------------------------------------------------------------------
; 大型辅助例程结束
; ===================================================================
