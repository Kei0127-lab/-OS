***************************************************************
** 各種レジスタ定義
***************************************************************
***************
** レジスタ群の先頭
***************
.equ REGBASE, 0xFFF000 | DMAP を使用．
.equ IOBASE, 0x00d00000
***************
** 割り込み関係のレジスタ
***************
.equ IVR, REGBASE+0x300 | 割り込みベクタレジスタ
.equ IMR, REGBASE+0x304 | 割り込みマスクレジスタ
.equ ISR, REGBASE+0x30c | 割り込みステータスレジスタ
.equ IPR, REGBASE+0x310 | 割り込みペンディングレジスタ
***************
** タイマ関係のレジスタ
***************
.equ TCTL1, REGBASE+0x600 | タイマ１コントロールレジスタ
.equ TPRER1, REGBASE+0x602 | タイマ１プリスケーラレジスタ
.equ TCMP1, REGBASE+0x604 | タイマ１コンペアレジスタ
.equ TCN1, REGBASE+0x608 | タイマ１カウンタレジスタ
.equ TSTAT1, REGBASE+0x60a | タイマ１ステータスレジスタ
***************
** UART1（送受信）関係のレジスタ
***************
.equ USTCNT1, REGBASE+0x900 | UART1 ステータス/コントロールレジスタ
.equ UBAUD1, REGBASE+0x902 | UART1 ボーコントロールレジスタ
.equ URX1, REGBASE+0x904 | UART1 受信レジスタ
.equ UTX1, REGBASE+0x906 | UART1 送信レジスタ
***************
** LED
***************
.equ LED7, IOBASE+0x000002f | ボード搭載の LED 用レジスタ
.equ LED6, IOBASE+0x000002d | 使用法については付録 A.4.3.1
.equ LED5, IOBASE+0x000002b
.equ LED4, IOBASE+0x0000029
.equ LED3, IOBASE+0x000003f
.equ LED2, IOBASE+0x000003d
.equ LED1, IOBASE+0x000003b
.equ LED0, IOBASE+0x0000039
***************
** Q
***************
.section .bss
.even
.equ B_SIZE, 256        /* キューバッファのサイズ(byte) */
.equ NUM_QUEUES, 2      /* サポートするキューの総数 */

.equ Q_TOP, 0         /* キューバッファ先頭 */
.equ Q_BOT, B_SIZE-1  /* キューバッファ終端 */
.equ Q_IN, B_SIZE     /* 書き込みポインタ  */
.equ Q_OUT, B_SIZE+4  /* 読み出しポインタ */
.equ Q_S, B_SIZE+8    /* データ数 */
.equ Q_SIZE, B_SIZE+12    /* キュー1つあたりの総メモリサイズ */
***************
** システムコール番号
***************
.equ SYSCALL_NUM_GETSTRING, 1
.equ SYSCALL_NUM_PUTSTRING, 2
.equ SYSCALL_NUM_RESET_TIMER, 3
.equ SYSCALL_NUM_SET_TIMER, 4
***************
**タイマ割り込み時に飛ぶアドレス
***************
.section .bss
.even
task_p:	.ds.l 1
***************************************************************
** スタック領域の確保
***************************************************************
.section .bss
.even
SYS_STK:
	.ds.b 0x4000 | システムスタック領域
	.even
SYS_STK_TOP: | システムスタック領域の最後尾
	.even
Q_AREA_BASE:
	.ds.b Q_SIZE * NUM_QUEUES	/* 全キュー(2個)の領域を一括確保 */
                                	/* (Q_SIZE * 2) バイト */	
