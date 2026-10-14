//set this to match the sample rate of your speakers
//if you get a message about mismatch audio rate, you'll need
//to adjust your audio settings on the computer, then reboot the
//supercollider audio server

//run this block to initialize things (the orchestra)
(
// p = ProxySpace.push(s);
s.reboot;
s.waitForBoot({
	fork{
		d = ();
		d.requiredSounds = ["Piano_Samples"];

		d.onComplete = {
			fork {
				// Step 1: Load all piano samples into buffers
				~pianoBufs = Dictionary.new;
				~pianoPath = PathName(Platform.userAppSupportDir +/+ "sounds" +/+ "twm_samples" +/+ "Piano_Samples");

				// Load samples numbered 21-108 (MIDI note numbers)
				(21..108).do { |midiNum|
					var path = ~pianoPath.fullPath +/+ (midiNum.asString ++ ".wav");
					path.postln;
					if(File.exists(path), {
						~pianoBufs[midiNum] = Buffer.read(s, path);
						("Loaded: " ++ midiNum ++ ".wav").postln;
					}, {
						("Warning: Missing " ++ midiNum ++ ".wav").postln;
					});
				};

				// {PlayBuf.ar(1,~pianoBufs[21], BufRateScale.kr(~pianoBufs[21]))}.play;

				// Wait for buffers to load
				s.sync;

				// Step 2: Define the SynthDef
				SynthDef(\pianoSynth, {
					arg
					amp = 0.5,
					out = 0,
					pan = 0,
					gate = 1,
					attack = 0.001,
					release = 3,
					bufnum = 0,
					playbackRate = 1;

					var sig, env;

					// Play the buffer with pitch shifting
					sig = PlayBuf.ar(
						numChannels: 1,
						bufnum: bufnum,
						rate: playbackRate * BufRateScale.kr(bufnum),
						trigger: 1,
						startPos: 0,
						loop: 0,
						doneAction: 2
					);

					// Envelope for amplitude control
					env = EnvGen.kr(
						Env.asr(attack, 1, release),
						gate: gate,
						doneAction: 2
					);

					// Apply amplitude and envelope
					sig = sig * amp * env;

					// Pan and output
					sig = Pan2.ar(sig, pan);
					Out.ar(out, sig);
				}).add;

				"Piano synth loaded successfully!".postln;


				~dir = PathName(thisProcess.nowExecutingPath.dirname +/+ "glass_662hz.wav").fullPath;
				//starts sending mouseY values to the client machine
				{SendReply.kr(Impulse.kr(4), '/reply', MouseY.kr(),-1)}.play;

				//sample (must be in the same directory as this patch)
				~b = Buffer.read(s, ~dir);
				//original frequency of sample
				~origFreq = 662;
				"LOADING SOUND SAMPLE".postln;
				s.sync;//allows time for buffer to finish loading (just in case)

				/*
		* in each stratum: 0 - mouse does note control dynamics
		* 1 - mouse does control dynamics
		*/
				~mouseDynamics = [0,0,0,0,0,0];

				/*
		* in each stratum default amp if not controled by mouse
		*/
				~amp = [0.5,0.5,0.5,0.5,0.5,0.5];
				~curAmp = [0.5,0.5,0.5,0.5,0.5,0.5];//used to create lag (gradual dynamic change)



				//don't worry about the synths
				SynthDef(\ln, {
					arg out;
					Out.kr(out, LFNoise2.ar(1 / 3.0));
				}).add;

				SynthDef(\sampleSynth, {
					arg freq, voice = 0, amp, mouseDynamics;
					var sig;
					amp = 0.25 * SelectX.kr(mouseDynamics, [amp, MouseX.kr()]);//no varlag
					sig = amp * PlayBuf.ar(1,~b,BufRateScale.kr(~b) * freq / ~origFreq, doneAction: Done.freeSelf);
					sig = BLowPass4.ar(sig,20000 * (In.kr(6 + (1 + voice) % 6) + 1) / 2);
					Out.ar(4,Pan2.ar(sig, In.kr(6 + voice)));
				}).add;

				SynthDef(\rev, {
					//arg mix = 0.5, room = 0.7, damp = 0.5;
					var sig;
					sig = In.ar(4,2);
					sig = FreeVerb2.ar(sig[0],sig[1],\mix.kr(0.5,2),\room.kr(0.7,2),\damp.kr(0.5,2));
					Out.ar(0,sig);
				}).add;

				SynthDef(\filter, {
					var sig;
					sig = In.ar(4,2);
					sig = BLowPass4.ar(sig, 0 + 20000 * (LFNoise2.kr(1 / 3.0) + 1) / 2);
					Out.ar(0,sig);
				}).add;

				"LOADING SYNTHS".postln;
				s.sync;//allows time for synths to finish loading (just in case)

				/*
		Transforms
		*/
				~transforms = [
					[[ 0,    0],     [0,    0.16]],
					[[ 0.85, 0.04], [-0.04, 0.85]],
					[[ 0.2, -0.26],  [0.23, 0.22]],
					[[-0.15, 0.28],  [0.26, 0.24]]
				];
				~translations = [
					[0, 0],
					[0, 1.6],
					[0, 1.6],
					[0, 0.44]
				];
				~probs = [0.01, 0.85, 0.07, 0.07];

				//gets a scale degree based on previous scale degree
				//using transitional prob. matrix
				~getNextNotes = {
					arg notes;
					var rnd = 1.0.rand, tot = 0, transform, translation, newX, newY;
					i = 0;

					while({tot <= rnd},{
						tot = tot + ~probs[i];
						transform = ~transforms[i];
						translation = ~translations[i];
						i = i + 1;
					});

					newX = (notes.x * transform[0][0]) + (notes.y * transform[0][1]) + translation[0];
					newY = (notes.x * transform[1][0]) + (notes.y * transform[1][1]) + translation[1];

					(x: newX, y: newY);
				};



		/*which note of the scale each
		* stratum starts on
		*/
				~notes = (x: 0, y: 0);

				TempoClock.tempo = 1.0; //1 beat PER SECOND (i.e. quarter = 60

				~rhyth = [
					//rhythmic values used at rate zero (duration in beats)
					[0.1, 0.4/3.0, 0.16, 0.2],
					//rhythmic values used at rate 1 (duration in beats)
					[0.2, 0.3, 0.4],
					//rhythmic values used at rate 2 (duration in beats)
					[2 / 3.0, 0.8, 1]];

				//rate of each voice
				~stratumRate = [0,0,0,0,0,0];

				//an array that will hold the music streams
				~strata = [nil,nil,nil,nil,nil,nil];

				//Assigned values later
				~mouseY = 0;
				~mouseControlsHighestNote = false;
				~mouseControlsLowestNote = false;
				~targetHighest = 96;
				~highestNote = 96;
				~targetLowest = 24;
				~lowestNote = 24;
				~mouseControlsRhythm = false;

				//new variables
				d.scalingFactor = 1;
				~startTime = Main.elapsedTime;
				d.angle = 0;
				~scale = nil;
				d.interpoScale = 0;
				d.bottomRef = 60;
				d.ampScale = 0;
				~rampTo = { |target = 1, duration = 2, symb = \interpoScale, startVal = 'default', curve = \lin|
					if(startVal == 'default'){startVal = d[symb]};//can't use symb in args line
					Routine {
						var startTime = Main.elapsedTime;
						var endTime = startTime + duration;

						while { Main.elapsedTime < endTime } {
							var progress = (Main.elapsedTime - startTime) / duration;
							if(symb == \tempo){
								TempoClock.tempo = startVal.blend(target, progress);
								d[\tempo] = TempoClock.tempo;
							}
							{
								d[symb] = startVal.blend(target, progress);
							};
							0.001.wait;  // Update every 50ms
							// ("PROG:"++progress).postln;
						};
						("DONE"++(targ: target)++", is:"++(d[symb].asString)).postln;
						if(symb == \tempo){
							TempoClock.tempo = target;
							d[\tempo] = TempoClock.tempo;
						}
						{
							d[symb] = target;  // Ensure we hit exact target
						};

					}.play(SystemClock);
				};

				~oscillate = { |low = 0, high = 1, period = 4, symb = \interpoScale, phase = 0, rampDur = 1|

					var task = Routine {
						var startTime = Main.elapsedTime;
						var startVal = d[symb];

						// Calculate the initial target value of the sine wave
						var initialSineVal = sin(phase * 2pi);
						var initialTarget = initialSineVal.linlin(-1, 1, low, high);
						var rampEndTime = startTime + rampDur;

						var oscStartTime = 0;

						// Ramp phase
						while { Main.elapsedTime < rampEndTime } {
							var progress = (Main.elapsedTime - startTime) / rampDur;
							var rampedVal = startVal.blend(initialTarget, progress);
							if(symb == \tempo){
								TempoClock.tempo = rampedVal;
								d[\tempo] = TempoClock.tempo;
							}
							{
								d[symb] = rampedVal;
							};
							0.001.wait;
						};

						// oscillation phase
						oscStartTime = Main.elapsedTime;
						loop {
							var elapsed, cycle, sineVal, mappedVal;
							elapsed = Main.elapsedTime - oscStartTime;
							// Calculate sinusoidal position
							cycle = ((elapsed / period) + phase) * 2pi;
							sineVal = sin(cycle);
							// Map from [-1, 1] to [low, high]
							mappedVal = sineVal.linlin(-1, 1, low, high);
							if(symb == \tempo){
								TempoClock.tempo = mappedVal;
								d[\tempo] = TempoClock.tempo;
							}

							{
								d[symb] = mappedVal;
							};
							0.001.wait;
						};
					}.play(SystemClock);
					// Return the task so it can be stopped
					task;
				};

			/*f = File(thisProcess.nowExecutingPath.dirname +/+ "data.txt", "w");
			g = File(thisProcess.nowExecutingPath.dirname +/+ "normalized.txt", "w");*/
				d.writeData = false;

				{
					var v = 0;
					x = Synth.new(\ln,[\out,v+6]);
					//v.postln;
					~strata[v] = Pbind(
						\instrument, \pianoSynth,
						\pitch, Pfunc({
							var normalized, xCoord, yCoord, theta, rotated, freq1, freq2, freqArr;
							~notes = ~getNextNotes.value(~notes);
							// ~notes.postln;

							xCoord = (~notes.x + 2.2) / 4.9;
							yCoord = ~notes.y / 10.0;

							rotated = Point(xCoord - 0.5, yCoord - 0.5).rotate(d.angle * 2pi).translate(Point(0.5,0.5));
							xCoord = rotated.x;
							yCoord = rotated.y;

							normalized = (x: d.scalingFactor * xCoord, y: d.scalingFactor * yCoord);
							// ("NORM: " ++ normalized).postln;
					/*f.write((Main.elapsedTime - ~startTime).asString ++ "," ++ (~notes.x).asString ++ "," ++ (~notes.y).asString);*/
						/*if(d.writeData){
							f.write("%,%,%\n".format(Main.elapsedTime - ~startTime, ~notes.x, ~notes.y));
							g.write("%,%,%\n".format(Main.elapsedTime - ~startTime, normalized.x, normalized.y));
						};*/

							freq1 = ((normalized.x * 12) + d.bottomRef).midicps;
							freq2 = ((normalized.y * 12) + d.bottomRef).midicps;
							freqArr = [freq1, freq2];

							if(~scale.notNil){
								freqArr = freqArr.collect{
									|freq|
									var midi, oct, pitchClass;
									pitchClass = (freq.cpsmidi % 12);
									midi = ~scale.minItem({|x|
										var dist;
										dist = (x - pitchClass).abs;
										if(dist > 6){dist = 12 - dist};
										dist;
									});
									oct = (freq.cpsmidi / 12).round;
									midi = midi + (oct * 12);
									(d.interpoScale * midi.midicps) + ((1 - d.interpoScale) * freq);
								};
								// ("SCALED ARR:" ++ freqArr).postln;
							};
							freqArr;
						}),
						\bufnum, Pfunc({
							|ev|
							var arr;
							arr = ev[\pitch].collect{
								|freq|
								var targetMidi, closestMidi, playbackRate, bufnum;

								// Convert frequency to MIDI note number
								targetMidi = freq.cpsmidi;

								// Find closest available sample (round to nearest integer)
								closestMidi = targetMidi.round.clip(21, 108);

								// Get the buffer for the closest MIDI note
								bufnum = ~pianoBufs[closestMidi.asInteger];
								bufnum;
							};
							// ("BUFNUMARR: " + arr).postln;
							arr;
						}),
						\playbackRate, Pfunc({
							|ev|
							var arr;
							arr = ev[\pitch].collect{
								|freq|
								var targetMidi, closestMidi, playbackRate, bufnum;

								// Convert frequency to MIDI note number
								targetMidi = freq.cpsmidi;

								// Find closest available sample (round to nearest integer)
								closestMidi = targetMidi.round.clip(21, 108);

								// Get the buffer for the closest MIDI note
								bufnum = ~pianoBufs[closestMidi.asInteger];
								// Calculate playback rate to pitch shift to exact frequency
								// rate = 2^((targetMidi - closestMidi) / 12)
								playbackRate = 2.pow((targetMidi - closestMidi) / 12);
								playbackRate;
							};
							// ("ARR: " + arr).postln;
							arr;
						}),
						\dur, FuncStream({
							var val = ~rhyth[~stratumRate[v]].choose;
							~mouseControlsRhythm.if({
								var prob = [1 - (~mouseY - 0).abs, 1 - (~mouseY - 0.5).abs, 1 - (~mouseY - 1).abs], sum = 0, rnd = 1.0.rand, n = 0;
								prob.do({arg item, i;
									sum = sum + item;
								});
								prob.do({arg item, i;
									prob[i] = item / sum;
								});
								sum = 0;
								while({sum < rnd},
									{
										sum = sum + prob[n];
										n = n + 1;
								});
								//prob.postln;
								val = ~rhyth[~stratumRate[v]][n-1];
								//val.postln;
							});
							val;
						}),
						\out, 4,
						\voice, v,
						\amp, Pfunc({
							|ev|
							var freqArr = ev.pitch, ampArr, pitchClass;

							ampArr = 0.5!2;

							if(~scale.notNil){
								ampArr = freqArr.collect{
									|freq|
									var distance, amp, pitchClass;

									pitchClass = (freq.cpsmidi % 12);
									distance = ~scale.minValue({|x|
										var dist;
										dist = (x - pitchClass).abs;
										if(dist > 6){dist = 12 - dist};
										dist;
									});
									// ("DIST"++distance).postln;
									amp = (1 - (distance / 6.0)).pow(20 * d.ampScale);
									amp * 0.5;
								};


								// ("SCALED ARR:" ++ freqArr).postln;
							};

							ampArr;
						}),
						\mouseDynamics, FuncStream({~mouseDynamics[v]}),
						\addAction, 3,
						\group, x
					).play(quant: 1);
					~strata[v].stop;
				}.value;

				r = Synth.tail(s, \rev);
				x = 3;

				//Receives MouseY messages from the server
				y.free;
				y = OSCFunc.newMatching({ arg msg;
					~mouseY = msg[3];
					// d.interpoScale = msg[3];
				}, '/reply');

				"EVERYTHING IS READY TO PLAY!".postln;

				d.scalingFactor = 4;
				~startTime = Main.elapsedTime;
				//These commmands start (i.e. resume) each stratum
				~strata[0].resume(quant:1);
				// s.record(path: (thisProcess.nowExecutingPath.dirname +/+"myrecording.wav").standardizePath);
				TempoClock.tempo = 2.0;
				d.tempo = 2.0;

				~randOcts = Routine{
					loop{
						~scale = ([0,1,3,4,6,7,9,10] + 3.rand) % 12;
						"NEW OCT".postln;
						(2.5.rand + 0.5).wait;
					}
				}.play(SystemClock);
				~randOcts.stop;


				~randDiat = Routine{
					loop{
						~scale = ([0,2,4,5,7,9,11] + 12.rand) % 12;
						"NEW DIAT".postln;
						(2.5.rand + 0.5).wait;
					}
				}.play(SystemClock);
				~randDiat.stop;

				~randPent = Routine{
					loop{
						~scale = ([0,2,4,7,9] + 12.rand) % 12;
						"NEW PENT".postln;
						(10.0.rand + 5).wait;
					}
				}.play(SystemClock);
				~randPent.stop;
			};
		};
		"dependencies/sample-install.scd".loadRelative;
	}
});
)

