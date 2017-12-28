; The entire sound engine. Uses section "audio" in WRAM.

; Interfaces are in bank 0.

; Notable functions:
; 	FadeMusic
; 	PlayStereoSFX

_MapSetup_Sound_Off:: ; e8000
; restart sound operation
; clear all relevant hardware registers & wram
	push hl
	push de
	push bc
	push af
	ld hl, rNR50 ; channel control registers
	xor a
	ld [hli], a ; rNR50 ; volume/vin
	ld [hli], a ; rNR51 ; sfx channels
	ld a, $80 ; all channels on
	ld [hli], a ; ff26 ; music channels

	ld hl, rNR10 ; sound channel registers
	ld e, NUM_MUSIC_CHANS
.clearsound
;   sound channel   1      2      3      4
	xor a
	ld [hli], a ; rNR10, rNR20, rNR30, rNR40 ; sweep = 0

	ld [hli], a ; rNR11, rNR21, rNR31, rNR41 ; length/wavepattern = 0
	ld a, $8
	ld [hli], a ; rNR12, rNR22, rNR32, rNR42 ; envelope = 0
	xor a
	ld [hli], a ; rNR13, rNR23, rNR33, rNR43 ; frequency lo = 0
	ld a, $80
	ld [hli], a ; rNR14, rNR24, rNR34, rNR44 ; restart sound (freq hi = 0)
	dec e
	jr nz, .clearsound

	ld hl, Channels ; start of channel data
	ld de, ChannelsEnd - Channels ; length of area to clear (entire sound wram area)
.clearchannels ; clear Channel1-$c2bf
	xor a
	ld [hli], a
	dec de
	ld a, e
	or d
	jr nz, .clearchannels
	ld a, MAX_VOLUME
	ld [Volume], a
	pop af
	pop bc
	pop de
	pop hl
	ret

; e803d

MusicFadeRestart: ; e803d
; restart but keep the music id to fade in to
	ld a, [MusicFadeID + 1]
	push af
	ld a, [MusicFadeID]
	push af
	call _MapSetup_Sound_Off
	pop af
	ld [MusicFadeID], a
	pop af
	ld [MusicFadeID + 1], a
	ret

_UpdateSound:: ; e805c
; called once per frame
	; start at ch1
	xor a
	ld [CurChannel], a ; just
	ld [SoundOutput], a ; off
	ld bc, Channel1
.loop
	; is the channel active?
	ld hl, Channel1Flags - Channel1
	add hl, bc
	bit SOUND_CHANNEL_ON, [hl]
	jp z, .nextchannel
	; check time left in the current note
	ld hl, Channel1NoteDuration - Channel1
	add hl, bc
	ld a, [hl]
	cp $2 ; 1 or 0?
	jr c, .noteover
	dec [hl]
	jr .continue_sound_update

.noteover
	; reset vibrato delay
	ld hl, Channel1VibratoDelay - Channel1
	add hl, bc
	ld a, [hl]
	ld hl, Channel1VibratoDelayCount - Channel1
	add hl, bc
	ld [hl], a
	; turn vibrato off for now
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	res SOUND_PITCH_WHEEL, [hl]
	; get next note
	call ParseMusic
.continue_sound_update
	call ApplyPitchWheel
	; duty cycle
	ld hl, Channel1DutyCycle - Channel1
	add hl, bc
	ld a, [hli]
	ld [wCurTrackDuty], a
	; intensity
	ld a, [hli]
	ld [wCurTrackIntensity], a
	; frequency
	ld a, [hli]
	ld [wCurTrackFrequency], a
	ld a, [hl]
	ld [wCurTrackFrequency + 1], a
	; vibrato, noise
	call HandleTrackVibrato ; handle vibrato and other things
	call HandleNoise
	; turn off music when playing sfx?
	ld a, [SFXPriority]
	and a
	jr z, .next
	; are we in a sfx channel right now?
	ld a, [CurChannel]
	cp CHAN5
	jr nc, .next
	; are any sfx channels active?
	; if so, mute
	ld hl, Channel5Flags
	bit SOUND_CHANNEL_ON, [hl]
	jr nz, .restnote
	ld hl, Channel6Flags
	bit SOUND_CHANNEL_ON, [hl]
	jr nz, .restnote
	ld hl, Channel7Flags
	bit SOUND_CHANNEL_ON, [hl]
	jr nz, .restnote
	ld hl, Channel8Flags
	bit SOUND_CHANNEL_ON, [hl]
	jr z, .next
.restnote
	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	set NOTE_REST, [hl] ; Rest
.next
	; are we in a sfx channel right now?
	ld a, [CurChannel]
	cp CHAN5
	jr nc, .sfx_channel
	ld hl, Channel5Flags - Channel1
	add hl, bc
	bit SOUND_CHANNEL_ON, [hl]
	jr nz, .sound_channel_on
.sfx_channel
	call UpdateChannels
	ld hl, Channel1Tracks - Channel1
	add hl, bc
	ld a, [SoundOutput]
	or [hl]
	ld [SoundOutput], a
.sound_channel_on
	; clear note flags
	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	xor a
	ld [hl], a
.nextchannel
	; next channel
	ld hl, Channel2 - Channel1
	add hl, bc
	ld c, l
	ld b, h
	ld a, [CurChannel]
	inc a
	ld [CurChannel], a
	cp $8 ; are we done?
	jp nz, .loop ; do it all again

	call PlayDanger
	; fade music in/out
	call FadeMusic
	; write volume to hardware register
	ld a, [Volume]
	ld [rNR50], a
	; write SO on/off to hardware register
	ld a, [SoundOutput]
	ld [rNR51], a
	ret

; e8125

UpdateChannels: ; e8125
	ld hl, .ChannelFnPtrs
	ld a, [CurChannel]
	and $7
	add a
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	jp hl

.ChannelFnPtrs:
	dw .Channel1
	dw .Channel2
	dw .Channel3
	dw .Channel4
; sfx ch ptrs are identical to music chs
; ..except 5
	dw .Channel5
	dw .Channel6
	dw .Channel7
	dw .Channel8

.Channel1:
	ld a, [Danger]
	bit DANGER_ON_F, a
	ret nz
.Channel5:
	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	bit NOTE_UNKN_3, [hl]
	jr z, .asm_e8159
	;
	ld a, [SoundInput]
	ld [rNR10], a
.asm_e8159
	bit NOTE_REST, [hl] ; rest
	jr nz, .ch1rest
	bit NOTE_NOISE_SAMPLING, [hl]
	jr nz, .asm_e81a2
	bit NOTE_FREQ_OVERRIDE, [hl]
	jr nz, .frequency_override
	bit NOTE_VIBRATO_OVERRIDE, [hl]
	jr nz, .asm_e8184
	jr .check_duty_override

.frequency_override
	ld a, [wCurTrackFrequency]
	ld [rNR13], a
	ld a, [wCurTrackFrequency + 1]
	ld [rNR14], a
.check_duty_override
	bit NOTE_DUTY_OVERRIDE, [hl]
	ret z
	ld a, [wCurTrackDuty]
	ld d, a
	ld a, [rNR11]
	and $3f ; sound length
	or d
	ld [rNR11], a
	ret

.asm_e8184
	ld a, [wCurTrackDuty]
	ld d, a
	ld a, [rNR11]
	and $3f ; sound length
	or d
	ld [rNR11], a
	ld a, [wCurTrackFrequency]
	ld [rNR13], a
	ret

.ch1rest
	ld a, [rNR52]
	and %10001110 ; ch1 off
	ld [rNR52], a
	ld hl, rNR10
	call ClearChannel
	ret

.asm_e81a2
	ld hl, wCurTrackDuty
	ld a, $3f ; sound length
	or [hl]
	ld [rNR11], a
	ld a, [wCurTrackIntensity]
	ld [rNR12], a
	ld a, [wCurTrackFrequency]
	ld [rNR13], a
	ld a, [wCurTrackFrequency + 1]
	or $80
	ld [rNR14], a
	ret