***************************************************************
** 初期化　　
** 内部デバイスレジスタには特定の値が設定されている．
** その理由を知るには，付録 B にある各レジスタの仕様を参照すること．
***************************************************************
.section .text
.even
boot:
	* スーパーバイザ & 各種設定を行っている最中の割込禁止
	move.w #0x2700,%SR
	lea.l SYS_STK_TOP, %SP | Set SSP
	
	****************
	** 割り込みコントローラの初期化
	****************
	move.b #0x40, IVR | ユーザ割り込みベクタ番号を 0x40+level に設定．
	move.l #0x00ffffff,IMR | 全割り込みマスク
	
	****************
	** 送受信 (UART1) 関係の初期化 (割り込みレベルは 4 に固定されている)
	****************
	move.w #0x0000, USTCNT1 | リセット
	move.w #0xe100, USTCNT1 | 送受信可能, パリティなし, 1 stop, 8 bit, 送受割り込み禁止
	move.w #0x0038, UBAUD1 | baud rate = 230400 bps
	
	****************
	** タイマ関係の初期化 (割り込みレベルは 6 に固定されている)
	*****************
	move.w #0x0004, TCTL1 | restart, 割り込み不可, システムクロックの 1/16 を単位として計時， タイマ使用停止
	
SETTING:
	move.l #uart1_interrupt_interface, 0x110	/* レベル４ユーザ割り込み (UART1) */
	move.l	#TimerIF, 0x118				/* レベル６ユーザ割り込み (タイマ 1) */
	move.l	#SYSTEM_CALL_IF, 0x080			/* trap命令ベクタ(システムコール) */
	jsr INIT					/* キューの初期化 */
	move.l #0x00ff3ff9,IMR				/* すべての割り込みの許可 */
	
	bra MAIN
****************************************************************
*** プログラム領域
****************************************************************
.section .text
.even
MAIN:
	** 走行モードとレベルの設定 (「ユーザモード」への移行処理)
	move.w #0x0000, %SR | USER MODE, LEVEL 0
	lea.l USR_STK_TOP,%SP | user stack の設定
	
	** システムコールによる RESET_TIMER の起動
	move.l #SYSCALL_NUM_RESET_TIMER,%d0
	trap #0
	
	** システムコールによる SET_TIMER の起動
	move.l #SYSCALL_NUM_SET_TIMER, %d0
	move.w #50000, %d1
	move.l #TT, %d2
	trap #0
		
	******************************
	* sys_GETSTRING, sys_PUTSTRING のテスト
	* ターミナルの入力をエコーバックする
	******************************	
LOOP:
	move.l #SYSCALL_NUM_GETSTRING, %d0
	move.l #0, %d1 | ch = 0
	move.l #BUF, %d2 | p = #BUF
	move.l #256, %d3 | size = 256
	trap #0
	
	move.l %d0, %d3 | size = %d0 (length of given string)
	move.l #SYSCALL_NUM_PUTSTRING, %d0
	move.l #0, %d1 | ch = 0
	move.l #BUF,%d2 | p = #BUF
	trap #0
	
	bra LOOP


/* ハードウェア割り込み関連 */
***********************************************************
**INTERPUT:　　　
**チャネル ch の送信キューからデータを一つ取り出し，実際に送信する (=UTX1 に書き込む)．
**チャネル ch が 0 以外の場合は，何も実行しない．

**入力:チャネル ch → %D1.L
**戻り値:なし
***********************************************************
INTERPUT:
/* 割り込み処理の開始 */ 
	movem.l %d0/%a0, -(%sp)  /* レジスタの退避 */
	move.w %SR, -(%sp) /* 走行レベルの退避 */
	ori.w #0x2700, %SR /* 走行レベルを７に */

 
/* 送信キュー からデータを取り出す */
	moveq #1, %d0
	cmp.i #0, %d1
	bne INTERPUT_FINISH	/* ch≠0 -> end */
	
	jsr OUTQ

	cmpi.l #1, %d0           /* OUTQ の結果を確認 */
	bne INTERPUT_MASK
	addi.w  #0x0800, %d1	/* ビット拡張 */
	move.w %d1, UTX1	/* 代入処理 */
	
INTERPUT_FINISH:
	move.w (%sp)+, %SR       /* 割り込みハンドラから復帰 */
	movem.l (%sp)+, %d0/%a0  /* 待避した全レジスタを復帰 */
	rts

INTERPUT_MASK: 
	move.w #0xe108,USTCNT1	/* 送信割込不可・受信可能・パリティなし */
	bra INTERPUT_FINISH

