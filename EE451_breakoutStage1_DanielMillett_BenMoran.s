  # Breakout game
  ## Daniel Millett & Ben Moran

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
  # x14 checks if score multiple of 4
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

    # -- INFO -- If you want to remove 010 to start: comment this line below and uncomment the line under that jumps to 'setUpDefaultArena' (line 52)
    jal x1, waitForInput    # wait for IOIn(2) input to toggle 0-1-0 or L-R-L, then setups Arena according to the input
    #jal x1, setupDefaultArena

    # -- INFO -- You can uncomment one of these at a time to test different situations, full descriptions are beside the label names, just CTRL F search for them.
    #jal x1, setupArenaNext1
    #jal x1, setupArenaNext2
    #jal x1, setupArenaNext3 
    #jal x1, setupArenaNext4    
    #jal x1, setupArenaNext5 
    #jal x1, setupArenaNext6
    
    jal x1, updateWallMem
    jal x1, updateBallMem
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
      jal x1, chkBallZone     # find ball zone, update 1. ball, 2. wall, 3. score, 4. lives, loop or end game   *****Return x19 NSBallXAdd, x21 NSBallXAdd
      jal x1, updateBallVec   
      jal x1, updateBallMem   # clear CSBallYAdd row, write ballVec to NSBallYAdd, CSBallYAdd = NSBallYAdd (and for XAdd too) 
      jal x1, updateWallMem   ## update wall status, this might want to live elsewhere for nested function calls
      jal x1, UpdateScoreMem
      jal x1, UpdateLivesMem
      add x9, x0, x24         # load ballNumDlyCounter start value
      beq x16, x0, resetWall # if wall has been fully destroyed, reset it
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
    beq  x21, x20, keepLastState
    sw   x0, 0(x20)        ## delete current state of ball after the next state has been written
    keepLastState:

    add x18, x0, x19     ## CSBallXAdd = NSBallXAdd
    add x20, x0, x21     ## CSBallYAdd = NSBallYAdd
    add x22, x0, x23     ## ballCSDir = ballNSDir
    jalr x0, 0(x1)       # ret


  chkBallZone:
    addi x4, x0, 56
    bgt x20, x4, zone6  ## if highest y address (y=15), ball in wallVec
    addi x4, x0, 30
    bgt x18, x4, leftWall ## if highest x address (x>30), ball at left wall
    addi x4, x0, 1
    blt x18, x4, rightWall ## if lowest x address (x<1), ball at right wall
    addi x4, x0, 52
    bgt x20, x4, zone3 ## if 2nd highest y address (y=14), ball just below wallVec
    addi x4, x0, 16
    blt x20, x4, zone2  ## if y<4, ball above paddle zone
    beq x0, x0, updateBallLocationLinear   ## if none of these conditions meet, we are in the middle and can move in linear direction only

    zone6: #B, ball in wallVec
    addi x16, x13, 0
    addi x4, x0, 30
    bgt x18, x4, JMPSE ## if highest x address (x>30), ball in left corner
    addi x4, x0, 1
    blt x18, x4, JMPSW ## if lowest x address (x<1), ball in right corner
    addi x4, x0, 1
    beq x22, x4, JMPS   ## if Dir=1 (N), go S 
    beq x22, x0, z6Lft   ## if Dir=0 (NW)
    addi x4, x0, 2
    beq x22, x4, z6Rt   ## if Dir=2 (NE)    
    jalr x0, 0(x1)

    z6Lft: #B, Zone6 ball going left
    slli x11, x17, 1 #shifting the ball left 1
    and x12, x11, x16 #anding ball vector shifted left with wall to see if wall to left
    beq x0, x12, JMPSW #no brick to left so can bounce off top wall
    xor x16, x16, x12 #Removing brick from wall and mirror bounce
    addi x29, x29, 1  # score
    addi x14, x14, 1  # counter
    beq x0, x0, JMPSE

    z6Rt: #B
    srli x11, x17, 1 #shifting the ball right 1
    and x12, x11, x16 #anding ball vector shifted left with wall to see if wall to left
    beq x0, x12, JMPSE #no brick to right so can bounce of top wall
    xor x16, x16, x12 #Removing brick from wall and mirror bounce
    addi x29, x29, 1 
    addi x14, x14, 1
    beq x0, x0, JMPSW


    leftWall:
    addi x4, x0, 16
    blt x20, x4, zone7  ## if y is just above paddle zone, ball at bottom left corner
    addi x4, x0, 52
    blt x20, x4, zone5  ## if y is between corners, ball against left wall not in corners
    beq x0, x0, zone8 #B   else ball in top left corner below wallVec
    jalr x0, 0(x1)

    rightWall:
    addi x4, x0, 16
    blt x20, x4, zone10  ## if y is above just paddle zone, ball at bottom right corner
    addi x4, x0, 52
    blt x20, x4, zone4  ## if y is between corners, ball against right wall not in corners
    beq x0, x0, zone9 #B   else ball in top right corner below wallVec
    jalr x0, 0(x1)
    

    zone8: #B          top left corner below wallVec
    addi x4, x0, 2
    bgt x22, x4, JMPSE #Checking if the direction is south -> mirror bounce
    and x11, x16, x17 # Checking if the ball is below a brick
    bne x0, x11, zone8Brick #there is a brick if this is equal
    srli x11, x17, 1 #Shifting the ball right one
    and x12, x11, x16 # Anding the wall and shifted wall right one
    addi x13, x16, 0                ## stores wall without ball vector for restoring later
    beq x12, x0, putBallInWallL #if this is equal, no brick in way, put ball in wall
    addi x29, x29, 1   ## increment score   
    xor x16, x11, x16 # deleting wall piece with temp shifted Ball
    beq x0, x0, JMPSE

    zone8Brick:#B
    addi x29, x29, 1              ## increment score
    addi x14, x14, 1    
    xor x16, x16, x17 #Removing brick from wall    
    beq x0, x0, JMPSE

    putBallInWallL:
    or x16, x16, x11
    beq x0, x0, JMPNE 


    zone9: #B      top right corner below wallVec
    addi x4, x0, 2
    bgt x22, x4, JMPSW #Checking if the direction is south
    and x11, x16, x17 # Checking if the ball is below a brick
    bne x0, x11, zone9Brick #there is a brick if this is equal
    slli x11, x17, 1 #Shifting the ball left one
    and x12, x11, x16 # Anding the wall and shifted wall left ball vector
    addi x13, x16, 0                ## stores wall without ball vector for restoring later
    beq x12, x0, putBallInWallR #if this is equal, no brick in way, we put ball in wall
    addi x29, x29, 1   ## increment score   
    xor x16, x12, x16 #deleting wall with temp shifted Ball
    beq x0, x0, JMPSW

    zone9Brick:#B
    addi x29, x29, 1 ## increment score
    addi x14, x14, 1    
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
    bne x4, x0, ballHitWall         ## if ball and wall brick beside each other going anyway north, ball has hit wall
    beq x0, x22, checkIfWallLeft    ## if no brick above us and we are not going directly north, we check the bricks beside us
    addi x4, x0, 2
    beq x4, x22, checkIfWallRight
    or x16, x16, x17                ## if not going south or NW or NE and there is no wall brick, we are going north into the wall vector
    beq x0, x0, JMPN

    ballHitWall:
    xor x16, x16, x17               ## XOR results in brick missing where ball was
    addi x29, x29, 1                ## update score
    addi x14, x14, 1
    beq x0, x22, JMPSW              ## NW=0
    addi x4, x0, 1                  ## N=1
    beq x4, x22, JMPS         
    addi x4, x0, 2                  ## NE=2
    beq x4, x22, JMPSE

    checkIfWallLeft:
    slli x31, x17, 1                ## shift ball left, then we can AND it against wall
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
    addi x29, x29, 1                ## score
    addi x14, x14, 1
    addi x4, x0, 2                  ## NW=2
    beq x4, x22, JMPSW              ## we mirror back if hitting brick at corner
    beq x0, x22, JMPSE

  
    zone2:
    addi x4, x0, 1
    beq x22, x4, JMPN

    sub x31, x18, x27             ## subtract balls xAdd from the paddles LSBxAdd
    beq x31, x0, hitRightPaddle   ## if 0 on right side
    addi x12, x0, 4
    beq x31, x12, hitLeftPaddle   ## if 4 on left side
    bgt x31, x26, endRound        ## if > 5, not near paddle
    addi x12, x0, -1  
    blt x31, x12, endRound        ## if < -1, not near paddle
    and x4, x17, x25              ## AND ball and paddle to see if they're definetly beside each other
    bne x4, x0, hitMiddlePaddle   ## if AND postive, paddle bounces ball
    addi x12, x0, 3
    beq x12, x22, JMPNW           ## if coming in at an angle we can bounce at angle off paddle
    addi x12, x0, 5
    beq x12, x22, JMPNE
    beq x0, x0, endRound

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

    ret_chkZone:
      jalr x0, 0(x1)    # ret


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
    addi x27, x0, 14
    beq x0, x0, sadFace ## display sad face

  updateBallLocationLinear:  ## update linear ball direction according to CSBallDir
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
    addi x27, x27, -1
    srli x25, x25, 1              ## shift right 1
    beq x0, x0, ret_chkPaddle

    movePaddleLeft:
    addi x27, x27, 1
    slli x25, x25, 1              ## shift left 1
    beq x0, x0, ret_chkPaddle 

  ret_chkPaddle:
    jalr x0, 0(x1)    # ret
  # ====== Paddle functions END ======


  # ====== Score and Lives functions START ======
  UpdateScoreMem:
    addi x4, x0, 5
    blt x28, x4, ballspeed        ## if paddle delay is already below 5, go to ball speed
    addi x4, x0, 12
    bne x4, x29, ballspeed        ## if score not yet at 12, go to ball speed
    addi x28, x28, -2             ## else decrement paddle delay
    ballspeed:
    addi x4, x0, 4
    beq x24, x4, saveScore        ## if ball delay already at 4, go to save score
    bne x14, x4, saveScore        ## if score not multiple of 4, go to save score
    addi x14, x0, 0
    addi x24, x24, -1             ## else reset counter and decrement ball delay
    saveScore:
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
  # Wall
    xori x16, x0, -1    # wall x16 = 0xffffffff
  # Ball
    addi x18, x0, 16    # CSBallXAdd (4:0)
    addi x19, x0, 16    # NSBallXAdd (4:0)
    addi x17, x0, 1
    sll  x17, x17, x19  ## putting ball in location regarding x19, NSBallXAdd
    addi x20, x0, 12    # CSBallYAdd (4:0)
    addi x21, x0, 12    # NSBallYAdd (4:0)
    addi x22, x0, 1     # CSBallDir  (2:0) N
    addi x23, x0, 1	    # NSBallDir  (2:0) N
    addi x24, x0, 8     # ballNumDlyMax
  # Paddle
    lui  x25, 0x0007c   # paddleVec 0b0000 0000 0000 0111 1100 0000 0000 0000 = 0x0007c000
    addi x26, x0, 5     # paddleSize
    addi x27, x0, 14     # paddleXAddLSB
    addi x28, x0, 5      # paddleNumDlyMax
  # Score
    addi x29, x0, 0     # score
    addi x30, x0, 3     # lives 
  beq x0, x0, ret_setUpArena       # ret


  setupArenaFMode:      ## BALL DELAY HALVED IN FMODE (ball and paddle same speed) & BALL STARTS TO THE RIGHT (BE READY TO LOSE)
  # dlyCountMax 
              # 12.5MHz clock frequency. Two instructions per delay cycle => 6,250,000 delay cycles per second, 625,000 (0x98968) delay cycles per 100msec
    lui  x15, 0x98968   # 0x98968000 
    srli x15, x15, 12   # 0x00098968 
  # Wall
    xori x16, x0, -1    # wall x16 = 0xffffffff
  # Ball
    addi x18, x0, 1    # CSBallXAdd (4:0)
    addi x19, x0, 1    # NSBallXAdd (4:0)
    addi x17, x0, 1
    sll  x17, x17, x19  ## putting ball in location regarding x19, NSBallXAdd
    addi x20, x0, 12    # CSBallYAdd (4:0)
    addi x21, x0, 12    # NSBallYAdd (4:0)
    addi x22, x0, 1     # CSBallDir  (2:0) N
    addi x23, x0, 1	    # NSBallDir  (2:0) N
    addi x24, x0, 4     # ballNumDlyMax
  # Paddle
    lui  x25, 0x0007c   # paddleVec 0b0000 0000 0000 0111 1100 0000 0000 0000 = 0x0007c000
    addi x26, x0, 5     # paddleSize
    addi x27, x0, 14     # paddleXAddLSB
    addi x28, x0, 4     # paddleNumDlyMax
  # Score
    addi x29, x0, 0     # score
    addi x30, x0, 3     # lives 
  beq x0, x0, ret_setUpArena       # ret

  ret_setUpArena:
    jalr x0, 0(x1)       # ret


