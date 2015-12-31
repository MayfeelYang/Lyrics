//
//  AppController.swift
//  Lyrics
//
//  Created by Eru on 15/11/10.
//  Copyright © 2015年 Eru. All rights reserved.
//

import Cocoa
import ScriptingBridge

class AppController: NSObject, NSUserNotificationCenterDelegate {
    
    //Singleton
    static let sharedAppController = AppController()
    
    @IBOutlet weak var statusBarMenu: NSMenu!
    @IBOutlet weak var lyricsDelayView: NSView!
    @IBOutlet weak var delayMenuItem: NSMenuItem!
    @IBOutlet weak var lyricsModeMenuItem: NSMenuItem!
    @IBOutlet weak var lyricsHeightMenuItem: NSMenuItem!
    
    var timeDly:Int = 0
    var timeDlyInFile:Int = 0
    
    private var isTrackingThreadRunning = false
    private var hasDiglossiaLrc:Bool = false
    private var lyricsWindow:LyricsWindowController!
    private var menuBarLyrics:MenuBarLyrics!
    private var lyricsEidtWindow:LyricsEditWindowController!
    private var statusItem:NSStatusItem!
    private var lyricsArray:[LyricsLineModel]!
    private var idTagsArray:[NSString]!
    private var vox:VoxBridge!
    private var currentLyrics: NSString!
    private var currentSongID:NSString!
    private var currentSongTitle:NSString!
    private var currentArtist:NSString!
    private var songList:[SongInfos]!
    private var qianqian:QianQian!
    private var xiami:Xiami!
    private var ttpod:TTPod!
    private var geciMe:GeCiMe!
    private var qqMusic:QQMusic!
    private var lrcSourceHandleQueue:NSOperationQueue!
    private var userDefaults:NSUserDefaults!
    private var timer: NSTimer!
    private var regexForTimeTag: NSRegularExpression!
    private var regexForIDTag: NSRegularExpression!
    
// MARK: - Init & deinit
    override init() {
        super.init()
        vox = VoxBridge()
        lyricsArray = Array()
        idTagsArray = Array()
        songList = Array()
        qianqian = QianQian()
        xiami = Xiami()
        ttpod = TTPod()
        geciMe = GeCiMe()
        qqMusic = QQMusic()
        userDefaults = NSUserDefaults.standardUserDefaults()
        lrcSourceHandleQueue = NSOperationQueue()
        lrcSourceHandleQueue.maxConcurrentOperationCount = 1
        
        NSBundle(forClass: object_getClass(self)).loadNibNamed("StatusMenu", owner: self, topLevelObjects: nil)
        setupStatusItem()
        
        lyricsWindow=LyricsWindowController()
        lyricsWindow.showWindow(nil)
        
        if userDefaults.boolForKey(LyricsMenuBarLyricsEnabled) {
            menuBarLyrics = MenuBarLyrics()
        }
        // check lrc saving path
        if !userDefaults.boolForKey(LyricsDisableAllAlert) && !checkSavingPath() {
            let alert: NSAlert = NSAlert()
            alert.messageText = NSLocalizedString("ERROR_OCCUR", comment: "")
            alert.informativeText = NSLocalizedString("PATH_IS_NOT_DIR", comment: "")
            alert.addButtonWithTitle(NSLocalizedString("OPEN_PREFS", comment: ""))
            alert.addButtonWithTitle(NSLocalizedString("IGNORE", comment: ""))
            let response: NSModalResponse = alert.runModal()
            if response == NSAlertFirstButtonReturn {
                showPreferences(nil)
            }
        }
    
        let nc = NSNotificationCenter.defaultCenter()
        nc.addObserver(self, selector: "lrcLoadingCompleted:", name: LrcLoadedNotification, object: nil)
        nc.addObserver(self, selector: "handleUserEditLyrics:", name: LyricsUserEditLyricsNotification, object: nil)
        
        let ndc = NSDistributedNotificationCenter.defaultCenter()
        ndc.addObserver(self, selector: "voxPlayerInfoChanged:", name: "com.coppertino.Vox.trackChanged", object: nil)
        ndc.addObserver(self, selector: "handleExtenalLyricsEvent:", name: "ExtenalLyricsEvent", object: nil)
        
        do {
            regexForTimeTag = try NSRegularExpression(pattern: "\\[[0-9]+:[0-9]+.[0-9]+\\]|\\[[0-9]+:[0-9]+\\]", options: [])
        } catch let theError as NSError {
            NSLog("%@", theError.localizedDescription)
            return
        }
        //the regex below should only use when the string doesn't contain time-tags
        //because all time-tags would be matched as well.
        do {
            regexForIDTag = try NSRegularExpression(pattern: "\\[.*:.*\\]", options: [])
        } catch let theError as NSError {
            NSLog("%@", theError.localizedDescription)
            return
        }
        
        currentLyrics = "LyricsVox"
        isTrackingThreadRunning = true
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) { () -> Void in
            self.voxTrackingThread()
        }
        
