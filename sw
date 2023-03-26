#!/usr/bin/python
# TODO:        
#                * the lap implementation in Timer is a mess, understand/simplify/clean
#                * intervalometer ,  backwards counting timer,  sw -i <command>
#                * fix display after resizing 
#                * bug: status warning if LINES/COLS are under required values, and laps dont mix well
#                * redo the arg parser, positional arguments need to be as they come and not asume strings are of any format
#                * copy to clip
#                * vim quick, create a file somewhere in /tmp/sw_$PID, and when run with --retrieve simply dump_data in it, ...,  use import at exit
#                * remove -c its redundant, --Edit to open script, 'm'ini stopwatch

# this script provides examples of: faux global hotkeys, console resizing,  and the following modules:
import datetime, signal, curses

import os, sys, time

def print_version():
    print 'sw v0.99 (2020-04-15) by Rigormortis'
    quit()

def print_help():
    print 'sw - StopWatch, ncurses stopwatch with a few nifty features                          '
    print 'sw [-CFphv] [-c <time>] [-l <label>]                                                 '
    print 'sw -m [-CFphv] [-c <time1> <time2> <time3>] [-l "<label1>;<label2>;<label3>"         '
    print ''
    print 'keybinds: press "h" inside the program'
    print ''
    print 'arguments:'
    print '  -C              monocrome mode, dont use colors                                    '
    print '  -F              non figlet mode, don\'t use ascii art, not very useful              '
    print '  -p              start paused                                                       '
    print '  -c "hhh:mm:ss"  continue from string instead of 000:00:00                          '
    print '  -l "label"      put short description on stopwatch                                 '
    print '  -m              multi-stopwatch  ffx concept                                       '
    print '  -i <sec> <cmd>  intervalometer, run <cmd> every  n  seconds       *not implemented*'
    print '  -s              simple mode, removes the extra timers, and labels, overrides -l    '
    print '  -h              print this help, then quit                                         '
    print '  -v              print version, then quit                                           '
    quit()


def dump_data(timers, cur_timer):
    global LABELS_LIST
    sz = ''
    timers[cur_timer].pause()
    if MULTI_STOPWATCH:
        total_time = 0
        for i in range(3):
            sz += '{:20} {:10} {} seconds\n'.format(LABELS_LIST[i], sec2time(timers[i].accumulator), timers[i].accumulator)
            total_time += timers[i].accumulator
        sz +=  '{:20} {:10} {} seconds\n'.format('TOTAL', sec2time(total_time), total_time)
    else:
        sz += '{:20} {:10} {} seconds\n'.format(LABELS_LIST[cur_timer], sec2time(timers[cur_timer].accumulator), timers[cur_timer].accumulator)
        sz += timers[cur_timer].list_laps(show_all=True)
    if CONTINUE:
        sz += '\n' + progressed(timers, cur_timer)
    timers[cur_timer].unpause()
    return sz

def figify(sz):
    # sz needs to be of the form  123:45:65,  no other characters are supported
    #        0      8       16      24      32      40      48      56      64      72      80      88
    #        0123456 0123456 0123456 0123456 0123456 0123456 0123456 0123456 0123456 0123456 0123456 
    font = r'  ___      _     ____    _____   _  _    ____     __     _____    ___     ___           ' +\
           r' / _ \    / |   |___ \  |___ /  | || |  | ___|   / /_   |___  |  ( _ )   / _ \     _    ' +\
           r'| | | |   | |     __) |   |_ \  | || |_ |___ \  |  _ \     / /   / _ \  | (_) |   (_)   ' +\
           r'| |_| |   | |    / __/   ___) | |__   /  ___) | | (_) |   / /   | (_) |  \__  |    _    ' +\
           r' \___/    |_|   |_____| |____/     |_|  |____/   \___/   /_/     \___/     /_/    (_)   '
    output = ''
    for ch in sz:
        if not ch in '0123456789:':
            return 'ERROR'

    for line in range(0,441,88):
        for ch in sz:
            if ch == ':':
                column = line + 10*8
                output += font[(column+1):(column+7-1)]
            else:
                column = line + int(ch) * 8
                output += font[(column):(column+7)]
        output += '\n'
    return output

# what is this shit, fix this 2 functions
def sec2time(s, incl_milisec=False):
    if incl_milisec:
        ms =  str(s - int(s))[1:]
    s = int(s)
    h,s = divmod(s,3600)
    m,s = divmod(s,60)
    return '{:03}:{:02}:{:02}{}'.format(h,m,s, ms if incl_milisec else '')