~randOcts.reset;
~randOcts.play;

~randOcts.stop;

d.angle = 0.25;
d.scalingFactor = 8;
d.bottomRef = 24;

a = ~oscillate.(0,1,4, \angle);
a.stop;

//cue 1
(
~rampTo.();//start rounding to scale degrees
~scale = [0,2,4,7,9];//penatonic
)

(
~rampTo.(8, 5, \scalingFactor);//expand the range
~rampTo.(12, 5, \bottomRef);
)

(
~randDiat.reset;//start using diatonic scales
~randDiat.play(SystemClock);
)

(
~randDiat.stop;
~randPent.reset;
~randPent.play(SystemClock);
a = ~oscillate.(0,1,8, \angle);//gradually rotate the fern
~rampTo.(8, 60, \tempo);//make the texture denser
d.writeData = false;//stop animating the fern (too many points!)
)


(
~randPent.stop;
~scale = [0,4,7];
~rampTo.(0, 5, \interpoScale);
a = ~oscillate.(0,1,4, \ampScale);
b = ~oscillate.(2,10,4, \tempo);
)
b.stop;


(
~rampTo.(4, 30, \scalingFactor);
~rampTo.(60, 30, \bottomRef);
)

(
~rampTo.(16, 30, \scalingFactor);
~rampTo.(0, 30, \bottomRef);
)