        if vox.running() && vox.playing() {
            currentSongID = vox.currentPersistentID().copy() as! NSString
            currentSongTitle = vox.currentTitle().copy() as! NSString
            currentArtist = vox.currentArtist().copy() as! NSString
            
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) { () -> Void in
                self.handleSongChange()
            }
        } else {
            currentSongID = ""
            currentSongTitle = ""
            currentArtist = ""
        }
    }
    
    deinit {
        NSStatusBar.systemStatusBar().removeStatusItem(statusItem)
        NSNotificationCenter.defaultCenter().removeObserver(self)
        NSDistributedNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    private func setupStatusItem() {
        let icon:NSImage = NSImage(named: "status_icon")!
        icon.template = true
        statusItem = NSStatusBar.systemStatusBar().statusItemWithLength(NSSquareStatusItemLength)
        statusItem.menu = statusBarMenu
        if #available(OSX 10.10, *) {
            statusItem.button?.image = icon
        } else {
            statusItem.image = icon
            statusItem.highlightMode = true
        }
    
        delayMenuItem.view = lyricsDelayView
        lyricsDelayView.autoresizingMask = [.ViewWidthSizable]
        if userDefaults.boolForKey(LyricsIsVerticalLyrics) {
            lyricsModeMenuItem.title = NSLocalizedString("HORIZONTAL", comment: "")
        } else {
            lyricsModeMenuItem.title = NSLocalizedString("VERTICAL", comment: "")
        }
    }
    
    private func checkSavingPath() -> Bool{
        let savingPath:NSString
        if userDefaults.integerForKey(LyricsSavingPathPopUpIndex) == 0 {
            savingPath = NSSearchPathForDirectoriesInDomains(.MusicDirectory, [.UserDomainMask], true).first! + "/LyricsX"
        } else {
            savingPath = userDefaults.stringForKey(LyricsUserSavingPath)!
        }
        let fm: NSFileManager = NSFileManager.defaultManager()
        
        var isDir: ObjCBool = false
        if fm.fileExistsAtPath(savingPath as String, isDirectory: &isDir) {
            if !isDir {
                return false
            }
        } else {
            do {
                try fm.createDirectoryAtPath(savingPath as String, withIntermediateDirectories: true, attributes: nil)
            } catch let theError as NSError{
                NSLog("%@", theError.localizedDescription)
            }
        }
        return true
    }
    