.Channel2:
.Channel6:
	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	bit NOTE_REST, [hl] ; rest
	jr nz, .ch2rest
	bit NOTE_NOISE_SAMPLING, [hl]
	jr nz, .asm_e8204
	bit NOTE_VIBRATO_OVERRIDE, [hl]
	jr nz, .asm_e81e6
	bit NOTE_DUTY_OVERRIDE, [hl]
	ret z
	ld a, [wCurTrackDuty]
	ld d, a
	ld a, [rNR21]
	and $3f ; sound length
	or d
	ld [rNR21], a
	ret

.asm_e81db ; unused
	ld a, [wCurTrackFrequency]
	ld [rNR23], a
	ld a, [wCurTrackFrequency + 1]
	ld [rNR24], a
	ret

.asm_e81e6
	ld a, [wCurTrackDuty]
	ld d, a
	ld a, [rNR21]
	and $3f ; sound length
	or d
	ld [rNR21], a
	ld a, [wCurTrackFrequency]
	ld [rNR23], a
	ret

.ch2rest
	ld a, [rNR52]
	and %10001101 ; ch2 off
	ld [rNR52], a
	ld hl, rNR20
	call ClearChannel
	ret

.asm_e8204
	ld hl, wCurTrackDuty
	ld a, $3f ; sound length
	or [hl]
	ld [rNR21], a
	ld a, [wCurTrackIntensity]
	ld [rNR22], a
	ld a, [wCurTrackFrequency]
	ld [rNR23], a
	ld a, [wCurTrackFrequency + 1]
	or $80 ; initial (restart)
	ld [rNR24], a
	ret

.Channel3:
.Channel7:
	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	bit NOTE_REST, [hl] ; rest
	jr nz, .ch3rest
	bit NOTE_NOISE_SAMPLING, [hl]
	jr nz, .asm_e824d
	bit NOTE_VIBRATO_OVERRIDE, [hl]
	jr nz, .asm_e823a
	ret

.asm_e822f ; unused
	ld a, [wCurTrackFrequency]
	ld [rNR33], a
	ld a, [wCurTrackFrequency + 1]
	ld [rNR34], a
	ret

.asm_e823a
	ld a, [wCurTrackFrequency]
	ld [rNR33], a
	ret

.ch3rest
	ld a, [rNR52]
	and %10001011 ; ch3 off
	ld [rNR52], a
	ld hl, rNR30
	call ClearChannel
	ret

.asm_e824d
	ld a, $3f
	ld [rNR31], a
	xor a
	ld [rNR30], a
	call .asm_e8268
	ld a, $80
	ld [rNR30], a
	ld a, [wCurTrackFrequency]
	ld [rNR33], a
	ld a, [wCurTrackFrequency + 1]
	or $80
	ld [rNR34], a
	ret

.asm_e8268
	push hl
	ld a, [wCurTrackIntensity]
	and $f ; only 0-9 are valid
	ld l, a
	ld h, 0
	; hl << 4
	; each wavepattern is $f bytes long
	; so seeking is done in $10s
rept 4
	add hl, hl
endr
	ld de, WaveSamples
	add hl, de
	; load wavepattern into rWave_0-rWave_f
	ld a, [hli]
	ld [rWave_0], a
	ld a, [hli]
	ld [rWave_1], a
	ld a, [hli]
	ld [rWave_2], a
	ld a, [hli]
	ld [rWave_3], a
	ld a, [hli]
	ld [rWave_4], a
	ld a, [hli]
	ld [rWave_5], a
	ld a, [hli]
	ld [rWave_6], a
	ld a, [hli]
	ld [rWave_7], a
	ld a, [hli]
	ld [rWave_8], a
	ld a, [hli]
	ld [rWave_9], a
	ld a, [hli]
	ld [rWave_a], a
	ld a, [hli]
	ld [rWave_b], a
	ld a, [hli]
	ld [rWave_c], a
	ld a, [hli]
	ld [rWave_d], a
	ld a, [hli]
	ld [rWave_e], a
	ld a, [hli]
	ld [rWave_f], a
	pop hl
	ld a, [wCurTrackIntensity]
	and $f0
	sla a
	ld [rNR32], a
	ret

.Channel4:
.Channel8:
	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	bit NOTE_REST, [hl] ; rest
	jr nz, .ch4rest
	bit NOTE_NOISE_SAMPLING, [hl]
	jr nz, .asm_e82d4
	ret

.asm_e82c1 ; unused
	ld a, [wCurTrackFrequency]
	ld [rNR43], a
	ret

.ch4rest
	ld a, [rNR52]
	and %10000111 ; ch4 off
	ld [rNR52], a
	ld hl, rNR40
	call ClearChannel
	ret

.asm_e82d4
	ld a, $3f ; sound length
	ld [rNR41], a
	ld a, [wCurTrackIntensity]
	ld [rNR42], a
	ld a, [wCurTrackFrequency]
	ld [rNR43], a
	ld a, $80
	ld [rNR44], a
	ret

; e82e7

_CheckSFX: ; e82e7
; return carry if any sfx channels are active
	ld hl, Channel5Flags
	bit SOUND_CHANNEL_ON, [hl]
	jr nz, .sfxon
	ld hl, Channel6Flags
	bit SOUND_CHANNEL_ON, [hl]
	jr nz, .sfxon
	ld hl, Channel7Flags
	bit SOUND_CHANNEL_ON, [hl]
	jr nz, .sfxon
	ld hl, Channel8Flags
	bit SOUND_CHANNEL_ON, [hl]
	jr nz, .sfxon
	and a
	ret

.sfxon
	scf
	ret

; e8307

PlayDanger: ; e8307
	ld a, [Danger]
	bit DANGER_ON_F, a
	ret z
	and $ff ^ (1 << DANGER_ON_F)
	ld d, a
	call _CheckSFX
	jr c, .asm_e8335
	and a
	jr z, .asm_e8323
	cp 16 ; halfway
	jr z, .asm_e831e
	jr .asm_e8335

.asm_e831e
	ld hl, Tablee8354
	jr .updatehw

.asm_e8323
	ld hl, Tablee8350
.updatehw
	xor a
	ld [rNR10], a ; sweep off
	ld a, [hli]
	ld [rNR11], a ; sound length / duty cycle
	ld a, [hli]
	ld [rNR12], a ; ch1 volume envelope
	ld a, [hli]
	ld [rNR13], a ; ch1 frequency lo
	ld a, [hli]
	ld [rNR14], a ; ch1 frequency hi
.asm_e8335
	ld a, d
	inc a
	cp 30
	jr c, .asm_e833c
	xor a
.asm_e833c
	or 1 << DANGER_ON_F
	ld [Danger], a
	; is hw ch1 on?
	ld a, [SoundOutput]
	and $11
	ret nz
	; if not, turn it on
	ld a, [SoundOutput]
	or $11
	ld [SoundOutput], a
	ret

; e8350

Tablee8350: ; e8350
	db $80 ; duty 50%
	db $e2 ; volume 14, envelope decrease sweep 2
	db $50 ; frequency: $750
	db $87 ; restart sound
; e8354

Tablee8354: ; e8354
	db $80 ; duty 50%
	db $e2 ; volume 14, envelope decrease sweep 2
	db $ee ; frequency: $6ee
	db $86 ; restart sound
; e8358

FadeMusic: ; e8358
; fade music if applicable
; usage:
;	write to MusicFade
;	song fades out at the given rate
;	load song id in MusicFadeID
;	fade new song in
; notes:
;	max # frames per volume level is $3f

	; fading?
	ld a, [MusicFade]
	and a
	ret z
	; has the count ended?
	ld a, [MusicFadeCount]
	and a
	jr z, .update
	; count down
	dec a
	ld [MusicFadeCount], a
	ret