~rampTo.(0, 30, \ampScale);
(
~rampTo.(0, 2, \interpoScale);
~rampTo.(0.9, 2, \ampScale);
~scale = [0,4,7];
)

(
~scale = [0,4,7];
~rampTo.(1, 30, \ampScale);
~rampTo.(8, 30, \tempo);
)

(
// ~scale = [0,4,7];
// ~rampTo.(8, 4, \tempo);
a = ~oscillate.(0,1,4, \ampScale);
b = ~oscillate.(2,10,4, \tempo);
~rampTo.(0, 4, \interpoScale);
)
a.stop;
b.stop;

~randPent.stop;
~randPent.reset;
~randPent.play(SystemClock);

(
~rampTo.(1, 3, \interpoScale);
~scale = [0,2,4,7,9];//penatonic
)

a = ~oscillate.(0,1,4, \interpoScale);

~rampTo.(0, 5, \ampScale);
~rampTo.(2, 5, \tempo);

d.ampScale = 1;
~scale = [0,4,7];
~scale = [3,8,11];
~scale = [3,6,10];
~scale = [2,7,11];

~scale = [3,6,11];
~scale = [2,7,10];


~scale = [3,6,11];
~scale = [2,7,10];
~scale = [0,3,7];
~scale = [4,8,11];
~scale = [0,4,7];