// MARK: - Interface Methods
    
    @IBAction func handleWorkSpaceChange(sender:AnyObject?) {
        //before finding the way to detect full screen, user should adjust lyrics by selves
        lyricsWindow.isFullScreen = !lyricsWindow.isFullScreen
        if lyricsWindow.isFullScreen {
            lyricsHeightMenuItem.title = NSLocalizedString("HIGHER_LYRICS", comment: "")
        } else {
            lyricsHeightMenuItem.title = NSLocalizedString("LOWER_LYRICS", comment: "")
        }
        dispatch_async(dispatch_get_main_queue()) { () -> Void in
            self.lyricsWindow.reflash()
        }
    }
    
    @IBAction func enableDesktopLyrics(sender:AnyObject?) {
        if (sender as! NSMenuItem).state == NSOnState {
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                self.lyricsWindow.displayLyrics(nil, secondLyrics: nil)
            })
        } else {
            //Force lyrics to show(handlePositionChange: method will update it if lyrics changed.)
            currentLyrics = nil
        }
    }
    
    @IBAction func enableMenuBarLyrics(sender:AnyObject?) {
        if (sender as! NSMenuItem).state == NSOnState {
            menuBarLyrics = nil
        } else {
            menuBarLyrics = MenuBarLyrics()
            menuBarLyrics.displayLyrics(currentLyrics as String)
        }
    }
    
    @IBAction func changeLyricsMode(sender:AnyObject?) {
        let isVertical = !userDefaults.boolForKey(LyricsIsVerticalLyrics)
        userDefaults.setObject(NSNumber(bool: isVertical), forKey: LyricsIsVerticalLyrics)
        if isVertical {
            lyricsModeMenuItem.title = NSLocalizedString("HORIZONTAL", comment: "")
        } else {
            lyricsModeMenuItem.title = NSLocalizedString("VERTICAL", comment: "")
        }
        dispatch_async(dispatch_get_main_queue()) { () -> Void in
            self.lyricsWindow.reflash()
        }
    }
    
    @IBAction func showPreferences(sender:AnyObject?) {
        let prefs = AppPrefsWindowController.sharedPrefsWindowController()
        if !(prefs.window?.visible)! {
            prefs.showWindow(nil)
        }
        prefs.window?.makeKeyAndOrderFront(nil)
        NSApp.activateIgnoringOtherApps(true)
    }
    
    @IBAction func checkForUpdate(sender: AnyObject) {
        NSWorkspace.sharedWorkspace().openURL(NSURL(string: "https://github.com/MichaelRow/Lyrics/releases")!)
    }
    
    @IBAction func searchLyricsAndArtworks(sender: AnyObject?) {
        let appPath = NSBundle.mainBundle().bundlePath + "/Contents/Library/LrcSeeker.app"
        NSWorkspace.sharedWorkspace().launchApplication(appPath)
    }
    
    @IBAction func copyLyricsToPb(sender: AnyObject?) {
        if lyricsArray.count == 0 {
            MessageWindowController.sharedMsgWindow.displayMessage(NSLocalizedString("OPERATION_FAILED", comment: ""))
            return
        }
        let theLyrics: NSMutableString = NSMutableString()
        for lrc in lyricsArray {
            theLyrics.appendString(lrc.lyricsSentence as String + "\n")
        }
        let pb = NSPasteboard.generalPasteboard()
        pb.clearContents()
        pb.writeObjects([theLyrics])
        MessageWindowController.sharedMsgWindow.displayMessage(NSLocalizedString("COPYED_TO_PB", comment: ""))
    }
    
    @IBAction func copyLyricsWithTagsToPb(sender: AnyObject) {
        let lrcContents = readLocalLyrics()
        if lrcContents != nil && lrcContents != "" {
            let pb = NSPasteboard.generalPasteboard()
            pb.clearContents()
            pb.writeObjects([lrcContents!])
            MessageWindowController.sharedMsgWindow.displayMessage(NSLocalizedString("COPYED_TO_PB", comment: ""))
        } else {
            MessageWindowController.sharedMsgWindow.displayMessage(NSLocalizedString("OPERATION_FAILED", comment: ""))
        }
    }
    
    @IBAction func makeLrc(sender: AnyObject?) {
        let appPath = NSBundle.mainBundle().bundlePath + "/Contents/Library/LrcMaker.app"
        NSWorkspace.sharedWorkspace().launchApplication(appPath)
    }
    
    @IBAction func mergeLrc(sender: AnyObject) {
        let appPath = NSBundle.mainBundle().bundlePath + "/Contents/Library/LrcMerger.app"
        NSWorkspace.sharedWorkspace().launchApplication(appPath)
    }
    
    @IBAction func editLyrics(sender: AnyObject?) {
        var lrcContents = readLocalLyrics()
        if lrcContents == nil {
            lrcContents = ""
        }
        if lyricsEidtWindow == nil {
            lyricsEidtWindow = LyricsEditWindowController()
        }
        lyricsEidtWindow.setLyricsContents(lrcContents! as String, songID: currentSongID, songTitle: currentSongTitle, andArtist: currentArtist)
        if !(lyricsEidtWindow.window?.visible)! {
            lyricsEidtWindow.showWindow(nil)
        }
        lyricsEidtWindow.window?.makeKeyAndOrderFront(nil)
        NSApp.activateIgnoringOtherApps(true)
    }
    
    @IBAction func importLrcFile(sender: AnyObject) {
        let songTitle: String = currentSongTitle.copy() as! String
        let artist: String = currentArtist.copy() as! String
        let songID: String = currentSongID.copy() as! String
        let panel: NSOpenPanel = NSOpenPanel()
        panel.allowedFileTypes = ["lrc", "txt"]
        panel.extensionHidden = false
        if panel.runModal() == NSFileHandlingPanelOKButton {
            let lrcContents: NSString!
            do {
                lrcContents = try NSString(contentsOfURL: panel.URL!, encoding: NSUTF8StringEncoding)

            } catch let theError as NSError {
                lrcContents = nil
                NSLog("%@", theError.localizedDescription)
                
                // Error must be the text encoding thing.
                if !userDefaults.boolForKey(LyricsDisableAllAlert) {
                    let alert: NSAlert = NSAlert()
                    alert.messageText = NSLocalizedString("UNSUPPORTED_ENCODING", comment: "")
                    alert.informativeText = NSLocalizedString("ONLY_UTF8", comment: "")
                    alert.addButtonWithTitle(NSLocalizedString("OK", comment: ""))
                    alert.runModal()
                }
                return
            }
            if lrcContents != nil && testLrc(lrcContents) {
                lrcSourceHandleQueue.cancelAllOperations()
                lrcSourceHandleQueue.addOperationWithBlock({ () -> Void in
                    //make the current lrc the better one so that it can't be replaced.
                    if songID == self.currentSongID {
                        self.parsingLrc(lrcContents)
                        self.hasDiglossiaLrc = true
                    }
                    self.saveLrcToLocal(lrcContents, songTitle: songTitle, artist: artist)
                })
            }
        }
    }
    
    @IBAction func exportLrcFile(sender: AnyObject) {
        let savingPath: NSString
        if userDefaults.integerForKey(LyricsSavingPathPopUpIndex) == 0 {
            savingPath = NSSearchPathForDirectoriesInDomains(.MusicDirectory, [.UserDomainMask], true).first! + "/LyricsX"
        } else {
            savingPath = userDefaults.stringForKey(LyricsUserSavingPath)!
        }
        let songTitle:String = currentSongTitle.stringByReplacingOccurrencesOfString("/", withString: "&")
        let artist:String = currentArtist.stringByReplacingOccurrencesOfString("/", withString: "&")
        let lrcFilePath = savingPath.stringByAppendingPathComponent("\(songTitle) - \(artist).lrc")
        
        let panel: NSSavePanel = NSSavePanel()
        panel.allowedFileTypes = ["lrc","txt"]
        panel.nameFieldStringValue = (lrcFilePath as NSString).lastPathComponent as String
        panel.extensionHidden = false
        
        if panel.runModal() == NSFileHandlingPanelOKButton {
            let fm = NSFileManager.defaultManager()
            if fm.fileExistsAtPath(panel.URL!.path!) {
                do {
                    try fm.removeItemAtURL(panel.URL!)
                } catch let theError as NSError {
                    NSLog("%@", theError.localizedDescription)
                }
            }
            do {
                try fm.copyItemAtPath(lrcFilePath, toPath: panel.URL!.path!)
            } catch let theError as NSError {
                NSLog("%@", theError.localizedDescription)
            }
        }
    }
    
    @IBAction func wrongLyrics(sender: AnyObject) {
        if !userDefaults.boolForKey(LyricsDisableAllAlert) {
            let alert: NSAlert = NSAlert()
            alert.messageText = NSLocalizedString("CONFIRM_MARK_WRONG", comment: "")
            alert.informativeText = NSLocalizedString("CANT_UNDONE", comment: "")
            alert.addButtonWithTitle(NSLocalizedString("CANCEL", comment: ""))
            alert.addButtonWithTitle(NSLocalizedString("MARK", comment: ""))
            let response: NSModalResponse = alert.runModal()
            if response == NSAlertFirstButtonReturn {
                return
            }
        }
        let wrongLyricsTag: String = NSLocalizedString("WRONG_LYRICS", comment: "")
        lyricsArray.removeAll()
        currentLyrics = nil
        dispatch_async(dispatch_get_main_queue()) { () -> Void in
            self.lyricsWindow.displayLyrics(nil, secondLyrics: nil)
        }
        saveLrcToLocal(wrongLyricsTag, songTitle: currentSongTitle, artist: currentArtist)
    }
    
