pico-8 cartridge // http://www.pico-8.com
version 14
__lua__

-- globals --

--directions
d={
 up=0,
 right=1,
 down=2,
 left=3
}
--constants
c={
 t_flag=0, --terrain flag
 h_flag=1, --hazard flag
 i_flag=5  --item flag
}
--tile types
tt={
 none=-1,
 bg=0,     --background
 grnd=10,
 ceil=11,
 transition={
  bg=1,
  grnd=12,
  ceil=13
 },
 i={
  p=20,    --bg w/ potential item
  batt=21, --battery
  hp=23    --heart
 },
 --hazards
 h={
  imb=30,    --immobile hazard
  moving=31, --moving hazard (also unused)
  ul=35      --upper left corner of a 2x2 hazard
 }
}
gravity=0.15
friction=0.95
slip_duration=0.4
burn_duration=2 --time player can burn before taking dmg
icicle_shake_duration=0.75
pit_boil_duration=1

--data explosion vars
tile_delimiter="|"
col_delimiter="\n"
plain_col_sym="_"
itemless_col_sym="@"

function _init()
 screen={
  upd=update_title,
  draw=draw_title
 }
 title={
  celw=32
 }
 p={
  sp=113,
  x=3*8,
  y=12*8,
  w=8,
  h=8,
  dx=0,
  dy=0,
  max_dx=1.5,
  max_dy=3,
  dx_mult=1,
  dx_mult_default=1,
  dy_mult=1,
  dy_mult_default=1,
  fwd_spd=1,
  back_spd=1,
  upright=true,
  anim=0, --anim cycle
  last_anim=0,
  no_anim=false,
  idle=true,
  grounded=true,
  jumping=false,
  falling=false,
  slipping=false,
  slip_time=0,  --time of last slip
  burning=false,
  burn_time=0, --time of burning start
  grav_charge=100,
  grav_cap=100,
  overcharge_cap=200,
  secret_extra_overcharge=1,
  charge_inc=0.1,
  decay_inc=0.05,
  grav_cost=10,
  hp=5, --5
  i_frames=60, --iframes granted after taking dmg
  i_frames_left=0,
  jump={
   min_jump_time=0.15,
   last_jump_time=-10,
   init_str=1.75,
   inc_str=0.2,
   curr_str=0,
   max_str=2.5
  },
  controllable=true
 }
 --data for player's falling sprites when losing. this should be inside p but i need the tokens
 flop={
  sprites={
   {falling=101,sliding=102,stopped=103},
   {falling=117,sliding=118,stopped=119}
  },
  selected=nil,
  stopped_moving=false,
  stop_time=0,
  flop_delay=4 --time to wait before transitioning from sliding spr to stopped spr
 }
 potential_charge=p.grav_charge --the min grav charge given perfect play (disregarding overcharge)
 --map
 m={
  start_cell_y=2,
  celw=16,
  w=128, --celw*8
  celh=12,
  x=0,
  y=0,
  ptr=title.celw, --marks x of cell where unloaded cells begin
  default_scroll_spd=2,
  scroll_spd=0
 }
 m.scroll_spd=m.default_scroll_spd
 buffer={
  num=2, --quantity of buffers
  celw=64,
  w=512, --celw*8
  celh=16,
  curr=0, --the current buffer screen
  offscreen_marker=0 --the point ahead of the screen where the map should be loaded up to at the minimum
 }
 buffers_celw=buffer.celw*buffer.num --total celw of all buffers. mostly for tokens saving
 --active entities
 entities={
  flames={},    --animated immobile hazards in fire level
  smoke={},     --smoke effects from burning
  webs={},      --webs on cave level. includes spiders
  icicles={},
  pits={},      --fireball spawning lava pits
  fireballs={}, --fireballs spawned from pits
  embers={},    --fire effects coming out of pits and off of fireballs
  npcs={},      --creatures affected by gravity like the player
  hearts={}     --little hearts at the end
 }
 items={
  heart={
   name="heart",
   chance=0.4,
   sp=120,
   heal_amount=1
  },
  batt={
   name="batt",
   chance=0.6,
   sp=121,
   charge_amount=50
  }
 }
 item_chance_default=0.05
 item_chance=item_chance_default --curr chance a chunk will spawn an item
 item_chance_inc=0.003 --additional chance each time chunk doesn't spawn item
 --level vars
 smoke_interval=0.2 --time between addition of smoke particles
 last_smoke_spawn=0 --time of last addition of smoke
 web_mvmt_mult=0.25 --velocity multiplier in webs
 web_scroll_spd=m.scroll_spd/2
 dist_scrolled=0
 dist_scrolled_in_level=0
 default_levelw=2560 --(64*5)*8 - 320 tiles, or 5 buffers' worth of cells
 --level transition vars
 prev_level=nil
 curr_level=forest_level
 curr_land=curr_level.land
 curr_sprint=curr_level.sprint
 curr_level_num=1
 transition_tile_ptr=-1 --celx of tile between two levels during a transition
 end_game_ptr=-1 --celx of tile after which the game ends
 transition_celw=24 --width of plain/safe chunk during transitions for each side
 ui_bg_colour=curr_level.ui_bg_c
 cheat_code={d.up,d.up,d.down,d.down,d.up,d.down,d.up,d.down}
 code_index=1 --curr place in cheat code

 start_time=0
 game_over_time=0
 victory=false
 show_run_info=false
 show_run_info_time=0
 shake_frames=0

 last_heart_sent_time=0
 --stats
 dist_scrolled_at_game_over=0
 total_hearts=p.hp
 gravity_flips=0
end


-->8
--update and draw

function _update()
 screen.upd()
end

function update_title()
 player_animate()
 --start game on button press
 if btn(0) or btn(1) or btn(4) or btn(5) then
  p.idle=false
  screen.upd=update_game
  screen.draw=draw_game
  play_level_music()
 elseif btnp(2) and code_index<=#cheat_code then
  if cheat_code[code_index]==d.up then
   code_index+=1
  else
   code_index=1
  end
 elseif btnp(3) and code_index<=#cheat_code then
  if cheat_code[code_index]==d.down then
   code_index+=1
  else
   code_index=1
  end
 end
 if code_index==#cheat_code+1 then
  --activate cheat
  sfx(4)
  p.hp=10
  total_hearts=p.hp
  code_index+=1
 end
end

function update_game()
 map_update()
 player_update()
 player_animate()
end

function update_ending()
 map_update()
 physics_update(p)
 player_animate()
 other_animate()
 physics_update(other)
 update_ending_scene()
end

function update_game_over()
 map_update()
 player_update_game_over()
 player_animate()
end

function _draw()
 screen.draw()
end