~rampTo.(0.5, 3, \ampScale);

~scale = [0,4,7];
~scale = [0,4,9];
~scale = [0,5,9];
~scale = [2,7,11];


// i - VI - III - VII
~scale = [0,3,7];
~scale = [0,3,8];
~scale = [3,7,10];
~scale = [2,5,10];

~scale = [0,2,4,5,7,9,11,12];//major
~scale = [0,2,3,5,7,8,10,12];//natural minor
~scale = [0,2,3,5,7,9,10,12];//dorian
~scale = [0,1,3,5,7,8,10,12];//phrygian
~scale = [0,2,4,6,7,9,11,12];//lydian
~scale = [0,2,4,5,7,9,10,12];//mixolydian
~scale = [0,1,3,5,6,8,10,12];//locrian
~scale = [0,2,4,6,7,9,10,12];//acoustic

~rampTo.();
~scale = [0,2,4,7,9];//penatonic
~scale = [0,1,3,4,6,7,9,10];//octotonic
~scale = [0,2,3,5,6,8,9,11];//another octotonic
~scale = [0,2,4,6,8,10,12,14];//whole tone (more than an octave, to make it 8 notes)
~scale = [0,1,4,5,8,9,12,13];//hexatonic (more than an octave, to make it 8 notes)

~scale = ([0,1,3,4,6,7,9,10] + 1) % 12;