***********************************************************
**INTERGET:　　　　
**受信データを受信キューに格納する．
**チャネル ch が，0 以外の場合は，何も実行しない．

**入力:チャネル ch → %D1.L
**　　:受信データ data → %D2.B
**戻り値:なし
***********************************************************
INTERGET:
	movem.l %d0-%d2, -(%sp)		/* レジスタ退避 */
	cmpi.l #0, %d1			/* ch≠0 -> end */
	bne INTERGET_FINISH
	move.b %d2, %d1                 /* INQのためデータとchのレジスタをずらす */
	moveq.l #0, %d0
	jsr INQ

INTERGET_FINISH:
	movem.l (%sp)+, %d0-%d2 
	rts


***********************************************************
**CALL_RP:         
**タイマ割り込み時に処理すべきルーチンを呼び出す
**入力:なし
**戻り値:なし
***********************************************************
CALL_RP:
	movem.l	%a0, -(%sp)	/* レジスタ退避 */
	movea.l	(task_p), %a0	/* メモリ task_p の中にあるルーチンアドレスを %a0 にロード */
	jsr	(%a0)		/* %a0 が指すアドレスの関数を呼ぶ */
	movem.l	(%sp)+, %a0	/* レジスタ復帰 */	
	rts

			
/* システムコール関連 */
***********************************************************
**RESET_TIMER:     
**タイマ割り込みを不可にし、タイマも停止する
**入力:なし
**戻り値:なし　
***********************************************************
RESET_TIMER:
	move.w	#0x0004, TCTL1	/* TCTL1を設定 (restart, 割り込み不可，システムクロックの 1/16 を単位として計時，タイマ使用停止) */
	rts

***********************************************************
**SET_TIMER:　　　
**タイマ割り込み時に呼び出すべきルーチンを設定する	
**タイマ割り込み周期 t を設定し，t * 0.1 msec 秒毎に割り込みが発生するようにする
**タイマ使用を許可し，タイマ割り込みを許可する．(=タイマをスタートさせる)
**入力:タイマ割り込み発生周期t -> %d1.w
**　　:割り込み時に起動するルーチンの先頭アドレスp -> %d2.L	
**戻り値:なし	
***********************************************************
SET_TIMER:
	move.l	%d2, task_p	/* task_pに割り込み時に起動するルーチンの先頭アドレスを代入 */
	move.w	#206, TPRER1	/* 0.1 msec 進むとカウンタが1増えるようにTPRER1を設定 */
	move.w	%d1, TCMP1	/* TCMP1にタイマ割り込み発生周期を代入 */
	move.w	#0x0015, TCTL1	/* TCTL1を設定 (restart, 割り込み許可 (enable the compare interrupt)，システムクロックの 1/16 を単位として計時，タイマ使用許可)し、タイマをスタートさせる */
	rts

***********************************************************
**PUTSTRING:　　　
**チャネル ch 用の送信キューに， p 番地から始まる size バイト分のデータを格納する．
**その後，送信割り込みを許可し，戻り値として%D0 に書き込みサイズを代入したあと，走行レベルを元に戻す．
**復帰値 (%D0) はキューに書き込んだデータのバイト数である．
**送信キューが一杯になるとそれ以上は書き込まない．つまり，指定サイズ以下の個数で書き込めるだけのデータをキューに書き込む．
**本実験では，チャネル ch が 0 以外の場合は何も実行しないように実装する

**入力:チャネル ch → %D1.L
**　　:データ読み込み先の先頭アドレス p → %D2.L
**　　:送信するデータ数 size → %D3.L
**戻り値:実際に送信したデータ数 sz → %D0.L
***********************************************************
PUTSTRING:
	movem.l %d4/%a0, -(%SP)


	cmpi.l #0, %d1
	bne PUTSTRING_UNSUPPORTED_CH /*チャンネル0以外は(11)*/

	moveq #0, %d4 /*sz(%d4) = 0*/
	move.l %d2, %a0 /*i(%a0) = p (%d2)*/

	cmpi.l #0, %d3
	beq PUTSTRING_DONE_SIGNAL /*サイズ0なら(10)*/