def time2sec(sz):
    if   sz.count(':') == 2:
        h,m,s = sz.split(':')
        return int(h)*3600+int(m)*60+int(s)
    elif sz.count(':') == 1:
        m,s = sz.split(':')
        return int(m)*60+int(s)
    elif str.isdigit(sz):
        return int(sz)
    else:
        return None

class Stopwatch(object):
    def __init__(self, startfrom=0.0):
        self.accumulator = startfrom
        self.running = False
        self.lap_start = 0.0
        self.laps = list()
        self.lap_counter = 0
        self.lap_accumulator = 0.0
        self.lap_paused = False
    
    def lap_elapsed(self):
        return  (datetime.datetime.now() - self.lap_start).total_seconds()  + self.lap_accumulator
        
    def new_lap(self):
        global WARNING
        if self.lap_paused:
            return
        if self.lap_counter == 0:               # if this is the first lap, we copy it from timer
            self.laps.append(self.elapsed())
            self.lap_start = datetime.datetime.now()
            self.lap_counter = 1
            self.lap_accumulator = 0.0
            return
        if   self.lap_counter > 98: 
            WARNING = 'Only 99 laps are supported'
            return
        self.laps.append(self.lap_elapsed())
        self.lap_start = datetime.datetime.now()
        self.lap_counter += 1
        self.lap_accumulator = 0.0

    def list_laps(self, show_all=False):
        if self.lap_counter == 0:
            return ''
        output = ''
        if self.lap_counter < 5 or show_all:
            for n, t in enumerate(self.laps,1):
                output += 'lap #{:02}: {}\n'.format(n, sec2time(t, incl_milisec=True))
        else:
            last = self.lap_counter - 5
            for n, t in enumerate(self.laps[last:], last+1):
                output += 'lap #{:02}: {}\n'.format(n, sec2time(t, incl_milisec=True))
            
        output +=     'current:    {}\n'.format(self.lap_elapsed())
        return output

    def reset(self):
        """Resets the timer"""
        self.accumulator = 0.0
        self.start = datetime.datetime.now()

    def unpause(self):
        """Starts the timer"""
        if self.running: return
        self.lap_paused = False
        self.lap_start = datetime.datetime.now()
        self.start = datetime.datetime.now()
        self.running = True
        return
    
    def pause(self):
        """Stops the timer.  Returns the time elapsed"""
        if not self.running: return
        self.lap_paused = True
        self.lap_accumulator = self.lap_elapsed()
        self.accumulator = self.accumulator + (datetime.datetime.now() - self.start).total_seconds()
        self.running = False
        return self.accumulator

    def toggle(self):
        """Toggles between stop/start"""
        if self.running == True:
            self.pause()
        else:
            self.unpause()
    
    def now(self):
        """Returns the current time"""
        return str(datetime.datetime.now())
    
    def elapsed(self, convert_to_time=False):
        """Time elapsed since start was called"""
        if self.running:
            seconds = self.accumulator + (datetime.datetime.now() - self.start).total_seconds()
            return sec2time(int(seconds)) if convert_to_time else seconds
        else:
            return sec2time(int(self.accumulator)) if convert_to_time else self.accumulator
    

def write_status(stdscr, sz, color):
    i = 0
    while True:
        try:
            stdscr.addch(curses.LINES-1, i, ord(' '), color)
        except curses.error:
            break
        i += 1

    try:
        stdscr.addstr(curses.LINES-1, 1, sz[:(curses.COLS-1)], color)
    except curses.error:
        pass

def progressed(timers, cur_timer):
    global CONTINUE_LIST
    timers[cur_timer].pause()
    timers[cur_timer].unpause()
    sz = 'Progress: '
    for n, x in enumerate(CONTINUE_LIST):
        sz += sec2time(timers[n].accumulator - x) + '\t'
    return sz

def get_color(pair):
    """color :: fg bg
    fg, bg ::  {d|r|g|y|b|m|c|w}
    returns color_pair"""
    color_initials = {'d':0, 'r':1, 'g':2, 'y':3, 'b':4, 'm':5, 'c':6, 'w':7}
    fg = color_initials[pair[0]]
    bg = color_initials[pair[1]]
    return curses.color_pair(bg*8 +fg)

def init_colors():
#    curses.init_pair(1, curses.COLOR_RED, curses.COLOR_BLACK) 
    for bg in range(8):
        for fg in range(8):
            # init_pair 0 is always white on black, so we skip it
            if bg == 0 and fg == 0: continue
            curses.init_pair(bg*8+fg, fg, bg) 

def tst_colors(win):
    for y in range(8):
        for x in range(8):
            win.addstr(y, x+2*x, '#', curses.color_pair(y*8+x))

