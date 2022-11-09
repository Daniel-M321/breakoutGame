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
  # x11 program variable
  # x12 program variable 
  # x13 stores orginal wall if ball enters it
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
  # x31  program variable
  # ====== Register allocation END ======

  main:
    addi x2, x0, 0x6c  ## init stack pointer (sp). Game uses 16x32-bit memory locations (low 64 bytes addresses), we can use 0x40 and above
    addi x2, x2, -16   ## reserves 4x32 bit words

    jal x1, clearArena 
    jal x1, startScreen
    jal x1, waitForInput    # wait for IOIn(2) input to toggle 0-1-0 or L-R-L
    #jal x1, setupArena1       
    
    jal x1, updateWallMem
    sw   x17, 0(x21)          ## storing init ball vector in NSBallYAdd
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
      addi x11, x0, 32
      beq x29, x11, resetWall
      addi x11, x0, 64
      beq x29, x11, resetWall
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


  chkBallZone:
    addi x4, x0, 56
    bgt x20, x4, zone6  ## if highest y address (y=15), ball in wall
    addi x4, x0, 30
    bgt x18, x4, leftWall ## if highest x address (x=31), ball at left wall
    addi x4, x0, 1
    blt x18, x4, rightWall ## if lowest x address (x=0), ball at right wall
    addi x4, x0, 52
    bgt x20, x4, zone3 ## if 2nd highest y address (y=14), ball just below wall
    addi x4, x0, 16
    blt x20, x4, zone2  ## if y below y=5, ball above paddle zone
    beq x0, x0, updateBallLocationLinear

    zone6: #B 
    addi x16, x13, 0
    addi x4, x0, 30
    bgt x18, x4, JMPSE ## if highest x address (x=31), ball in left corner
    addi x4, x0, 1
    blt x18, x4, JMPSW ## if lowest x address (x=0), ball in right corner
    addi x4, x0, 1
    beq x22, x4, JMPS   ## N=1 
    beq x22, x0, z6Lft   ## NW=0 
    addi x4, x0, 2
    beq x22, x4, z6Rt   ## NE=2    
    jalr x0, 0(x1)

    z6Lft: #B
    slli x11, x17, 1 #shifting the ball left 1
    and x12, x11, x16 #anding ball vector shifted left with wall to see if wall to left
    beq x0, x12, JMPSW #no brick to left so can bounce off top wall
    xor x16, x16, x12 #Removing brick from wall and mirror bounce
    addi x29, x29, 1 
    beq x0, x0, JMPSE

    z6Rt: #B
    srli x11, x17, 1 #shifting the ball right 1
    and x12, x11, x16 #anding ball vector shifted left with wall to see if wall to left
    beq x0, x12, JMPSE #no brick to right so can bounce of top wall
    xor x16, x16, x12 #Removing brick from wall and mirror bounce
    addi x29, x29, 1 
    beq x0, x0, JMPSW


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
    addi x4, x0, 2
    bgt x22, x4, JMPSE #Checking if the direction is south
    and x11, x16, x17 # Checking if the ball is below a brick
    bne x0, x11, zone8Brick #there is a brick if this is equal
    srli x11, x17, 1 #Shifting the ball right one
    and x12, x11, x16 # Anding the wall and shifted wall right one
    addi x13, x16, 0                ## stores wall without ball vector for restoring later
    beq x12, x0, putBallInWallL #if this is equal, no brick in way, put ball in wall
    addi x29, x29, 1   ## increment score   
    xor x16, x11, x16 #deleteing wall to temp
    beq x0, x0, JMPSE

    zone8Brick:#B
    addi x29, x29, 1              ## increment score    
    xor x16, x16, x17 #Removing brick from wall    
    beq x0, x0, JMPSE

    putBallInWallL:
    or x16, x16, x11
    beq x0, x0, JMPNE 


    zone9: #B
    addi x4, x0, 2
    bgt x22, x4, JMPSW #Checking if the direction is south
    and x11, x16, x17 # Checking if the ball is below a brick
    bne x0, x11, zone9Brick #there is a brick if this is equal
    slli x11, x17, 1 #Shifting the ball left one
    and x12, x11, x16 # Anding the wall and shifted wall left ball vector
    addi x13, x16, 0                ## stores wall without ball vector for restoring later
    beq x12, x0, putBallInWallR #if this is equal, no brick in way, we put ball in wall
    addi x29, x29, 1   ## increment score   
    xor x16, x12, x16 #deleting wall to temp
    beq x0, x0, JMPSW

    zone9Brick:#B
    addi x29, x29, 1 ## increment score    
    xor x16, x16, x17 #Removing brick from wall    
    beq x0, x0, JMPSW

    putBallInWallR:
    or x16, x16, x11      ## putting shifted ball in wall
    beq x0, x0, JMPNW     ## going into wall zone


    zone3:
    addi x4, x0, 2
    bgt x22, x4, updateBallLocationLinear ## Checking if the direction is south
    addi x13, x16, 0                ## stores wall without ball vector for restoring later
    and x4, x16, x17
    bne x4, x0, ballHitWall         ## if ball and wall brick beside each other going north, ball has hit wall
    beq x0, x22, checkIfWallLeft    ## if no brick above us and we are not going directly north, we check the bricks beside us
    addi x4, x0, 2
    beq x4, x22, checkIfWallRight
    or x16, x16, x17                ## if not going south or NW or NE and there is no wall brick, we are going north into the wall vector
    beq x0, x0, JMPN

    ballHitWall:
    xor x16, x16, x17               ## XOR results in brick missing where ball was
    addi x29, x29, 1                ## update score
    beq x0, x22, JMPSW              ## NW=0
    addi x4, x0, 1                  ## N=1
    beq x4, x22, JMPS         
    addi x4, x0, 2                  ## NE=2
    beq x4, x22, JMPSE

    checkIfWallLeft:
    slli x31, x17, 1                ## shift ball left to AND against wall
    and x4, x31, x16
    bne x0, x4, scoreDiag               ## if AND postive, ball is heading towards brick
    or x16, x31, x16                ## if AND negative, OR the shifted ball with the wall to put the ball in the wall vector.
    beq x0, x0, JMPNW               ## Since left we go NW

    checkIfWallRight:               ## same as above but going right
    srli x31, x17, 1
    and x4, x31, x16
    bne x0, x4, scoreDiag
    or x16, x31, x16
    beq x0, x0, JMPNE

    scoreDiag:
    xor x16, x16, x31               ## XOR ball and wall to delete brick where previously shifted ball is
    addi x29, x29, 1
    addi x4, x0, 2                  ## NW=2
    beq x4, x22, JMPSW              ## we mirror back if hitting brick at corner
    beq x0, x22, JMPSE

  
    zone2:
    addi x4, x0, 1
    beq x22, x4, JMPN
    and x4, x17, x25            ## AND ball and wall to see if they're beside each other
    beq x4, x0, endRound        ## if AND 0, paddle cannot bounce ball and we lose life
    slli x31, x17, 1            ## We check if ball is on left edge of paddle, by shifting the ball left and AND it again.
    and x4, x25, x31
    beq x4, x0, hitLeftPaddle   ## if AND 0, ball was on left edge 
    srli x31, x17, 1            ## we do same check for right check 
    and x4, x25, x31
    beq x4, x0, hitRightPaddle
    beq x0, x0, hitMiddlePaddle ## if left and right checks fail, ball at centre of paddle

    hitMiddlePaddle:            ## SEE fearghals rebound strategy
    addi x4, x0, 5
    beq x22, x4, JMPNW
    addi x4, x0, 4
    beq x22, x4, JMPN
    addi x4, x0, 3
    beq x22, x4, JMPNE
    jalr x0, 0(x1)

    hitLeftPaddle:
    addi x4, x0, 3
    beq x22, x4, JMPN
    bgt x22, x4, JMPNW
    jalr x0, 0(x1)

    hitRightPaddle:
    addi x4, x0, 5
    beq x22, x4, JMPN
    blt x22, x4, JMPNE
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
    lui  x24, 0x00130   # ballNumDlyCounter (4:0)  ## enough delay to see ball move
  # Paddle
    lui  x25, 0x0007c   # paddleVec 0b0000 0000 0000 0111 1100 0000 0000 0000 = 0x0007c000
    addi x26, x0, 5     # paddleSize
    addi x27, x0, 2     # paddleXAddLSB
    lui  x28, 0x00098   # paddleNumDlyCounter 
  # Score
    addi x29, x0, 0     # score
    addi x30, x0, 3     # lives 
  beq x0, x0, ret_setUpArena       # ret


  setupArenaFMode:      ## BALL DELAY HALVED IN FMODE
  # dlyCountMax 
              # 12.5MHz clock frequency. Two instructions per delay cycle => 6,250,000 delay cycles per second, 625,000 (0x98968) delay cycles per 100msec
    lui  x15, 0x98968   # 0x98968000 
    srli x15, x15, 12   # 0x00098968 
    addi x15, x0, 2     # low count delay, for testing 
  # Wall
    xori x16, x0, -1    # wall x16 = 0xffffffff
  # Ball
    ## lui x17,  0x00010   # ballVec 0b0000 0000 0000 0001 0000 0000 0000 0000 = 0x0007c000
    addi x18, x0, 1    # CSBallXAdd (4:0)
    addi x19, x0, 1    # NSBallXAdd (4:0)
    addi x17, x0, 1
    sll  x17, x17, x19  ## putting ball in location regarding x19, NSBallXAdd
    addi x20, x0, 12    # CSBallYAdd (4:0)
    addi x21, x0, 12    # NSBallYAdd (4:0)
    addi x22, x0, 1     # CSBallDir  (2:0) N
    addi x23, x0, 1	    # NSBallDir  (2:0) N
    lui  x24, 0x00098   # ballNumDlyCounter (4:0)  ## double ball speed to default
  # Paddle
    lui  x25, 0x0007c   # paddleVec 0b0000 0000 0000 0111 1100 0000 0000 0000 = 0x0007c000
    addi x26, x0, 5     # paddleSize
    addi x27, x0, 2     # paddleXAddLSB
    lui  x28, 0x00098   # paddleNumDlyCounter 
  # Score
    addi x29, x0, 0     # score
    addi x30, x0, 3     # lives 
  beq x0, x0, ret_setUpArena       # ret

  ret_setUpArena:
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
    addi x11, x0, 0     ## various program variables used through the program
    addi x12, x0, 0 
    addi x31, x0, 0 
    addi x5, x0, 0  
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


  resetWall:
    xori x16, x0, -1    # wall x16 = 0xffffffff

  SmileyFace:
    addi x31, x0, 52     #1
    lui x12, 0x03030
    sw x12, 0(x31)
    addi x31, x0, 48     #2
    lui x12, 0x03030
    sw x12, 0(x31)
    addi x31, x0, 36     #3
    lui x12, 0x00300
    sw x12, 0(x31)
    addi x31, x0, 20     #4
    lui x12, 0x01860
    sw x12, 0(x31)
    addi x31, x0, 16     #5
    lui x12, 0x00FC0
    sw x12, 0(x31)
    addi x11, x0, 64
    beq x11, x29, endGame
    jal x1, loop1
    
  waitForInput:                    # wait 0-1-0 on input IOIn(2) control switches to start game	
                                    # one clock delay required in memory peripheral to register change in switch state
  lui  x4, 0x00030                 # 0x00030000 
  addi x4, x4, 8                   # 0x00030008 IOIn(31:0) address 
  addi x8, x0, 4                   # IOIn(2) = 1 compare value
  addi x31, x0, 2                  # IOIn(1:0) = L compare
  addi x12, x0, 1                  # IOIn(1:0) = R compare
  sw x1, 0(x2)  ## store return address (ra) on sp
  addi x2, x2, 4  ## increment sp

  waitUntilIOIn2Start: 
    lw   x3, 0(x4)                  # read IOIn(31:0) switches
    andi x7, x3, 4                  # mask to keep IOIn(2) 
    beq  x7, x0, waitUntilIOIn2     # chk / progress if IOIn(2) = 0
    beq  x0, x0, waitUntilIOIn2Start  # unconditional loop (else keep checking)
  
  waitUntilIOIn2: 
    lw   x3, 0(x4)                  # read IOIn(31:0) switches
    andi x7, x3, 4                  # mask to keep IOIn(2) 
    beq  x3, x31, waitUntilR
    beq  x7, x8, waitUntilIOIn2Eq0b # chk / progress if IOIn(2) = 1
    beq  x0, x0, waitUntilIOIn2  # unconditional loop (else keep checking)

  waitUntilIOIn2Eq0b: 
    lw   x3, 0(x4)                  # read IOIn(31:0) switches
    andi x7, x3, 4                  # mask to keep IOIn(2) 
    beq  x7, x0, ret_waitForInput010  # chk / progress if IOIn(2) = 0
    beq  x0, x0, waitUntilIOIn2Eq0b # unconditional loop (else keep checking)

  waitUntilR:
    lw x3, 0(x4)
    beq x3, x12, waitUntilLEnd
    beq x0, x0, waitUntilR

  waitUntilLEnd:
    lw x3, 0(x4)
    beq x3, x31, ret_waitForInputLR
    beq x0, x0, waitUntilLEnd

  ret_waitForInputLR:
    jal x1, clearArena
    jal x1, setupArenaFMode
    addi x2, x2, -4  # decrement sp by 4
    lw x1, 0(x2)  # load ra from stack
    jalr x0, 0(x1)                  # ret

  ret_waitForInput010:
    jal x1, clearArena
    jal x1, setupDefaultArena
    addi x2, x2, -4  # decrement sp by 4
    lw x1, 0(x2)  # load ra from stack
    jalr x0, 0(x1)                  # ret


  startScreen:
    addi x31, x0, 52     #1
    lui x12, 0x49723
    addi x12, x12, 0x76e
    sw x12, 0(x31)
    addi x31, x0, 48     #2
    lui x12, 0xaaa54
    addi x12, x12, 0x254
    sw x12, 0(x31)
    addi x31, x0, 44     #3
    lui x12, 0xaaa53
    addi x12, x12, 0x264
    sw x12, 0(x31)
    addi x31, x0, 40     #4
    lui x12, 0x49227
    addi x12, x12, 0x254
    sw x12, 0(x31)
    addi x31, x0, 32     #5
    lui x12, 0x47404
    addi x12, x12, 0x940
    sw x12, 0(x31)
    addi x31, x0, 28     #6
    lui x12, 0x4547a
    addi x12, x12, 0x2a0
    sw x12, 0(x31)
    addi x31, x0, 24     #7
    lui x12, 0x46404
    addi x12, x12, 0xaa0
    sw x12, 0(x31)
    addi x31, x0, 20     #8
    lui x12, 0x7577a
    addi x12, x12, 0x2a8
    sw x12, 0(x31)
    jalr x0, 0(x1)

  endScreen:
    addi x31, x0, 52     #1
    lui x12, 0x0e111
    addi x12, x12, 0x780
    sw x12, 0(x31)
    addi x31, x0, 48     #2
    lui x12, 0x1029b
    addi x12, x12, 0x400
    sw x12, 0(x31)
    addi x31, x0, 44     #3
    lui x12, 0x277d5
    addi x12, x12, 0x700
    sw x12, 0(x31)
    addi x31, x0, 40     #4
    lui x12, 0x12451
    addi x12, x12, 0x400
    sw x12, 0(x31)
    addi x31, x0, 36     #5
    lui x12, 0x0c451
    addi x12, x12, 0x780
    sw x12, 0(x31)
    addi x31, x0, 28     #6
    lui x12, 0x1c82f
    addi x12, x12, 0x710
    sw x12, 0(x31)
    addi x31, x0, 24     #7
    lui x12, 0x22448
    addi x12, x12, 0x490
    sw x12, 0(x31)
    addi x31, x0, 20     #8
    lui x12, 0x2228e
    addi x12, x12, 0x710
    sw x12, 0(x31)
    addi x31, x0, 16     #9
    lui x12, 0x22288
    addi x12, x12, 0x480
    sw x12, 0(x31)
    addi x31, x0, 12     #10
    lui x12, 0x1C10F
    addi x12, x12, 0x490
    sw x12, 0(x31)
    jalr x0, 0(x1)

    # 00011100000100001111010010010000 1C10F490

  endGame:                # highlight game over in display
    bne x11, x29, noJMP2Delay  
    jal x1, delay
    noJMP2Delay:
    lui  x15, 0x98968     # 0x98968000 
    srli x15, x15, 12     # 0x00098968  
    jal x1, clearArena                
    displayloop:          ## loops and flickers GAME OVER message to user
      jal x1, endScreen
      jal x1, delay
      jal x1, clearArena
      jal x1, delay
    beq x0, x0, displayloop   ## loop until reset
    
  # ====== Other functions END ======