.update
	ld a, [MusicFade]
	ld d, a
	; get new count
	and $3f
	ld [MusicFadeCount], a
	; get SO1 volume
	ld a, [Volume]
	and VOLUME_SO1_LEVEL
	; which way are we fading?
	bit MUSIC_FADE_IN_F, d
	jr nz, .fadein
	; fading out
	and a
	jr z, .novolume
	dec a
	jr .updatevolume

.novolume
	; make sure volume is off
	xor a
	ld [Volume], a
	; did we just get on a bike?
	push bc
	; restart sound
	call MusicFadeRestart
	; get new song id
	ld a, [MusicFadeID]
	and a
	jr z, .quit ; this assumes there are fewer than 256 songs!
	ld e, a
	ld a, [MusicFadeID + 1]
	ld d, a
	; load new song
	call _PlayMusic
.quit
	; cleanup
	pop bc
	; stop fading
	xor a
	ld [MusicFade], a
	ret

.fadein
	; are we done?
	cp $7
	jr nc, .maxvolume
	; inc volume
	inc a
	jr .updatevolume

.maxvolume
	; we're done
	xor a
	ld [MusicFade], a
	ret

.updatevolume
	; hi = lo
	ld d, a
	swap a
	or d
	ld [Volume], a
	ret

; e83d1

LoadNote: ; e83d1
	; wait for pitch wheel to finish
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	bit SOUND_PITCH_WHEEL, [hl]
	ret z
	; get note duration
	ld hl, Channel1NoteDuration - Channel1
	add hl, bc
	ld a, [hl]
	ld hl, wCurNoteDuration
	sub [hl]
	jr nc, .ok
	ld a, 1
.ok
	ld [hl], a
	; get frequency
	ld hl, Channel1Frequency - Channel1
	add hl, bc
	ld e, [hl]
	inc hl
	ld d, [hl]
	; get direction of pitch wheel
	ld hl, Channel1PitchWheelTarget - Channel1
	add hl, bc
	ld a, e
	sub [hl]
	ld e, a
	ld a, d
	sbc 0
	ld d, a
	ld hl, Channel1PitchWheelTarget + 1 - Channel1
	add hl, bc
	sub [hl]
	jr nc, .greater_than
	ld hl, Channel1Flags3 - Channel1
	add hl, bc
	set SOUND_PITCH_WHEEL_DIR, [hl]
	; get frequency
	ld hl, Channel1Frequency - Channel1
	add hl, bc
	ld e, [hl]
	inc hl
	ld d, [hl]
	; ????
	ld hl, Channel1PitchWheelTarget - Channel1
	add hl, bc
	ld a, [hl]
	sub e
	ld e, a
	ld a, d
	sbc 0
	ld d, a
	; ????
	ld hl, Channel1PitchWheelTarget + 1 - Channel1
	add hl, bc
	ld a, [hl]
	sub d
	ld d, a
	jr .resume

.greater_than
	ld hl, Channel1Flags3 - Channel1
	add hl, bc
	res SOUND_PITCH_WHEEL_DIR, [hl]
	; get frequency
	ld hl, Channel1Frequency - Channel1
	add hl, bc
	ld e, [hl]
	inc hl
	ld d, [hl]
	; get distance from pitch wheel target
	ld hl, Channel1PitchWheelTarget - Channel1
	add hl, bc
	ld a, e
	sub [hl]
	ld e, a
	ld a, d
	sbc 0
	ld d, a
	ld hl, Channel1PitchWheelTarget + 1 - Channel1
	add hl, bc
	sub [hl]
	ld d, a
.resume
	; de = x * [wCurNoteDuration] + y
	; x + 1 -> d
	; y -> a
	push bc
	ld hl, wCurNoteDuration
	ld b, 0 ; quotient
.loop
	inc b
	ld a, e
	sub [hl]
	ld e, a
	jr nc, .loop
	ld a, d
	and a
	jr z, .quit
	dec d
	jr .loop

.quit
	ld a, e ; remainder
	add [hl]
	ld d, b ; quotient
	pop bc
	ld hl, Channel1PitchWheelAmount - Channel1
	add hl, bc
	ld [hl], d ; quotient
	ld hl, Channel1PitchWheelAmountFraction - Channel1
	add hl, bc
	ld [hl], a ; remainder
	ld hl, Channel1Field0x25 - Channel1
	add hl, bc
	xor a
	ld [hl], a
	ret

; e8466

HandleTrackVibrato: ; e8466
; handle duty, cry pitch, and vibrato
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	bit SOUND_DUTY, [hl] ; duty
	jr z, .next
	ld hl, Channel1SFXDutyLoop - Channel1
	add hl, bc
	ld a, [hl]
	rlca
	rlca
	ld [hl], a
	and $c0
	ld [wCurTrackDuty], a
	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	set NOTE_DUTY_OVERRIDE, [hl]
.next
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	bit SOUND_CRY_PITCH, [hl]
	jr z, .vibrato
	ld hl, Channel1CryPitch - Channel1
	add hl, bc
	ld e, [hl]
	inc hl
	ld d, [hl]
	ld hl, wCurTrackFrequency
	ld a, [hli]
	ld h, [hl]
	ld l, a
	add hl, de
	ld e, l
	ld d, h
	ld hl, wCurTrackFrequency
	ld [hl], e
	inc hl
	ld [hl], d
.vibrato
	; is vibrato on?
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	bit SOUND_VIBRATO, [hl] ; vibrato
	jr z, .quit
	; is vibrato active for this note yet?
	; is the delay over?
	ld hl, Channel1VibratoDelayCount - Channel1
	add hl, bc
	ld a, [hl]
	and a
	jr nz, .subexit
	; is the extent nonzero?
	ld hl, Channel1VibratoExtent - Channel1
	add hl, bc
	ld a, [hl]
	and a
	jr z, .quit
	; save it for later
	ld d, a
	; is it time to toggle vibrato up/down?
	ld hl, Channel1VibratoRate - Channel1
	add hl, bc
	ld a, [hl]
	and $f ; count
	jr z, .toggle
.subexit
	dec [hl]
	jr .quit

.toggle
	; refresh count
	ld a, [hl]
	swap [hl]
	or [hl]
	ld [hl], a
	; ????
	ld a, [wCurTrackFrequency]
	ld e, a
	; toggle vibrato up/down
	ld hl, Channel1Flags3 - Channel1
	add hl, bc
	bit SOUND_VIBRATO_DIR, [hl] ; vibrato up/down
	jr z, .down
; up
	; vibrato down
	res SOUND_VIBRATO_DIR, [hl]
	; get the delay
	ld a, d
	and $f ; lo
	;
	ld d, a
	ld a, e
	sub d
	jr nc, .no_carry
	ld a, 0
	jr .no_carry

.down
	; vibrato up
	set SOUND_VIBRATO_DIR, [hl]
	; get the delay
	ld a, d
	and $f0 ; hi
	swap a ; move it to lo
	;
	add e
	jr nc, .no_carry
	ld a, $ff
.no_carry
	ld [wCurTrackFrequency], a
	;
	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	set NOTE_VIBRATO_OVERRIDE, [hl]
.quit
	ret

; e84f9