def signal_handler(sig, frame):
    global WARNING, GLOBAL_HOTKEY
    if  sig == 2:
        WARNING = 'SIGINT (ie. ^C) is disabled, to stop press "QY"'
    elif sig == 10:
        WARNING = 'Global Hotkey Pause'
        GLOBAL_HOTKEY = 'p'
    elif sig == 12:
        WARNING = 'Global Hotkey Continue'
        GLOBAL_HOTKEY = 'c'

def tui_sub(stdscr):
    global WARNING, MONOCHROME, NON_FIGLET, PAUSED, CONTINUE, MULTI_STOPWATCH, LABELS, LABELS_LIST, SIMPLE, GLOBAL_HOTKEY
    curses.curs_set(False)
    curses.mousemask(curses.ALL_MOUSE_EVENTS)
    stdscr.nodelay(True)
    stdscr.keypad(True)

    timers = list()
    cur_timer = 0

    # set timers and start them if -p not used
    if   MULTI_STOPWATCH and CONTINUE:
        timers.append( Stopwatch(CONTINUE_LIST[0]) )
        timers.append( Stopwatch(CONTINUE_LIST[1]) )
        timers.append( Stopwatch(CONTINUE_LIST[2]) )
        total_timer = Stopwatch(sum([timers[0].accumulator, timers[1].accumulator, timers[2].accumulator]))
    elif MULTI_STOPWATCH and (not CONTINUE):
        timers.append( Stopwatch(0) )
        timers.append( Stopwatch(0) )
        timers.append( Stopwatch(0) )
        total_timer = Stopwatch(0)
    elif (not MULTI_STOPWATCH) and CONTINUE:
        timers.append( Stopwatch(CONTINUE_LIST[0]) )
        progress_timer = Stopwatch(0)
    elif (not MULTI_STOPWATCH) and (not CONTINUE):
        timers.append( Stopwatch(0) )

    since_resume_timer = Stopwatch(0)
    paused_since_timer = Stopwatch(0)
    paused_since_timer.unpause()

    stdscr.bkgd(32, curses.A_REVERSE)
    if not PAUSED:
        stdscr.bkgd(32, curses.A_NORMAL)
        timers[cur_timer].unpause()
        since_resume_timer.unpause()
        paused_since_timer.pause()
        if (not MULTI_STOPWATCH) and CONTINUE:
            progress_timer.unpause()
        if MULTI_STOPWATCH:
            total_timer.unpause()

    init_colors()
    color_statusbar   = get_color('dw')
    color_timer0      = get_color('cd')
    color_timer1      = get_color('rd')
    color_timer2      = get_color('gd')
    color_warning     = get_color('wr')
    color_lap         = get_color('cd')
    color_extra_timers= get_color('bd')

    if MONOCHROME:
        color_statusbar = color_timer0 = color_timer1 = color_timer2 = color_warning = color_lap = color_extra_timers = get_color('wd')
        
    if not LABELS:
        LABELS_LIST = ['Stopwatch 1', 'Stopwatch 2', 'Stopwatch 3']

    # update the status bar, for the first time
    write_status(stdscr,  'Press "h" for keybinds', color_statusbar)

    # you dont want to close this accidentaly
    signal.signal(signal.SIGINT , signal_handler)
    signal.signal(signal.SIGUSR1, signal_handler)
    signal.signal(signal.SIGUSR2, signal_handler)

    lastkey = ''

    # main loop
    while True:                              
        c = stdscr.getch()
        if c > curses.ERR:
            write_status(stdscr, 'Press "h" for keybinds;    lastkey: {}'.format(lastkey if lastkey else curses.keyname(c)), color_statusbar)
            lastkey = ''

        if GLOBAL_HOTKEY:
            curses.ungetch(GLOBAL_HOTKEY)
            GLOBAL_HOTKEY = ''
        try:
            if MULTI_STOPWATCH:
                if NON_FIGLET or curses.COLS < 65 or curses.LINES < 20:
                    stdscr.addstr(1, 0, '{:20} {}'.format(LABELS_LIST[0], timers[0].elapsed(True)), color_timer0)
                    stdscr.addstr(2, 0, '{:20} {}'.format(LABELS_LIST[1], timers[1].elapsed(True)), color_timer1)
                    stdscr.addstr(3, 0, '{:20} {}'.format(LABELS_LIST[2], timers[2].elapsed(True)), color_timer2)
                else:
                    stdscr.addstr(1,  0, LABELS_LIST[0]             , color_timer0)
                    stdscr.addstr(2,  0, figify(timers[0].elapsed(True)), color_timer0)
                    stdscr.addstr(7,  0, LABELS_LIST[1]             , color_timer1)
                    stdscr.addstr(8,  0, figify(timers[1].elapsed(True)), color_timer1)
                    stdscr.addstr(13, 0, LABELS_LIST[2]             , color_timer2)
                    stdscr.addstr(14, 0, figify(timers[2].elapsed(True)), color_timer2)
            else:
                if NON_FIGLET or curses.COLS < 65 or curses.LINES < 20:
                    stdscr.addstr(1, 0, '{:20} {}'.format(LABELS_LIST[0], timers[cur_timer].elapsed(True)), color_timer0)
                else:
                    stdscr.addstr(1, 0, LABELS_LIST[0]                     , color_timer0)
                    stdscr.addstr(2, 0, figify(timers[cur_timer].elapsed(True)), color_timer0)

                if timers[cur_timer].lap_counter and (not timers[cur_timer].lap_paused):
                    stdscr.addstr(8, 0, timers[cur_timer].list_laps(), color_lap)

            if not SIMPLE:
                if (not MULTI_STOPWATCH) and CONTINUE:
                    stdscr.addstr(curses.LINES-3, 0, 'Progresed:        ' + progress_timer.elapsed(True), color_extra_timers)
                stdscr.addstr(curses.LINES-2, 0, 'Since last pause: ' + since_resume_timer.elapsed(True), color_extra_timers)
                stdscr.addstr(curses.LINES-4, 0, 'Paused since:     ' + paused_since_timer.elapsed(True), color_extra_timers)

                if  MULTI_STOPWATCH:
                    sz =  '{:8} {:10} {:20} seconds'.format('TOTAL            ', total_timer.elapsed(True), total_timer.elapsed(False))
                    stdscr.addstr(curses.LINES-3, 0, sz, color_extra_timers)

            if  curses.COLS < 30 or curses.LINES < 15:
                write_status(stdscr, 'WINDOW TO SMALL', color_warning)

        except curses.error:
            pass

        # on console window resize, LINES/COLS will be refreshed 
        if curses.is_term_resized(curses.LINES, curses.COLS):
            y, x = stdscr.getmaxyx()
            stdscr.clear()
            curses.resizeterm(y, x)
            stdscr.refresh()
                                                    # KEYBINDS
        if c == ord(' '):                           # TOGGLE TIMER PAUSE/RESUME
            if timers[cur_timer].running:
                curses.ungetch('p')
            else:
                curses.ungetch('c')
            lastkey =  'SPACE'
        elif c == ord('p'):                         # PAUSE TIMER
            timers[cur_timer].pause()
            since_resume_timer.pause()
            paused_since_timer.reset()
            paused_since_timer.unpause()
            if (not MULTI_STOPWATCH) and CONTINUE:
                progress_timer.pause()
            if MULTI_STOPWATCH:
                total_timer.pause()
            stdscr.bkgd(32, curses.A_REVERSE)
        elif c == ord('c'):                         # CONTINUE TIMER
            timers[cur_timer].unpause()
            since_resume_timer.reset()
            since_resume_timer.unpause()
            paused_since_timer.pause()
            if (not MULTI_STOPWATCH) and CONTINUE:
                progress_timer.unpause()
            if MULTI_STOPWATCH:
                total_timer.unpause()
            stdscr.bkgd(32, curses.A_NORMAL)
            write_status(stdscr, 'Press "h" for keybinds;    lastkey: {}'.format(lastkey if lastkey else curses.keyname(c)), color_statusbar)
        elif c == ord('R'):                         # RESET TIMER
            if  (not CONTINUE):
                since_resume_timer.reset()
                timers[cur_timer].reset()
                if not MULTI_STOPWATCH:
                    stdscr.clear()
                    timers[cur_timer].lap_start = datetime.datetime.now()
                    timers[cur_timer].laps = list()
                    timers[cur_timer].lap_counter = 0
                else:
                    total_timer.reset()
                    total_timer.accumulator = sum([timers[0].accumulator, timers[1].accumulator, timers[2].accumulator])
            else:
                WARNING='(R)eset is disabled in continue mode'

        elif c == ord('1') and MULTI_STOPWATCH:     # SWITCH TIMER 1 ON TIMER 2/3 OFF
            timers[cur_timer].pause()
            cur_timer = 0
            timers[cur_timer].unpause()
        elif c == ord('2') and MULTI_STOPWATCH:     # SWITCH TIMER 2 ON TIMER 1/3 OFF
            timers[cur_timer].pause()
            cur_timer = 1
            timers[cur_timer].unpause()
        elif c == ord('3') and MULTI_STOPWATCH:     # SWITCH TIMER 3 ON TIMER 2/2 OFF
            timers[cur_timer].pause()
            cur_timer = 2
            timers[cur_timer].unpause()
        elif c == ord('Q'):                         # QUIT NEEDS CONFIRMATION
            write_status(stdscr,  'Quit, are you sure? (Y/N)', color_warning)
            stdscr.nodelay(False)
            ch = stdscr.getch()
            if  ch == ord('Y'):
                timers[cur_timer].pause()
                break
            curses.ungetch(ch)
            stdscr.nodelay(True)
        elif c == ord('l')and(not MULTI_STOPWATCH): # BEGIN LAPS
            timers[cur_timer].new_lap()
        elif c == ord('n'):                         # SHOW CLOCK, much more useful in console
            write_status(stdscr, timers[cur_timer].now(), color_statusbar)
        elif c == ord('s'):                         # SAVE TO FILE
            t = datetime.datetime.now()
            fname = '/tmp/sw{}_{}{}{}.txt'.format(t.day, t.hour, t.minute, t.second)
            with open(fname, 'w') as fin:
                    fin.write(dump_data(timers, cur_timer))
            write_status(stdscr, 'SAVED TO: "{}"'.format(fname), color_warning)
        elif c == ord('h'):                         # PRINT KEYBINDS
            sz  = '(Q)uit (c)ontinue (p)ause (n)ow (s)napshot (SPACE)toggle (RCLICK)continue (LCLICK)pause '
            sz += '' if CONTINUE else '(R)eset '
            sz += '(#)_timer#' if MULTI_STOPWATCH else '(l)ap (MClick)lap'
            write_status(stdscr, sz, color_statusbar)
        elif c == curses.KEY_MOUSE:
            try:
                id, x, y, z, bstate = curses.getmouse()
            except curses.error:
                pass
            if   bstate & curses.BUTTON1_CLICKED:
                curses.ungetch('p')
                lastkey =  'LEFT_CLICK'
            elif bstate & curses.BUTTON2_CLICKED:
                timers[cur_timer].new_lap()
                lastkey =  'MIDDLE_CLICK'
            elif bstate & curses.BUTTON3_CLICKED:
                curses.ungetch('c')
                lastkey =  'RIGHT_CLICK'