## ----- test setups START ------

  setupArenaNext1:      ## Drops ball on to side of paddle: Tests paddle, right wall zone, and zone below wall
  # Ball
    addi x18, x0, 16    # CSBallXAdd (4:0)
    addi x19, x0, 16    # NSBallXAdd (4:0)
    addi x17, x0, 1
    sll  x17, x17, x19  ## putting ball in location regarding x19, NSBallXAdd
    addi x20, x0, 24    # CSBallYAdd (4:0)
    addi x21, x0, 20    # NSBallYAdd (4:0)
    addi x22, x0, 4     # CSBallDir  (2:0) S
    addi x23, x0, 4	    # NSBallDir  (2:0) S
  # Paddle
    lui  x25, 0x001f0   # paddleVec 0b0000 0000 0001 1111 0000 0000 0000 0000 = 0x0007c000
    addi x27, x0, 16    # paddleXAddLSB
  beq x0, x0, ret_setUpArena       # ret

  setupArenaNext2:         # ball is going to bottom left corner, can move the paddle or not to test if bounces or life lost
  # Ball
    addi x18, x0, 29    # CSBallXAdd (4:0)
    addi x19, x0, 29    # NSBallXAdd (4:0)
    addi x17, x0, 1
    sll  x17, x17, x19  ## putting ball in location regarding x19, NSBallXAdd
    addi x20, x0, 20    # CSBallYAdd (4:0)
    addi x21, x0, 20    # NSBallYAdd (4:0)
    addi x22, x0, 5     # CSBallDir  (2:0) SW
    addi x23, x0, 5	    # NSBallDir  (2:0) SW
  # Paddle
    lui  x25, 0xf8000   # paddleVec 0b1111 1000 0000 0000 0000 0000 0000 0000 = 0x0007c000
    addi x27, x0, 27     # paddleXAddLSB
  beq x0, x0, ret_setUpArena       # ret

  setupArenaNext3:         ## ball will start going to top right corner under the wallVec (if you leave the paddle, it will mirror bounce and test further edge cases
  # Ball                                                                                  ## such as going into wallVec zone, leaving wallVec and hitting paddle on corner) 
    addi x18, x0, 2    # CSBallXAdd (4:0)
    addi x19, x0, 2    # NSBallXAdd (4:0)
    addi x17, x0, 1
    sll  x17, x17, x19  ## putting ball in location regarding x19, NSBallXAdd
    addi x20, x0, 48    # CSBallYAdd (4:0)
    addi x21, x0, 48    # NSBallYAdd (4:0)
    addi x22, x0, 2     # CSBallDir  (2:0) NE
    addi x23, x0, 2	    # NSBallDir  (2:0) NE
  # Paddle
    lui  x25, 0x0001f   # paddleVec 0b0000 0000 0000 0001 1111 0000 0000 0000 = 0x0007c000
    addi x27, x0, 12     # paddleXAddLSB
  beq x0, x0, ret_setUpArena       # ret

  setupArenaNext4:         ## There is only one wall piece left, have fun entering and leaving wallVec especially at angles. You can also see what happens when you hit the last piece.
  # Wall                                                                                                           ## And you can first see the ball hitting the corner in the wallVec
    lui x16, 0x40000    # wall x16 = 0x40000000
  # Ball 
    addi x18, x0, 3    # CSBallXAdd (4:0)
    addi x19, x0, 3    # NSBallXAdd (4:0)
    addi x17, x0, 1
    sll  x17, x17, x19  ## putting ball in location regarding x19, NSBallXAdd
    addi x20, x0, 48    # CSBallYAdd (4:0)
    addi x21, x0, 48    # NSBallYAdd (4:0)
    addi x22, x0, 2     # CSBallDir  (2:0) NE
    addi x23, x0, 2	    # NSBallDir  (2:0) NE
  # Score
    addi x29, x0, 31     # score
  beq x0, x0, ret_setUpArena       # ret

  setupArenaNext5:        ## The wall is empty every second piece, you can test hitting these pieces at different angles, the ball first hits one and mirror bounces back
  # Wall
    lui x16, 0xaaaab
    addi x16, x16, 0xaaa    # wall x16 = 0xaaaaaaaa
  # Ball
    addi x18, x0, 6    # CSBallXAdd (4:0)
    addi x19, x0, 6    # NSBallXAdd (4:0)
    addi x17, x0, 1
    sll  x17, x17, x19  ## putting ball in location regarding x19, NSBallXAdd
    addi x20, x0, 48    # CSBallYAdd (4:0)
    addi x21, x0, 48    # NSBallYAdd (4:0)
    addi x22, x0, 2     # CSBallDir  (2:0) NE
    addi x23, x0, 2	    # NSBallDir  (2:0) NE
  # Score
    addi x29, x0, 16
  beq x0, x0, ret_setUpArena       # ret