ApplyPitchWheel: ; e84f9
	; quit if pitch wheel inactive
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	bit SOUND_PITCH_WHEEL, [hl]
	ret z
	; de = Frequency
	ld hl, Channel1Frequency - Channel1
	add hl, bc
	ld e, [hl]
	inc hl
	ld d, [hl]
	; check whether pitch wheel is going up or down
	ld hl, Channel1Flags3 - Channel1
	add hl, bc
	bit SOUND_PITCH_WHEEL_DIR, [hl]
	jr z, .decreasing
	; frequency += [Channel*PitchWheelAmount]
	ld hl, Channel1PitchWheelAmount - Channel1
	add hl, bc
	ld l, [hl]
	ld h, 0
	add hl, de
	ld d, h
	ld e, l
	; [Channel*Field0x25] += [Channel*PitchWheelAmountFraction]
	; if rollover: Frequency += 1
	ld hl, Channel1PitchWheelAmountFraction - Channel1
	add hl, bc
	ld a, [hl]
	ld hl, Channel1Field0x25 - Channel1
	add hl, bc
	add [hl]
	ld [hl], a
	ld a, 0
	adc e
	ld e, a
	ld a, 0
	adc d
	ld d, a
	; Compare the dw at [Channel*PitchWheelTarget] to de.
	; If frequency is greater, we're finished.
	; Otherwise, load the frequency and set two flags.
	ld hl, Channel1PitchWheelTarget + 1 - Channel1
	add hl, bc
	ld a, [hl]
	cp d
	jp c, .finished_pitch_wheel
	jr nz, .continue_pitch_wheel
	ld hl, Channel1PitchWheelTarget - Channel1
	add hl, bc
	ld a, [hl]
	cp e
	jp c, .finished_pitch_wheel
	jr .continue_pitch_wheel

.decreasing
	; frequency -= [Channel*PitchWheelAmount]
	ld a, e
	ld hl, Channel1PitchWheelAmount - Channel1
	add hl, bc
	ld e, [hl]
	sub e
	ld e, a
	ld a, d
	sbc 0
	ld d, a
	; [Channel*Field0x25] *= 2
	; if rollover: Frequency -= 1
	ld hl, Channel1PitchWheelAmountFraction - Channel1
	add hl, bc
	ld a, [hl]
	add a
	ld [hl], a
	ld a, e
	sbc 0
	ld e, a
	ld a, d
	sbc 0
	ld d, a
	; Compare the dw at [Channel*PitchWheelTarget] to de.
	; If frequency is lower, we're finished.
	; Otherwise, load the frequency and set two flags.
	ld hl, Channel1PitchWheelTarget + 1 - Channel1
	add hl, bc
	ld a, d
	cp [hl]
	jr c, .finished_pitch_wheel
	jr nz, .continue_pitch_wheel
	ld hl, Channel1PitchWheelTarget - Channel1
	add hl, bc
	ld a, e
	cp [hl]
	jr nc, .continue_pitch_wheel
.finished_pitch_wheel
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	res SOUND_PITCH_WHEEL, [hl]
	ld hl, Channel1Flags3 - Channel1
	add hl, bc
	res SOUND_PITCH_WHEEL_DIR, [hl]
	ret

.continue_pitch_wheel
	ld hl, Channel1Frequency - Channel1
	add hl, bc
	ld [hl], e
	inc hl
	ld [hl], d
	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	set NOTE_FREQ_OVERRIDE, [hl]
	set NOTE_DUTY_OVERRIDE, [hl]
	ret

; e858c

HandleNoise: ; e858c
	; is noise sampling on?
	ld hl, Channel1Flags - Channel1
	add hl, bc
	bit SOUND_NOISE, [hl] ; noise sampling
	ret z
	; are we in a sfx channel?
	ld a, [CurChannel]
	bit 2, a ; sfx
	jr nz, .next
	; is ch8 on? (noise)
	ld hl, Channel8Flags
	bit SOUND_CHANNEL_ON, [hl] ; on?
	jr z, .next
	; is ch8 playing noise?
	bit SOUND_NOISE, [hl]
	ret nz ; quit if so
	;
.next
	ld a, [wNoiseSampleDelay]
	and a
	jr z, ReadNoiseSample
	dec a
	ld [wNoiseSampleDelay], a
	ret

; e85af

ReadNoiseSample: ; e85af
; sample struct:
;	[wx] [yy] [zz]
;	w: ? either 2 or 3
;	x: duration
;	zz: intensity
;       yy: frequency

	; de = [NoiseSampleAddress]
	ld hl, NoiseSampleAddress
	ld e, [hl]
	inc hl
	ld d, [hl]

	; is it empty?
	ld a, e
	or d
	jr z, .quit

	ld a, [de]
	inc de

	cp $ff
	jr z, .quit

	and $f
	inc a
	ld [wNoiseSampleDelay], a
	ld a, [de]
	inc de
	ld [wCurTrackIntensity], a
	ld a, [de]
	inc de
	ld [wCurTrackFrequency], a
	xor a
	ld [wCurTrackFrequency + 1], a

	ld hl, NoiseSampleAddress
	ld [hl], e
	inc hl
	ld [hl], d

	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	set NOTE_NOISE_SAMPLING, [hl]
	ret

.quit
	ret

; e85e1

ParseMusic: ; e85e1
; parses until a note is read or the song is ended
	call GetMusicByte ; store next byte in a
	cp $ff ; is the song over?
	jr z, .endchannel
	cp $d0 ; is it a note?
	jr c, .readnote
	; then it's a command
.readcommand
	call ParseMusicCommand
	jr ParseMusic ; start over

.readnote
; CurMusicByte contains current note
; special notes
	ld hl, Channel1Flags - Channel1
	add hl, bc
	bit SOUND_SFX, [hl]
	jp nz, ParseSFXOrRest
	bit SOUND_REST, [hl] ; rest
	jp nz, ParseSFXOrRest
	bit SOUND_NOISE, [hl] ; noise sample
	jp nz, GetNoiseSample
; normal note
	; set note duration (bottom nybble)
	ld a, [CurMusicByte]
	and $f
	call SetNoteDuration
	; get note pitch (top nybble)
	ld a, [CurMusicByte]
	swap a
	and $f
	jr z, .rest ; pitch 0-> rest
	; update pitch
	ld hl, Channel1Pitch - Channel1
	add hl, bc
	ld [hl], a
	; store pitch in e
	ld e, a
	; store octave in d
	ld hl, Channel1Octave - Channel1
	add hl, bc
	ld d, [hl]
	; update frequency
	call GetFrequency
	ld hl, Channel1Frequency - Channel1
	add hl, bc
	ld [hl], e
	inc hl
	ld [hl], d
	; ????
	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	set NOTE_NOISE_SAMPLING, [hl]
	jp LoadNote

.rest
; note = rest
	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	set NOTE_REST, [hl] ; Rest
	ret

.endchannel
; $ff is reached in music data
	ld hl, Channel1Flags - Channel1
	add hl, bc
	bit SOUND_SUBROUTINE, [hl] ; in a subroutine?
	jr nz, .readcommand ; execute
	ld a, [CurChannel]
	cp CHAN5
	jr nc, .chan_5to8
	; ????
	ld hl, Channel5Flags - Channel1
	add hl, bc
	bit SOUND_CHANNEL_ON, [hl]
	jr nz, .ok
.chan_5to8
	ld hl, Channel1Flags - Channel1
	add hl, bc
	bit SOUND_REST, [hl]
	call nz, RestoreVolume
	; end music
	ld a, [CurChannel]
	cp CHAN5
	jr nz, .ok
	; ????
	xor a
	ld [rNR10], a ; sweep = 0
.ok
; stop playing
	; turn channel off
	ld hl, Channel1Flags - Channel1
	add hl, bc
	res SOUND_CHANNEL_ON, [hl]
	; note = rest
	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	set NOTE_REST, [hl]
	; clear music id & bank
	ld hl, Channel1MusicID - Channel1
	add hl, bc
	xor a
	ld [hli], a ; id hi
	ld [hli], a ; id lo
	ld [hli], a ; bank
	ret

; e8679

RestoreVolume: ; e8679
	; ch5 only
	ld a, [CurChannel]
	cp CHAN5
	ret nz
	xor a
	ld hl, Channel6CryPitch
	ld [hli], a
	ld [hl], a
	ld hl, Channel8CryPitch
	ld [hli], a
	ld [hl], a
	ld a, [LastVolume]
	ld [Volume], a
	xor a
	ld [LastVolume], a
	ld [SFXPriority], a
	ret

; e8698