PUTSTRING_LOOP:
	cmp.l %d3, %d4
	beq PUTSTRING_DONE_SIGNAL /*sz == sizeなら(9)*/

/*INQの引数設定*/
	moveq #1, %d0 /*'no' = 1*/
	move.b (%a0), %d1 /*'data' = p[i] & i++*/
	lea.l  1(%a0), %a0

	jsr INQ


	cmpi.l #0, %d0
	beq PUTSTRING_DONE_SIGNAL  /*0なら(9)へ*/

	addq.l #1, %d4 /*sz++*/

	bra PUTSTRING_LOOP

/*(11)*/
PUTSTRING_UNSUPPORTED_CH:
	moveq #0, %d0
	bra PUTSTRING_FINISH

/*(9)*/
PUTSTRING_DONE_SIGNAL:
	move.w #0xe10c,USTCNT1 /*送信割り込み許可*/

/*(10)*/	
PUTSTRING_DONE_NOSIGNAL:
	move.l %d4, %d0 /*szを%d0に*/

PUTSTRING_FINISH:	
	movem.l (%SP)+, %d4/%a0
	rts

***********************************************************
**GETSTRING:　　　　
**チャネル ch の受信キューから size バイトのデータを取り出し，p 番地以降にコピーする
**復帰値 (%D0) は読み出したデータのサイズである
**入力キューが空になるとそれ以上は読み出さない．つまり，size 以下の個数の読み出せるだけのデータを取り出す
**本実験では、チャネル 0 以外の場合は，何も実行しないように実装する

**入力:チャネル ch → %D1.L
**　　:データ書き込み先の先頭アドレス p → %D2.L
**　　:取り出すデータ数 size → %D3.L
**戻り値:実際に取り出したデータ数 sz → %D0.L
***********************************************************
GETSTRING:
	movem.l %d4/%a0, -(%SP)

	cmpi.l #0, %d1
	bne GETSTRING_FINISH /* チャンネル0以外は終了 */

	moveq #0, %d4 /* sz(%d4) = 0 */
	move.l %d2, %a0 /*i(%a0) = p (%d2)*/

GETSTRING_LOOP:
	cmp.l %d3, %d4
	beq GETSTRING_LOOPEND /* sz == sizeなら */

/* OUTQの引数設定 */
	moveq #0, %d0 /*'no' = 0 */

	jsr OUTQ

	cmpi.l #0, %d0
	beq GETSTRING_LOOPEND /* 0ならend */

	move.b  %d1, (%a0)

	lea.l 1(%a0), %a0 /* インクリメント*/
	addq.l #1, %d4 /* sz++ */

	bra GETSTRING_LOOP

GETSTRING_LOOPEND:
	move.l %d4, %d0 /* szを%d0 */

GETSTRING_FINISH:	
	movem.l (%SP)+, %d4/%a0
	rts


/* インターフェース関連 */
***********************************************************
**送受信割り込み用のハードウェア割り込みインタフェース
***********************************************************
uart1_interrupt_interface:                
          movem.l %d1-%d4, -(%sp) /* レジスタの退避 */
         move.w  URX1, %d3 /* 受信レジスタの値をd3にコピー */
          move.b  %d3, %d2 /* データ部分のみをd2に転送 */
          and.w  #0x2000, %d3
          cmpi.w  #0, %d3 /* 13bit目が0かどうか比較 */
          
          BEQ  CHECK_INTERPUT /* 0のときはINTERPUTのチェックへ */
         
          move.l  #0, %d1 /* チャンネル設定 */
          jsr  INTERGET

CHECK_INTERPUT:
          move.w  UTX1, %d4 /* 送信レジスタの値をd4にコピー */
          and.w  #0x8000, %d4 
          cmpi.w  #0, %d4 /* 15bit目が0かどうか比較 */
          BEQ    END_of_INTERFACE /* 0のときは割り込み終了 */
          
          move.l  #0, %d1 /* チャンネル設定 */
          
          jsr  INTERPUT