// MARK: - Vox Events
    
    private func voxTrackingThread() {
        var currentPosition: Int = 0
        while !vox.running() {
            NSThread.sleepForTimeInterval(1.5)
        }
        
        while true {
            if vox.running() {
                if vox.playing() {
                    if lyricsArray.count != 0 {
                        currentPosition = vox.playerPosition()
                        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), { () -> Void in
                            self.handlePositionChange(currentPosition)
                        })
                    }
                } else {
                    //Pause
                    if userDefaults.boolForKey(LyricsDisabledWhenPaused) {
                        if currentLyrics != nil {
                            currentLyrics = nil
                            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                                self.lyricsWindow.displayLyrics(nil, secondLyrics: nil)
                            })
                        }
                    }
                }
            }
            else {
                //Check whether terminate.
                if userDefaults.boolForKey(LyricsQuitWithVox) {
                    NSApp.terminate(nil)
                    return
                }
                if currentLyrics != nil {
                    currentLyrics = nil
                    dispatch_async(dispatch_get_main_queue(), { () -> Void in
                        self.lyricsWindow.displayLyrics(nil, secondLyrics: nil)
                    })
                }
                isTrackingThreadRunning = false
                return
            }
            NSThread.sleepForTimeInterval(0.2)
        }
    }
    
    
    func voxPlayerInfoChanged (n:NSNotification){
        // check whether song is changed
        if !isTrackingThreadRunning {
            isTrackingThreadRunning = true
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), { () -> Void in
                self.voxTrackingThread()
            })
        }
        if currentSongID == vox.currentPersistentID() {
            return
        } else {
            //if time-Delay for the previous song is changed, we should save the change to lrc file.
            //Save time-Delay laziely for better I/O performance.
            if timeDly != timeDlyInFile {
                handleLrcDelayChange()
            }
            
            lyricsArray.removeAll()
            idTagsArray.removeAll()
            self.setValue(0, forKey: "timeDly")
            timeDlyInFile = 0
            currentLyrics = nil
            lyricsWindow.displayLyrics(nil, secondLyrics: nil)
            currentSongID = vox.currentPersistentID().copy() as! NSString
            currentSongTitle = vox.currentTitle().copy() as! NSString
            currentArtist = vox.currentArtist().copy() as! NSString
            NSLog("Song Changed to: %@",currentSongTitle)
            handleSongChange()
        }
    }

    