~rampTo.(1,0);
// f.write("HI");
f.close;
//The score:
/*
* The patch produces 6 strata of musical textures
stratum 0: C3 - C4
stratum 1: C4 - C5
stratum 2: C5 - C6
stratum 3: C6 - C7
stratum 4: C7 - C8
stratum 5: C8 - C9

midi nums 24 - 96
*/


d.scalingFactor = 4;
//These commmands start (i.e. resume) each stratum
~strata[0].resume(quant:1);
~strata[1].resume(quant:1);
~strata[2].resume(quant:1);
~strata[3].resume(quant:1);
~strata[4].resume(quant:1);
~strata[5].resume(quant:1);

//These commmands stop (i.e. pause) each stratum
~strata[0].stop;
~strata[1].stop;
~strata[2].stop;
~strata[3].stop;
~strata[4].stop;
~strata[5].stop;

//The commands below alter a given stratum x,
//replace 'x' with the number stratum you'd like
//to use.

//use these command to set the dynamics of a stratum x
//valid dynamics are 0 - 1. 0 = silence, 1 = full volume
~amp[x] = 0.1; // soft
~amp[x] = 0.5; // medium
~amp[x] = 0.9; // loud
~amp[x] = 0;//fade out to silence

//By the way, to control a parameter for all 6 strata at once, put your command within a loop:
6.do({arg i; ~amp[i] = 0});//fades everything to 0
6.do({arg i; ~strata[i].resume(quant: 1)});//starts all stata
6.do({arg i; ~strata[i].stop});//stops all stata

