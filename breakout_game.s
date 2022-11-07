  # Breakout game

  # ====== Register allocation START ======
  # x0 always = 0
  # x1 return address
  # x2 stack pointer (when used)
  # x3 IOIn(31:0) switches, address 0x00030008
  # x4 program variable
  # x5 memory address
  # x6 dly counter
  # x7 counter variable
  # x8 paddleNumDlyCounter
  # x9 ballNumDlyCounter
  # x10 arena XY variable
  # x11 Not used
  # x12 Not used 
  # x13 Not used
  # x14 zone
  # x15 dlyCountMax. 12.5MHz clock frequency. Two instructions per delay cycle => 6,250,000 delay cycles per second, 625,000 (0x98968) delay cycles per 100msec

  # Wall
  #  x16 wallVec value, default 0xffffffff
  # Ball
  #  x17 ballVec
  #  x18 CSBallXAdd (4:0)
  #  x19 NSBallXAdd (4:0)
  #  x20 CSBallYAdd (4:0)
  #  x21 NSBallYAdd (4:0)
  #  x22 CSBallDir  (2:0)
  #  x23 NSBallDir  (2:0)
  #  x24 ballNumDlyMax (4:0)
  # Paddle
  #  x25 paddleVec
  #  x26 paddleSize (5)
  #  x27 paddleXAddLSB
  #  x28 paddleNumDlyMax (4:0)
  # Score and Lives 
  #  x29 Score
  #  x30 Lives
  # x31  Not used
  # ====== Register allocation END ======

  main:
    #jal x1, clearArena 
    #jal x1, waitForGameGo    # wait for IOIn(2) input to toggle 0-1-0
    
    addi x2, x0, 0x6c  ## init stack pointer (sp). Game uses 16x32-bit memory locations (low 64 bytes addresses), we can use 0x40 and above
    addi x2, x2, -16   ## reserves 4x32 bit words

    jal x1, setupDefaultArena # initialise arena values 
    #jal x1, setupArena1       
    
    jal x1, updateWallMem
    sw   x17, 0(x21)          ## storing init ball vector in NSBallYAdd
    #jal x1, updateBallMem
    jal x1, updatePaddleMem
    jal x1, UpdateScoreMem
    jal x1, UpdateLivesMem
    add x8, x0, x28           # load paddleNumDlyCounter start value
    add x9, x0, x24           # load ballNumDlyCounter start value

    loop1:
    jal x1, delay
    processPaddle:
      bne x8, x0, processBall # paddleNumDlyCounter = 0? => skip chkPaddle
      jal x1, chkPaddle # read left/right controls to move paddle between left and right boundaries
      jal x1, updatePaddleMem
      add x8,  x0, x28        # load paddleNumDlyCounter start value
    processBall:
      bne x9, x0, loop1       # ballNumDlyCounter = 0? => skip check ball functions 
      jal x1, chkBallZone     # find ball zone, update 1. ball, 2. wall, 3. score, 4. lives, loop or end game   *****Retuun x19 NSBallXAdd, x21 NSBallXAdd
      jal x1, updateBallVec   
      jal x1, updateBallMem   # clear CSBallYAdd row, write ballVec to NSBallYAdd, CSBallYAdd = NSBallYAdd (and for XAdd too) 
      jal x1, updateWallMem   ## update wall status, this might want to live elsewhere for nested function calls
      jal x1, UpdateScoreMem
      jal x1, UpdateLivesMem
      add x9, x0, x24         # load ballNumDlyCounter start value
      jal x0, loop1
    
    addi x2, x2, 16  ## restore sp back to init
    1b: jal x0, 1b           # loop until reset asserted
  

  # ====== Wall functions START ======
  updateWallMem:
    addi x5, x0, 60   ## using x5 as memory out
    sw   x16, 0(x5)   ##x16 wall at top y address
    jalr x0,  0(x1)          # ret
  # ====== Wall functions END ======


  # ====== Ball functions START ======
  updateBallVec:            # Generate new ballVec using x19 (NSBallXAdd)
    addi x17, x0, 1
    sll  x17, x17, x19  ## shift ball vector to ballNSXAdd
    jalr x0, 0(x1)           # ret


  updateBallMem: 		     # write to memory. Requires NSBallXAdd and NSBallYAdd. 
    sw   x17, 0(x21)     ## storing ball vector in NSBallYAdd
    sw x0, 0(x20)        ## delete current state of ball after the next state has been written

    add x18, x0, x19     ## CSBallXAdd = NSBallXAdd
    add x20, x0, x21     ## CSBallYAdd = NSBallYAdd
    add x22, x0, x23     ## ballCSDir = ballNSDir
    jalr x0, 0(x1)       # ret


  ##ret_updateBallMem:
    ##jalr x0, 0(x1)          # ret


  chkBallZone:
    addi x4, x0, 56
    bgt x20, x4, topzone  ## if highest y address (y=15), ball in wall
    addi x4, x0, 30
    bgt x18, x4, leftWall ## if highest x address (x=31), ball at left wall
    addi x4, x0, 1
    blt x18, x4, rightWall ## if lowest x address (x=0), ball at right wall
    addi x4, x0, 52
    bgt x20, x4, zone3 ## if 2nd highest y address (y=14), ball just below wall
    addi x4, x0, 16
    blt x20, x4, zone2  ## if y below y=5, ball above paddle zone
    beq x0, x0, zone1

    topzone: #B
    addi x4, x0, 30
    bgt x18, x4, zone11 ## if highest x address (x=31), ball at left wall
    addi x4, x0, 1
    blt x18, x4, zone12 ## if lowest x address (x=0), ball at right wall
    beq x0, x0, zone6

    zone1:
    sw x1, 0(x2)  ## store return address (ra) on sp
    addi x2, x2, 4  ## increment sp
    jal x1, updateBallLocationLinear ## nested call
    addi x2, x2, -4  # decrement sp by 4
    lw x1, 0(x2)  # load ra from stack
    jalr x0, 0(x1)  # return from this func using ra

    zone11: #B Top left corner
    addi x4, x0, 1
    beq x22, x4, JMPS   ## S=4
    addi x4, x0, 0
    beq x22, x4, JMPSE  ## SW=5
    jalr x0, 0(x1)

    zone12: #B Top right corner
    addi x4, x0, 1
    beq x22, x4, JMPS   ## S=4
    addi x4, x0, 2
    beq x22, x4, JMPSW  ## SW=5
    jalr x0, 0(x1)

    zone6: #B Top not beside a side
    addi x4, x0, 1
    beq x22, x4, JMPS   ## S=4 
    addi x4, x0, 0
    beq x22, x4, z6Lft   ## S=4 
    addi x4, x0, 2
    beq x22, x4, z6Rt   ## S=4    
    jalr x0, 0(x1)

    z6Lft: #B
    slli x11, x17, 1 #shifting the ball left 1
    and x12, x11, x16 #anding ball vector shifted left with wall to see if wall to left
    addi x4, x0, 0
    beq x4, x12, JMPSE #no brick to left so can return a mirror bounce
    xor x16, x16, x12 #Removing brick from wall
    addi x29, x29, 1 
    bez x0, x0, JMPSW

    z6Rt: #B
    srli x11, x17, 1 #shifting the ball right 1
    and x12, x11, x16 #anding ball vector shifted left with wall to see if wall to left
    addi x4, x0, 0
    beq x4, x12, JMPSW #no brick to left so can return a mirror bounce
    xor x16, x16, x12 #Removing brick from wall
    addi x29, x29, 1 
    bez x0, x0, JMPSE


    leftWall:
    addi x4, x0, 16
    blt x20, x4, zone7  ## if y is just above paddle zone, ball at bottom left corner
    addi x4, x0, 52
    blt x20, x4, zone5  ## if y is between corners, ball against left wall not in corners
    beq x0, x0, zone8 #B
    jalr x0, 0(x1)

    rightWall:
    addi x4, x0, 16
    blt x20, x4, zone10  ## if y is above just paddle zone, ball at bottom right corner
    addi x4, x0, 52
    blt x20, x4, zone4  ## if y is between corners, ball against right wall not in corners
    beq x0, x0, zone9 #B
    jalr x0, 0(x1)

    zone8: #B
    addi x4, x0, 3
    blt x22, x4, zone5 #Checking if the direction is south
    and x11, x16,x17 # Checking if the ball is below a brick
    addi x4, x0, 0
    bne x4, x11, zone8Brick #there is a brick if this is equal
    addi x4, x0, 1
    beq x4, x17, JMPN #North and no brick, move north
    srli x11, x7, 1 #Shifting the ball left one
    and x12, x11, x16 # Anding the wall and shifted wall right one
    addi x4, x0, 0
    beq x12, x4, zone5 #if this is equal, no brick in way, normal wall movement move to zone 5
    addi x29, x29, 1   ## increment score   
    xor x12, x11, 16 #deleteing wall to temp
    addi x16, x12, 0  # making temp the ball
    beq x0, x0, JMPSE
    jalr x0, 0(x1)

    zone8Brick:#B
    addi x29, x29, 1              ## increment score    
    xor x16, x16, x17 #Removing brick from wall    
    addi x4, x0, 1
    beq x4, x17, JMPS
    beq x0, x0, JMPSE

    zone9: #B
    addi x4, x0, 3
    blt x22, x4, zone4 #Checking if the direction is south
    and x11, x16,x17 # Checking if the ball is below a brick
    addi x4, x0, 0
    bne x4, x11, zone9Brick #there is a brick if this is equal
    addi x4, x0, 1
    beq x4, x17, JMPN #North and no brick, move north
    slli x11, x7, 1 #Shifting the ball left one
    and x12, x11, x16 # Anding the wall and shifted wall left ball vector
    addi x4, x0, 0
    beq x12, x4, zone4 #if this is equal, no brick in way, normal wall movement move to zone 5
    addi x29, x29, 1   ## increment score   
    xor x12, x11, 16 #deleteing wall to temp
    addi x16, x12, 0  # making temp the ball
    beq x0, x0, JMPSW
    jalr x0, 0(x1)

    zone9Brick:#B
    addi x29, x29, 1 ## increment score    
    xor x16, x16, x17 #Removing brick from wall    
    addi x4, x0, 1
    beq x4, x17, JMPS
    beq x0, x0, JMPSW


    zone3:  # test code, change me
    and x31, x16, x17             ## AND ball and wall vector to see if the ball is against a wall piece
    bgt x31, x0, incrementScore   ## if AND resulted in 1, we can delete the wall piece and increment score
    #beq x31, x0, zone6
    addi x23, x0, 4
    addi x21, x20, -4
    addi x19, x18, 0
    jalr x0, 0(x1)

    incrementScore:
    xor x16, x16, x17             ## XOR ball and wall to remove wall piece since 1 and 1 -> 0 with XOR
    addi x29, x29, 1              ## increment score
    beq x0, x0, zone3

    zone2:  # test code, change me
    addi x23, x0, 1
    addi x21, x20, 4
    addi x19, x18, 0
    jalr x0, 0(x1)

    zone7:
    and x4, x25, x17              ## if ball and paddle are beside each other, AND will result in 1
    beq x4, x0, endRound          ## therefore if paddle not below, we lose a life
    addi x23, x0, 2               ## however if the paddle is below, we can bounce the ball
    bne x4, x0, JMPNE
    jalr x0, 0(x1)

    zone5:
    beq x22, x0, JMPNE            ## if CSdir = NW -> NSdir = NE
    addi x4, x0, 5
    beq x22, x4, JMPSE            ## if CSdir = SW -> NSdir = SE
    beq x0, x0, updateBallLocationLinear  ## ball will go either N or S linearly
    jalr x0, 0(x1)

    zone10:
    and x4, x25, x17              ## if ball and paddle are beside each other, AND will result in 1
    beq x4, x0, endRound          ## therefore if paddle not below, we lose a life
    addi x23, x0, 0               ## however if the paddle is below, we can bounce the ball
    bne x4, x0, JMPNW
    jalr x0, 0(x1)

    zone4:
    addi x4, x0, 2
    beq x22, x4, JMPNW            ## if CSdir = NE -> NSdir = NW
    addi x4, x0, 3
    beq x22, x4, JMPSW            ## if CSdir = SE -> NSdir = SW
    beq x0, x0, updateBallLocationLinear  ## ball will go either N or S linearly
    jalr x0, 0(x1)


  ret_chkBallZone:
    jalr x0, 0(x1)          # ret
  # ====== Ball functions END ======


  ## ====== Functions for zones START ======
  endRound:
    addi x30, x30, -1   ## decrementing a life 
    beq x30, x0, endGame
    # ball
    addi x18, x0, 16    ## CSBallXAdd (4:0)
    addi x19, x0, 16    ## NSBallXAdd (4:0)
    addi x17, x0, 1
    sll x17, x17, x19   ## putting ball back in middle using NSBallXAdd
    addi x20, x0, 12    ## CSBallYAdd (4:0)
    addi x21, x0, 12    ## NSBallYAdd (4:0)
    addi x22, x0, 1     ## CSBallDir  (2:0) N 
    addi x23, x0, 1	    ## NSBallDir  (2:0) N
    # paddle
    lui  x25, 0x0007c   ## paddleVec 0b0000 0000 0000 0111 1100 0000 0000 0000 = 0x0007c000
    jalr x0, 0(x1)

  updateBallLocationLinear:  ## update linear ball direction according to CSBallDir (North & South are fist as they have a higher % of being called on)
    addi x4, x0, 1
    beq x22, x4, JMPN   ## N=1
    addi x4, x0, 4
    beq x22, x4, JMPS   ## S=4
    beq x22, x0, JMPNW  ## NW=0 
    addi x4, x0, 2
    beq x22, x4, JMPNE  ## NE=2
    addi x4, x0, 3
    beq x22, x4, JMPSE  ## SE=3
    addi x4, x0, 5
    beq x22, x4, JMPSW  ## SW=5
    jalr x0, 0(x1)

  JMPNW:              ## function to put ball going north west
    addi x21, x21, 4  ## NSy = CSy+4
    addi x19, x19, 1  ## NSx = CSx+1
    addi x23, x0, 0   ## dir = 0, -> NW
    jalr x0, 0(x1)

  JMPN:               ## north
    addi x21, x21, 4  ## NSy = CSy+4 
    addi x23, x0, 1   ## dir = 1, -> N
    jalr x0, 0(x1)

  JMPNE:              ## north east
    addi x21, x21, 4  ## NSy = CSy+4
    addi x19, x19, -1 ## NSx = CSx-1
    addi x23, x0, 2   ## dir = 2, -> NE
    jalr x0, 0(x1)

  JMPSE:              ## south east
    addi x21, x21, -4 ## NSy = CSy-4
    addi x19, x19, -1 ## NSx = CSx-1
    addi x23, x0, 3   ## dir = 3, -> SE
    jalr x0, 0(x1)

  JMPS:               ## south
    addi x21, x21, -4 ## NSy = CSy-4
    addi x23, x0, 4   ## dir = 4, -> S
    jalr x0, 0(x1)

  JMPSW:              ## south west
    addi x21, x21, -4 ## NSy = CSy-4
    addi x19, x19, 1  ## NSx = CSx+1
    addi x23, x0, 5   ## dir = 5, -> SW
    jalr x0, 0(x1)

  ## ====== Functions for zones END ======



  # ====== Paddle functions START ======
  updatePaddleMem:     # Generate new paddleVec and write to memory. Requires paddleSize and paddleXAddLSB 
    sw   x25, 8(x0)
    jalr x0, 0(x1)      # ret


  chkPaddle:
    # read left/right paddle control switches, memory address 0x00030008
    # one clock delay is required in memory peripheral to register change in switch state
    lui  x4, 0x00030              # 0x00030000 
    addi x4, x4, 8                # 0x00030008 # IOIn(31:0) address 
    lw   x3, 0(x4)                # read IOIn(31:0) switches
    
    lui x4, 0x80000               ## x4 = 0x80000000
    and x31, x4, x25              ## if the paddle is against left wall this AND will result in a positive value
    bne x31, x0, chkCanMoveRight  ## if positive, we cannot move the paddle left

    addi x4, x0, 1                ## x4 = 0x00000001
    and x31, x4, x25              ## if the paddle is against right wall this AND will result in a positive value
    bne x31, x0, chkCanMoveLeft   ## if positive, we cannot move the paddle right

    chkCanMoveRight:
    addi x4, x0, 1
    beq x4, x3, movePaddleRight   ## if IOIn = 01, paddle goes right
    bne x31, x0, ret_chkPaddle    ## if ball against left wall and we cant move -> exit. else if not against wall, check it we can move left.

    chkCanMoveLeft:
    addi x4, x0, 2
    beq x4, x3, movePaddleLeft    ## if IOIn = 10, paddle goes left 
    beq x0, x0, ret_chkPaddle     ## if IOIn = 00 or 11, paddle does not move

    movePaddleRight:
    srli x25, x25, 1              ## shift right 1
    beq x0, x0, ret_chkPaddle

    movePaddleLeft:
    slli x25, x25, 1              ## shift left 1
    beq x0, x0, ret_chkPaddle 

  ret_chkPaddle:
    jalr x0, 0(x1)    # ret
  # ====== Paddle functions END ======


  # ====== Score and Lives functions START ======
  UpdateScoreMem:  
    sw   x29, 0(x0)     # store score 
    jalr x0, 0(x1)      # ret

  UpdateLivesMem:  
    sw   x30, 4(x0)     # store lives
    jalr x0, 0(x1)      # ret

  # ====== Score and Lives functions END ======




  # ====== Setup arena variables START ======
  setupDefaultArena: 
  # dlyCountMax 
              # 12.5MHz clock frequency. Two instructions per delay cycle => 6,250,000 delay cycles per second, 625,000 (0x98968) delay cycles per 100msec
    lui  x15, 0x98968   # 0x98968000 
    srli x15, x15, 12   # 0x00098968 
    addi x15, x0, 2     # low count delay, for testing 
  # Wall
    xori x16, x0, -1    # wall x16 = 0xffffffff
  # Ball
    ## lui x17,  0x00010   # ballVec 0b0000 0000 0000 0001 0000 0000 0000 0000 = 0x0007c000
    addi x18, x0, 16    # CSBallXAdd (4:0)
    addi x19, x0, 16    # NSBallXAdd (4:0)
    addi x17, x0, 1
    sll  x17, x17, x19  ## putting ball in location regarding x19, NSBallXAdd
    addi x20, x0, 12    # CSBallYAdd (4:0)
    addi x21, x0, 12    # NSBallYAdd (4:0)
    addi x22, x0, 1     # CSBallDir  (2:0) N 
    addi x23, x0, 1	    # NSBallDir  (2:0) N
    lui  x24, 0x00098   # ballNumDlyCounter (4:0)  ## enough delay to see ball move
  # Paddle
    lui  x25, 0x0007c   # paddleVec 0b0000 0000 0000 0111 1100 0000 0000 0000 = 0x0007c000
    addi x26, x0, 5     # paddleSize
    addi x27, x0, 2     # paddleXAddLSB
    lui  x28, 0x00098   # paddleNumDlyCounter 
  # Score
    addi x29, x0, 0     # score
    addi x30, x0, 3     # lives 
  jalr x0, 0(x1)       # ret


  setupArena1: 
  # dlyCountMax 
              # 12.5MHz clock frequency. Two instructions per delay cycle => 6,250,000 delay cycles per second, 625,000 (0x98968) delay cycles per 100msec
    lui  x15, 0x98968   # 0x98968000 
    srli x15, x15, 12   # 0x00098968 
    #addi x15, x0, 2    # low count delay, for testing 
  # Wall
    lui  x16, 0xfedcb  
  # Ball
  # lui  x17, 0x00010  # ballVec 0b0000 0000 0000 0001 0000 0000 0000 0000 = 0x0007c000
    addi x18, x0, 6     # CSBallXAdd (4:0)
    addi x19, x0, 6     # NSBallXAdd (4:0)
    addi x20, x0, 12     # CSBallYAdd (4:0) ##added in 12 for y address 3
    addi x21, x0, 12     # NSBallYAdd (4:0) ## same^
    addi x22, x0, 6     # CSBallDir  (2:0)  NW
    addi x23, x0, 6	  # NSBallDir  (2:0)  NW
    addi x24, x0, 0x5    # ballNumDlyCounter (4:0)
  # Paddle
    lui  x25, 0x007f8   # 0x007f8000 paddleVec = 0b0000 0000 0111 1111 1000 0000 0000 0000
    addi x26, x0, 8     # paddleSize
    addi x27, x0, 3     # paddleXAddLSB
    addi x28, x0, 0x4    # paddleNumDlyCounter 
  # Score
    addi x29, x0, 3     # score
    addi x30, x0, 5     # lives 
    jalr x0, 0(x1)      # ret


  clearArena: 
                        # initialise registers 
    addi x5, x0, 0      # base memory address
    addi x4, x0, 0      # loop counter
    addi x7, x0, 15     # max count value
    clearMemLoop:
      sw x0, 0(x5)      # clear memory word
    addi x5, x5, 4    # increment memory byte address
    addi x4, x4, 1    # increment loop counter 	
    ble  x4, x7, clearMemLoop  
    jalr x0, 0(x1)    # ret

  # ====== Setup arena variables END ======


  # ====== Other functions START ======
  delay:
  add x6, x0, x15         # load delay count start value
  mainDlyLoop:
    addi x6, x6, -1        # decrement delay counter
    bne  x6, x0, mainDlyLoop
    addi x8, x8, -1        # decrement paddleNumDlyCounter
    addi x9, x9, -1        # decrement ballNumDlyCounter
    jalr x0, 0(x1)         # ret
    

  waitForGameGo:                    # wait 0-1-0 on input IOIn(2) control switches to start game	
                                    # one clock delay required in memory peripheral to register change in switch state
  lui  x4, 0x00030                 # 0x00030000 
  addi x4, x4, 8                   # 0x00030008 IOIn(31:0) address 
  addi x8, x0, 4                   # IOIn(2) = 1 compare value  

  waitUntilIOIn2Eq0: 
    lw   x3, 0(x4)                  # read IOIn(31:0) switches
    andi x7, x3, 4                  # mask to keep IOIn(2) 
    beq  x7, x0, waitUntilIOIn2Eq1  # chk / progress if IOIn(2) = 0
    beq  x0, x0, waitUntilIOIn2Eq0  # unconditional loop (else keep checking)
  
  waitUntilIOIn2Eq1: 
    lw   x3, 0(x4)                  # read IOIn(31:0) switches
    andi x7, x3, 4                  # mask to keep IOIn(2) 
    beq  x7, x8, waitUntilIOIn2Eq0b # chk / progress if IOIn(2) = 1
    beq  x0, x0, waitUntilIOIn2Eq1  # unconditional loop (else keep checking)

  waitUntilIOIn2Eq0b: 
    lw   x3, 0(x4)                  # read IOIn(31:0) switches
    andi x7, x3, 4                  # mask to keep IOIn(2) 
    beq  x7, x0, ret_waitForGameGo  # chk / progress if IOIn(2) = 0
    beq  x0, x0, waitUntilIOIn2Eq0b # unconditional loop (else keep checking)

  ret_waitForGameGo:
    jalr x0, 0(x1)                  # ret



  endGame:                          # highlight game over in display 
    jalr x0, 0(x1)                  # ret
    
  # ====== Other functions END ======