// MARK: - Lrc Methods
    
    private func parsingLrc(theLrcContents:NSString) {
        // Parse lrc file to get lyrics, time-tags and time offset
        NSLog("Start to Parse lrc")
        lyricsArray.removeAll()
        idTagsArray.removeAll()
        self.setValue(0, forKey: "timeDly")
        timeDlyInFile = 0
        let lrcContents: NSString
        
        // whether convert Chinese type
        if userDefaults.boolForKey(LyricsAutoConvertChinese) {
            switch userDefaults.integerForKey(LyricsChineseTypeIndex) {
            case 0:
                lrcContents = convertToSC(theLrcContents)
            case 1:
                lrcContents = convertToTC(theLrcContents)
            case 2:
                lrcContents = convertToTC_Taiwan(theLrcContents)
            case 3:
                lrcContents = convertToTC_HK(theLrcContents)
            default:
                lrcContents = theLrcContents
                break
            }
        } else {
            lrcContents = theLrcContents
        }
        let newLineCharSet: NSCharacterSet = NSCharacterSet.newlineCharacterSet()
        let lrcParagraphs: NSArray = lrcContents.componentsSeparatedByCharactersInSet(newLineCharSet)
        
        for str in lrcParagraphs {
            let timeTagsMatched: NSArray = regexForTimeTag.matchesInString(str as! String, options: [.ReportProgress], range: NSMakeRange(0, str.length))
            if timeTagsMatched.count > 0 {
                let index: Int = (timeTagsMatched.lastObject?.range.location)! + (timeTagsMatched.lastObject?.range.length)!
                let lyricsSentence: NSString = str.substringFromIndex(index)
                for result in timeTagsMatched {
                    let matched:NSRange = result.range
                    let lrcLine: LyricsLineModel = LyricsLineModel()
                    lrcLine.lyricsSentence = lyricsSentence
                    lrcLine.setMsecPositionWithTimeTag(str.substringWithRange(matched))
                    let currentCount: Int = lyricsArray.count
                    var j: Int
                    for j=0; j<currentCount; ++j {
                        if lrcLine.msecPosition < lyricsArray[j].msecPosition {
                            lyricsArray.insert(lrcLine, atIndex: j)
                            break
                        }
                    }
                    if j == currentCount {
                        lyricsArray.append(lrcLine)
                    }
                }
            }
            else {
                let theMatchedRange: NSRange = regexForIDTag.rangeOfFirstMatchInString(str as! String, options: [.ReportProgress], range: NSMakeRange(0, str.length))
                if theMatchedRange.length == 0 {
                    continue
                }
                let theIDTag: NSString = str.substringWithRange(theMatchedRange)
                let colonRange: NSRange = theIDTag.rangeOfString(":")
                let idStr: NSString = theIDTag.substringWithRange(NSMakeRange(1, colonRange.location-1))
                if idStr.stringByReplacingOccurrencesOfString(" ", withString: "") != "offset" {
                    idTagsArray.append(str as! NSString)
                    continue
                }
                else {
                    let delayStr: NSString=theIDTag.substringWithRange(NSMakeRange(colonRange.location+1, theIDTag.length-colonRange.length-colonRange.location-1))
                    self.setValue(delayStr.integerValue, forKey: "timeDly")
                    timeDlyInFile = timeDly
                }
            }
        }
    }
    
    
    private func testLrc(lrcFileContents: NSString) -> Bool {
        // test whether the string is lrc
        let newLineCharSet: NSCharacterSet = NSCharacterSet.newlineCharacterSet()
        let lrcParagraphs: NSArray = lrcFileContents.componentsSeparatedByCharactersInSet(newLineCharSet)
        let regexForTimeTag: NSRegularExpression
        do {
            regexForTimeTag = try NSRegularExpression(pattern: "\\[[0-9]+:[0-9]+.[0-9]+\\]|\\[[0-9]+:[0-9]+\\]", options: [.CaseInsensitive])
        } catch let theError as NSError {
            NSLog("%@", theError.localizedDescription)
            return false
        }
        var numberOfMatched: Int = 0
        for str in lrcParagraphs {
            numberOfMatched = regexForTimeTag.numberOfMatchesInString(str as! String, options: [.ReportProgress], range: NSMakeRange(0, str.length))
            if numberOfMatched > 0 {
                return true
            }
        }
        return false
    }
    
    private func readLocalLyrics() -> NSString? {
        let savingPath: NSString
        if userDefaults.integerForKey(LyricsSavingPathPopUpIndex) == 0 {
            savingPath = NSSearchPathForDirectoriesInDomains(.MusicDirectory, [.UserDomainMask], true).first! + "/LyricsX"
        } else {
            savingPath = userDefaults.stringForKey(LyricsUserSavingPath)!
        }
        let songTitle:String = currentSongTitle.stringByReplacingOccurrencesOfString("/", withString: "&")
        let artist:String = currentArtist.stringByReplacingOccurrencesOfString("/", withString: "&")
        let lrcFilePath = savingPath.stringByAppendingPathComponent("\(songTitle) - \(artist).lrc")
        if  NSFileManager.defaultManager().fileExistsAtPath(lrcFilePath) {
            let lrcContents: NSString?
            do {
                lrcContents = try NSString(contentsOfFile: lrcFilePath, encoding: NSUTF8StringEncoding)
            } catch {
                lrcContents = nil
                NSLog("Failed to load lrc")
            }
            return lrcContents
        } else {
            return nil
        }
    }

    private func saveLrcToLocal (lyricsContents: NSString, songTitle: NSString, artist: NSString) {
        let savingPath:NSString
        if userDefaults.integerForKey(LyricsSavingPathPopUpIndex) == 0 {
            savingPath = NSSearchPathForDirectoriesInDomains(.MusicDirectory, [.UserDomainMask], true).first! + "/LyricsX"
        } else {
            savingPath = userDefaults.stringForKey(LyricsUserSavingPath)!
        }
        let fm: NSFileManager = NSFileManager.defaultManager()
        
        var isDir: ObjCBool = false
        if fm.fileExistsAtPath(savingPath as String, isDirectory: &isDir) {
            if !isDir {
                return
            }
        } else {
            do {
                try fm.createDirectoryAtPath(savingPath as String, withIntermediateDirectories: true, attributes: nil)
            } catch let theError as NSError{
                NSLog("%@", theError.localizedDescription)
                return
            }
        }
        
        let titleForSaving = songTitle.stringByReplacingOccurrencesOfString("/", withString: "&")
        let artistForSaving = artist.stringByReplacingOccurrencesOfString("/", withString: "&")
        let lrcFilePath = savingPath.stringByAppendingPathComponent("\(titleForSaving) - \(artistForSaving).lrc")
        
        if fm.fileExistsAtPath(lrcFilePath) {
            do {
                try fm.removeItemAtPath(lrcFilePath)
            } catch let theError as NSError {
                NSLog("%@", theError.localizedDescription)
                return
            }
        }
        do {
            try lyricsContents.writeToFile(lrcFilePath, atomically: false, encoding: NSUTF8StringEncoding)
        } catch let theError as NSError {
            NSLog("%@", theError.localizedDescription)
        }
    }