#            if bstate & curses.BUTTON_ALT: #      .BUTTON_SHIFT  .BUTTON_CTRL

        if WARNING:
            write_status(stdscr, WARNING, color_warning)
            WARNING = ''

        stdscr.refresh()
        curses.napms(125)

    stdscr.keypad(False)
    return dump_data(timers, cur_timer)


def parse_arguments():
    global MULTI_STOPWATCH, CONTINUE, MONOCHROME, NON_FIGLET, PAUSED, LABELS, LABELS_LIST, SIMPLE
    args = sys.argv[1:]
    while len(args) > 0:
        arg = args.pop(0)
        if arg[0] == '-':
            if  'h' in arg:     print_help()
            if  'v' in arg:     print_version()
            if  'C' in arg:     MONOCHROME      = True
            if  'm' in arg:     MULTI_STOPWATCH = True
            if  'F' in arg:     NON_FIGLET      = True
            if  'p' in arg:     PAUSED          = True
            if  'l' in arg:     LABELS          = True
            if  's' in arg:     SIMPLE          = True
            if  'c' in arg:     CONTINUE        = True 
        elif CONTINUE  and  ':' in arg:     
            CONTINUE_LIST.append(time2sec(arg))
        elif LABELS:     
            LABELS_LIST.extend(arg.split(';'))
            if MULTI_STOPWATCH and len(LABELS_LIST) != 3:
                quit('In multistopwatch, label must be a string such as "label1;label2;label3"')
            for n,l in enumerate(LABELS_LIST):
                LABELS_LIST[n] = LABELS_LIST[n][0:20]
                

if __name__ == '__main__':
    WARNING = ''   # used to pass messages from functions to statusbar
    MONOCHROME = False
    MULTI_STOPWATCH = False
    CONTINUE = False
    CONTINUE_LIST = list()
    NON_FIGLET = False
    PAUSED = False
    LABELS = False
    LABELS_LIST = list()
    SIMPLE = False
    GLOBAL_HOTKEY = ''
    parse_arguments()

    # change title of terminal 
    print  "\033]0;{}\a".format('stopwatch ' + str(os.getpid()))
    print curses.wrapper(tui_sub) 
    print  "\033]0;{}\a".format('xterm')