END_of_INTERFACE:    
          movem.l (%sp)+, %d1-%d4 /* レジスタの復帰 */
          rte     

***********************************************************
**タイマ割り込みインターフェース	
***********************************************************
TimerIF:
	move.w	TSTAT1, %d0	/* %d0にTSTAT1を代入 */
	andi.w	#0x01, %d0	/* TSTAT1の第0ビットが1となっているかどうかをチェック */
	cmpi.w	#0, %d0	
	beq	TimerIF_END	/* 0なら分岐して終了 */
	move.w	#0, TSTAT1	/* TSTAT1をクリア */
	jsr	CALL_RP		/* CALL_RPを呼び出す */

TimerIF_END:
	rte

***********************************************************
**システムコールインターフェース 　　
**SYSTEM_CALL_IF:呼び出すべきシステムコールを%D0(システムコール番号1-4を格納)を用いて判別
**入力:システムコール番号 -> %d0.L
**　　:システムコールの引数 -> %d1 以降
**戻り値:システムコール呼び出しの結果	
***********************************************************
SYSTEM_CALL_IF:
	movem.l	%d1-%d7/%a0, -(%sp)	
	cmpi.l	#1, %d0			/* 番号1ならGETSTRINGのアドレスをセット */
	beq	SYSTEM_CALL_GETSTR
	cmpi.l	#2, %d0			/* 番号2ならPUTSTRINGのアドレスをセット */
	beq	SYSTEM_CALL_PUTSTR
	cmpi.l	#3, %d0			/* 番号3ならRESET_TIMERのアドレスをセット */
	beq	SYSTEM_CALL_RESET_TIMER	
	cmpi.l	#4, %d0			/* 番号4ならSET_TIMERのアドレスをセット */
	beq	SYSTEM_CALL_SET_TIMER

SYSTEM_CALL_GETSTR:
	lea.l	GETSTRING, %a0
	bra	SC_IF_JAMP_and_END

SYSTEM_CALL_PUTSTR:
	lea.l	PUTSTRING, %a0
	bra	SC_IF_JAMP_and_END

SYSTEM_CALL_RESET_TIMER:
	lea.l	RESET_TIMER, %a0
	bra	SC_IF_JAMP_and_END

SYSTEM_CALL_SET_TIMER:
	lea.l	SET_TIMER, %a0
	bra	SC_IF_JAMP_and_END

SC_IF_JAMP_and_END:
	jsr	(%a0)			/* 番号に対応するシステムコールを呼び出す */
	movem.l	(%sp)+, %d1-%d7/%a0
	rte


***********************************************************
**キュー　　　
***********************************************************
/*初期化*/
INIT:    /*Qの初期化*/
        movem.l %a0/%d0, -(%sp)
	lea.l Q_AREA_BASE, %a0
	moveq #0, %d0  /*loop内カウンタも兼用*/

INTI_loop:
	move.l %a0, Q_IN(%a0)
	move.l %a0, Q_OUT(%a0)
	move.l #00, Q_S(%a0)   
	addq.w #1,  %d0
	adda.l #Q_SIZE, %a0
	cmpi.b  #1, %d0 /*送受信用両方とも初期化*/
	bls    INTI_loop

INTI_Finish:
	movem.l (%sp)+, %d0/%a0
	rts

/* 書き込み */
INQ:
	move.w  %SR, -(%sp)     
	move.w  #0x2700, %SR        /* 割込み禁止 (走行レベル7) */   
	movem.l %d2/%a0-%a2, -(%sp) 
	mulu    #Q_SIZE, %d0        /* d0 = キュー番号 * Q_SIZE */
	lea.l   Q_AREA_BASE, %a0   
	adda.l  %d0, %a0            /* a0 = 対象キューのベースアドレス */

INQ_CheckFull:
	move.l  Q_S(%a0), %d2       /* d2 = Q_S  */
	cmp.l   #B_SIZE, %d2     
	bne     INQ_Write
	moveq   # 0, %d0     /* 満杯 */
	bra     INQ_Finish

INQ_Write:
	movea.l Q_IN(%a0), %a1       /* a1 = Q_IN (書き込みポインタ) */
	move.b  %d1, (%a1)  
	lea.l  1(%a1), %a1       