// MARK: - Handle Events
    
    func handlePositionChange (playerPosition: Int) {
        let tempLyricsArray = lyricsArray
        var index: Int
        //1.Find the first lyrics which time position is larger than current position, and its index is "index"
        //2.The index of first-line-lyrics which needs to display is "index - 1"
        for index=0; index < tempLyricsArray.count; ++index {
            if playerPosition < tempLyricsArray[index].msecPosition - timeDly {
                if index-1 == -1 {
                    if currentLyrics != nil {
                        currentLyrics = nil
                        if userDefaults.boolForKey(LyricsDesktopLyricsEnabled) {
                            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                                self.lyricsWindow.displayLyrics(nil, secondLyrics: nil)
                            })
                        }
                        if menuBarLyrics != nil {
                            menuBarLyrics.displayLyrics(nil)
                        }
                    }
                    return
                }
                else {
                    var secondLyrics: NSString!
                    if currentLyrics != tempLyricsArray[index-1].lyricsSentence {
                        currentLyrics = tempLyricsArray[index-1].lyricsSentence
                        if userDefaults.boolForKey(LyricsDesktopLyricsEnabled) {
                            if userDefaults.boolForKey(LyricsTwoLineMode) && userDefaults.integerForKey(LyricsTwoLineModeIndex)==0 && index < tempLyricsArray.count {
                                if tempLyricsArray[index].lyricsSentence != "" {
                                    secondLyrics = tempLyricsArray[index].lyricsSentence
                                }
                            }
                            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                                self.lyricsWindow.displayLyrics(self.currentLyrics, secondLyrics: secondLyrics)
                            })
                        }
                        if menuBarLyrics != nil {
                            menuBarLyrics.displayLyrics(currentLyrics as String)
                        }
                    }
                    return
                }
            }
        }
        if index == tempLyricsArray.count && tempLyricsArray.count>0 {
            if currentLyrics != tempLyricsArray[tempLyricsArray.count - 1].lyricsSentence {
                currentLyrics = tempLyricsArray[tempLyricsArray.count - 1].lyricsSentence
                if userDefaults.boolForKey(LyricsDesktopLyricsEnabled) {
                    dispatch_async(dispatch_get_main_queue(), { () -> Void in
                        self.lyricsWindow.displayLyrics(self.currentLyrics, secondLyrics: nil)
                    })
                }
                if menuBarLyrics != nil {
                    menuBarLyrics.displayLyrics(currentLyrics as String)
                }
            }
        }
    }
    
    func handleSongChange() {
        //load lyrics for the song which is about to play
        let lrcContents: NSString? = readLocalLyrics()
        if lrcContents != nil {
            parsingLrc(lrcContents!)
            if lyricsArray.count != 0 {
                return
            }
        }
        lrcSourceHandleQueue.cancelAllOperations()
        
        //Search in the Net if local lrc is nil or invalid
        let loadingSongID: String = currentSongID.copy() as! String
        let loadingArtist: String = currentArtist.copy() as! String
        let loadingTitle: String = currentSongTitle.copy() as! String
        hasDiglossiaLrc = false
        
        let artistForSearching: String = self.delSpecificSymbol(loadingArtist) as String
        let titleForSearching: String = self.delSpecificSymbol(loadingTitle) as String
        
        //千千静听不支持繁体中文搜索，先转成简体中文。搜歌词组件参数是Vox中显示的歌曲名
        //歌手名以及Vox的唯一编号（防止歌曲变更造成的歌词对错歌），以及用于搜索用的歌曲
        //名与歌手名。另外，天天动听只会获取歌词文本，其他歌词源都是获取歌词URL
        qianqian.getLyricsWithTitle(loadingTitle, artist: loadingArtist, songID: loadingSongID, titleForSearching: convertToSC(titleForSearching) as String, andArtistForSearching: convertToSC(artistForSearching) as String)
        xiami.getLyricsWithTitle(loadingTitle, artist: loadingArtist, songID: loadingSongID, titleForSearching: titleForSearching, andArtistForSearching: artistForSearching)
        ttpod.getLyricsWithTitle(loadingTitle, artist: loadingArtist, songID: loadingSongID, titleForSearching: titleForSearching, andArtistForSearching: artistForSearching)
        geciMe.getLyricsWithTitle(loadingTitle, artist: loadingArtist, songID: loadingSongID, titleForSearching: titleForSearching, andArtistForSearching: artistForSearching)
        qqMusic.getLyricsWithTitle(loadingTitle, artist: loadingArtist, songID: loadingSongID, titleForSearching: titleForSearching, andArtistForSearching: artistForSearching)
    }
    
    func handleUserEditLyrics(n: NSNotification) {
        let userInfo: [NSObject:AnyObject] = n.userInfo!
        let lyrics: String = self.lyricsEidtWindow.textView.string!
        
        if testLrc(lyrics) {
            //User lrc has the highest priority level
            lrcSourceHandleQueue.cancelAllOperations()
            lrcSourceHandleQueue.addOperationWithBlock { () -> Void in
                if (userInfo["SongID"] as! String) == self.currentSongID {
                    //make the current lrc the better one so that it can't be replaced.
                    self.hasDiglossiaLrc = true
                    self.parsingLrc(lyrics)
                }
                self.saveLrcToLocal(lyrics, songTitle: userInfo["SongTitle"] as! String, artist: userInfo["SongArtist"] as! String)
            }
        }
    }
    
    func handleExtenalLyricsEvent (n:NSNotification) {
        let userInfo = n.userInfo
        NSLog("Recieved notification from %@",userInfo!["Sender"] as! String)
        
        //no playing track?
        if currentSongID == "" {
            let notification: NSUserNotification = NSUserNotification()
            notification.title = NSLocalizedString("NO_PLAYING_TRACK", comment: "")
            notification.informativeText = NSLocalizedString("IGNORE_LYRICS", comment: "")
            NSUserNotificationCenter.defaultUserNotificationCenter().deliverNotification(notification)
            return
        }
        //User lrc has the highest priority level
        lrcSourceHandleQueue.cancelAllOperations()
        lrcSourceHandleQueue.addOperationWithBlock { () -> Void in
            let lyricsContents: String = userInfo!["LyricsContents"] as! String
            if self.testLrc(lyricsContents) {
                self.parsingLrc(lyricsContents)
                //make the current lrc the better one so that it can't be replaced.
                self.hasDiglossiaLrc = true
                self.saveLrcToLocal(lyricsContents, songTitle: self.currentSongTitle, artist: self.currentArtist)
            }
        }
    }
    
    func handleLrcDelayChange () {
        //save the delay change to file.
        if lyricsArray.count == 0{
            return
        }
        let theLyrics: NSMutableString = NSMutableString()
        for idtag in idTagsArray {
            theLyrics.appendString((idtag as String) + "\n")
        }
        theLyrics.appendString("[offset:\(timeDly)]\n")
        for lrc in lyricsArray {
            theLyrics.appendString((lrc.timeTag as String) + (lrc.lyricsSentence as String) + "\n")
        }
        if lyricsArray.count > 0 {
            theLyrics.deleteCharactersInRange(NSMakeRange(theLyrics.length-1, 1))
        }
        NSLog("Writing the time delay to file")
        saveLrcToLocal(theLyrics, songTitle: currentSongTitle, artist: currentArtist)
    }
    
