// DualPerc Engine
// Two independent PolyPerc-style voices

Engine_DualPerc : CroneEngine {
    var pg;

    // LEFT voice params
    var amp_l = 0.3;
    var release_l = 0.5;
    var pw_l = 0.5;
    var cutoff_l = 1000;
    var gain_l = 2;

    // RIGHT voice params
    var amp_r = 0.3;
    var release_r = 0.5;
    var pw_r = 0.5;
    var cutoff_r = 1000;
    var gain_r = 2;

    *new { arg context, doneCallback;
        ^super.new(context, doneCallback);
    }

    alloc {
        pg = ParGroup.tail(context.xg);

        // LEFT SynthDef
        SynthDef("DualPerc_left", {
            arg out, freq = 440, pw = 0.5, amp = 0.3, cutoff = 1000, gain = 2, release = 0.5;
            var snd = Pulse.ar(freq, pw);
            var filt = MoogFF.ar(snd, cutoff, gain);
            var env = Env.perc(level: amp, releaseTime: release).kr(2);
            Out.ar(out, (filt * env).dup);
        }).add;

        // RIGHT SynthDef
        SynthDef("DualPerc_right", {
            arg out, freq = 440, pw = 0.5, amp = 0.3, cutoff = 1000, gain = 2, release = 0.5;
            var snd = Pulse.ar(freq, pw);
            var filt = MoogFF.ar(snd, cutoff, gain);
            var env = Env.perc(level: amp, releaseTime: release).kr(2);
            Out.ar(out, (filt * env).dup);
        }).add;

        // LEFT commands
        this.addCommand("hz_left", "f", { arg msg;
            var val = msg[1];
            Synth("DualPerc_left", [
                \out, context.out_b,
                \freq, val,
                \pw, pw_l,
                \amp, amp_l,
                \cutoff, cutoff_l,
                \gain, gain_l,
                \release, release_l
            ], target: pg);
        });

        this.addCommand("amp_left", "f", { arg msg; amp_l = msg[1]; });
        this.addCommand("pw_left", "f", { arg msg; pw_l = msg[1]; });
        this.addCommand("release_left", "f", { arg msg; release_l = msg[1]; });
        this.addCommand("cutoff_left", "f", { arg msg; cutoff_l = msg[1]; });
        this.addCommand("gain_left", "f", { arg msg; gain_l = msg[1]; });

        // RIGHT commands
        this.addCommand("hz_right", "f", { arg msg;
            var val = msg[1];
            Synth("DualPerc_right", [
                \out, context.out_b,
                \freq, val,
                \pw, pw_r,
                \amp, amp_r,
                \cutoff, cutoff_r,
                \gain, gain_r,
                \release, release_r
            ], target: pg);
        });

        this.addCommand("amp_right", "f", { arg msg; amp_r = msg[1]; });
        this.addCommand("pw_right", "f", { arg msg; pw_r = msg[1]; });
        this.addCommand("release_right", "f", { arg msg; release_r = msg[1]; });
        this.addCommand("cutoff_right", "f", { arg msg; cutoff_r = msg[1]; });
        this.addCommand("gain_right", "f", { arg msg; gain_r = msg[1]; });
    }
}