INQ_RingBUF:
	lea.l   B_SIZE(%a0), %a2       /* a2 = バッファの終端+1のアドレス  */
	cmpa.l  %a2, %a1            /* ポインタ < 終端？ */
	blt     INQ_Update          /* a1 < a2 -> そのまま */
	move.l   %a0, %a1      /*ポインタを先頭へ */

INQ_Update:
	move.l  %a1, Q_IN(%a0)      /* 更新後の書き込みポインタを保存 */
	addq.l  #1, Q_S(%a0)        /* Q_S インクリメント */
	moveq   #1, %d0                         

INQ_Finish:
	movem.l (%sp)+, %d2/%a0-%a2  
	move.w  (%sp)+, %SR        
	rts

/* 読み出し */
OUTQ:
	move.w  %SR, -(%sp)       
	move.w  #0x2700, %SR  
	movem.l %d2/%a0-%a2, -(%sp)       
	mulu    #Q_SIZE, %d0        /* d0 = キュー番号 * Q_SIZE */
	lea.l   Q_AREA_BASE, %a0   
	adda.l  %d0, %a0            /* a0 = 対象キューのベースアドレス */
	

OUTQ_CheckEmpty:
	move.l  Q_S(%a0), %d2       /* d2 = Q_S */
	cmp.l   #0, %d2                
	bne     OUTQ_Read
	moveq   #0, %d0 		 /*空 */
	bra     OUTQ_Finish
	
OUTQ_Read:
	movea.l Q_OUT(%a0), %a1      /* a1 = Q_OUT (読み出しポインタ) */
	move.b  (%a1), %d1   
	move.b	#0, (%a1)
	lea.l  1(%a1), %a1   

OUTQ_RingBUF:
	lea.l   B_SIZE(%a0), %a2       /* a2 = バッファの終端+1のアドレス */
	cmpa.l  %a2, %a1            /* ポインタ > 終端？ */
	blt     OUTQ_Update         /* a1 < a2-> そのまま */
	move.l   %a0, %a1      /* ポインタを先頭へ */

OUTQ_Update:
	move.l  %a1, Q_OUT(%a0)     /* 更新後の読み出しポインタを保存 */
	subq.l  #1, Q_S(%a0)        /* Q_S デクリメント */
	moveq   #1, %d0                   

OUTQ_Finish:
	movem.l (%sp)+, %d2/%a0-%a2 
	move.w  (%sp)+, %SR        
	rts
	

******************************
* タイマのテスト
* ’******’ を表示し改行する．
* ５回実行すると，RESET_TIMER をする．
******************************
.section .text
.even
TT:
	movem.l %d0-%d7/%a0-%a6,-(%SP)
	cmpi.w #5,TTC | TTC カウンタで 5 回実行したかどうか数える
	beq TTKILL | 5 回実行したら，タイマを止める
	move.l #SYSCALL_NUM_PUTSTRING,%d0
	move.l #0, %d1 | ch = 0
	move.l #TMSG, %d2 | p = #TMSG
	move.l #8, %d3 | size = 8
	trap #0
	addi.w #1,TTC | TTC カウンタを 1 つ増やして
	bra TTEND | そのまま戻る
TTKILL:
	move.l #SYSCALL_NUM_RESET_TIMER,%d0
	trap #0
TTEND:
	movem.l (%SP)+,%d0-%d7/%a0-%a6
	rts
	
****************************************************************
*** 初期値のあるデータ領域
****************************************************************
.section .data
TMSG:
	.ascii "******\r\n" | \r: 行頭へ (キャリッジリターン)
	.even | \n: 次の行へ (ラインフィード)
TTC:
	.dc.w 0
	.even
	
****************************************************************
*** 初期値の無いデータ領域
****************************************************************
.section .bss
BUF:
	.ds.b 256 | BUF[256]
	.even
USR_STK:
	.ds.b 0x4000 | ユーザスタック領域
	.even
USR_STK_TOP: | ユーザスタック領域の最後尾
