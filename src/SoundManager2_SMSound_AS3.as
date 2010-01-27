﻿/*
   SoundManager 2: Javascript Sound for the Web
   ----------------------------------------------
   http://schillmania.com/projects/soundmanager2/

   Copyright (c) 2007, Scott Schiller. All rights reserved.
   Code licensed under the BSD License:
   http://www.schillmania.com/projects/soundmanager2/license.txt

   Flash 9 / ActionScript 3 version
*/

package {

  import flash.external.*;
  import flash.events.*;
  import flash.display.Sprite;
  import flash.display.StageDisplayState;
  import flash.display.StageScaleMode;
  import flash.display.StageAlign;
  import flash.geom.Rectangle;
  import flash.media.Sound;
  import flash.media.SoundChannel;
  import flash.media.SoundLoaderContext;
  import flash.media.SoundTransform;
  import flash.media.SoundMixer;
  import flash.media.Video;
  import flash.net.URLRequest;
  import flash.utils.ByteArray;
  import flash.net.NetConnection;
  import flash.net.NetStream;

  public class SoundManager2_SMSound_AS3 extends Sound {

    public var sm: SoundManager2_AS3 = null;
    // externalInterface references (for Javascript callbacks)
    public var baseJSController: String = "soundManager";
    public var baseJSObject: String = baseJSController + ".sounds";
    public var soundChannel: SoundChannel = new SoundChannel();
    public var urlRequest: URLRequest;
    public var soundLoaderContext: SoundLoaderContext;
    public var waveformData: ByteArray = new ByteArray();
    public var waveformDataArray: Array = [];
    public var eqData: ByteArray = new ByteArray();
    public var eqDataArray: Array = [];
    public var usePeakData: Boolean = false;
    public var useWaveformData: Boolean = false;
    public var useEQData: Boolean = false;
    public var sID: String;
    public var sURL: String;
    public var justBeforeFinishOffset: int;
    public var didJustBeforeFinish: Boolean;
    public var didFinish: Boolean;
    public var loaded: Boolean;
    public var connected: Boolean;
    public var failed: Boolean;
    public var paused: Boolean;
    public var duration: Number;
    public var totalBytes: Number;
    public var handledDataError: Boolean = false;
    public var ignoreDataError: Boolean = false;

    public var lastValues: Object = {
      bytes: 0,
      position: 0,
      volume: 100,
      pan: 0,
      nLoops: 1,
      leftPeak: 0,
      rightPeak: 0,
      waveformDataArray: null,
      eqDataArray: null,
      isBuffering: null
    };
    public var didLoad: Boolean = false;
    public var sound: Sound = new Sound();

    public var cc: Object;
    public var nc: NetConnection;
    public var ns: NetStream;
    public var st: SoundTransform;
    public var useNetstream: Boolean;
    public var useVideo: Boolean = false;
    public var bufferTime: Number = -1;
    public var lastNetStatus: String = null;
    public var serverUrl: String = null;

    public var oVideo: Video = null;
    public var videoWidth: Number = 0;
    public var videoHeight: Number = 0;

    public function SoundManager2_SMSound_AS3(oSoundManager: SoundManager2_AS3, sIDArg: String = null, sURLArg: String = null, usePeakData: Boolean = false, useWaveformData: Boolean = false, useEQData: Boolean = false, useNetstreamArg: Boolean = false, useVideo: Boolean = false, netStreamBufferTime: Number = -1, serverUrl: String = null, duration: Number = 0, totalBytes: Number = 0) {
      this.sm = oSoundManager;
      this.sID = sIDArg;
      this.sURL = sURLArg;
      this.usePeakData = usePeakData;
      this.useWaveformData = useWaveformData;
      this.useEQData = useEQData;
      this.urlRequest = new URLRequest(sURLArg);
      this.justBeforeFinishOffset = 0;
      this.didJustBeforeFinish = false;
      this.didFinish = false; // non-MP3 formats only
      this.loaded = false;
      this.connected = false;
      this.failed = false;
      this.soundChannel = null;
      this.lastNetStatus = null;
      this.useNetstream = useNetstreamArg;
      this.serverUrl = serverUrl;
      this.duration = duration;
      this.totalBytes = totalBytes;
      this.useVideo = useVideo;
      this.bufferTime = netStreamBufferTime;
      writeDebug('in SoundManager2_SMSound_AS3, got duration '+duration+' and totalBytes '+totalBytes);

      if (this.useNetstream) {
        this.cc = new Object();
        this.nc = new NetConnection();

        // Handle FMS bandwidth check callback.
        // @see onBWDone
        // @see http://www.adobe.com/devnet/flashmediaserver/articles/dynamic_stream_switching_04.html
        // @see http://www.johncblandii.com/index.php/2007/12/fms-a-quick-fix-for-missing-onbwdone-onfcsubscribe-etc.html
        this.nc.client = this;

        // TODO: security/IO error handling
        // this.nc.addEventListener(SecurityErrorEvent.SECURITY_ERROR, doSecurityError);
        // this.nc.addEventListener(IOErrorEvent.IO_ERROR, doIOError);
        nc.addEventListener(NetStatusEvent.NET_STATUS, netStatusHandler);

        writeDebug('Got server URL: '+ this.serverUrl);
        if (this.serverUrl != null) {
          writeDebug('NetConnection: connecting to server ' + this.serverUrl + '...');
        }
        this.nc.connect(serverUrl);
      } else {
        this.connected = true;
      }
    }

    private function netStatusHandler(event:NetStatusEvent):void {
      switch (event.info.code) {
        case "NetConnection.Connect.Success":

          writeDebug('NetConnection: connected');
          try {
            this.ns = new NetStream(this.nc);
            this.ns.checkPolicyFile = true;
            // bufferTime reference: http://livedocs.adobe.com/flash/9.0/ActionScriptLangRefV3/flash/net/NetStream.html#bufferTime
            if (this.bufferTime != -1) {
              this.ns.bufferTime = this.bufferTime; // set to 0.1 or higher. 0 is reported to cause playback issues with static files.
            }
            this.st = new SoundTransform();
            this.cc.onMetaData = this.metaDataHandler;
            this.ns.client = this.cc;
            this.ns.receiveAudio(true);
            if (this.useVideo) {
              this.oVideo = new Video();
              this.ns.receiveVideo(true);
              this.sm.stage.addEventListener(Event.RESIZE, this.resizeHandler);
              this.oVideo.smoothing = true; // http://livedocs.adobe.com/flash/9.0/ActionScriptLangRefV3/flash/media/Video.html#smoothing
              this.oVideo.visible = false; // hide until metadata received
              this.sm.addChild(this.oVideo);
              this.oVideo.attachNetStream(this.ns);
              writeDebug('setting video w/h to stage: ' + this.sm.stage.stageWidth + 'x' + this.sm.stage.stageHeight);
              this.oVideo.width = this.sm.stage.stageWidth;
              this.oVideo.height = this.sm.stage.stageHeight;
            }
            this.connected = true;
            ExternalInterface.call(this.sm.baseJSObject + "['" + this.sID + "']._onconnect", 1);
          } catch(e: Error) {
            this.failed = true;
            writeDebug('netStream error: ' + e.toString());
          }
          break;

        case "NetStream.Play.StreamNotFound":
          this.failed = true;
          writeDebug("NetConnection: Stream not found!");
          ExternalInterface.call(this.sm.baseJSObject + "['" + this.sID + "']._onconnect", 0);
          break;

        default:
          this.failed = true;
          writeDebug("NetConnection: got unhandled code '" + event.info.code + "'!");
          ExternalInterface.call(this.sm.baseJSObject + "['" + this.sID + "']._onconnect", 0);
          break;
      }
    }

    public function resizeHandler(e: Event) : void {
      // scale video to stage dimensions
      // probably less performant than using native flash scaling, but that doesn't quite seem to work. I'm probably missing something simple.
      this.oVideo.width = this.sm.stage.stageWidth;
      this.oVideo.height = this.sm.stage.stageHeight;
    }

    public function writeDebug(s: String, bTimestamp: Boolean = false) : Boolean {
      return this.sm.writeDebug(s, bTimestamp); // defined in main SM object
    }

    public function doNetStatus(e: NetStatusEvent) : void {
      writeDebug('netStatusEvent: ' + e.info.code);
    }

    public function metaDataHandler(infoObject: Object) : void {
      /*
    var data:String = new String();
    for (var prop:* in infoObject) {
    data += prop+': '+infoObject[prop]+' ';
    }
    ExternalInterface.call('soundManager._writeDebug','Metadata: '+data);
    */
      if (this.oVideo) {
        // set dimensions accordingly
        if (!infoObject.width && !infoObject.height) {
          writeDebug('No width/height specified');
          infoObject.width = 0;
          infoObject.height = 0;
        }
        writeDebug('video dimensions: ' + infoObject.width + 'x' + infoObject.height + ' (w/h)');
        this.videoWidth = infoObject.width;
        this.videoHeight = infoObject.height;
        // implement a subset of metadata to pass over EI bridge
        // some formats have extra stuff, eg. "aacaot", "avcprofile"
        // http://livedocs.adobe.com/flash/9.0/main/wwhelp/wwhimpl/common/html/wwhelp.htm?context=LiveDocs_Parts&file=00000267.html
        var oMeta: Object = new Object();
        var item: Object = null;
        for (item in infoObject) {
          // exclude seekpoints for now, presumed not useful and overly large.
          if (item != 'seekpoints') {
            oMeta[item] = infoObject[item];
          }
        }
        ExternalInterface.call(baseJSObject + "['" + this.sID + "']._onmetadata", oMeta);
        writeDebug('showing video for ' + this.sID);
        this.oVideo.visible = true; // show ze video!
      }
      if (!this.loaded) {
        ExternalInterface.call(baseJSObject + "['" + this.sID + "']._whileloading", this.bytesLoaded, (this.bytesTotal || this.totalBytes), (infoObject.duration || this.duration));
      }
      this.duration = infoObject.duration * 1000;
      // null this out for the duration of this object's existence.
      // it may be called multiple times.
      this.cc.onMetaData = function (infoObject: Object) : void {}

    }

    public function getWaveformData() : void {
      // http://livedocs.adobe.com/flash/9.0/ActionScriptLangRefV3/flash/media/SoundMixer.html#computeSpectrum()
      SoundMixer.computeSpectrum(this.waveformData, false, 0); // sample wave data at 44.1 KHz
      this.waveformDataArray = [];
      for (var i: int = 0, j: int = this.waveformData.length / 4; i < j; i++) { // get all 512 values (256 per channel)
        this.waveformDataArray.push(int(this.waveformData.readFloat() * 1000) / 1000);
      }
    }

    public function getEQData() : void {
      // http://livedocs.adobe.com/flash/9.0/ActionScriptLangRefV3/flash/media/SoundMixer.html#computeSpectrum()
      SoundMixer.computeSpectrum(this.eqData, true, 0); // sample EQ data at 44.1 KHz
      this.eqDataArray = [];
      for (var i: int = 0, j: int = this.eqData.length / 4; i < j; i++) { // get all 512 values (256 per channel)
        this.eqDataArray.push(int(this.eqData.readFloat() * 1000) / 1000);
      }
    }

    public function start(nMsecOffset: int, nLoops: int) : void {
      this.sm.currentObject = this; // reference for video, full-screen
      if (this.useNetstream) {
        writeDebug('start: seeking to ' + nMsecOffset);
        this.cc.onMetaData = this.metaDataHandler;
        this.ns.seek(nMsecOffset);
        if (this.paused) {
          this.ns.resume(); // get the sound going again
          if (!this.didLoad) this.didLoad = true;
        } else if (!this.didLoad) {
          this.ns.play(this.sURL);
          this.didLoad = true;
        }
        // this.ns.addEventListener(Event.SOUND_COMPLETE, _onfinish);
        this.applyTransform();
      } else {
        this.soundChannel = this.play(nMsecOffset, nLoops);
        this.addEventListener(Event.SOUND_COMPLETE, _onfinish);
        this.applyTransform();
      }
    }

    private function _onfinish() : void {
      this.removeEventListener(Event.SOUND_COMPLETE, _onfinish);
    }

    public function loadSound(sURL: String, bStream: Boolean) : void {
      if (this.useNetstream) {
        if (this.didLoad != true) {
          ExternalInterface.call('loadSound(): loading ' + this.sURL);
          this.ns.play(this.sURL);
          this.didLoad = true;
        }
        // this.addEventListener(Event.SOUND_COMPLETE, _onfinish);
        this.applyTransform();
      } else {
        try {
          this.didLoad = true;
          this.urlRequest = new URLRequest(sURL);
          this.soundLoaderContext = new SoundLoaderContext(1000, true); // check for policy (crossdomain.xml) file on remote domains - http://livedocs.adobe.com/flash/9.0/ActionScriptLangRefV3/flash/media/SoundLoaderContext.html
          this.load(this.urlRequest, this.soundLoaderContext);
        } catch(e: Error) {
          writeDebug('error during loadSound(): ' + e.toString());
        }
      }
    }

    public function setVolume(nVolume: Number) : void {
      this.lastValues.volume = nVolume / 100;
      this.applyTransform();
    }

    public function setPan(nPan: Number) : void {
      this.lastValues.pan = nPan / 100;
      this.applyTransform();
    }

    public function applyTransform() : void {
      var st: SoundTransform = new SoundTransform(this.lastValues.volume, this.lastValues.pan);
      if (this.useNetstream) {
        this.ns.soundTransform = st;
      } else if (this.soundChannel) {
        this.soundChannel.soundTransform = st; // new SoundTransform(this.lastValues.volume, this.lastValues.pan);
      }
    }

    // Handle FMS bandwidth check callback.
    // @see http://www.adobe.com/devnet/flashmediaserver/articles/dynamic_stream_switching_04.html
    // @see http://www.johncblandii.com/index.php/2007/12/fms-a-quick-fix-for-missing-onbwdone-onfcsubscribe-etc.html
    public function onBWDone():void{
      writeDebug('onBWDone: called and ignored');
    }
  }

}