setupArenaNext6:         ## end game, one wall piece left and score is 63
  # Wall
    lui x16, 0x00010    # wall x16 = 0xffffffff
  # Score
    addi x29, x0, 63     
  beq x0, x0, ret_setUpArena       # ret
  
## ---- test setups END -----


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

  bigDelay:
    lui x6, 0x5F5E1         # 1s delay
    srli x6, x6, 8 
    mainBDlyLoop:
      addi x6, x6, -1        # decrement delay counter
      bne  x6, x0, mainBDlyLoop
      beq x0, x0, clearArena

  resetWall:
    xori x16, x0, -1    # wall x16 = 0xffffffff
    addi x24, x0, 4     # ballNumDlyMax, when wall reset after clearing, immediately go into F mode pace
    addi x28, x0, 4     # paddleNumDlyMax

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
    beq x11, x29, endGame # if wall destroyed 2nd time we endgame
    jal x1, loop1

  sadFace:
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
    lui x12, 0x00FC0
    sw x12, 0(x31)
    addi x31, x0, 16     #5
    lui x12, 0x01860
    sw x12, 0(x31)
    addi x31, x0, 12     #6
    lui x12, 0x0
    sw x12, 0(x31)
    beq x0, x0, bigDelay
    
  waitForInput:                    # wait 0-1-0 on input IOIn(2) control switches to start normal game	or L-R-L for f-Mode
                                    # one clock delay required in memory peripheral to register change in switch state
  lui  x4, 0x00030                 # 0x00030000 
  addi x4, x4, 8                   # 0x00030008 IOIn(31:0) address 
  addi x8, x0, 4                   # IOIn(2) = 1 compare value
  addi x11, x0, 2                  # IOIn(1:0) = L compare
  addi x12, x0, 1                  # IOIn(1:0) = R compare
  sw x1, 0(x2)  ## store return address (ra) on sp
  addi x2, x2, 4  ## increment sp
  beq x0, x0, startScreen         # displays message on how to start the game

  waitUntilIOInStart: 
    lw   x3, 0(x4)                  # read IOIn(31:0) switches
    andi x7, x3, 4                  # mask to keep IOIn(2) 
    beq  x7, x0, waitUntilIOIn2     # chk / progress if IOIn(2) = 0
    beq  x0, x0, waitUntilIOInStart  # unconditional loop (else keep checking)
  
  waitUntilIOIn2: 
    lw   x3, 0(x4)                  # read IOIn(31:0) switches
    andi x7, x3, 4                  # mask to keep IOIn(2) 
    beq  x3, x11, waitUntilR        # if L activated, we go to waiting for R
    beq  x7, x8, waitUntilIOIn2Eq0 # chk / progress if IOIn(2) = 1
    beq  x0, x0, waitUntilIOIn2  # unconditional loop (else keep checking)

  waitUntilIOIn2Eq0: 
    lw   x3, 0(x4)                  # read IOIn(31:0) switches
    andi x7, x3, 4                  # mask to keep IOIn(2) 
    beq  x7, x0, ret_waitForInput010  # chk / progress if IOIn(2) = 0
    beq  x0, x0, waitUntilIOIn2Eq0 # unconditional loop (else keep checking)

  waitUntilR:
    lw x3, 0(x4)
    beq x3, x12, waitUntilLEnd  ## checking if IOIn(0) active
    beq x0, x0, waitUntilR      ## unconditional loop 

  waitUntilLEnd:
    lw x3, 0(x4)
    beq x3, x11, ret_waitForInputLR ## checking if IOIn(1) active
    beq x0, x0, waitUntilLEnd       ## unconditional loop 

  ret_waitForInputLR:
    jal x1, clearArena        ## clear start screen
    jal x1, setupArenaFMode   ## if L-R-L activated we set up f-Mode
    addi x2, x2, -4  # decrement sp by 4
    lw x1, 0(x2)  # load ra from stack
    jalr x0, 0(x1)                  # ret

  ret_waitForInput010:
    jal x1, clearArena        ## clear start screen
    jal x1, setupDefaultArena ## if 0-1-0 activated, default setup 
    addi x2, x2, -4  # decrement sp by 4
    lw x1, 0(x2)  # load ra from stack
    jalr x0, 0(x1)                  # ret


  startScreen:
    addi x31, x0, 52     #1
    lui x10, 0x49723
    addi x10, x10, 0x76e
    sw x10, 0(x31)
    addi x31, x0, 48     #2
    lui x10, 0xaaa54
    addi x10, x10, 0x254
    sw x10, 0(x31)
    addi x31, x0, 44     #3
    lui x10, 0xaaa53
    addi x10, x10, 0x264
    sw x10, 0(x31)
    addi x31, x0, 40     #4
    lui x10, 0x49227
    addi x10, x10, 0x254
    sw x10, 0(x31)
    addi x31, x0, 32     #5
    lui x10, 0x47404
    addi x10, x10, 0x940
    sw x10, 0(x31)
    addi x31, x0, 28     #6
    lui x10, 0x4547a
    addi x10, x10, 0x2a0
    sw x10, 0(x31)
    addi x31, x0, 24     #7
    lui x10, 0x46404
    addi x10, x10, 0xaa0
    sw x10, 0(x31)
    addi x31, x0, 20     #8
    lui x10, 0x7577a
    addi x10, x10, 0x2a8
    sw x10, 0(x31)
    beq x0, x0, waitUntilIOInStart

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
    jalr x0, 0(x1)      # ret

  endGame:                # highlight game over in display
    bne x11, x29, displayloop  
    jal x1, bigDelay               
    displayloop:          ## loops and flickers GAME OVER message to user
      jal x1, endScreen
      jal x1, bigDelay    ## clears Arena
      jal x1, bigDelay
    beq x0, x0, displayloop   ## loop until reset
    
  # ====== Other functions END ======