function lose_game()
 game_over_time=time()
 music(-1,5500)
 dist_scrolled_at_game_over=dist_scrolled
 --give player random fall sprite
 flop.selected=flop.sprites[1+flr(rnd(#flop.sprites))]
 p.i_frames_left=0
 --add momentum
 p.dx=m.scroll_spd
 m.scroll_spd=1
 screen.upd=update_game_over
 screen.draw=draw_game_over
end

function player_update_game_over()
 physics_update(p)
 --have player falling over/sliding for 3 secs
 if time()-game_over_time<=3 then
  p.dx=mid(-p.max_dx,p.dx,p.max_dx)
  p.x+=p.dx
  p.x=mid(0,p.x+p.dx,m.w-p.w)
  p.dx*=friction
  if not flop.stopped_moving then
   flop.stopped_moving=true
   flop.stop_time=time()
  end
 end
 --stop scrolling screen after 3 secs or if player approaches 3 tiles of the left edge
 if time()-game_over_time>3 or p.x<=24 then
  m.scroll_spd=0
 end
 --activate info display after 6 seconds or if player presses the jump/flip btns (after a 1 sec delay)
 if time()-game_over_time>1 and (time()-game_over_time>6 or btn(4) or btn(5)) and not show_run_info then
  show_run_info=true
  show_run_info_time=time()
 end
 --allow reset after 3 seconds on info screen
 if show_run_info and time()-show_run_info_time>1 and btn(5) then
  run()
 end
end

function draw_title()
 cls()
 --draw background
 for i=0,m.celw do
   for j=m.start_cell_y,get_bottom_cely() do
    spr(curr_level.bg_sprite,i*8,j*8)
   end
 end
 --draw ground and ceiling
 map(0,0,0,0,title.celw,buffer.celh)
 spr(p.sp,p.x,p.y)
 --draw title card
 palt(6,true)
 palt(0,false)
 spr(1,127/2-7*8/2,28,7,4)
 palt(6,false)
 palt(0,true)
end

function draw_game_over()
 draw_game()
 if show_run_info then
  --draw game over info
  local dist_msg_y=35
  if victory then
  --print this only if the player won
   print_centred("congratulations!",6)
  else
   print_centred("game over!",6)
  end
  print_centred("you ran",dist_msg_y)
  print_centred(dist_scrolled_at_game_over.." pixels",dist_msg_y+8)
  print_centred("in",dist_msg_y+16)
  print_centred(time_to_text(game_over_time-start_time),dist_msg_y+24)
  local heart_display={
   x=30,
   y=dist_msg_y+35
  }
  local heart_line="x"..total_hearts
  heart_display.x-=4+#heart_line*2
  spr(items.heart.sp,heart_display.x,heart_display.y)
  print_outlined(heart_line,heart_display.x+10,heart_display.y+2)

  local flip_line="grav. flips:"..gravity_flips
  print_outlined(flip_line,112-#flip_line*4,heart_display.y+2)
  print_centred("press flip to run again",dist_msg_y+50)
 end
end

function draw_ui()
 --draw charge bar
 local ui={
  --upper left pixel of charge bar
  x=4,
  y=5,
  --dimensions of one bar
  w=10,
  h=3,
  gutter=1, --width of gap between bars
  curr_charge=p.grav_charge
 }
 --width of entire charge ui
 ui.charge_w=(ui.w+1+ui.gutter)*((p.grav_cap)/p.grav_cost)-(1+ui.gutter)+2
 --colours
 local c={
  outline=0,
  filling_bar=13,
  full_bar=7,
  overcharge_bar=9,
  shadow=0
 }
 local bar_num=p.grav_cap/p.grav_cost
 --draw container
 rect(ui.x,ui.y,ui.x+ui.charge_w,ui.y+ui.h+2,c.outline)
 for i=1,bar_num do
  line(ui.x+i*(ui.w+ui.gutter+1),ui.y,ui.x+i*(ui.w+ui.gutter+1),ui.y+2+ui.h,c.outline)
 end
 --draw shadow
 line(ui.x+1,ui.y+ui.h+3,ui.x+(bar_num*(ui.w+ui.gutter+1)-1),ui.y+ui.h+3,c.shadow)
 line(ui.x+(bar_num*(ui.w+ui.gutter+1)-1)+2,ui.y+1,ui.x+(bar_num*(ui.w+ui.gutter+1)-1)+2,ui.y+ui.h+1,c.shadow)
 --draw bars
 fill_container(ui,c)
 if p.grav_charge>p.grav_cap then
  c.full_bar=c.overcharge_bar
  c.filling_bar=c.overcharge_bar
  ui.curr_charge-=p.grav_cap
  fill_container(ui,c)
 end

 --draw charge icon
 palt(7,true)
 palt(0,false)
 spr(192,ui.x-3,ui.y-3,2,2)
 palt(7,false)
 palt(0,true)

 --draw health
 local hp_ui={
  x=5,
  y=14*8+2
 }
 local row_length=12
 if p.i_frames_left>0 then
  --draw hearts as pink if player has iframes
  pal(8,14)
 end
 if p.hp<=row_length then
  --draw in one row, centred
  for i=1,min(p.hp,row_length) do
   spr(items.heart.sp,hp_ui.x+10*(i-1),hp_ui.y+1)
  end
 else
  --draw number amount
   spr(items.heart.sp,hp_ui.x,hp_ui.y+1)
   print("x"..p.hp,hp_ui.x+10,hp_ui.y+3,7)
 end
 pal(8,8)
end

function fill_container(ui,c)
 curr_x=ui.x+1
 local filled_bars=min(flr(ui.curr_charge/p.grav_cost),p.grav_cap/p.grav_cost)
 for i=1,filled_bars do
  rectfill(curr_x,ui.y+1,curr_x+ui.w,ui.y+1+ui.h,c.full_bar)
  curr_x+=ui.w+1+ui.gutter
 end
 --the last bar--only draw if first cap isn't reached
 if filled_bars!=p.grav_cap/p.grav_cost then
  local charging_bar_w=ui.curr_charge-filled_bars*ui.w
  --draw the bar as full if it's almost full
  if charging_bar_w/p.grav_cost>0.98 then
   charging_bar_w=ui.w
  end
  if charging_bar_w>=0.1 then
   rectfill(curr_x,ui.y+1,curr_x+charging_bar_w,ui.y+1+ui.h,c.filling_bar)
  end
 end
end

function draw_game()
 cls()
 draw_map()
 --draw top and bottom borders
 rectfill(0,0,127,m.start_cell_y*8-1,ui_bg_colour)
 rectfill(0,(get_bottom_cely()+1)*8,127,127,0)
 if not show_run_info then
  draw_ui()
 end
 if p.i_frames_left>0 then
  --draw player as pink while invincible
  pal(7,14)
 end
 spr(p.sp,p.x,p.y,1,1,false,not p.upright)
 pal(7,7)
end

function play_level_music()
 if curr_level.music!=nil then
  music(curr_level.music,0,7)
 end
end

function update_ending_scene()
 p.x-=m.scroll_spd
 if get_screen_position(transition_tile_ptr,0).x<=8 then
  --stop map scrolling when transition col is within 2 tiles of left side
  m.scroll_spd=0
  dist_scrolled_at_game_over=dist_scrolled
 end
 if p.x-get_screen_position(transition_tile_ptr,0).x<42 then
  --make player continue to move slowly until they're 5.25 tiles past the transition col
  p.x+=0.5
 else
  p.idle=true
 end

 --game jam code, sorry
 --stuff before sending out hearts
 if p.hp>0 then
  if time()-game_over_time>4 and other.x>127-p.x-p.w then
   --move toward player after a delay (at 1 speed before flipping and 0.5 speed after)
   other.x-=((other.flip_y==p.upright) and 1 or 0.5)
   --flip onto player's side when two thirds of the way through the path
   if other.x<=127-(p.x-p.w)/1.5 and other.flip_y==p.upright then
    sfx(2)
    shake_frames=3
    other.flip_y=not other.flip_y
    other.upright=not other.upright
   end
  elseif other.x<=127-p.x-p.w and not other.idle then
   other.idle=true
  elseif time()-game_over_time>8 and not other.no_anim then
   other.sp=125
   other.no_anim=true
   first_heart=generate_heart(other.x-1,other.y,0,0,true,other.flip_y)
  elseif time()-game_over_time>9.5 and not p.no_anim then
   p.sp=115
   p.no_anim=true
   second_heart=generate_heart(p.x+1,p.y,0,0,false,not p.upright)
  end

  if time()-game_over_time>12 and time()-last_heart_sent_time>0.1 then
   if first_heart.dx==0 then
    first_heart.dx=1
    first_heart.dy=rnd()-0.5
    second_heart.dx=-1
    second_heart.dy=rnd()-0.5
   end
   generate_heart(p.x+1,p.y,1,rnd()-0.5,false,not p.upright)
   generate_heart(other.x-1,other.y,-1,rnd()-0.5,true,other.flip_y)

   p.hp-=1
   last_heart_sent_time=time()
  end
 elseif time()-last_heart_sent_time>1 and p.sp!=116 then
  --stuff after sending out hearts
  if other.x-p.x>2 then
   p.no_anim=false
   p.idle=false
   other.no_anim=false
   other.idle=false
   p.x+=1
   if other.x-p.x>2 then
    other.x-=1
   end
  else
   p.sp=116
   p.no_anim=true
   other.sp=126
   other.no_anim=true
  end
 elseif time()-last_heart_sent_time>4 and not show_run_info then
  --show game over screen
  screen.draw=draw_game_over
  show_run_info=true
  --play the victory fanfare
  sfx(0)
 elseif show_run_info then
  --reset game on flip button
  if btn(5) then
   run()
  end
 end

 --update hearts
 to_del={}
 for _,v in pairs(entities.hearts) do
  v.x+=v.dx
  v.y+=v.dy
  if (v.dx>0 and v.x>other.x) or (v.dx<0 and v.x<p.x) then
   add(to_del,v)
  end
 end
 delete_entities(entities.hearts,to_del)
end

--deletes values in to_del from seq
function delete_entities(seq,to_del)
 --traverse backwards to delete entities
 for i=0,#to_del-1 do
  del(seq,to_del[#to_del-i])
 end
end

--creates and returns heart with given parameters
function generate_heart(x,y,dx,dy,flip_x,flip_y)
 local heart={
  sp=122,
  x=x,
  y=y,
  dx=dx,
  dy=dy,
  flip_x=flip_x,
  flip_y=flip_y
 }
 add(entities.hearts,heart)
 return heart
end
-->8
--player

--applies physics like gravity and collision to given object o
function physics_update(o)
 local direction
 
 --get direction of movement
 if o.dy>0 then
  direction=d.down
 elseif o.dy<0 then
  direction=d.up
 else
  direction=o.upright and d.down or d.up
 end
 
 --check grounded
 if collision(o,direction,1) then
  if not o.grounded then
   curr_land(o)
  end
  curr_sprint(o)
 else
  o.grounded=false
  o.burning=false
 end
 
 --apply gravity to dy
 if not o.grounded then
  o.dy+=(o.upright and gravity or -gravity)
 end
 o.dy=mid(-o.max_dy,o.dy,o.max_dy)
 local moved=0
 --move to destination while possible
 while moved<abs(o.dy)+1 do
  if not collision(o,direction,0) then
   if direction==d.down then
    o.y+=1*o.dy_mult
   elseif direction==d.up then
    o.y-=1*o.dy_mult
   end
   moved+=1
  else
   break
  end
 end
 
 --fix player if inside ground
 if collision(o,direction,0) then
  o.dy=0
  if direction==d.down then
   o.y-=(o.y+o.h)%8
  else
   o.y+=8-o.y%8
  end
 end
 
 --check if falling
 if (o.upright and o.dy>0) or
    (not o.upright and o.dy<0) then
  o.falling=true
  if o==p then
   --end jump for player
   end_jumping()
  end
 end
end

function player_update()
 physics_update(p)
 
 p.i_frames_left=max(0,p.i_frames_left-1)
 
 --check for hazard collisions
 local hurtbox={
  x1=get_map_position(p)+2,
  y1=p.y+1,
  x2=get_map_position(p)+p.w-2,
  y2=p.y+p.h-1
 }
 if rect_collision(hurtbox.x1,
                   hurtbox.y1,
                   hurtbox.x2,
                   hurtbox.y2,
                   c.h_flag) then
 take_damage(1)
 end
 --check for entity collisions
 local damage_hazards={}
 foreach({entities.flames,entities.fireballs,entities.icicles},function(group)
  for _,v in pairs(group) do
   add(damage_hazards,v)
  end
 end)
 --add spiders
 for _,v in pairs(entities.webs) do
  add(damage_hazards,v.spider)
 end
 if entity_collision(p,damage_hazards) then
  take_damage(1)
 end
 --web effects
 if not victory then
  if entity_collision(p,entities.webs) then
   p.dx_mult=web_mvmt_mult
   p.dy_mult=web_mvmt_mult
   m.scroll_spd=web_scroll_spd
  else
   p.dx_mult=p.dx_mult_default
   p.dy_mult=p.dy_mult_default
   m.scroll_spd=m.default_scroll_spd
   --move map forward if dist_scrolled is odd
   if dist_scrolled%2!=0 then
    m.x-=1
    dist_scrolled+=1
    dist_scrolled_in_level+=1
   end
  end
 end
 
 --check for item collisions
 if rect_collision(hurtbox.x1,
                   hurtbox.y1,
                   hurtbox.x2,
                   hurtbox.y2,
                   c.i_flag) then
  get_item(hurtbox.x1,hurtbox.y1)
  get_item(hurtbox.x1,hurtbox.y2)
  get_item(hurtbox.x2,hurtbox.y1)
  get_item(hurtbox.x2,hurtbox.y2)
 end
 
 --charge/decay grav charge and clamp
 if p.grav_charge<p.grav_cap then
  add_charge(p.charge_inc)
  p.grav_charge=mid(0,p.grav_charge,p.grav_cap)
 else
  add_charge(-p.decay_inc)
  p.grav_charge=mid(p.grav_cap,p.grav_charge,p.overcharge_cap+p.secret_extra_overcharge)
 end
 --add potential charge
 potential_charge=min(potential_charge+p.charge_inc,p.grav_cap)
 
 --input
 
 --movement
 p.dx=0
 if not p.slipping then
  if btn(1) and p.controllable then
   p.dx+=p.fwd_spd*p.dx_mult
  end
  if btn(0) and p.controllable then
   p.dx-=p.back_spd*p.dx_mult
  end
  --jump
  if btn(4) and p.controllable then
   if p.grounded then
    jump()
    p.jumping=true
    p.jump.last_jump_time=time()
   elseif p.jumping then
    jump()
   end
  else
   end_jumping()
  end
 else
  if time()>=p.slip_time+slip_duration then
   p.slipping=false
  end
 end
 p.dx=mid(-p.max_dx,p.dx,p.max_dx)
 p.x=mid(0,p.x+p.dx,m.w-p.w)
 p.dx*=friction

 --reverse gravity
 if btnp(5) and p.controllable and p.grav_charge>=p.grav_cost then
  sfx(2)
  gravity_flips+=1
  p.grav_charge=min(p.grav_charge,p.overcharge_cap)
  p.upright=not p.upright
  p.grav_charge-=p.grav_cost
  shake_frames=3
  p.slipping=false
  --reset velocity
  p.dy=0
 end
 
 if p.hp<=0 then
  lose_game()
 end
end

function add_charge(amt)
 p.grav_charge+=amt
end

--start jump or continue jumping
function jump()
 local j=p.jump
 local add_force=0
 if j.curr_str==0 then
  add_force=j.init_str
 else
  add_force=j.inc_str
 end
 j.curr_str+=add_force
 if j.curr_str<=j.max_str then
  if p.upright then
   p.dy-=add_force
  else
   p.dy+=add_force
  end
 end
end

--stops jumping after a jump ends and also when falling
function end_jumping()
 p.jumping=false
 p.jump.curr_str=0
 --immediately start falling (if min jump time reached)
 if time()>=p.jump.last_jump_time+p.jump.min_jump_time then
  if p.upright then
   p.dy=max(0,p.dy)
  else
   p.dy=min(0,p.dy)
  end
 end
end

function normal_land(o)
 o.dy=0
 o.grounded=true
 o.jumping=false
 o.falling=false
 o.slipping=false
end

function ice_land(o)
 normal_land(o)
 o.slipping=true
 o.slip_time=time()
end

--called whenever player is grounded
function normal_sprint(o)
 o.burning=false
end

function fire_sprint(o)
 if not o.burning then
  if o==p and p.i_frames_left<=0 and p.hp>0 then
   o.burning=true
   o.burn_time=time()
  end
 else
  if time()>=p.burn_time+burn_duration then
   take_damage(1)
   o.burning=false
  elseif o.i_frames_left>0 then
   o.burning=false
  else
   --add increasingly large smoke entities
   local burn_percent=(1-(p.burn_time+burn_duration-time())/burn_duration)
   local radius=min(3,flr(burn_percent*4))
   add_smoke(radius)
  end
 end
end

--create smoke at player's feet
function add_smoke(radius)
 local anim_frame=p.anim%3
 --add smoke on frames where feet contact ground
 if (anim_frame==0 or anim_frame==2) and radius>=1 then
  if time()>last_smoke_spawn+smoke_interval then
   local foot_offset=anim_frame==0 and -2 or 1
   local y_velocity=-0.3+(rnd(0.2)-0.1)
   local pos_y=p.y
   if p.upright then pos_y+=p.h-1 end
   --three sizes of smoke clouds
   local smoke={
    sp=72+(radius-1),
    x=p.x+p.w/2+foot_offset-radius,
    y=pos_y,
    dx=0,
    dy=y_velocity
   }
   add(entities.smoke,smoke)
   last_smoke_spawn=time()
  end
 end
end

function take_damage(dmg)
 if p.i_frames_left<=0 and p.hp>0 and not victory then
  sfx(1)
  p.i_frames_left=p.i_frames
  p.hp-=dmg
 end
end

function player_animate()
 if p.no_anim then return end
 if flop.selected!=nil then
  --game over animations
  if flop.stopped_moving and time()>flop.stop_time+flop.flop_delay then
   p.sp=flop.selected.stopped
  elseif p.grounded then
   p.sp=flop.selected.sliding
  else
   p.sp=flop.selected.falling
  end
 elseif p.slipping then
  p.sp=81+p.anim%3
 elseif p.burning then
  p.sp=97+(p.anim/2)%3
 elseif p.jumping then
  p.sp=69
 elseif p.falling then
  p.sp=70
 elseif p.idle then
  p.sp=113+(p.anim/25)%2
 elseif p.grounded then
  p.sp=65+(p.anim/2)%3
 end
 --inc anim cycle
 if time()-p.last_anim>0.05 then
  p.anim+=1
  p.last_anim=time()
 end
end

function other_animate()
 if other.no_anim then return end
 if other.falling then
  other.sp=79
 elseif other.idle then
  other.sp=123+(other.anim/25)%2
 elseif p.grounded then
  other.sp=75+(other.anim/2)%3
 end
 --inc anim cycle
 if time()-other.last_anim>0.05 then
  other.anim+=1
  other.last_anim=time()
 end
end
-->8
--collisions

--checks if obj with x,y,w,h collides with terrain
function collision(obj,direction,dist)
 local dest={
  x=get_map_position(obj),
  y=obj.y
 }
 if direction==d.up then
  dest.x+=obj.w/2
  dest.y-=dist
 elseif direction==d.right then
  dest.x+=obj.w+dist
  dest.y+=obj.h/2
 elseif direction==d.down then
  dest.x+=obj.w/2
  dest.y+=obj.h+dist
 elseif direction==d.left then
  dest.x-=dist
  dest.y+=obj.h/2
 end
 dest.x%=buffers_celw
 if fget(mget(dest.x/8,dest.y/8),c.t_flag) then
  return true
 else
  return false
 end
end

--checks if rect with given coords overlaps flag
function rect_collision(x1,y1,x2,y2,flag)
 if fget(mget(x1/8,y1/8),flag)
 or fget(mget(x1/8,y2/8),flag)
 or fget(mget(x2/8,y1/8),flag)
 or fget(mget(x2/8,y2/8),flag) then
  return true
 end
 return false
end

--checks if given obj collides with any objects in given table of objs (with x,y values)
function entity_collision(obj,objs)
 local corners={
  x1=obj.x,
  y1=obj.y,
  x2=obj.x+obj.w-1,
  y2=obj.y+obj.h-1
 }
 --make player hurtbox more accurate
 if obj==p then
  corners.x2-=1
 end
 for _,v in pairs(objs) do
  --corners of curr obj in objs
  local curr={
   x1=v.x,
   y1=v.y,
   x2=v.x+v.w-1,
   y2=v.y+v.h-1
  }
  if not(corners.x1>curr.x2 or corners.x2<curr.x1 or corners.y1>curr.y2 or corners.y2<curr.y1) then
   return true
  end
 end
 return false
end
-->8
--map

function map_update()
 if shake_frames>0 then
  shake_frames-=1
  camera(rnd(6)-3,rnd(6)-3)
  if shake_frames==0 then
    --end shake
    camera()
  end
 end
 update_entities()
 m.x-=m.scroll_spd
 dist_scrolled+=m.scroll_spd
 dist_scrolled_in_level+=m.scroll_spd
 --mod ptr if buffer is about to loop
 local new_marker=get_buffer_start()+m.celw-m.x/8+1
 if buffer.offscreen_marker>new_marker then
  m.ptr%=buffers_celw
 end
 --load a chunk if the ptr is immediately outside the screen
 buffer.offscreen_marker=new_marker
 while m.ptr<buffer.offscreen_marker and curr_level.chunks!=nil do
  load_chunk()
 end
 --move prev buffer ahead if it has passed
 if abs(m.x)/8>=buffer.celw then
  buffer.curr+=1
  buffer.curr%=buffer.num
  m.x=0
 end
 --the distance after which this level ends
 local end_dist=curr_level.levelw!=nil and curr_level.levelw or default_levelw
 if dist_scrolled_in_level>=end_dist then
  --load next level if enough distance has passed
  next_level()
  dist_scrolled_in_level=0
 end
 if get_screen_position(transition_tile_ptr,0).x<=-8 then
  --transition has finished, so reset transition ptr and update bg colour & music
  transition_tile_ptr=-1
  ui_bg_colour=curr_level.ui_bg_c
  play_level_music()
  dist_scrolled_in_level=0
 end
 if transition_tile_ptr!=-1 then
  transition_pos_x=get_screen_position(transition_tile_ptr,0).x
  --update player's land and sprint functions based on where they're standing
  if p.x<transition_pos_x then
   curr_land=prev_level.land
   curr_sprint=prev_level.sprint
  elseif p.x>=transition_pos_x+8 then
   curr_land=curr_level.land
   curr_sprint=curr_level.sprint
  else
   --transition column has no land effects
   curr_land=normal_land
   curr_sprint=normal_sprint
  end
 end
 --check for game ending (if transition ptr has hit the left side or is more than two tiles behind player)
 if curr_level==meeting_place and game_over_time==0 and 
  (get_screen_position(transition_tile_ptr,0).x<=8 or (p.x>get_screen_position(transition_tile_ptr,0).x and p.x-get_screen_position(transition_tile_ptr,0).x>16)) then
  --stop screen movement if ptr has hit left side; otherwise slow down
  if get_screen_position(transition_tile_ptr,0).x<=8 then
   m.scroll_spd=0
  else
   m.scroll_spd=1
  end
  ui_bg_colour=curr_level.ui_bg_c
  curr_land=curr_level.land
  curr_sprint=curr_level.sprint
  p.i_frames_left=0
  game_over_time=time()
  victory=true
  --fade out music
  music(-1,1500)

  --create other person
  other={
   sp=75,
   flip_x=true,
   flip_y=p.upright,
   x=128, --16*8
   y=p.upright and (m.start_cell_y+1)*8 or (get_bottom_cely()-1)*8,
   w=p.w,
   h=p.h,
   dx=0,
   dy=0,
   max_dx=p.max_dx,
   max_dy=p.max_dy,
   dx_mult=p.dx_mult,
   dy_mult=p.dy_mult,
   upright=not p.upright,
   anim=0, --anim cycle
   no_anim=false,
   idle=false,
   grounded=true,
   jumping=false,
   falling=false,
   slipping=false,
   burning=false,
   last_anim=0
  }
  add(entities.npcs,other)

  screen.upd=update_ending
  p.controllable=false
 end
end

function update_entities()
 local to_del={}
 
 --flames
 for _,v in pairs(entities.flames) do
  v.x-=m.scroll_spd
  --show only if visible, otherwise mark entity for deletion
  if -8<v.x then
   if time()-v.last_anim_time>=0.1 then
    v.sp=(v.sp+1)%3+172
    v.last_anim_time=time()
   end
  else
   add(to_del,v)
  end
 end
 delete_entities(entities.flames,to_del)
 
 to_del={}
 --smoke
 for _,v in pairs(entities.smoke) do
  v.x-=m.scroll_spd
  v.x+=v.dx
  v.y+=v.dy
  v.dx*=friction
  if v.x<-8 then
   add(to_del,v)
  end
 end
 delete_entities(entities.smoke,to_del)
 
 to_del={}
 --webs
 for _,v in pairs(entities.webs) do
  v.x-=m.scroll_spd
  v.spider.x-=m.scroll_spd
  wx=v.x
  wy=v.y
  --spider moves clockwise around web
  if -16<v.x-v.safe_border then
   if v.spider.y==v.y-v.safe_border and v.spider.x!=v.x-v.safe_border+(v.w+v.safe_border*2)/2-1 then
    --move from upper left to upper right
    v.spider.x+=v.spider.spd
    v.spider.sp=157
    v.spider.flip_x=false
    v.spider.flip_y=false
   elseif v.spider.y==v.y-v.safe_border+(v.h+v.safe_border*2)/2-1 and v.spider.x!=v.x-v.safe_border then
    --move from lower right to lower left
    v.spider.x-=v.spider.spd
    v.spider.sp=157
    v.spider.flip_x=true
    v.spider.flip_y=false
   elseif v.spider.x==v.x-v.safe_border then
    --move from lower right to upper left
    v.spider.y-=v.spider.spd
    v.spider.sp=141
    v.spider.flip_x=false
    v.spiderflip_y=false
   else
    --move from upper right to lower right
    v.spider.y+=v.spider.spd
    v.spider.sp=141
    v.spider.flip_x=false
    v.spider.flip_y=true
   end
  else
   add(to_del,v)
  end
 end
 delete_entities(entities.webs,to_del)

 to_del={}
 --icicles
 for _,v in pairs(entities.icicles) do
  v.x-=m.scroll_spd
  v.y+=v.dy
  if v.x<-8 then
   add(to_del,v)
  end
  if v.x<=v.fall_x and not v.shaking and not v.falling then
   --start shaking
   v.shaking=true
   v.shake_time=time()
  end
  if v.shaking then
   --random shaking
   v.offset_x=flr(rnd(2))-1
   v.offset_y=flr(rnd(2))-1
  end
  if v.shaking and time()-v.shake_time>icicle_shake_duration then
   --start falling
   v.shaking=false
   v.falling=true
   v.dy=v.fall_spd
  end
 end
 delete_entities(entities.icicles,to_del)


 to_del={}
 --embers
 for _,v in pairs(entities.embers) do
  v.x-=m.scroll_spd
  v.x+=v.dx
  v.y+=v.dy
  if v.x<0 or time()>v.spawn_time+v.lifetime then
   add(to_del,v)
  end
 end
 delete_entities(entities.embers,to_del)

 to_del={}
 --fireballs
 for _,v in pairs(entities.fireballs) do
  v.x-=m.scroll_spd
  v.dy+=v.grav
  v.y+=v.dy
  if v.dy>0 then
    v.flip_y=true
  end
  if v.x<-8 then
   add(to_del,v)
  end
  if time()>v.last_ember+v.ember_delay then
   --spawn ember
   local ember={
    x=v.x+rnd(v.w-1)+1,
    y=v.y+v.h/2,
    dx=rnd(0.1)-0.05, -- -0.05 to 0.05
    dy=rnd(0.1)-0.05, -- should be less than bubble
    spawn_time=time(),
    lifetime=rnd(1)+0.5, -- 0.5 to 1.5
    colour=8
   }
   add(entities.embers,ember)
   v.last_ember=time()
  end
 end
 delete_entities(entities.fireballs,to_del)

 to_del={}
 --pits
 for _,v in pairs(entities.pits) do
  v.x-=m.scroll_spd
  --show only if visible, otherwise mark entity for deletion
  if v.x<-8 then
   add(to_del,v)
  else
   if v.x<=v.boil_x and not v.boiling and not v.inert then
    v.boiling=true
    v.boil_time=time()
   end
   if v.boiling and time()>v.last_bubble+v.bubble_delay then
    --spawn bubble
    local ember={
     x=v.x+flr(rnd(v.w)),
     y=v.y+4,
     dx=rnd(0.5)-0.25,   -- -0.25 to 0.25
     dy=-(rnd(0.1)+0.1), -- 0.1 to 0.2
     spawn_time=time(),
     lifetime=rnd(0.25)+0.25, -- 0.25 to 0.5
     colour=7
    }
    add(entities.embers,ember,to_del)
    v.last_bubble=time()
   end
   if v.boiling and time()>v.boil_time+pit_boil_duration then
    v.inert=true
    v.boiling=false
    local fireball={
     sp=175,
     x=v.x,
     y=v.y,
     w=8,
     h=8,
     flip_y=false,
     dy=-v.fireball_force,
     grav=v.fireball_gravity,
     last_ember=0,
     ember_delay=0.1
    }
    add(entities.fireballs,fireball)
   end
  end
 end
 delete_entities(entities.pits,to_del)
end

function draw_map()
 --draw background
 if transition_tile_ptr<0 then
  --draw 16x12 background for entire level
  for i=0,m.celw do
   for j=m.start_cell_y,get_bottom_cely() do
    spr(curr_level.bg_sprite,i*8,j*8)
   end
  end
 else
  --draw split background during transitions
  --celx of transition column
  local celx=get_screen_position(transition_tile_ptr,0).x/8
  --draw prev level's background
  for i=0,celx do
   for j=m.start_cell_y,get_bottom_cely() do
    spr(prev_level.bg_sprite,i*8+m.x%8-8,j*8)
   end
  end
  --draw next level's background
  for i=flr(celx)+1,flr(celx)+m.celw do
   for j=m.start_cell_y,get_bottom_cely() do
    spr(curr_level.bg_sprite,i*8+m.x%8,j*8)
   end
  end
 end
 --map buffers in order
 if buffer.curr==0 then
  map(0,0,m.x,m.y,buffer.celw,buffer.celh)
  map(buffer.celw,0,m.x+buffer.w,m.y*8,buffer.celw,buffer.celh)
 elseif buffer.curr==1 then
  map(buffer.celw,0,m.x,m.y,buffer.celw,buffer.celh)
  map(0,0,m.x+buffer.w,m.y*8,buffer.celw,buffer.celh)
 end
 draw_entities()
end

function draw_entities()
 --draw special case entities
 for _,v in pairs(entities.webs) do
  spr(142,v.x-v.safe_border,v.y-v.safe_border,2,2)
  spr(v.spider.sp,v.spider.x,v.spider.y,1,1,v.spider.flip_x,v.spider.flip_y)
 end
 for _,v in pairs(entities.icicles) do
  spr(154,v.x+v.offset_x,v.y-1+v.offset_y,1,1,false,true)
 end
 for _,v in pairs(entities.embers) do
  pset(v.x,v.y,v.colour)
 end
 
 --draw all entities with an sp key
 for _,category in pairs(entities) do
  for _,v in pairs(category) do
   if v.sp!=nil then
    local flip_x=v.flip_x!=nil and v.flip_x or false
    local flip_y=v.flip_y!=nil and v.flip_y or false
    spr(v.sp,v.x,v.y,1,1,flip_x,flip_y)
   end
  end
 end
end

--returns the celx of the first cell on the current buffer. mostly used to save on tokens
function get_buffer_start()
 return buffer.curr*buffer.celw
end

--returns cely of bottom-most (visible) cells
function get_bottom_cely()
 return m.start_cell_y+m.celh-1
end

--returns an object's x position on the map (/8 to get celx position ranging 0-127)
function get_map_position(obj)
 return (obj.x-m.x+get_buffer_start()*8)%(buffers_celw*8-1)
end

--returns celx of the tile that is a screen and one tile away from the most recent tile to have completely passed the left edge of the screen
function get_offscreen_right_tile()
 return (get_buffer_start()+(-m.x/8)+m.celw+1)%buffers_celw
end

--converts a celx and cely on the map to an x, y coord on the screen
function get_screen_position(celx, cely)
 --x position relative to beginning of current buffer
 local x_pos=(celx%buffer.celw)*8+m.x
 --add extra buffer width if the celx is on the next buffer
 if not(get_buffer_start()<=celx and celx<=get_buffer_start()+buffer.celw-1) then
  x_pos+=buffer.w
 end
 local y_pos=cely*8+m.y
 return {x=x_pos,y=y_pos}
end

--gets possible item at position x,y
function get_item(x,y)
 sp=mget(x/8,y/8)
 if sp==items.heart.sp then
  sfx(4)
  total_hearts+=1
  p.hp+=items.heart.heal_amount
  curr_level.add_tile(tt.none,x/8,y/8)
 elseif sp==items.batt.sp then
  sfx(3)
  add_charge(items.batt.charge_amount)
  curr_level.add_tile(tt.none,x/8,y/8)
 end
end

function get_random_chunk(chunks)
 return chunks[flr(rnd(#chunks)+1)]
end

--add more chunks to the map
function load_chunk()
 --choose random chunk
 local chunk=get_random_chunk(curr_level.chunks)
 --reroll chunk while its required flips are too expensive
 while chunk.req_flips!=nil and chunk.req_flips*p.grav_cost>potential_charge do
  chunk=get_random_chunk(curr_level.chunks)
 end
 if chunk.req_flips!=nil then
  potential_charge-=chunk.req_flips*p.grav_cost
 end
 --randomize flipping
 local flip_v=rnd()<0.5 and true or false
 local flip_h=rnd()<0.5 and true or false
 if chunk.flippable!=nil then
  --set flipping to false if specified
  if not chunk.flippable.v then flip_v=false end
  if not chunk.flippable.h then flip_h=false end
 end

 local item_placed=false
 local spawn_item=rnd()<item_chance+(chunk.item_mods!=nil and chunk.item_mods.item_chance or 0)
 local eligible_spots={}
 
 --add chunk tiles to buffer
 for i=#chunk.tiles,1,-1 do --read from last sequence and iterate backwards
  for j=1,#chunk.tiles[i] do
   --celx on map to place tile
   local x=m.ptr%buffers_celw
   --location of the tile in the chunk to use
   local tile_x=i
   if flip_v then
    tile_x=#chunk.tiles-(i-1)
   end
   local tile_y=j
   --don't flip ceiling and ground tiles
   if flip_h and j!=1 and j!=#chunk.tiles[i] then
    tile_y=#chunk.tiles[i]-(j-1)
   end
   --calculate offsets for entities that take up two tiles
   local celx_offset=flip_v and -1 or 0
   local cely_offset=flip_h and -1 or 0
   curr_level.add_tile(chunk.tiles[tile_x][tile_y],x,j-1+m.start_cell_y,celx_offset,cely_offset)
   if chunk.tiles[tile_x][tile_y]==tt.i.p then
    add(eligible_spots,{x=#chunk.tiles-(i-1),y=j})
   end
  end
  --update ptr; loop if needed
  m.ptr+=1
 end
 --spawn item if necessary
 if spawn_item and #eligible_spots>0 then
  local rnd_coord=eligible_spots[flr(rnd(#eligible_spots))+1]
  place_item((m.ptr-#chunk.tiles-1+rnd_coord.x)%buffers_celw,rnd_coord.y-1+m.start_cell_y,chunk.item_mods)
  item_placed=true
 end
 --reset chance if spawned or inc if not spawned
 item_chance=item_placed and item_chance_default or item_chance+item_chance_inc
end

--randomly chooses and places an item at cell at x,y
function place_item(x,y,item_mods)
 local chosen_item
 local roll=rnd()
 for _,v in pairs(items) do
  if chosen_item==nil then
   local total=0
   total+=v.chance+(item_mods!=nil and item_mods[v.name] or 0)
   if roll<total then
    chosen_item=v.sp
   end
  end
 end
 mset(x,y,chosen_item)
end

--loads in a chunk of tiles with no hazards from the given level at m.ptr, with given width
function load_plain_chunk(level,celw)
 for i=1,celw do
  level.add_tile(tt.ceil,m.ptr%buffers_celw,m.start_cell_y)
  for j=m.start_cell_y+1,get_bottom_cely()-1 do
   level.add_tile(tt.bg,m.ptr%buffers_celw,j)
  end
  level.add_tile(tt.grnd,m.ptr%buffers_celw,get_bottom_cely())
  m.ptr+=1
 end
end

--add transition column of tiles of given level at current pointer
function load_transition_column(level)
  level.add_tile(tt.transition.ceil,m.ptr%buffers_celw,m.start_cell_y)
  for j=m.start_cell_y+1,get_bottom_cely()-1 do
    level.add_tile(tt.transition.bg,m.ptr%buffers_celw,j)
  end
  level.add_tile(tt.transition.grnd,m.ptr%buffers_celw,get_bottom_cely())
  m.ptr+=1
end

function next_level()
 --move pointer to tile off the right edge of screen
 m.ptr=get_offscreen_right_tile()

 --delete offscreen entities
 local to_del={}
 for _,group in pairs(entities) do
  for _,v in pairs(group) do
   if v.x>=m.w then
    add(to_del,v)
   end
  end
 end
 for _,pit in pairs(entities.pits) do
  --replace pits with ground tiles
  if pit.x>=m.w then
   curr_level.add_tile(tt.grnd,pit.celx,pit.cely)
  end
 end
 local to_del_size=#to_del
 for i=0,to_del_size-1 do
  for _,group in pairs(entities) do
   del(group,to_del[to_del_size-i])
  end
 end

 if curr_level.next_level==trial then
  --load final trial
  curr_level=trial
 elseif curr_level.next_level==meeting_place then
  load_meeting_place()
 else
  --normal level transition

  --load plain tiles
  load_plain_chunk(curr_level,transition_celw)
  transition_tile_ptr=m.ptr%buffers_celw
  load_transition_column(curr_level)

  --set next level and load its plain tiles
  prev_level=curr_level
  curr_level=curr_level.next_level
  load_plain_chunk(curr_level,transition_celw)
  curr_level_num+=1
 end
end

function load_meeting_place()
 transition_tile_ptr=m.ptr%buffers_celw
 --load entrance transition on left side
 load_transition_column(curr_level)
 prev_level=curr_level
 curr_level=curr_level.next_level
 curr_level_num+=1
 load_plain_chunk(curr_level,m.celw-4)
 --load exit transition on right side
 load_transition_column(curr_level)
 --randomly add flames to the centre tiles of the first col after this transition
 for j=m.start_cell_y+2,get_bottom_cely()-3 do
  if 0.3<rnd() then
   fire_level.add_tile(tt.h.imb,m.ptr%buffers_celw,j)
  end
 end
 load_plain_chunk(fire_level,m.celw*2)
end

--given tile type and cell coords, converts tile type to spr num and places spr at location
function forest_add_tile(tile,celx,cely)
 local sp=0
 if tile==tt.bg or tile==tt.i.p   then sp=forest_level.bg_sprite
 elseif tile==tt.grnd  then sp=128+rnd(4)
 elseif tile==tt.ceil  then sp=132+rnd(4)
 elseif tile==tt.h.imb then sp=137+rnd(3)
 elseif tile==tt.transition.bg    then sp=25+flr(rnd(2))*16 --25 or 41
 elseif tile==tt.transition.grnd  then sp=57
 elseif tile==tt.transition.ceil  then sp=9
 elseif tile==tt.none             then sp=0
 end
 mset(celx,cely,sp)
end

--takes potential offsets for flipping entities that span more than one tile
function cave_add_tile(tile,celx,cely,celx_offset,cely_offset)
 local sp=0
 if tile==tt.bg or tile==tt.i.p then sp=cave_level.bg_sprite
 elseif tile==tt.grnd then sp=176+rnd(4)
 elseif tile==tt.ceil then
  sp=180+rnd(4)
  local roll=rnd()
  if roll<0.001 then
   --0.1% chance to spawn grnd with diamond in it
   sp=186
  elseif roll<0.01 then
   --1% chance for emerald
   sp=185
  end
 elseif tile==tt.h.imb then sp=141
 elseif tile==tt.h.ul  then
  mset(celx,cely,184)
  --get centre point of chunk
  local pos=get_screen_position(celx+celx_offset,cely+cely_offset)
  --choose random part of web path for spider pos
  local spider_pos_x=pos.x+flr(rnd(5))
  local spider_pos_y=pos.y+(rnd()<0.5 and 0 or 8)
  local border=3 --border of web where player isn't affected
  local web={
   x=pos.x+border,
   y=pos.y+border,
   w=12,
   h=12,
   safe_border=border,
   spider={
    sp=141,
    flip_x=false,
    flip_y=false,
    x=spider_pos_x,
    y=spider_pos_y,
    w=8,
    h=8,
    spd=0.25
   }
  }
  add(entities.webs,web)
  return
 elseif tile==tt.transition.bg    then sp=27+flr(rnd(2))*16 --27 or 43
 elseif tile==tt.transition.grnd  then sp=59
 elseif tile==tt.transition.ceil  then sp=11
 elseif tile==tt.none             then sp=0
 end
 mset(celx,cely,sp)
end

function ice_add_tile(tile,celx,cely)
 local sp=0
 if tile==tt.bg or tile==tt.i.p then sp=ice_level.bg_sprite
 elseif tile==tt.grnd  then sp=144
 elseif tile==tt.ceil  then sp=148
 elseif tile==tt.h.imb then sp=154
 elseif tile==tt.h.moving then
  mset(celx,cely,152)
  local pos=get_screen_position(celx,cely)
  --range of x screen positions where icicles can fall
  local min_fall_x=6*8
  local max_fall_x=20*8
  local fall_x=rnd(max_fall_x-min_fall_x)+min_fall_x
  --30% chance this icicle won't fall. keep em on their toes
  if rnd()<0.3 then fall_x=-8 end
  local icicle={
   x=pos.x,
   y=pos.y,
   offset_x=0,
   offset_y=0,
   dy=0,
   w=8,
   h=8,
   shaking=false,
   shake_time=0, --time at which icicle begins to shake
   falling=false,
   fall_x=fall_x, --screen x at which this icicle will start falling
   fall_spd=2
  }
  add(entities.icicles,icicle)
  return
 elseif tile==tt.transition.bg   then sp=29+flr(rnd(2))*16 --29 or 45
 elseif tile==tt.transition.grnd then sp=61
 elseif tile==tt.transition.ceil then sp=13
 elseif tile==tt.none            then sp=0
 end
 mset(celx,cely,sp)
end

function fire_add_tile(tile,celx,cely)
 local sp=0
 if tile==tt.bg or tile==tt.i.p then sp=fire_level.bg_sprite
 elseif tile==tt.grnd or tile==tt.ceil then sp=160+rnd(4)
 elseif tile==tt.h.imb then
  fire_add_tile(tt.bg,celx,cely)
  local pos=get_screen_position(celx,cely)
  local flame={
   sp=172+rnd(3),
   x=pos.x,
   y=pos.y,
   w=8,
   h=8,
   last_anim_time=time()
  }
  add(entities.flames,flame)
  return
 elseif tile==tt.h.moving then
  mset(celx,cely,169)
  --range of x screen positions where pit can spawn fireball
  local pos=get_screen_position(celx,cely)
  local min_boil_x=80 --10*8
  local max_boil_x=200 --25*8
  local pit={
   sp=170+flr(rnd(2)),
   celx=celx,
   cely=cely,
   x=pos.x,
   y=pos.y,
   w=8,
   h=8,
   boiling=false,
   boil_time=0,         --time at which pit begins to spawn fireball
   last_bubble=0,       --time of last bubble spawn
   bubble_delay=0.1,    --time between bubble spawns
   inert=false,         --whether this pit has spawned a fireball or not
   boil_x=rnd(max_boil_x-min_boil_x)+min_boil_x, --screen x at which pit begins to spawn fireball
   fireball_force=4,
   fireball_gravity=0.1
  }
  add(entities.pits,pit)
  return
 elseif tile==tt.transition.bg   then sp=30
 elseif tile==tt.transition.grnd then sp=62
 elseif tile==tt.transition.ceil then sp=14
 elseif tile==tt.none            then sp=0
 end
 mset(celx,cely,sp)
end

function end_add_tile(tile,celx,cely)
 local sp=0
 if tile==tt.bg or tile==tt.i.p then sp=meeting_place.bg_sprite
 elseif tile==tt.grnd or tile==tt.ceil then sp=188
 elseif tile==tt.transition.bg   then sp=31
 elseif tile==tt.transition.grnd then sp=63
 elseif tile==tt.transition.ceil then sp=15
 elseif tile==tt.none            then sp=0
 end
 mset(celx,cely,sp)
end
-->8
--helper

--returns given string with all whitespace removed
function trim(string)
 local ret=""
 for i=1,#string do
  local char=sub(string,i,i)
  if char!=" " then
   ret=ret..char
  end
 end
 return ret
end

--returns a time t in seconds as _h_m_s format
function time_to_text(t)
 local ret=""
 if t>=60 then
  --minutes
  ret=ret..flr(t/60).."m"
  t%=60
 end
 --add a 0 if seconds is one digit but only if there are already minutes
 if t<10 and ret != "" then
  ret=ret.."0"
 end
 ret=ret..flr(t).."s"
 return ret
end

--prints letter l with an outline, at x,y
function print_letter(l,x,y)
 palt(0,false)
 --print letter all around x,y
 for i=-1,1 do
  for j=-1,1 do
   print(l,x+i,y+j,0)
  end
 end
 print(l,x,y,7)
 palt(0,true)
end

--prints a string outlined at y and centred on the given x
function print_outlined(str,x,y)
 for i=1,#str do
  --individually print each outlined letter
  print_letter(sub(str,i,i),x,y)
  x+=4
 end
end

--prints a string outlined and horizontally centred on the given y
function print_centred(str,y)
 print_outlined(str,64-#str*2,y)
end

--converts a set of chunk tiles in string format to a table of tile column tables and returns it
--note this reverses the order of columns so that the leftmost ones appear first in the sequence instead of last
function explode_chunk_tiles(string)
 local tiles={}
 local col_i=1 --index of beginning of unprocessed string
 for i=1,#string do
  if sub(string,i,i)==col_delimiter then
   local col_str=sub(string,col_i,i-1)
   local col={}
   --check for special _ or @ row
   if col_str==plain_col_sym or col_str==itemless_col_sym then
    add(col,11)
    for i=2,11 do
     if col_str==plain_col_sym then
      -- plain row of 11|20|...|20|10|
      add(col,20)
     elseif col_str==itemless_col_sym then
      --plain, itemless row of 11|00|...|00|10|
      add(col,0)
     end
    end
    add(col,10)
   else
    --read data for normal col
    col_i=i+1
    --explode this column
    local tile_i=1 --index of beginning of unprocessed tile
    for j=1,#col_str do
     if sub(col_str,j,j)==tile_delimiter then
      --add 0 to cast str to num
      add(col,sub(col_str,tile_i,j-1)+0)
      tile_i=j+1
     end
    end
   end
   --add exploded column to table of columns
   add(tiles,col)
   col_i=i+1
  end
 end
 return tiles
end

-->8
--data

--chunk template
--[[
chunk={
 tiles={},   --sequence of columns, listed right to left. within a sequence, tiles are listed from top to bottom. i.e. the first tile of the first sequence is the upper right one
 flippable={ --h and v are true if this chunk can be horizontally and vertically flipped during chunk loading, respectively. if not specified, defaults to true
  h=true,
  v=false
 },
 item_mods={ --optional. increases or decreases each item's individual spawn chance and the spawn chance of items in general for this chunk
  item_chance=1,
  batt=1,
  heart=-1
 },
 req_flips=1 --optional num of required grav flips for this chunk
}
]]

meeting_place={
 -- name="meeting place",
 bg_sprite=189,
 ui_bg_c=14,
 add_tile=end_add_tile,
 land=normal_land,
 sprint=normal_sprint
}

--final trial at the end of the fire level
trial={
 -- name="trial",
 --copy fire level's values by hand to save tokens
 bg_sprite=168,
 ui_bg_c=8,
 add_tile=fire_add_tile,
 land=normal_land,
 sprint=fire_sprint,
 next_level=meeting_place,
 levelw=1200 --150 tiles
}
trial.chunks={
 {tiles=
[[
@
@
@
@
11|30|30|00|00|00|00|00|00|30|30|10|
11|30|30|00|00|00|00|00|00|30|30|10|
11|30|30|00|00|00|00|00|00|30|30|10|
11|30|30|00|00|00|00|00|00|30|30|10|
11|30|30|00|00|00|00|00|00|30|30|10|
11|30|30|00|00|00|00|00|00|30|30|10|
11|30|30|00|00|20|20|00|00|30|30|10|
11|30|30|00|00|20|20|00|00|30|30|10|
11|30|30|00|00|00|00|00|00|30|30|10|
11|30|30|00|00|00|00|00|00|30|30|10|
11|30|30|00|00|00|00|00|00|30|30|10|
11|30|30|00|00|00|00|00|00|30|30|10|
11|30|30|00|00|00|00|00|00|30|30|10|
11|30|30|00|00|00|00|00|00|30|30|10|
11|00|00|20|20|20|20|20|20|00|00|10|
@
]],
  flippable={
  h=true,
  v=false
  },
  item_mods={
   item_chance=1,
   batt=1,
   heart=-1
  }
 },
 {tiles=
[[
@
@
11|00|00|00|00|00|00|30|30|00|00|10|
11|00|00|00|00|30|30|00|00|00|00|10|
11|00|00|30|30|00|00|00|00|00|00|10|
11|30|30|00|00|00|00|00|00|00|00|10|
@
@
11|00|00|00|00|30|30|00|00|00|00|10|
11|00|00|00|00|00|00|30|30|00|00|10|
11|00|00|00|00|00|00|00|00|30|30|10|
@
@
@
11|00|00|00|00|00|00|30|30|00|00|10|
11|00|00|00|00|30|30|00|00|00|00|10|
11|00|00|30|30|00|00|00|00|00|00|10|
11|30|30|00|00|00|00|00|00|00|00|10|
@
11|00|20|20|00|00|00|00|00|00|00|10|
11|00|20|20|00|30|30|00|00|00|00|10|
11|00|00|00|00|00|00|30|30|00|00|10|
11|00|00|00|00|00|00|00|00|30|30|10|
@
@
]],
  flippable={
  h=true,
  v=false
  },
  item_mods={
   item_chance=1,
   batt=1,
   heart=-1
  }
 },
 {tiles=
[[
@
@
11|00|00|30|00|00|00|00|00|30|00|10|
11|00|00|30|00|00|00|00|30|00|00|10|
11|00|00|30|00|00|00|30|00|00|00|10|
11|00|00|30|00|00|30|00|00|00|00|10|
11|00|00|30|00|30|00|00|00|00|00|10|
11|00|00|00|30|00|00|00|00|30|30|10|
11|00|00|00|00|30|00|00|00|00|00|10|
11|30|00|00|00|00|30|00|00|00|00|10|
11|00|00|00|00|30|00|30|00|00|00|10|
11|00|00|00|30|00|00|00|30|00|00|10|
11|00|00|30|00|00|00|00|00|30|00|10|
11|00|00|00|30|00|00|00|30|00|00|10|
11|00|00|00|00|30|00|30|00|00|00|10|
11|30|00|00|00|00|30|00|00|00|00|10|
11|00|00|00|00|30|00|00|00|00|00|10|
11|00|00|00|30|00|00|00|00|00|30|10|
11|00|00|30|00|30|00|00|00|00|00|10|
11|00|00|30|00|00|30|00|00|00|00|10|
11|00|00|30|00|00|00|30|00|00|00|10|
11|00|00|30|00|00|00|00|30|00|00|10|
11|00|00|30|00|00|00|00|00|30|00|10|
@
@
]],
  flippable={
  h=true,
  v=false
  }
 },
 {tiles=
[[
@
@
11|00|00|00|00|00|00|00|30|00|00|10|
11|00|00|00|00|00|00|00|30|00|00|10|
11|30|30|30|30|00|00|00|30|00|00|10|
11|30|30|30|30|00|00|00|30|00|00|10|
11|00|00|00|00|00|00|00|30|00|00|10|
11|00|00|00|00|00|00|00|30|00|00|10|
11|00|00|00|00|00|00|00|30|00|00|10|
11|00|00|00|00|00|00|30|00|00|00|10|
11|00|00|00|00|00|30|00|00|00|00|10|
11|00|00|00|00|00|00|30|00|00|00|10|
11|00|30|30|00|00|00|00|30|00|00|10|
11|30|30|30|00|00|00|00|30|00|00|10|
11|30|30|30|00|00|00|00|30|00|00|10|
11|00|30|30|00|00|00|00|30|00|00|10|
11|00|00|00|00|00|00|00|30|00|00|10|
11|00|00|00|00|00|00|00|30|00|00|10|
@
]],
  flippable={
  h=true,
  v=false
  }
 },
 {tiles=
[[
@
@
@
11|30|30|30|00|00|00|00|00|00|00|10|
11|00|30|30|30|00|00|00|00|00|00|10|
11|00|00|30|30|30|00|00|00|00|00|10|
11|00|00|00|30|00|00|00|00|00|00|10|
11|00|00|00|00|00|00|00|30|00|00|10|
11|00|00|00|00|00|00|30|30|30|00|10|
11|00|00|00|00|00|00|00|30|30|30|10|
11|00|00|00|00|00|00|30|30|30|00|10|
11|00|00|00|00|00|00|00|30|00|00|10|
11|00|00|00|30|00|00|00|00|00|00|10|
11|00|00|30|30|30|00|00|00|00|00|10|
11|00|30|30|30|00|00|00|00|00|00|10|
11|30|30|30|00|00|00|00|00|00|00|10|
11|00|30|30|30|00|00|00|00|00|00|10|
11|00|00|30|30|30|00|00|00|00|00|10|
11|00|00|00|30|00|20|00|00|00|00|10|
11|00|00|00|00|00|20|00|30|00|00|10|
11|00|00|00|00|00|00|30|30|30|00|10|
11|00|00|00|00|00|00|00|30|30|30|10|
@
@
@
]],
  flippable={
  h=true,
  v=false
  },
  item_mods={
   item_chance=1,
   batt=1,
   heart=-1
  }
 },


}


fire_level={
 -- name="fire",
 bg_sprite=168,
 ui_bg_c=8,
 music=37,
 add_tile=fire_add_tile,
 land=normal_land,
 sprint=fire_sprint,
 next_level=trial
}
fire_level.chunks={
 {tiles=
[[
_
_
11|30|30|20|20|20|20|20|20|20|20|10|
11|30|30|20|20|20|20|20|20|30|30|10|
11|30|30|20|20|20|20|20|20|30|30|10|
11|20|20|20|20|20|20|20|20|30|30|10|
_
_
]]
 },
 {tiles=
[[
_
_
11|20|20|20|20|20|20|20|20|00|00|10|
11|20|20|20|20|20|20|20|30|30|30|10|
11|20|20|30|20|20|20|30|30|30|30|10|
11|20|20|20|20|20|20|20|30|30|30|10|
11|20|20|20|20|20|20|20|20|00|00|10|
_
_
]]
 },
 {tiles=
[[
_
_
11|00|00|20|20|20|20|20|20|00|00|10|
11|00|30|20|20|20|20|20|30|30|30|10|
11|30|30|30|20|20|20|20|30|30|30|10|
11|00|30|20|20|20|20|20|30|30|30|10|
11|00|00|20|20|20|20|20|20|00|00|10|
_
_
]]
 },
 {tiles=
[[
_
_
11|20|20|20|20|20|20|20|20|00|00|10|
11|00|20|20|20|20|20|20|30|30|00|10|
11|00|00|20|20|20|20|30|30|30|30|10|
11|00|30|20|20|20|20|30|30|30|30|10|
11|30|30|30|20|20|20|20|30|30|00|10|
11|30|30|30|30|20|20|20|20|00|00|10|
11|30|30|30|20|20|20|20|20|20|20|10|
11|00|30|20|20|20|20|20|20|20|20|10|
11|00|00|20|20|20|20|20|20|20|20|10|
11|00|20|20|20|20|20|20|20|20|20|10|
_
]]
 },
 {tiles=
[[
_
11|20|20|20|20|20|20|20|20|20|20|31|
_
]]
 },
 {tiles=
[[
_
_
11|20|20|20|20|20|20|20|30|30|30|10|
_
_
]]
 },
 {tiles=
[[
_
_
11|20|20|20|20|20|20|20|20|20|00|31|
11|20|20|20|20|20|20|20|20|30|30|10|
_
_
]]
 },
 {tiles=
[[
_
_
11|30|30|20|20|20|20|20|20|20|20|10|
11|30|30|20|20|20|20|20|20|20|20|10|
_
11|20|20|20|20|20|20|20|20|20|20|31|
11|20|20|20|20|20|20|20|30|30|20|10|
11|20|20|20|20|20|20|20|30|30|20|10|
_
_
]]
 },
{tiles=
[[
_
_
11|20|30|20|20|20|20|20|20|30|20|10|
11|20|30|20|20|20|20|20|20|30|20|10|
11|20|30|20|20|20|20|20|20|30|20|10|
11|20|30|20|20|20|20|20|20|30|20|31|
11|20|30|20|20|20|20|20|20|30|20|10|
11|20|30|20|20|20|20|20|20|30|20|10|
11|20|30|20|20|20|20|20|20|30|20|10|
11|20|30|20|20|20|20|20|20|30|20|10|
11|20|30|20|20|20|20|20|20|30|20|10|
11|20|30|20|20|20|20|20|20|30|20|10|
11|20|30|20|20|20|20|20|20|30|20|31|
11|20|30|20|20|20|20|20|20|30|20|10|
11|20|30|20|20|20|20|20|20|30|20|10|
11|20|30|20|20|20|20|20|20|30|20|10|
_
_
]]
},
 {tiles=
[[
_
_
11|20|20|30|20|20|20|20|30|20|20|10|
11|20|20|30|20|20|20|20|30|20|20|10|
11|20|20|30|20|20|20|20|30|20|20|10|
11|20|20|30|20|20|20|20|30|20|20|10|
11|20|20|30|20|20|20|20|30|20|20|31|
11|20|20|30|20|20|20|20|30|20|20|10|
11|20|20|30|20|20|20|20|30|20|20|10|
11|20|20|30|20|20|20|20|30|20|20|10|
11|20|20|30|20|20|20|20|30|20|20|10|
11|20|20|30|20|20|20|20|30|20|20|31|
11|20|20|30|20|20|20|20|30|20|20|10|
11|20|20|30|20|20|20|20|30|20|20|10|
11|20|20|30|20|20|20|20|30|20|20|10|
11|20|20|30|20|20|20|20|30|20|20|10|
11|20|20|30|20|20|20|20|30|20|20|31|
11|20|20|30|20|20|20|20|30|20|20|10|
11|20|20|30|20|20|20|20|30|20|20|10|
11|20|20|30|20|20|20|20|30|20|20|10|
11|20|20|30|20|20|20|20|30|20|20|10|
_
_
]],
 req_flips=4
 },
 {tiles=
[[
_
_
_
11|20|20|20|20|20|20|20|20|20|20|31|
_
_
_
11|20|20|20|20|20|20|20|20|20|20|31|
_
_
_
]]
 },
 {tiles=
[[
_
_
11|30|20|20|20|20|20|20|20|20|30|10|
11|30|20|20|20|20|20|20|20|20|30|10|
11|30|20|20|20|20|20|20|20|20|30|10|
11|30|20|20|20|20|20|20|20|20|30|10|
_
_
]]
 },
 {tiles=
[[
_
_
11|30|20|20|20|20|20|20|20|20|30|10|
11|30|20|20|20|20|20|20|20|20|30|10|
11|30|20|20|20|20|20|20|20|20|30|10|
_
_
11|30|20|20|20|20|20|20|20|20|30|10|
11|30|20|20|20|20|20|20|20|20|30|10|
11|30|20|20|20|20|20|20|20|20|30|10|
_
_
]]
 },
 {tiles=
[[
_
_
11|20|20|20|20|30|30|30|20|20|20|10|
11|20|20|20|20|30|30|30|20|20|20|10|
11|20|20|20|20|30|30|30|20|20|20|10|
_
_
11|30|20|20|20|20|20|20|20|20|30|10|
11|30|20|20|20|20|20|20|20|20|30|10|
11|30|20|20|20|20|20|20|20|20|30|10|
11|30|20|20|20|20|20|20|20|20|30|10|
_
_
]]
 },
 {tiles=
[[
_
_
11|00|30|20|20|20|20|20|30|00|20|10|
11|30|00|20|20|20|20|30|00|30|20|10|
11|00|30|20|20|20|20|20|30|00|20|10|
_
_
]]
 },
 {tiles=
[[
_
_
_
11|30|20|20|20|20|20|20|20|20|30|10|
11|30|20|20|20|20|20|20|20|20|30|10|
11|30|20|20|20|20|20|20|20|20|30|10|
11|30|20|20|20|20|20|20|20|20|30|10|
11|30|20|20|20|20|20|20|20|20|30|10|
11|30|20|20|20|20|20|20|20|20|30|10|
11|30|20|20|20|20|20|20|20|20|30|10|
_
_
_
]]
 },
 {tiles=
[[
_
_
_
11|30|20|20|20|20|20|20|20|20|30|10|
11|30|20|20|20|20|20|20|20|20|30|10|
11|30|20|20|20|20|20|20|20|20|30|10|
11|30|20|20|20|20|20|20|20|20|30|10|
11|30|20|20|20|20|20|20|20|20|30|10|
11|30|20|20|20|20|20|20|20|20|30|10|
11|30|20|20|20|20|20|20|20|20|30|10|
11|30|20|20|20|20|20|20|20|20|30|10|
11|30|20|20|20|20|20|20|20|20|30|10|
11|30|20|20|20|20|20|20|20|20|30|10|
_
_
_
]],
  req_flips=1
 },


}


ice_level={
 -- name="ice",
 bg_sprite=152,
 ui_bg_c=12,
 music=26,
 add_tile=ice_add_tile,
 land=ice_land,
 sprint=normal_sprint,
 next_level=fire_level,
 levelw=2464 --default-12 tiles
}
ice_level.chunks={
 {tiles=
[[
_
11|20|20|20|20|20|20|20|20|20|30|10|
_
_
11|31|20|20|20|20|20|20|20|20|20|10|
_
_
_
]],
  flippable={
   h=false,
   v=true
  }
 },
 {tiles=
[[
_
_
_
11|31|20|20|20|20|20|20|20|20|30|10|
_
_
_
]],
  flippable={
   h=false,
   v=true
  }
 },
 {tiles=
[[
_
_
_
11|31|20|20|20|20|20|20|20|20|20|10|
11|20|20|20|20|20|20|20|20|20|30|10|
_
_
]],
  flippable={
   h=false,
   v=true
  }
 },
 {tiles=
[[
_
_
_
11|31|20|20|20|20|20|20|20|20|20|10|
_
_
_
]],
  flippable={
   h=false,
   v=true
  }
 },
 {tiles=
[[
_
_
_
11|31|20|20|20|20|20|20|20|20|20|10|
_
_
11|20|20|20|20|20|20|20|20|20|30|10|
_
_
11|31|20|20|20|20|20|20|20|20|20|10|
_
_
_
]],
  flippable={
   h=false,
   v=true
  }
 },
 {tiles=
[[
_
_
_
11|20|20|20|20|20|20|20|20|20|30|10|
11|31|20|20|20|20|20|20|20|20|30|10|
11|20|20|20|20|20|20|20|20|20|30|10|
_
_
_
]],
  flippable={
   h=false,
   v=true
  }
 },
 {tiles=
[[
_
_
_
11|20|20|20|20|20|20|20|20|20|30|10|
11|20|20|20|20|20|20|20|20|20|30|10|
11|20|20|20|20|20|20|20|20|20|30|10|
_
_
_
]],
  flippable={
   h=false,
   v=true
  }
 },
 {tiles=
[[
_
_
_
11|31|20|20|20|20|20|20|20|20|20|10|
11|31|20|20|20|20|20|20|20|20|20|10|
11|31|20|20|20|20|20|20|20|20|20|10|
_
_
_
]],
  flippable={
   h=false,
   v=true
  }
 },
 {tiles=
[[
_
_
11|31|20|20|20|20|20|20|20|20|20|10|
_
11|31|20|20|20|20|20|20|20|20|20|10|
_
11|31|20|20|20|20|20|20|20|20|20|10|
_
_
]],
  flippable={
   h=false,
   v=true
  }
 },
 {tiles=
[[
_
_
11|20|20|20|20|20|20|20|20|20|30|10|
11|31|20|20|20|20|20|20|20|20|20|10|
11|20|20|20|20|20|20|20|20|20|30|10|
11|31|20|20|20|20|20|20|20|20|20|10|
11|20|20|20|20|20|20|20|20|20|30|10|
_
_
]],
  flippable={
   h=false,
   v=true
  }
 },


}


cave_level={
 -- name="cave",
 bg_sprite=184,
 ui_bg_c=5,
 music=13,
 add_tile=cave_add_tile,
 land=normal_land,
 sprint=normal_sprint,
 next_level=ice_level
}
cave_level.chunks={
 {tiles=
[[
_
11|30|20|20|20|20|20|20|20|20|30|10|
_
]]
 },
 {tiles=
[[
_
11|00|20|20|20|20|20|20|20|20|20|10|
11|00|00|20|20|20|20|20|20|20|00|10|
11|35|00|20|20|20|20|20|20|00|00|10|
11|00|20|20|20|20|20|20|20|35|00|10|
11|20|20|20|20|20|20|20|20|20|00|10|
_
]]
 },
 {tiles=
[[
_
_
11|20|20|20|20|20|20|20|20|00|00|10|
11|20|20|20|20|20|20|00|00|00|30|10|
11|20|20|20|20|20|20|35|00|00|00|10|
11|20|20|20|20|20|20|20|20|00|00|10|
11|20|20|20|20|20|20|20|20|00|00|10|
]]
 },
 {tiles=
[[
_
_
_
11|30|20|20|20|00|00|20|20|20|30|10|
11|30|20|20|20|35|00|20|20|20|30|10|
_
_
_
]]
 },
 {tiles=
[[
_
11|20|20|20|20|20|20|20|20|00|00|10|
11|20|20|20|20|20|20|20|00|00|00|10|
11|20|20|00|00|20|20|20|30|00|30|10|
11|20|20|35|00|20|20|20|00|30|00|10|
11|20|20|20|20|20|20|20|00|00|00|10|
11|20|20|20|20|20|20|20|20|00|00|10|
_
]]
 },
 {tiles=
[[
_
11|20|20|20|20|20|20|00|00|00|00|10|
11|20|20|20|20|20|20|00|00|00|00|10|
11|20|20|20|20|20|30|00|00|30|00|10|
11|30|20|20|20|00|00|00|00|00|00|10|
11|20|20|20|20|30|00|00|30|00|30|10|
11|20|20|20|20|20|00|00|00|00|00|10|
11|20|20|20|20|20|20|00|00|00|00|10|
_
]],
  req_flips=1
 },
 {tiles=
[[
_
11|20|20|20|20|20|20|20|00|00|00|10|
11|00|00|20|20|20|00|00|00|00|00|10|
11|35|00|20|20|20|30|00|00|00|00|10|
11|00|00|20|20|20|00|00|30|00|30|10|
11|20|20|20|20|20|20|00|00|00|00|10|
11|20|20|20|20|20|20|20|00|00|00|10|
_
]],
  req_flips=1
 },
 {tiles=
[[
_
_
11|20|20|20|20|20|20|20|20|30|00|10|
11|20|30|20|20|20|20|20|20|00|00|10|
11|20|20|30|20|20|20|20|20|30|00|10|
11|20|20|20|20|20|20|20|20|20|30|10|
_
_
]]
 },
 {tiles=
[[
_
_
_
11|20|00|00|20|20|20|20|20|00|00|10|
11|20|35|00|20|00|00|20|20|35|00|10|
11|20|20|20|20|35|00|20|20|20|20|10|
_
_
_
]]
 },
 {tiles=
[[
_
_
_
11|00|00|20|20|20|30|20|20|20|20|10|
11|35|00|20|20|00|20|20|20|00|00|10|
11|20|20|20|20|30|00|20|20|35|00|10|
_
_
_
_
]]
 },
 {tiles=
[[
_
11|00|00|00|20|20|20|20|20|00|00|10|
11|00|30|00|20|20|20|20|00|00|00|10|
11|00|00|00|20|20|20|30|00|00|30|10|
11|30|00|30|20|20|20|20|30|00|00|10|
11|00|00|00|20|20|20|20|20|00|00|10|
_
]]
 },


}


forest_level={
 -- name="forest",
 bg_sprite=136,
 ui_bg_c=11,
 music=0,
 add_tile=forest_add_tile,
 land=normal_land,
 sprint=normal_sprint,
 next_level=cave_level,
 levelw=2080 --default-60 tiles
}
forest_level.chunks={
 {tiles=
[[
_
_
]]
 },
 {tiles=
[[
_
_
_
]]
 },
 {tiles=
[[
_
11|20|20|20|20|20|20|20|20|20|30|10|
_
]]
 },
 {tiles=
[[
_
11|30|20|20|20|20|20|20|20|20|30|10|
_
]]
 },
 {tiles=
[[
11|00|20|20|20|20|20|20|20|20|20|10|
11|30|30|20|20|20|20|20|20|20|00|10|
11|00|20|20|20|20|20|20|20|30|30|10|
11|20|20|20|20|20|20|20|20|20|00|10|
]]
 },
 {tiles=
[[
_
11|30|20|20|20|20|20|20|20|20|30|10|
11|30|20|20|20|20|20|20|20|20|30|10|
_
]]
 },
 {tiles=
[[
11|20|20|20|20|20|20|20|20|20|00|10|
11|20|20|20|20|20|20|20|20|30|30|10|
11|20|20|20|20|20|20|20|20|30|30|10|
11|20|20|20|20|20|20|20|20|20|00|10|
]]
 },
 {tiles=
[[
11|20|20|20|20|20|20|20|20|20|00|10|
11|30|20|20|20|20|20|20|20|30|30|10|
11|30|20|20|20|20|20|20|20|30|30|10|
11|20|20|20|20|20|20|20|20|20|00|10|
]]
 },
 {tiles=
[[
_
11|00|20|20|20|20|20|20|20|20|00|10|
11|30|30|20|20|20|20|20|20|30|30|10|
11|30|30|20|20|20|20|20|20|30|30|10|
11|00|20|20|20|20|20|20|20|20|00|10|
_
]]
 },
 {tiles=
[[
11|20|20|20|20|20|20|20|00|00|00|10|
11|20|20|20|20|20|20|20|30|30|30|10|
11|20|20|20|20|20|20|20|30|30|30|10|
11|20|20|20|20|20|20|20|20|00|00|10|
_
]],
  flippable={
   h=true,
   v=false
  }
 },
 {tiles=
[[
_
11|20|20|20|20|20|20|20|20|20|30|10|
11|30|20|20|20|20|20|20|20|20|30|10|
11|20|20|20|20|20|20|20|20|20|30|10|
_
]]
 },
 {tiles=
[[
_
11|20|20|20|20|20|20|20|20|00|00|10|
11|20|20|20|20|20|20|20|30|30|30|10|
11|20|20|20|20|20|20|20|20|00|00|10|
_
]]
 },
 {tiles=
[[
_
11|20|20|20|20|20|20|20|20|20|00|10|
11|00|20|20|20|20|20|20|20|00|30|10|
11|30|30|20|20|20|20|20|00|30|30|10|
11|00|20|20|20|20|20|20|30|30|30|10|
11|20|20|20|20|20|20|20|20|00|00|10|
_
]],
  flippable={
   h=true,
   v=false
  }
 },
 {tiles=
[[
11|20|20|20|20|20|20|20|20|20|00|10|
11|20|20|20|20|20|20|20|20|00|30|10|
11|30|20|20|20|20|20|20|00|30|30|10|
11|30|20|20|20|20|20|20|30|30|30|10|
11|20|20|20|20|20|20|20|20|00|00|10|
_
]],
  flippable={
   h=true,
   v=false
  }
 },
 {tiles=
[[
_
_
11|30|20|20|20|20|20|20|00|00|00|10|
11|30|20|20|20|20|20|20|30|30|30|10|
11|30|20|20|20|20|20|20|00|30|30|10|
11|30|20|20|20|20|20|20|20|00|30|10|
11|20|20|20|20|20|20|20|20|20|00|10|
]]
 },
 {tiles=
[[
_
11|00|20|20|20|20|20|20|20|20|20|10|
11|30|30|20|20|20|20|20|20|20|30|10|
11|30|30|20|20|20|20|20|20|20|30|10|
11|00|20|20|20|20|20|20|20|20|30|10|
11|20|20|20|20|20|20|20|20|20|30|10|
_
_
]]
 },
 {tiles=
[[
_
11|20|20|20|20|20|20|20|00|00|00|10|
11|20|20|20|20|20|20|30|30|30|30|10|
11|20|20|20|20|20|20|20|00|00|00|10|
_
]],
  flippable={
   h=true,
   v=false
  }
 },
 {tiles=
[[
_
11|20|20|20|20|20|20|00|00|00|00|10|
11|20|20|20|20|20|30|30|30|30|30|10|
11|20|20|20|20|20|20|00|00|00|00|10|
_
]],
  req_flips=1
 },


}

meeting_place.next_level=fire_level

function load_data()
 foreach({forest_level.chunks,cave_level.chunks,ice_level.chunks,fire_level.chunks,trial.chunks},function(chunks)
  for _,v in pairs(chunks) do
   v.tiles=explode_chunk_tiles(trim(v.tiles))
  end
 end)
end

load_data()

__gfx__
0000000066666666666666666666660000000000066666666666666666666666bbbbbbbbbbbb311155555555555555cccccccccccc555555555f555ff555f555
0000000066666666666666660000000000000000000000006666666666666666bbbbbbbbbbbb311155555d55555555cccccc77ccccc1955595555f5555f55559
0070070066666660000000000000000099000990000000000000000066666666bbbbbb8bb8bb311159555555555555ccccc77ccccccc5585855f555ff555f555
0007700066666660000000009999990099000990099999900000000066666666bbb8bbbbbbbb31115555555555555cccccccc77ccccc559555555f5555f55555
0007700066666660099999909999990099000990099999909999990066666666bbbbbbbbbbbb3111551555555111cccccccc77cccccc5555555f555ff555f555
0070070066666660099999909900990099000990000990009999990066666666bbbbbbbbb33311115511555511cccccccccccccccccc155589555f5555f55558
00000000000000000990099099009900990009900009900000990000000000063bbbbb33344dd111111111111dcdc5cccccccccccccc5155555f555ff555f595
000000000000000009900990999999009900099000099000009900000000000603333300444dddd111111111ddddc555ccccccccccc5222555555f5555f55555
0000000000009999099990009999990099000990000990000099000990099006444444444444dddddddddddddddd555555555555555522222222222ee2222222
000000000000999909999000990099009900099000099000009900099009900644444444444dddddddddddddddd55555555555555552222222222e2222e22222
00000000009900000990099099009900009990000009900000990009900990064444444444dddddddddddddddd55555555555555552222222222222ee2222222
00000000009900000990099099009900009990000999999000990009900990064444444444dddddddddddddddd555555555555555522222222222e2222e22222
000000000099000009900990990099000099900009999990009900099999900644444444444dddddddddddddddd5555555555555555222222222222ee2222222
000000000099000009900990000000000000000000000000009900099999900644444444444dddddddddddddddd55555555555555552222222222e2222e22222
0000000000990099000000000000000000000000000000000000000000099006444444444444dddddddddddddddd555555555555555522222222222ee2222222
00000000009900990000009999990009990009990009999990000000000990064444444444444dddddddddddddddd555555555555555522222222e2222e22222
0000000000999999000000999999000999000999000999999000000999999006bbbbbbbb44444ddd01111001ddddd555cccccccc555552220000000000000000
0000000000999999000000999999000999000999000999999000000999999006bbbbbbbb44444ddd15515111ddddd555cccc77cc555552220000000000000000
0000000000000000000999000999000999000999000999000999000000000006bbbbbbbb444444dd55155551dddddd55ccc77ccc555555220000000000000000
00000000000000000009990009990009990009990009990009990000000000063bbbb333444444dd55555155dddddd55ccccc77c555555220000000000000000
000000006666666600099900099900099900099900099900099900066666666643bb344444444ddd15551151ddddd555cccc77cc555552220000000000000000
00000000666666660009999990000009990009990009990009990006666666664433444444444ddd15155555ddddd555cccccccc555552220000000000000000
0000000066666666000999999000000999000999000999000999000666666666444444444444dddd55155551dddd5555cccccccc555522220000000000000000
0000000066666666000999999000000999000999000999000999000666666666444444444444dddd55511515dddd5555cccccccc555522220000000000000000
000000006666666600099900099900099900099900099900099900066666666600000000bbbb111100000000ddc1cccc00000000ccccc5555555555ff5555555
000000006666666600099900099900099900099900099900099900066666666600000000bbbbb111000000001115cc7c00000000cccc555589555f5555f55555
000000006666666600099900099900099900099900099900099900066666666600000000bbbbbb15000000005555c7cc00000000cccc5955555f555ff555f555
0000000066666666000999000999000999999999000999000999000666666666000000003bbbb35500000000515ccc7c00000000cccc155555555f5555f55555
0000000066666666000999000999000999999999000999000999000666666666000000004333355500000000555cc7cc00000000cccc5555555f555ff555f595
0000000066666666000999000999000999999999000999000999000666666666000000004444451500000000515ccccc00000000cccc559859555f5555f55558
00000000666666660000000000000000000000000000000000000006666666660000000044444555000000005555cccc00000000ccc15555855f555ff555f555
000000006666666600000000000000000000000000000000000000066666666600000000444445550000000055155ccc00000000cc55155555555f5555f55555
00000000000000000000077000000000000000000000770000077000000000006500000006600000066600000000000000000660000000000000000000066000
00000000000007700000077000000770000000000000770007077000000000005500000066650000666650000000066000000660000006600000000006066000
00000000000007700000770000000770000000000007700000777070000000000000000066550000666650000000066000006600000006600000000000666060
00000000000077000007770000007700000000000007700000077700000000000000000005500000666550000000660000066600000066000000000000066600
00000000000777000007700000077700000000000007100000077000000000000000000000000000055500000006660000066000000666000000000000066000
00000000010170000007700007071000000000000070010000077000000000000000000000000000000000000d0d6000000660000606d0000000000000066000
000000000010070000017000007001000000000007001000007010000000000000000000000000000000000000d00600000d600000600d00000000000060d000
00000000000007000010700000000100000000000000000007010000000000000000000000000000000000000000060000d0600000000d0000000000060d0000
00000000007700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000007700700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000777000770700000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000077770000777700077070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000777000077770077777707000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000077700700777700707770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000001070000010007000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000001000000010000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000007700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000007700000007700000007700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000007707000777777000707700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000077770000007700000077770000000007707010000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000707700000007710000007707000000007777010700000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000007711000007001000077700000000000077777000070001000700000000000000000000000000000000000000000000000000000000000000000000
00000000007001000007000000070100000000000700770077777710777777110000000000000000000000000000000000000000000000000000000000000000
00000000007000000000000000000100000000000000000077777777777777770000000000000000000000000000000000000000000000000000000000000000
00000000000077000000000000007700000007700000000000000000000000000000000000700700000000000000660000000000000066000000066000000000
00000000000077000000770000007700000007700000107000000100000000000880088009999990000000000000660000006600000066000000066000000000
00000000000770000000770000077000000077000000017000001770000001008888878809999990000008080006600000006600000660000006000000000000
00000000000770000007700000077770000077700007077000007700000017708888887807777660000008880006600000066000000666600000006000000000
00000000000770000007700000077000000770000007777000077000000777008888888807777660000000800006600000066000000660000006600000000000
00000000000710000007700000071000000710000777770000077000007770000888888007777660000000000006d000000660000006d0000006d00000000000
00000000000710000007100000071000000710000770070000077770007777000088880007777660000000000006d0000006d0000006d0000006d00000000000
00000000000711000007110000071100000710000000000000000770000777700008800007777660000000000006dd000006dd000006dd000006d00000000000
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb8bbbbbbbbbbbbbbbbbbb4444444400022000000222200002200000000000200000020000007007000000
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb8bbb4444444400222000000220000222200000000000200000020700007777000070
bbbbbbbbbb3333bbbbbbbbbbb3333bbbbbbbbb8bbbbbbb8bbbb8bbbbbbbbbbbb4444444422222000022220000002200000000000020220200070777007770700
3bbbb3333344443333bb3333344443b3bbb8bbbbb8bbbbbbbbbbbbbbbbbbbbbb4444444400022220000022000002222000000000002222000007007007007000
43bb3444444444444433344444444334bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb4444444400222000000022220002200000000000222222220070707777070700
44334444444444444443444444444444bbbbbbbb3bbbbbb333bbbbb3bbbb333b4444444422220000000022000222000000000000002222000070077007700700
444444444444444444444444444444443bbbbb3303bbb330003bbb30b33300034444444400222220022220000002000000000000020220207777777777777777
44444444444444444444444444444444033333000033300000033300300000034444444400022000000220000002222000000000200000020700707777070070
cccccccc000000000000000000000000cccccccc0000000000000000000000005555555500000000000c70000000000000000000200200220700707777070070
cccc77cc000000000000000000000000cccc77cc0077770000000000000700005555555500070000000c70000000000000000000020202007777777777777777
ccc77ccc000000000000000000000000ccc77ccc0770000000070000000700005555555500777000000c70000000000000000000002220000070077007700700
ccccc77c000000000000000000000000ccccc77c070000000007000000070000555555550707070000ccc7000000000000000000022222000070707777070700
cccc77cc000000000000000000000000cccc77cc077770000007000000070000555555557777777000ccc7000000000000000000022222000007007007007000
cccccccc000000000000000000000000cccccccc077000000007000000077700555555550707070000ccc7000000000000000000002220000070777007770700
cccccccc000000000000000000000000cccccccc00777000000000000000000055555555007770000ccccc700000000000000000020202000700007777000070
cccccccc000000000000000000000000cccccccc00000000000000000000000055555555000700000ccccc700000000000000000200200220000007007000000
595555555555555555595555555555555155555555555555555155555555555522222222000000005558555558555855000000000008000008000800008aa800
58555555555555955555955558555555515555555555551555551555515555552222222200000000585555955555555500880080008880000000880008a77a80
8555895558555858855555555585585515551155515551511555555555155155222222220000000000000000000000000888800000888800000888808aa99aa8
5598555555955555595555555555559555115555551555555155555555555515222222220000000000000000000000008889880008898880008889808a9999a8
55555558555955555555855555555955555555515551555555551555555551552222222200000000888888888888888888999800088998800889998088988988
55555985855555555555585555955555555551151555555555555155551555552222222200000000888888888888888808aa9880089aa9800899a98008888880
598555555555955559555559585555955115555555551555515555515155555122222222000000008888888888888888089aa980089aa980089aa98000888800
585555555558555585555585555558555155555555515555155555155555551522222222000000008888888888888888009aa900009aa900009aaa0000088000
0011110011100011110011111111110055555555555565555555555555555555dddddddd555555555555555500000000ffffffffeeeeeeee0000000000000000
1151511155111151151151511155151155555d55555555555555555555555595dddddddd55555d555555555500000000ffffffffeeeeeeee0000000007000070
5155555155155555511551555515515559555555555555555555555555555555dddddddd5b55555555555c5500000000ffffffffeeeeeeee0000000000700700
5555555555515515555555155155d55555555555555515555555155555555555dddddddd555555555115555500000000ffffffffeeeeeeee0000000000077000
5555d5515d5555555555555555555555551555555d5511555551155555511555dddddddd555511555115555500000000ffffffffeeeeeeee0000000000077000
d51555555555555555d55d5555d5555555115555555511155511111555511555dddddddd551111555115555500000000ffffffffeeeeeeee0000000000700700
5555555555515555555555555555595511111111111111111111111111111111dddddddd111111111111111100000000ffffffffeeeeeeee0000000007000070
5555515555555d55d55555555555555511111111111111111111111111111111dddddddd111111111111111100000000ffffffffeeeeeeee0000000000000000
77770077777777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
7770a907777777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
770aa907777777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
70aa9077777777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0aa90000777777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0aaaaaa9077777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0aaaaaa9077777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
70000aa9077777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
7770aa90777777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
770aa907777777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
770a9077777777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
77700777777777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
77777777777777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
77777777777777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
77777777777777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
77777777777777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000

__gff__
0000000000000000010101010101010100000000000000000000000000000000000000000000000001000100010000000000000000000000000100010001010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002020000000000000
0101010101010101000202020002080801000000010000000002020000020808010101010101010100010000000000000101010101010101000101000100000200000000000000000000010000000000000000000000000101000000000000000202020000010101010001020202020202020000000202020202020000000000
__map__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
8586878586848785868486848785848685878684868584878584858786878587000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
8183828081838280838182838081808280838182808182808182838081828183000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
011000002903028030260302903028030260302903028030260302903028030260302b03029030280302b03029030280302b03029030280302b03029030280302d0302d0302d0302d0302d0302d0302d0302d030
010200002c6402864025640226401f6401c6401864014640106400c64009640066400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010200002b250041502725009150242501015023250141501f2501c150182501d10021200241001e200291001c2002d1001b2003210019200351001820038100172003a100162003b100152003c1003e20024000
01020000116501115012650131501365014150156501615018650191501b6501d1501f6502115024650261501b4001c1001d1001e1001f1002110022100241002610027100281002a1002c1002d1002f10031100
00020000284502a4502d4503045032450344503745039450000000000020400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010c00003e625000000000000000000000000000000000003c6303c6203c6103c61000000000000000000000000000000000000000003e6250000000000000003c6303c6203c6103c61000000000000000000000
010c00000c3540c3510c3510c355103541035110351103550e3540e3510e3510e3550c3540c3510c3510c3550e3540e3510e3510e355003000030000300003000030000300003000030000300003000030000300
010c00000c3540c3510c3510c355103541035110351103550e3540e3510e3510e3550c3540c3510c3510c355093540935109351093550030000300003000030000000000000e3000e3000e3000e3000e3000e300
010c00000c3540c3510c3510c355103541035110351103550e3540e3510e3510e355000000000000000000000e3540e3510e3510e355000000000000000000000000000000000000000000000000000000000000
010c000009354093510935109355103541035110351103550e3540e3510e3510e3550c3540c3510c3510c355093540935109351093550030000300003000030000000000000e3000e3000e3000e3000e3000e300
010c000009354093510935109355103541035110351103550e3540e3510e3510e355000000000000000000000e3540e3510e3510e355000000000000000000000000000000000000000000000000000000000000
010c000009354093510935109355103541035110351103550e3540e3510e3510e35500000000000000000000093540935109351093550030000300003000030000000000000e3000e3000e3000e3000e3000e300
011000003702518000370051800037005180003700518000370251800037005180003700518000370051800037025180003700518000370051800037005180003702518000370051800037005180003700518000
011000003302530000330003000033000300003300030000330253000033000300003300030000330003000033015300003300030000330003000033000300003302530000330003000033000300003300030000
011000003304514000330001400033000140003300014000330351400033000140003300014000330001400033025140003300014000330001400033000140003301514000330001400033000140003300014000
011000003777500000377550000037735000003771500000397750000039755000003b775000003b7550000039775000003975500000397350000039715000003777500000377550000037735000003771500000
01100000357750000035755000003573500000357150000037775000003775500000397750000039755000003b775000003b755000003b745000003b735000003b725000003b725000003b715000003b71500000
011000003377500000337550000033735000003371500000377750000037755000003773500000377150000035775000003575500000357350000035715000003977500000397550000039735000003971500000
0110000039775000003975500000397350000039715000003b775000003b755000003b775000003b755000003d775000003d755000003d745000003d735000003d7253c0003d7253c0003d7153c0003d71500000
011000003b775000003b755000003b775000003b75500000377550000037775000003775500000377550000035755000003577500000357550000035755000003975504000397750400039755040003975504000
011000003777500000377550000037735000003771500000357750000035755000003573500000357150000033775000003375500000337350000033715000003177500000317550000031735000003171500000
011000003b775300003b755300003b745300003b735300003b7253a0003b7153a000300003000030000000003b775000003b755300003b745300003b735300003b7253a0003b7153a00000000000000000000000
011000002f775240002f755240002f745240002f735240002f7252e0002f7152e000240002400024000020002f775020002f755240002f745240002f735240002f7252e0002f7152e00002000020000200002000
011000003177500000317550000031735000003171500000337750000033755000003373500000337150000035775000003575500000357350000035715000003777500000377550600037735060003771500000
010c0000103541035110351103550e3540e3510e3510e3550c3540c3510c3510c3550e3540e3510e3510e3550e3540e3510e3510e355000000000000000000000000000000000000000000000000000000000000
010c0000103541035110351103550e3540e3510e3510e3550c3540c3510c3510c3550000000000000000000009354093510935109355000000000000000000000000000000000000000000000000000000000000
010c0000103741037110321103210e3740e3710e3210e3210c3740c3710c3410c3410c3310c3320c3220c3220e3710e3610e3610e375003000030000300003000030000300003000030000300003000030000000
010c0000103741037110321103210e3740e3710e3210e3210c3740c3710c3410c3410c3310c3320c3220c32209371093610936109375003000030000300003000030000300003000030000300003000030000000
010c000010374103711032110321103741037110321103210c3540c3520c3520c3520c3520c35500000000000e3740e3610e3610e3750030000300003000030000000000000e3000e30000000000000000000000
010c000010354103511035110355103541035110351103550c3540c3510c3510c355133541335113351133550e3540e3510e3510e355000000000000000000000000000000000000000000000000000000000000
010c00000c3540c3510c3510c355000000000000000000000e3740e3710e3710e375000000000000000000000e3540e3510e3510e355003000030000300003000030000300003000030000300003000030000300
010c00000c3540c3510c3510c355000000000000000000000e3740e3710e3710e37500000000000000000000093640936109361093650030000300003000030000000000000e3000e3000e3000e3000e3000e300
010c000010374103711032110321000000000000000000000c3740c3720c3720c3720c3720c37500000000000e3740e3610e3610e3750030000300003000030000000000000e3000e30000000000000000000000
010c000010374103711032110321000000000000000000000c3740c3720c3720c3720c3720c3750000000000093740936109361093750030000300003000030000000000000e3000e30000000000000000000000
010c00000c3540c3510c3510c35500000000000000000000000000000000000000000c3540c3520c3520c3520e3510e3510e3510e355003000030000300003000030000300003000030000300003000000000000
010c00000c3540c3510c3510c3550000000000000000000000000000000000000000133541335213352133520e3510e3510e3510e355003000030000300003000030000300003000030000300003000000000000
010c00001335413351133511335500000000000000000000000000000000000000000c3540c3520c3520c3520e3510e3510e3510e355003000030000300003000030000300003000030000300003000000000000
010c00001335413351133511335500000000000000000000000000000000000000000c3540c3520c3520c35209351093510935109355003000030000300003000030000300003000030000300003000000000000
011000000405004051040510405104051040510405104051040510405104051040510405104051040510405102051020510205102051020510205102041020410203102031020210202102011020150000000000
011000000005000050000500005000050000500005000050000500005000050000500005000050000500005002050020500205002050020500205002050020500205002050020500205002050020500205002050
011000000405004050040500405004050040500405004050040500405004050040500405004050040500405002050020500205002050020500205002050020500205002050020500205002050020500205002050
011000001a7121a7221a7321a7321a7421a7421a7521a7521a7421a7321a7221a7221a7121a7121a7121a71218712187221873218732187421874218752187521874218732187221871218712187121871218712
011000001a7121a7221a7321a7321a7421a7421a7521a7521a7421a7321a7221a7221a7121a7121a7121a71218712187221873218732187421874218752187521874218732187211871118711187150000000000
011000002623400000282340000026234000002923400000262340000028234000002623400000292340000024234000002823400000262340000028234000002423400000282340000026234000002823400000
0110000028234000002623400000232340000021234000001d2340000021234000002323400000262340000024234000002823400000262340000028234000002423400000282340000026234000002823400000
011000002824400000262340000023224000002121400000000000000000000000000000000000000000000028244000002623400000222240000021214000000000000000000000000000000000000000000000
01100000242340000028234000002623400000292340000024234000002823400000262340000029234000002b234000002923400000262340000024234000002423400000282340000029234000002b23400000
011000002823400000262340000023234000002123400000282340000026234000002321400000212140000028234000002623400000222340000021234000002823400000262340000022214000002121400000
011000002623400000282340000026234000002823400000262340000028234000002623400000282340000029234000002b2340000029234000002b2340000029234000002b2340000029234000002b23400000
011000001a234000002323400000242340000028234000001a214000002321400000242140000028214000001b234000002323400000242340000028234000001b21400000232140000024214000002821400000
011000001a234000001d234000001f234000001c234000001a214000001d214000001f214000001c214000001b2440000023244000001b2340000023234000001b2240000023224000001b214000002321400000
010c00000c150001000c150001000c150001000c150001000c150001000c150001000c150001000c150001000c150001000c150001000c150001000c150001000c150001000c150001000c150001000c15000100
010c00000915004100091500410009150041000915004100091500410009150041000915004100091500410009150041000915004100091500410009150041000915004100091500410009150041000915000000
010c00000e150021000e150021000e1500210000000021000e150021000e150021000e1500210000000021000e150021000e150021000e1500210000000021000e150021000e150021000e150021000210000000
010c0100101500c100101500c100101500c100000000c100101500c100101500c100101500c100000000c100101500c100101500c100101500c100000000c100101500c100101500c100101500c100000000c100
010c00202f3502f3422f3422f3322f3322f3222f3222f3122f3122f3122f3502f3422f3322f3222d3502d3422d3322d3223035030342303322f3502f3422f3322f3222b3522b3422b3322b3222d3522d3422d332
010c00002f3502f3422f3422f3322f3322f3222f3222f3122f3122f3122f3502f3422f3322f3222d3502d3422d3322d3223035030342303322f3502f3422f3322f3222b3522b3422b3322b322283522834228332
010c00002d3502d3422d3422d3322d3322d3222d3222d3122d3122d3122d3502d3422d3322d3222d3502d3422d3322d3223035030342303322f3502f3422f3322f3222b3522b3422b3322b322263522634226332
010c00002b3502b3422b3422b3322b3322b3222b3222b3122b3122b3122b3502b3422b3322b3222b3502b3422b3322b3223035030342303322d3502d3422d3322d3222d3122d3522d3422d332283522834228332
010c00002f3502f3422f3422f3322f3322f3222f3222f3122f3122f3122f3502f3422f3322f3222d3502d3422d3322d3223035030342303322f3502f3422f3422f3322f3222f3222f3122f3122f3122f3122f350
010c00002f3422f3322f3222d3502d3422d3322d3223035030342303322f3522f3422f3422f3322f3322f3222f3222f3122f3122f3122f3122f3502f3422f3322f3222b3522b3422b3322b322283522834228332
010c00002d3502d3422d3422d3322d3322d3222d3222d3122d3122d3122d3502d3422d3322d3222d3502d3422d3322d3223035030342303322f3502f3422f3322f3222b3522b3422b3322b322263522634226332
010c00002b3502b3522b3422b3422b3322b3322b3222b3222b3222b3222d3502d3422d3322d3222d3502d3422d3322d3223035030342303322d3502d3422d3322d3222d3122d3522d3422d332283522834228332
010c00002b3502b3522b3422b3422b3322b3322b3222b3222b3112b3112b3112b3112b3112b3112b3112b3152d3002d3002830028300283002830028300283000000000000000000000000000000000000000000
__music__
00 377d7c44
00 387d7c44
00 397d7c44
00 3a7d7c44
00 3b7d7c44
00 3c7d7c44
00 3d7d7c44
00 3a7d7c44
00 377d7c44
00 397d7c44
00 3e7d7c44
04 3f7d7c44
00 41424344
01 28697044
00 27697044
00 28292b44
00 27293044
00 28292c44
00 27292e44
00 28292c44
00 27292f44
00 28292d44
00 27293144
00 262a3244
00 41424344
00 0b424344
00 0c0f4344
00 0c104344
00 0d114344
00 0c124344
00 0c134344
00 0c144344
00 0d164344
00 0e174344
00 0d154344
04 0e554344
00 41424344
01 05063344
00 05073344
00 05083444
00 05093444
00 05063344
00 05073344
00 050a3444
00 050b3444
00 05183544
00 05193544
00 050a3544
00 05193544
00 051a3644
00 051b3644
00 051c3644
00 051d3644
00 051e3344
00 051f3344
00 05203444
00 05213444
00 05223344
00 05233344
00 05243444
02 05253544
00 41424344
00 41424344
00 41424344