ParseSFXOrRest: ; e8698
	; turn noise sampling on
	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	set NOTE_NOISE_SAMPLING, [hl] ; noise sample
	; update note duration
	ld a, [CurMusicByte]
	call SetNoteDuration ; top nybble doesnt matter?
	; update intensity from next param
	call GetMusicByte
	ld hl, Channel1Intensity - Channel1
	add hl, bc
	ld [hl], a
	; update lo frequency from next param
	call GetMusicByte
	ld hl, Channel1FrequencyLo - Channel1
	add hl, bc
	ld [hl], a
	; are we on the last channel? (noise sampling)
	ld a, [CurChannel]
	and $3
	cp $3
	ret z
	; update hi frequency from next param
	call GetMusicByte
	ld hl, Channel1FrequencyHi - Channel1
	add hl, bc
	ld [hl], a
	ret

; e86c5

GetNoiseSample: ; e86c5
; load ptr to sample header in NoiseSampleAddress
	; are we on the last channel?
	ld a, [CurChannel]
	and $3
	cp $3
	; ret if not
	ret nz
	; update note duration
	ld a, [CurMusicByte]
	and $f
	call SetNoteDuration
	; check current channel
	ld a, [CurChannel]
	bit 2, a ; are we in a sfx channel?
	jr nz, .sfx
	ld hl, Channel8Flags
	bit SOUND_CHANNEL_ON, [hl] ; is ch8 on? (noise)
	ret nz
	ld a, [MusicNoiseSampleSet]
	jr .next

.sfx
	ld a, [SFXNoiseSampleSet]
.next
	; load noise sample set id into de
	ld e, a
	ld d, 0
	; load ptr to noise sample set in hl
	ld hl, Drumkits
	add hl, de
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	; get pitch
	ld a, [CurMusicByte]
	swap a
	; non-rest note?
	and $f
	ret z
	; use 'pitch' to seek noise sample set
	ld e, a
	ld d, 0
	add hl, de
	add hl, de
	; load sample pointer into NoiseSampleAddress
	ld a, [hli]
	ld [NoiseSampleAddress], a
	ld a, [hl]
	ld [NoiseSampleAddress + 1], a
	; clear ????
	xor a
	ld [wNoiseSampleDelay], a
	ret

; e870f

ParseMusicCommand: ; e870f
	; reload command
	ld a, [CurMusicByte]
	; get command #
	sub $d0 ; first command
	ld e, a
	ld d, 0
	; seek command pointer
	ld hl, MusicCommands
	add hl, de
	add hl, de
	; jump to the new pointer
	ld a, [hli]
	ld h, [hl]
	ld l, a
	jp hl

; e8720

MusicCommands: ; e8720
; entries correspond to macros/sound.asm enumeration
	dw Music_Octave8 ; octave 8
	dw Music_Octave7 ; octave 7
	dw Music_Octave6 ; octave 6
	dw Music_Octave5 ; octave 5
	dw Music_Octave4 ; octave 4
	dw Music_Octave3 ; octave 3
	dw Music_Octave2 ; octave 2
	dw Music_Octave1 ; octave 1
	dw Music_NoteType ; note length + intensity
	dw Music_ForceOctave ; set starting octave
	dw Music_Tempo ; tempo
	dw Music_DutyCycle ; duty cycle
	dw Music_Intensity ; intensity
	dw Music_SoundStatus ; update sound status
	dw Music_SoundDuty ; sfx duty
	dw Music_ToggleSFX ; sound on/off
	dw Music_SlidePitchTo ; pitch wheel
	dw Music_Vibrato ; vibrato
	dw MusicE2 ; unused
	dw Music_ToggleNoise ; music noise sampling
	dw Music_Panning ; force panning
	dw Music_Volume ; volume
	dw Music_Tone ; tone
	dw MusicE7 ; unused
	dw MusicE8 ; unused
	dw Music_TempoRelative ; global tempo
	dw Music_RestartChannel ; restart current channel from header
	dw Music_NewSong ; new song
	dw Music_SFXPriorityOn ; sfx priority on
	dw Music_SFXPriorityOff ; sfx priority off
	dw MusicEE ; unused
	dw Music_StereoPanning ; stereo panning
	dw Music_SFXToggleNoise ; sfx noise sampling
	dw MusicF1 ; nothing
	dw MusicF2 ; nothing
	dw MusicF3 ; nothing
	dw MusicF4 ; nothing
	dw MusicF5 ; nothing
	dw MusicF6 ; nothing
	dw MusicF7 ; nothing
	dw MusicF8 ; nothing
	dw MusicF9 ; unused
	dw Music_SetCondition ; setcondition
	dw Music_JumpIf ; jumpif
	dw Music_JumpChannel ; jump
	dw Music_LoopChannel ; loop
	dw Music_CallChannel ; call
	dw Music_EndChannel ; return
; e8780

MusicF1: ; e8780
MusicF2: ; e8780
MusicF3: ; e8780
MusicF4: ; e8780
MusicF5: ; e8780
MusicF6: ; e8780
MusicF7: ; e8780
MusicF8: ; e8780
	ret

; e8781

Music_EndChannel: ; e8781
; called when $ff is encountered w/ subroutine flag set
; end music stream
; return to caller of the subroutine
	; reset subroutine flag
	ld hl, Channel1Flags - Channel1
	add hl, bc
	res SOUND_SUBROUTINE, [hl]
	; copy LastMusicAddress to MusicAddress
	ld hl, Channel1LastMusicAddress - Channel1
	add hl, bc
	ld e, [hl]
	inc hl
	ld d, [hl]
	ld hl, Channel1MusicAddress - Channel1
	add hl, bc
	ld [hl], e
	inc hl
	ld [hl], d
	ret

; e8796

Music_CallChannel: ; e8796
; call music stream (subroutine)
; parameters: ll hh ; pointer to subroutine
	; get pointer from next 2 bytes
	call GetMusicByte
	ld e, a
	call GetMusicByte
	ld d, a
	push de
	; copy MusicAddress to LastMusicAddress
	ld hl, Channel1MusicAddress - Channel1
	add hl, bc
	ld e, [hl]
	inc hl
	ld d, [hl]
	ld hl, Channel1LastMusicAddress - Channel1
	add hl, bc
	ld [hl], e
	inc hl
	ld [hl], d
	; load pointer into MusicAddress
	pop de
	ld hl, Channel1MusicAddress - Channel1
	add hl, bc
	ld [hl], e
	inc hl
	ld [hl], d
	; set subroutine flag
	ld hl, Channel1Flags - Channel1
	add hl, bc
	set SOUND_SUBROUTINE, [hl]
	ret

; e87bc

Music_JumpChannel: ; e87bc
; jump
; parameters: ll hh ; pointer
	; get pointer from next 2 bytes
	call GetMusicByte
	ld e, a
	call GetMusicByte
	ld d, a
	ld hl, Channel1MusicAddress - Channel1
	add hl, bc
	ld [hl], e
	inc hl
	ld [hl], d
	ret

; e87cc

Music_LoopChannel: ; e87cc
; loops xx - 1 times
; 	00: infinite
; params: 3
;	xx ll hh
;		xx : loop count
;   	ll hh : pointer

	; get loop count
	call GetMusicByte
	ld hl, Channel1Flags - Channel1
	add hl, bc
	bit SOUND_LOOPING, [hl] ; has the loop been initiated?
	jr nz, .checkloop
	and a ; loop counter 0 = infinite
	jr z, .loop
	; initiate loop
	dec a
	set SOUND_LOOPING, [hl] ; set loop flag
	ld hl, Channel1LoopCount - Channel1
	add hl, bc
	ld [hl], a ; store loop counter
.checkloop
	ld hl, Channel1LoopCount - Channel1
	add hl, bc
	ld a, [hl]
	and a ; are we done?
	jr z, .endloop
	dec [hl]
.loop
	; get pointer
	call GetMusicByte
	ld e, a
	call GetMusicByte
	ld d, a
	; load new pointer into MusicAddress
	ld hl, Channel1MusicAddress - Channel1
	add hl, bc
	ld [hl], e
	inc hl
	ld [hl], d
	ret

