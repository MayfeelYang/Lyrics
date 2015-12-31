//
//  AppDelegate.swift
//  Lyrics
//
//  Created by Eru on 15/11/6.
//  Copyright © 2015年 Eru. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationDidFinishLaunching(aNotification: NSNotification) {
        let userSavingPath: NSString = NSSearchPathForDirectoriesInDomains(.DownloadsDirectory, [.UserDomainMask], true).first! 
        
        let userDefaults: [String:AnyObject] = [
            //Menu
            LyricsDesktopLyricsEnabled : NSNumber(bool: true),
            LyricsMenuBarLyricsEnabled : NSNumber(bool: false),
            LyricsIsVerticalLyrics : NSNumber(bool: false),
            
            //General Preferences Defaults
            LyricsSavingPathPopUpIndex : NSNumber(integer: 0),
            LyricsUserSavingPath : userSavingPath,
            LyricsAutoLaunches : NSNumber(bool: true),
            LyricsLaunchTpyePopUpIndex : NSNumber(integer: 1),
            LyricsServerIndex : NSNumber(integer: 0),
            LyricsQuitWithVox : NSNumber(bool: false),
            LyricsDisableAllAlert : NSNumber(bool: false),
            LyricsUseAutoLayout : NSNumber(bool: true),
            LyricsHeightFromDockToLyrics : NSNumber(integer: 15),
            LyricsConstToLeft : NSNumber(integer: 50),
            LyricsConstToBottom : NSNumber(integer: 100),
            LyricsConstWidth : NSNumber(integer: 1000),
            LyricsConstHeight : NSNumber(integer: 60),
            
            //Lyrics Preferences Defaults
            LyricsAutoConvertChinese : NSNumber(bool: false),
            LyricsVerticalLyricsPosition : NSNumber(integer: 1),
            LyricsChineseTypeIndex : NSNumber(integer: 0),
            LyricsTwoLineMode : NSNumber(bool: true),
            LyricsTwoLineModeIndex : NSNumber(integer: 0),
            LyricsDisabledWhenPaused : NSNumber(bool: true),
            LyricsDisabledWhenSreenShot : NSNumber(bool: true),
            LyricsSearchForDiglossiaLrc : NSNumber(bool: true),
            LyricsDisplayInAllSpaces: NSNumber(bool: true),
            
            //Font and Color Preferences Defaults
            LyricsFontName : "HannotateSC-W7",
            LyricsFontSize : NSNumber(float: 36),
            LyricsShadowModeEnable : NSNumber(bool: true),
            LyricsTextColor : NSKeyedArchiver.archivedDataWithRootObject(NSColor.whiteColor()),
            LyricsBackgroundColor : NSKeyedArchiver.archivedDataWithRootObject(NSColor(calibratedWhite: 0, alpha: 0.5)),
            LyricsShadowColor : NSKeyedArchiver.archivedDataWithRootObject(NSColor.yellowColor()),
            LyricsShadowRadius : NSNumber(float: 4),
            LyricsBgHeightINCR : NSNumber(float: 0),
            LyricsYOffset : NSNumber(float: 0)
        ]
        
        NSUserDefaults.standardUserDefaults().registerDefaults(userDefaults)
        
        NSColorPanel.sharedColorPanel().showsAlpha = true
        
        let lyricsXHelpers = NSRunningApplication.runningApplicationsWithBundleIdentifier("Eru.LyricsVox-Helper")
        for helper in lyricsXHelpers {
            helper.forceTerminate()
        }
        
        // Force Singleton to init
        AppController.sharedAppController
        // Force Prefs to load and setup shortcuts
        let prefs = AppPrefsWindowController.sharedPrefsWindowController()
        prefs.showWindow(nil)
        prefs.window?.orderOut(nil)
    }
    
    func applicationWillTerminate(aNotification: NSNotification) {
        let appController = AppController.sharedAppController
        if appController.timeDly != appController.timeDlyInFile {
            NSLog("App terminating, saveing lrc time delay change...")
            appController.handleLrcDelayChange()
        }
        
        let userDefaults = NSUserDefaults.standardUserDefaults()
        if userDefaults.boolForKey(LyricsAutoLaunches) {
            if userDefaults.integerForKey(LyricsLaunchTpyePopUpIndex) != 0 {
                let helperPath = NSBundle.mainBundle().bundlePath + "/Contents/Library/LoginItems/LyricsVox Helper.app"
                NSWorkspace.sharedWorkspace().launchApplication(helperPath)
            }
        }
        
        //Terminate LrcSeeker
        let lrcSeekers = NSRunningApplication.runningApplicationsWithBundleIdentifier("Eru.LrcSeeker")
        for ls in lrcSeekers {
            ls.terminate()
        }
    }

}