// MARK: - Lyrics Source Loading Completion

    func lrcLoadingCompleted(n: NSNotification) {
        // we should run the handle thread one by one in the queue of maxConcurrentOperationCount =1
        let userInfo = n.userInfo
        let source: Int = userInfo!["source"]!.integerValue
        let songTitle: String = userInfo!["title"] as! String
        let artist: String = userInfo!["artist"] as! String
        let songID: String = userInfo!["songID"] as! String
        let serverLrcs: [SongInfos]
        switch source {
        case 1:
            serverLrcs = (self.qianqian.currentSongs as NSArray).copy() as! [SongInfos]
        case 2:
            serverLrcs = (self.xiami.currentSongs as NSArray).copy() as! [SongInfos]
        case 3:
            let info: SongInfos = self.ttpod.songInfos.copy() as! SongInfos
            if info.lyric == "" {
                return
            } else {
                serverLrcs = [info]
            }
        case 4:
            serverLrcs = (self.geciMe.currentSongs as NSArray).copy() as! [SongInfos]
        case 5:
            serverLrcs = (self.qqMusic.currentSongs as NSArray).copy() as! [SongInfos]
        default:
            return;
        }
        if serverLrcs.count > 0 {
            lrcSourceHandleQueue.addOperationWithBlock({ () -> Void in
                self.handleLrcURLDownloaded(serverLrcs, songTitle: songTitle, artist: artist, songID: songID)
            })
        }
    }
    
    
    private func handleLrcURLDownloaded(serverLrcs: [SongInfos], songTitle:String, artist:NSString, songID:NSString) {
        // alread has lyrics, check if user needs a better one.
        if lyricsArray.count > 0 {
            if userDefaults.boolForKey(LyricsSearchForDiglossiaLrc) {
                if hasDiglossiaLrc {
                    return
                }
            } else {
                return
            }
        }
        
        var lyricsContents: NSString! = nil
        for lrc in serverLrcs {
            if isDiglossiaLrc(lrc.songTitle + lrc.artist) {
                if lrc.lyric != nil {
                    lyricsContents = lrc.lyric
                }
                else if lrc.lyricURL != nil {
                    do {
                        lyricsContents = try NSString(contentsOfURL: NSURL(string: lrc.lyricURL)!, encoding: NSUTF8StringEncoding)
                    } catch let theError as NSError{
                        NSLog("%@", theError.localizedDescription)
                        lyricsContents = nil
                        continue
                    }
                }
                break
            }
        }
        if lyricsContents == nil && lyricsArray.count > 0 {
            return
        }
        
        var hasLrc: Bool
        if lyricsContents == nil || !testLrc(lyricsContents) {
            NSLog("better lrc not found or it's not lrc file,trying others")
            hasLrc = false
            lyricsContents = nil
            hasDiglossiaLrc = false
            for lrc in serverLrcs {
                if lrc.lyric != nil {
                    lyricsContents = lrc.lyric
                }
                else if lrc.lyricURL != nil {
                    do {
                        lyricsContents = try NSString(contentsOfURL: NSURL(string: lrc.lyricURL)!, encoding: NSUTF8StringEncoding)
                    } catch let theError as NSError{
                        NSLog("%@", theError.localizedDescription)
                        lyricsContents = nil
                        continue
                    }
                }
                if lyricsContents != nil && testLrc(lyricsContents) {
                    hasLrc = true
                    break
                }
            }
        } else {
            hasLrc = true
            hasDiglossiaLrc = true
        }
        if hasLrc {
            if songID == currentSongID {
                parsingLrc(lyricsContents)
            }
            saveLrcToLocal(lyricsContents, songTitle: songTitle, artist: artist)
        }
    }
    