.endloop
	; reset loop flag
	ld hl, Channel1Flags - Channel1
	add hl, bc
	res SOUND_LOOPING, [hl]
	; skip to next command
	ld hl, Channel1MusicAddress - Channel1
	add hl, bc
	ld e, [hl]
	inc hl
	ld d, [hl]
	inc de ; skip
	inc de ; pointer
	ld [hl], d
	dec hl
	ld [hl], e
	ret

; e880e

Music_SetCondition: ; e880e
; set condition for a jump
; used with FB
; params: 1
;	xx ; condition

	; set condition
	call GetMusicByte
	ld hl, Channel1Condition - Channel1
	add hl, bc
	ld [hl], a
	ret

; e8817

Music_JumpIf: ; e8817
; conditional jump
; used with FA
; params: 3
; 	xx: condition
;	ll hh: pointer

; check condition
	; a = condition
	call GetMusicByte
	; if existing condition matches, jump to new address
	ld hl, Channel1Condition - Channel1
	add hl, bc
	cp [hl]
	jr z, .jump
; skip to next command
	; get address
	ld hl, Channel1MusicAddress - Channel1
	add hl, bc
	ld e, [hl]
	inc hl
	ld d, [hl]
	; skip pointer
	inc de
	inc de
	; update address
	ld [hl], d
	dec hl
	ld [hl], e
	ret

.jump
; jump to the new address
	; get pointer
	call GetMusicByte
	ld e, a
	call GetMusicByte
	ld d, a
	; update pointer in MusicAddress
	ld hl, Channel1MusicAddress - Channel1
	add hl, bc
	ld [hl], e
	inc hl
	ld [hl], d
	ret

; e883e

MusicEE; e883e
; conditional jump
; checks a byte in ram corresponding to the current channel
; doesn't seem to be set by any commands
; params: 2
;		ll hh ; pointer

; if ????, jump
	; get channel
	ld a, [CurChannel]
	and $3 ; ch0-3
	ld e, a
	ld d, 0
	; hl = Channel1JumpCondition + channel id
	ld hl, Channel1JumpCondition
	add hl, de
	; if set, jump
	ld a, [hl]
	and a
	jr nz, .jump
; skip to next command
	; get address
	ld hl, Channel1MusicAddress - Channel1
	add hl, bc
	ld e, [hl]
	inc hl
	ld d, [hl]
	; skip pointer
	inc de
	inc de
	; update address
	ld [hl], d
	dec hl
	ld [hl], e
	ret

.jump
	; reset jump flag
	ld [hl], 0
	; de = pointer
	call GetMusicByte
	ld e, a
	call GetMusicByte
	ld d, a
	; update address
	ld hl, Channel1MusicAddress - Channel1
	add hl, bc
	ld [hl], e
	inc hl
	ld [hl], d
	ret

; e886d

MusicF9: ; e886d
; sets some flag
; seems to be unused
; params: 0
	ld a, 1
	ld [wc2b5], a
	ret

; e8873

MusicE2: ; e8873
; seems to have been dummied out
; params: 1
	call GetMusicByte
	ld hl, Channel1Field0x2c - Channel1
	add hl, bc
	ld [hl], a
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	set SOUND_UNKN_0B, [hl]
	ret

; e8882

Music_Vibrato: ; e8882
; vibrato
; params: 2
;	1: [xx]
	; delay in frames