//use these commands to map the dynamics of a stratum x
//to the horizontal position of your mouse. left = soft, right = loud
~mouseDynamics[x] = 1;//start mapping
~mouseDynamics[x] = 0;//stop mapping

//use these commands to change the rhythmic rate of a
//given stratum x. Valid rates are integers 0 - 2.
~stratumRate[x] = 0; // fast
~stratumRate[x] = 1; // medium
~stratumRate[x] = 2; // slow

//use these commands to change the tempo. The tempo is
//measured in beats per second, not PBM. so 2 means quarter = 120
TempoClock.tempo = 1.0; // 60 pbm
TempoClock.tempo = 2.0; // 120 pbm
TempoClock.tempo = 80/60; // 80 pbm

//use these commnands to change the scale.
// your scale isn't 8 notes (including the octave)
//you should adjust the ~transMatrix too
//the scales below don't require any change to ~transMatrix


/*
*You can compress the range of the whole texture, using the mouse's height.
*This will set the lowest allowed note or highest allowed note. Notes out side of
*the range will be transposed by octaves.
*Use the commands below to turn this feature on and off.
*/
~mouseControlsLowestNote = true; //turns it on
~mouseControlsLowestNote = false; //turns it off
~mouseControlsHighestNote = true; //turns it on
~mouseControlsHighestNote = false; //turns it off

/*
* You can use the mouse to make small adustmest to the rhythmic denisty.
* Use these commands to turn this on and off
*/
~mouseControlsRhythm = true;
~mouseControlsRhythm = false;

/*
*You can change the transitional probabilities to vary the texture.
*Here are some examples.
*/