// MARK: - Shortcut Events
    
    func increaseTimeDly() {
        self.willChangeValueForKey("timeDly")
        timeDly+=100
        if timeDly > 10000 {
            timeDly = 10000
        }
        self.didChangeValueForKey("timeDly")
        let message:String = NSString(format: NSLocalizedString("OFFSET", comment: ""), timeDly) as String
        MessageWindowController.sharedMsgWindow.displayMessage(message)
    }
    
    func decreaseTimeDly() {
        self.willChangeValueForKey("timeDly")
        timeDly-=100
        if timeDly < -10000 {
            timeDly = -10000
        }
        self.didChangeValueForKey("timeDly")
        let message:String = NSString(format: NSLocalizedString("OFFSET", comment: ""), timeDly) as String
        MessageWindowController.sharedMsgWindow.displayMessage(message)
    }
    
    func switchDesktopMenuBarMode() {
        let isDesktopLyricsOn = userDefaults.boolForKey(LyricsDesktopLyricsEnabled)
        let isMenuBarLyricsOn = userDefaults.boolForKey(LyricsMenuBarLyricsEnabled)
        if isDesktopLyricsOn && isMenuBarLyricsOn {
            userDefaults.setBool(false, forKey: LyricsMenuBarLyricsEnabled)
            MessageWindowController.sharedMsgWindow.displayMessage(NSLocalizedString("DESKTOP_ON", comment: ""))
            menuBarLyrics = nil
        }
        else if isDesktopLyricsOn && !isMenuBarLyricsOn {
            userDefaults.setBool(false, forKey: LyricsDesktopLyricsEnabled)
            userDefaults.setBool(true, forKey: LyricsMenuBarLyricsEnabled)
            MessageWindowController.sharedMsgWindow.displayMessage(NSLocalizedString("MENU_BAR_ON", comment: ""))
            lyricsWindow.displayLyrics(nil, secondLyrics: nil)
            menuBarLyrics = MenuBarLyrics()
            menuBarLyrics.displayLyrics(currentLyrics as String)
        }
        else {
            userDefaults.setBool(true, forKey: LyricsDesktopLyricsEnabled)
            MessageWindowController.sharedMsgWindow.displayMessage(NSLocalizedString("BOTH_ON", comment: ""))
            currentLyrics = nil
        }
    }
    
// MARK: - Other Methods
    
    private func isDiglossiaLrc(serverSongTitle: NSString) -> Bool {
        if serverSongTitle.rangeOfString("中").location != NSNotFound || serverSongTitle.rangeOfString("对照").location != NSNotFound || serverSongTitle.rangeOfString("双").location != NSNotFound {
            return true
        }
        return false
    }
    
    private func delSpecificSymbol(input: NSString) -> NSString {
        let specificSymbol: [String] = [
            ",", ".", "'", "\"", "`", "~", "!", "@", "#", "$", "%", "^", "&", "＆", "*", "(", ")", "（", "）", "，",
            "。", "“", "”", "‘", "’", "?", "？", "！", "/", "[", "]", "{", "}", "<", ">", "=", "-", "+", "×",
            "☆", "★", "√", "～"
        ]
        let output: NSMutableString = input.mutableCopy() as! NSMutableString
        for symbol in specificSymbol {
            output.replaceOccurrencesOfString(symbol, withString: " ", options: [], range: NSMakeRange(0, output.length))
        }
        return output
    }
    
}