;	2: [yz]
	; y: extent
	; z: rate (# frames per cycle)

	; set vibrato flag?
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	set SOUND_VIBRATO, [hl]
	; start at lower frequency (extent is positive)
	ld hl, Channel1Flags3 - Channel1
	add hl, bc
	res SOUND_VIBRATO_DIR, [hl]
	; get delay
	call GetMusicByte
; update delay
	ld hl, Channel1VibratoDelay - Channel1
	add hl, bc
	ld [hl], a
; update delay count
	ld hl, Channel1VibratoDelayCount - Channel1
	add hl, bc
	ld [hl], a
; update extent
; this is split into halves only to get added back together at the last second
	; get extent/rate
	call GetMusicByte
	ld hl, Channel1VibratoExtent - Channel1
	add hl, bc
	ld d, a
	; get top nybble
	and $f0
	swap a
	srl a ; halve
	ld e, a
	adc a, 0; round up
	swap a
	or e
	ld [hl], a
; update rate
	ld hl, Channel1VibratoRate - Channel1
	add hl, bc
	; get bottom nybble
	ld a, d
	and $f
	ld d, a
	swap a
	or d
	ld [hl], a
	ret

; e88bd

Music_SlidePitchTo: ; e88bd
; set the target for pitch wheel
; params: 2
; note duration
; target note
	call GetMusicByte
	ld [wCurNoteDuration], a

	call GetMusicByte
	; pitch in e
	ld d, a
	and $f
	ld e, a

	; octave in d
	ld a, d
	swap a
	and $f
	ld d, a
	call GetFrequency
	ld hl, Channel1PitchWheelTarget - Channel1
	add hl, bc
	ld [hl], e
	ld hl, Channel1PitchWheelTarget + 1 - Channel1
	add hl, bc
	ld [hl], d
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	set SOUND_PITCH_WHEEL, [hl]
	ret

; e88e4

Music_Tone: ; e88e4
; tone
; params: 1 (dw)
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	set SOUND_CRY_PITCH, [hl]
	ld hl, Channel1CryPitch + 1 - Channel1
	add hl, bc
	call GetMusicByte
	ld [hld], a
	call GetMusicByte
	ld [hl], a
	ret

; e88f7

MusicE7: ; e88f7
; unused
; params: 1
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	set SOUND_UNKN_0E, [hl]
	call GetMusicByte
	ld hl, Channel1Field0x29 - Channel1
	add hl, bc
	ld [hl], a
	ret

; e8906

Music_SoundDuty: ; e8906
; sequence of 4 duty cycles to be looped
; params: 1 (4 2-bit duty cycle arguments)
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	set SOUND_DUTY, [hl] ; duty cycle
	; sound duty sequence
	call GetMusicByte
	rrca
	rrca
	ld hl, Channel1SFXDutyLoop - Channel1
	add hl, bc
	ld [hl], a
	; update duty cycle
	and $c0 ; only uses top 2 bits
	ld hl, Channel1DutyCycle - Channel1
	add hl, bc
	ld [hl], a
	ret

; e891e

MusicE8: ; e891e
; unused
; params: 1
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	set SOUND_UNKN_0D, [hl]
	call GetMusicByte
	ld hl, Channel1Field0x2a - Channel1
	add hl, bc
	ld [hl], a
	ret

; e892d

Music_ToggleSFX: ; e892d
; toggle something
; params: none
	ld hl, Channel1Flags - Channel1
	add hl, bc
	bit SOUND_SFX, [hl]
	jr z, .on
	res SOUND_SFX, [hl]
	ret

.on
	set SOUND_SFX, [hl]
	ret

; e893b

Music_ToggleNoise: ; e893b
; toggle music noise sampling
; can't be used as a straight toggle since the param is not read from on->off
; params:
; 	noise on: 1
; 	noise off: 0
	; check if noise sampling is on
	ld hl, Channel1Flags - Channel1
	add hl, bc
	bit SOUND_NOISE, [hl]
	jr z, .on
	; turn noise sampling off
	res SOUND_NOISE, [hl]
	ret

.on
	; turn noise sampling on
	set SOUND_NOISE, [hl]
	call GetMusicByte
	ld [MusicNoiseSampleSet], a
	ret

; e894f

Music_SFXToggleNoise: ; e894f
; toggle sfx noise sampling
; params:
;	on: 1
; 	off: 0
	; check if noise sampling is on
	ld hl, Channel1Flags - Channel1
	add hl, bc
	bit SOUND_NOISE, [hl]
	jr z, .on
	; turn noise sampling off
	res SOUND_NOISE, [hl]
	ret

.on
	; turn noise sampling on
	set SOUND_NOISE, [hl]
	call GetMusicByte
	ld [SFXNoiseSampleSet], a
	ret

; e8963

Music_NoteType: ; e8963
; note length
;	# frames per 16th note
; intensity: see Music_Intensity
; params: 2
	; note length
	call GetMusicByte
	ld hl, Channel1NoteLength - Channel1
	add hl, bc
	ld [hl], a
	ld a, [CurChannel]
	and $3
	cp CHAN8 & $3
	ret z
	; intensity
	call Music_Intensity
	ret

; e8977

Music_SoundStatus: ; e8977
; update sound status
; params: 1
	call GetMusicByte
	ld [SoundInput], a
	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	set NOTE_UNKN_3, [hl]
	ret

; e8984

Music_DutyCycle: ; e8984
; duty cycle
; params: 1
	call GetMusicByte
	rrca
	rrca
	and $c0
	ld hl, Channel1DutyCycle - Channel1
	add hl, bc
	ld [hl], a
	ret

; e8991

Music_Intensity: ; e8991
; intensity
; params: 1
;	hi: pressure
;   lo: velocity
	call GetMusicByte
	ld hl, Channel1Intensity - Channel1
	add hl, bc
	ld [hl], a
	ret

; e899a

Music_Tempo: ; e899a
; global tempo
; params: 2
;	de: tempo
	call GetMusicByte
	ld d, a
	call GetMusicByte
	ld e, a
	call SetGlobalTempo
	ret

; e89a6

Music_Octave8: ; e89a6
Music_Octave7: ; e89a6
Music_Octave6: ; e89a6
Music_Octave5: ; e89a6
Music_Octave4: ; e89a6
Music_Octave3: ; e89a6
Music_Octave2: ; e89a6
Music_Octave1: ; e89a6
; set octave based on lo nybble of the command
	ld hl, Channel1Octave - Channel1
	add hl, bc
	ld a, [CurMusicByte]
	and 7
	ld [hl], a
	ret

; e89b1

Music_ForceOctave: ; e89b1
; set starting octave
; this forces all notes up by the starting octave
; params: 1
	call GetMusicByte
	ld hl, Channel1PitchOffset - Channel1
	add hl, bc
	ld [hl], a
	ret

; e89ba

Music_StereoPanning: ; e89ba
; stereo panning
; params: 1
	; stereo on?
	ld a, Options
	bit STEREO, a
	jr nz, Music_Panning
	; skip param
	call GetMusicByte
	ret

; e89c5

Music_Panning: ; e89c5
; force panning
; params: 1
	call SetLRTracks
	call GetMusicByte
	ld hl, Channel1Tracks - Channel1
	add hl, bc
	and [hl]
	ld [hl], a
	ret

; e89d2

Music_Volume: ; e89d2
; set volume
; params: 1
;	see Volume
	; read param even if it's not used
	call GetMusicByte
	; is the song fading?
	ld a, [MusicFade]
	and a
	ret nz
	; reload param
	ld a, [CurMusicByte]
	; set volume
	ld [Volume], a
	ret

; e89e1

Music_TempoRelative: ; e89e1
; set global tempo to current channel tempo +- param
; params: 1 signed
	call GetMusicByte
	ld e, a
	; check sign
	cp $80
	jr nc, .negative
;positive
	ld d, 0
	jr .ok

.negative
	ld d, -1
.ok
	ld hl, Channel1Tempo - Channel1
	add hl, bc
	ld a, [hli]
	ld h, [hl]
	ld l, a
	add hl, de
	ld e, l
	ld d, h
	call SetGlobalTempo
	ret

; e89fd

Music_SFXPriorityOn: ; e89fd
; turn sfx priority on
; params: none
	ld a, 1
	ld [SFXPriority], a
	ret

; e8a03

Music_SFXPriorityOff: ; e8a03
; turn sfx priority off
; params: none
	xor a
	ld [SFXPriority], a
	ret

; e8a08

Music_RestartChannel: ; e8a08
; restart current channel from channel header (same bank)
; params: 2 (5)
; ll hh: pointer to new channel header
;	header format: 0x yy zz
;		x: channel # (0-3)
;		zzyy: pointer to new music data

	; update music id
	ld hl, Channel1MusicID - Channel1
	add hl, bc
	ld a, [hli]
	ld [MusicID], a
	ld a, [hl]
	ld [MusicID + 1], a
	; update music bank
	ld hl, Channel1MusicBank - Channel1
	add hl, bc
	ld a, [hl]
	ld [MusicBank], a
	; get pointer to new channel header
	call GetMusicByte
	ld l, a
	call GetMusicByte
	ld h, a
	ld e, [hl]
	inc hl
	ld d, [hl]
	push bc ; save current channel
	call LoadChannel
	call StartChannel
	pop bc ; restore current channel
	ret

; e8a30

Music_NewSong: ; e8a30
; new song
; params: 2
;	de: song id
	call GetMusicByte
	ld e, a
	call GetMusicByte
	ld d, a
	push bc
	call _PlayMusic
	pop bc
	ret

; e8a3e

GetMusicByte: ; e8a3e
; returns byte from current address in a
; advances to next byte in music data
; input: bc = start of current channel
	push hl
	push de
	; load address into de
	ld hl, Channel1MusicAddress - Channel1
	add hl, bc
	ld a, [hli]
	ld e, a
	ld d, [hl]
	; load bank into a
	ld hl, Channel1MusicBank - Channel1
	add hl, bc
	ld a, [hl]
	; get byte
	call _LoadMusicByte ; load data into CurMusicByte
	inc de ; advance to next byte for next time this is called
	; update channeldata address
	ld hl, Channel1MusicAddress - Channel1
	add hl, bc
	ld a, e
	ld [hli], a
	ld [hl], d
	; cleanup
	pop de
	pop hl
	; store channeldata in a
	ld a, [CurMusicByte]
	ret

; e8a5d

GetFrequency: ; e8a5d
; generate frequency
; input:
; 	d: octave
;	e: pitch
; output:
; 	de: frequency

; get octave
	; get starting octave
	ld hl, Channel1PitchOffset - Channel1
	add hl, bc
	ld a, [hl]
	swap a ; hi nybble
	and $f
	; add current octave
	add d
	push af ; we'll use this later
	; get starting octave
	ld hl, Channel1PitchOffset - Channel1
	add hl, bc
	ld a, [hl]
	and $f ; lo nybble
	ld l, a ; ok
	ld d, 0
	ld h, d
	add hl, de ; add current pitch
	add hl, hl ; skip 2 bytes for each
	ld de, FrequencyTable
	add hl, de
	ld e, [hl]
	inc hl
	ld d, [hl]
	; get our octave
	pop af
	; shift right by [7 - octave] bits
.loop
	; [7 - octave] loops
	cp $7
	jr nc, .ok
	; sra de
	sra d
	rr e
	inc a
	jr .loop

.ok
	ld a, d
	and $7 ; top 3 bits for frequency (11 total)
	ld d, a
	ret

; e8a8d

SetNoteDuration: ; e8a8d
; input: a = note duration in 16ths
	; store delay units in de
	inc a
	ld e, a
	ld d, 0
	; store NoteLength in a
	ld hl, Channel1NoteLength - Channel1
	add hl, bc
	ld a, [hl]
	; multiply NoteLength by delay units
	ld l, 0 ; just multiply
	call .Multiply
	ld a, l ; low
	; store Tempo in de
	ld hl, Channel1Tempo - Channel1
	add hl, bc
	ld e, [hl]
	inc hl
	ld d, [hl]
	; add ???? to the next result
	ld hl, Channel1Field0x16 - Channel1
	add hl, bc
	ld l, [hl]
	; multiply Tempo by last result (NoteLength * LOW(delay))
	call .Multiply
	; copy result to de
	ld e, l
	ld d, h
	; store result in ????
	ld hl, Channel1Field0x16 - Channel1
	add hl, bc
	ld [hl], e
	; store result in NoteDuration
	ld hl, Channel1NoteDuration - Channel1
	add hl, bc
	ld [hl], d
	ret

; e8ab8

.Multiply: ; e8ab8
; multiplies a and de
; adds the result to l
; stores the result in hl
	ld h, 0
.loop
	; halve a
	srl a
	; is there a remainder?
	jr nc, .skip
	; add it to the result
	add hl, de
.skip
	; add de, de
	sla e
	rl d
	; are we done?
	and a
	jr nz, .loop
	ret

; e8ac7

SetGlobalTempo: ; e8ac7
	push bc ; save current channel
	; are we dealing with music or sfx?
	ld a, [CurChannel]
	cp CHAN5
	jr nc, .sfxchannels
	ld bc, Channel1
	call Tempo
	ld bc, Channel2
	call Tempo
	ld bc, Channel3
	call Tempo
	ld bc, Channel4
	call Tempo
	jr .end

.sfxchannels
	ld bc, Channel5
	call Tempo
	ld bc, Channel6
	call Tempo
	ld bc, Channel7
	call Tempo
	ld bc, Channel8
	call Tempo
.end
	pop bc ; restore current channel
	ret

; e8b03

Tempo: ; e8b03
; input:
; 	de: note length
	; update Tempo
	ld hl, Channel1Tempo - Channel1
	add hl, bc
	ld [hl], e
	inc hl
	ld [hl], d
	; clear ????
	xor a
	ld hl, Channel1Field0x16 - Channel1
	add hl, bc
	ld [hl], a
	ret

; e8b11

StartChannel: ; e8b11
	call SetLRTracks
	ld hl, Channel1Flags - Channel1
	add hl, bc
	set SOUND_CHANNEL_ON, [hl] ; turn channel on
	ret

; e8b1b

SetLRTracks: ; e8b1b
; set tracks for a the current channel to default
; seems to be redundant since this is overwritten by stereo data later
	push de
	; store current channel in de
	ld a, [CurChannel]
	and $3
	ld e, a
	ld d, 0
	; get this channel's lr tracks
	call GetLRTracks
	add hl, de ; de = channel 0-3
	ld a, [hl]
	; load lr tracks into Tracks
	ld hl, Channel1Tracks - Channel1
	add hl, bc
	ld [hl], a
	pop de
	ret

; e8b30

_PlayMusic:: ; e8b30
; load music
	ld hl, MusicID
	ld [hl], e ; song number
	inc hl
	ld [hl], d ; (always 0)
	ld hl, Music
	add hl, de ; three
	add hl, de ; byte
	add hl, de ; pointer
	ld a, [hli]
	ld [MusicBank], a
	ld e, [hl]
	inc hl
	ld d, [hl] ; music header address
	call LoadMusicByte ; store first byte of music header in a
	rlca
	rlca
	and $3 ; get number of channels
	inc a
.loop
; start playing channels
	push af
	call LoadChannel
	call StartChannel
	pop af
	dec a
	jr nz, .loop
	xor a
	ld [wc2b5], a
	ld [Channel1JumpCondition], a
	ld [Channel2JumpCondition], a
	ld [Channel3JumpCondition], a
	ld [Channel4JumpCondition], a
	ld [NoiseSampleAddress], a
	ld [NoiseSampleAddress + 1], a
	ld [wNoiseSampleDelay], a
	ld [MusicNoiseSampleSet], a
	ret

; e8b79

LoadChannel: ; e8d1b
; prep channel for use
; input:
; 	de:
	; get pointer to current channel
	call LoadMusicByte
	inc de
	and $7 ; bit 0-2 (current channel)
	ld [CurChannel], a
	ld c, a
	ld b, 0
	ld hl, ChannelPointers
	add hl, bc
	add hl, bc
	ld c, [hl]
	inc hl
	ld b, [hl] ; bc = channel pointer
	ld hl, Channel1Flags - Channel1
	add hl, bc
	res SOUND_CHANNEL_ON, [hl] ; channel off
	call ChannelInit
	; load music pointer
	ld hl, Channel1MusicAddress - Channel1
	add hl, bc
	call LoadMusicByte
	ld [hli], a
	inc de
	call LoadMusicByte
	ld [hl], a
	inc de
	; load music id
	ld hl, Channel1MusicID - Channel1
	add hl, bc
	ld a, [MusicID]
	ld [hli], a
	ld a, [MusicID + 1]
	ld [hl], a
	; load music bank
	ld hl, Channel1MusicBank - Channel1
	add hl, bc
	ld a, [MusicBank]
	ld [hl], a
	ret

; e8d5b

ChannelInit: ; e8d5b
; make sure channel is cleared
; set default tempo and note length in case nothing is loaded
; input:
;   bc = channel struct pointer
	push de
	xor a
	; get channel struct location and length
	ld hl, Channel1MusicID - Channel1 ; start
	add hl, bc
	ld e, Channel2 - Channel1 ; channel struct length
	; clear channel
.loop
	ld [hli], a
	dec e
	jr nz, .loop
	; set tempo to default ($100)
	ld hl, Channel1Tempo - Channel1
	add hl, bc
	xor a
	ld [hli], a
	inc a
	ld [hl], a
	; set note length to default ($1) (fast)
	ld hl, Channel1NoteLength - Channel1
	add hl, bc
	ld [hl], a
	pop de
	ret

; e8d76

LoadMusicByte:: ; e8d76
; input:
;   de = current music address
; output:
;   a = CurMusicByte
	ld a, [MusicBank]
	call _LoadMusicByte
	ld a, [CurMusicByte]
	ret

; e8d80


INCLUDE "audio/notes.asm"

INCLUDE "audio/wave_samples.asm"

INCLUDE "audio/drumkits.asm"


GetLRTracks: ; e8fc2
; gets the default sound l/r channels
; stores mono/stereo table in hl
	ld a, Options
	bit STEREO, a
	; made redundant, could have had a purpose in gold
	jr nz, .stereo
	ld hl, MonoTracks
	ret

.stereo
	ld hl, StereoTracks
	ret

; e8fd1

MonoTracks: ; e8fd1
; bit corresponds to track #
; hi: left channel
; lo: right channel
	db $11, $22, $44, $88
; e8fd5

StereoTracks: ; e8fd5
; made redundant
; seems to be modified on a per-song basis
	db $11, $22, $44, $88
; e8fd9

ChannelPointers: ; e8fd9
; music channels
	dw Channel1
	dw Channel2
	dw Channel3
	dw Channel4
; sfx channels
	dw Channel5
	dw Channel6
	dw Channel7
	dw Channel8
; e8fe9

ClearChannels:: ; e8fe9
; runs ClearChannel for all 4 channels
; doesn't seem to be used, but functionally identical to MapSetup_Sound_Off
	ld hl, rNR50
	xor a
	ld [hli], a
	ld [hli], a
	ld a, $80
	ld [hli], a
	ld hl, rNR10
	ld e, NUM_MUSIC_CHANS
.loop
	call ClearChannel
	dec e
	jr nz, .loop
	ret

; e8ffe

ClearChannel: ; e8ffe
; input: hl = beginning hw sound register (rNR10, rNR20, rNR30, rNR40)
; output: 00 00 80 00 80

;   sound channel   1      2      3      4
	xor a
	ld [hli], a ; rNR10, rNR20, rNR30, rNR40 ; sweep = 0

	ld [hli], a ; rNR11, rNR21, rNR31, rNR41 ; length/wavepattern = 0
	ld a, $8
	ld [hli], a ; rNR12, rNR22, rNR32, rNR42 ; envelope = 0
	xor a
	ld [hli], a ; rNR13, rNR23, rNR33, rNR43 ; frequency lo = 0
	ld a, $80
	ld [hli], a ; rNR14, rNR24, rNR34, rNR44 ; restart sound (freq hi = 0)
	ret

; e900a