//Only stepwise
(
~transMatrix = [
	[0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
	[0.5, 0.0, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0],
	[0.0, 0.5, 0.0, 0.5, 0.0, 0.0, 0.0, 0.0],
	[0.0, 0.0, 0.5, 0.0, 0.5, 0.0, 0.0, 0.0],
	[0.0, 0.0, 0.0, 0.5, 0.0, 0.5, 0.0, 0.0],
	[0.0, 0.0, 0.0, 0.0, 0.5, 0.0, 0.5, 0.0],
	[0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.0, 0.5],
	[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0],
];
)

//Trills (more static)
(
~transMatrix = [
	[0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
	[0.95, 0.0, 0.05, 0.0, 0.0, 0.0, 0.0, 0.0],
	[0.0, 0.05, 0.0, 0.95, 0.0, 0.0, 0.0, 0.0],
	[0.0, 0.0, 0.95, 0.0, 0.05, 0.0, 0.0, 0.0],
	[0.0, 0.0, 0.0, 0.05, 0.0, 0.95, 0.0, 0.0],
	[0.0, 0.0, 0.0, 0.0, 0.95, 0.0, 0.05, 0.0],
	[0.0, 0.0, 0.0, 0.0, 0.0, 0.05, 0.0, 0.95],
	[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0],
];
)

//Thirds Trills (more static)
(
~transMatrix = [
	[0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0],
	[0.05, 0.0, 0.0, 0.95, 0.0, 0.0, 0.0, 0.0],
	[0.95, 0.0, 0.0, 0.05, 0.0, 0.0, 0.0, 0.0],
	[0.0, 0.95, 0.0, 0.0, 0.05, 0.0, 0.0, 0.0],
	[0.0, 0.0, 0.0, 0.05, 0.0, 0.0, 0.95, 0.0],
	[0.0, 0.0, 0.0, 0.0, 0.05, 0.0, 0.0, 0.95],
	[0.0, 0.0, 0.0, 0.0, 0.95, 0.0, 0.0, 0.05],
	[0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0],
];
)

//default
(
~transMatrix = [
	[0.0, 0.1, 0.2, 0.1, 0.3, 0.1, 0.1, 0.1],
	[0.3, 0.0, 0.3, 0.1, 0.1, 0.1, 0.1, 0.0],
	[0.3, 0.1, 0.0, 0.1, 0.2, 0.1, 0.1, 0.1],
	[0.1, 0.0, 0.5, 0.0, 0.1, 0.2, 0.0, 0.1],
	[0.3, 0.1, 0.2, 0.1, 0.0, 0.1, 0.1, 0.2],
	[0.2, 0.0, 0.2, 0.2, 0.1, 0.0, 0.1, 0.2],
	[0.0, 0.2, 0.0, 0.0, 0.2, 0.1, 0.0, 0.5],
	[0.1, 0.1, 0.2, 0.1, 0.3, 0.1, 0.1, 0.0],
];
)

/*
* Adjust the reverb
*/
r.set(\room, 0.7, \mix, 0.5, \damp, 0.5); // default
r.set(\mix, 0); // dry
r.set(\room, 1, \mix, 1, \damp, 1);//drench it

/*to make a cue, put several commands together, one after the other
* with an open and closed parathesis above and below respectively.
* Be sure to label your cues with a name (e.g. cue 1, cue 2, etc).
*
*In the example below, a softer, more static section begins in a new
* mode by
* adusting several parameters at once.
*/

// Cue 7
(
~strata[1].resume(quant:1);
~strata[2].resume(quant:1);
~strata[3].resume(quant:1);
~strata[4].resume(quant:1);
~strata[5].resume(quant:1);

~mouseControlsHighestNote = true;
~transMatrix = [
	[0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
	[0.95, 0.0, 0.05, 0.0, 0.0, 0.0, 0.0, 0.0],
	[0.0, 0.05, 0.0, 0.95, 0.0, 0.0, 0.0, 0.0],
	[0.0, 0.0, 0.95, 0.0, 0.05, 0.0, 0.0, 0.0],
	[0.0, 0.0, 0.0, 0.05, 0.0, 0.95, 0.0, 0.0],
	[0.0, 0.0, 0.0, 0.0, 0.95, 0.0, 0.05, 0.0],
	[0.0, 0.0, 0.0, 0.0, 0.0, 0.05, 0.0, 0.95],
	[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0],
];
~scale = [0,2,4,6,7,9,10,12];
r.set(\room, 0.7, \mix, 0.9, \damp, 0.5);
~stratumRate[5] = 1;
~stratumRate[4] = 1;
~stratumRate[3] = 0;
~stratumRate[2] = 0;
~stratumRate[1] = 0;
~amp[5] = 0.1;
~amp[4] = 0.1;
~amp[3] = 0.1;
~amp[2] = 0.1;
~amp[1] = 0.1;
~amp[0] = 0.0;
)


// To play a midi mockup or other sound file alongside your markov patch,
// put the sound file in the same folder as this patch and run this.
// set the fileName variable to the name of your file and set stereo
// to false (all lower case, no quotes) if your file is mono (right
// click the file and check its properties / info).
// To start the sound part way through set startTime to the number of
// seconds in that you want to start.
(
{
	var fileName = "YOUR FILE NAME IN QUOTES.wav",//any standard sound format, include extension, but not path
	stereo = true,//set to false for mono files
	startTime = 0,//number of seconds in to start

	dir = PathName(thisProcess.nowExecutingPath.dirname +/+ fileName).fullPath,
	buff = Buffer.read(s, dir, action: {
		~mockupSound = {
			var sig, chan = 1;
			if(stereo){chan = 2};
			sig = PlayBuf.ar(chan, buff, BufRateScale.kr(buff), startPos: startTime * buff.sampleRate);
			if(stereo.not){sig = sig.dup};
			sig;
		}.play;
	});
}.value;
)

//To stop the sound after running the above:
~mockupSound.free;