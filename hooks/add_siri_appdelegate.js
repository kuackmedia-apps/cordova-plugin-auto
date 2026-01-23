#!/usr/bin/env node

'use strict';

const fs = require('fs');
const path = require('path');

module.exports = function(context) {
    console.log('Running add_siri_appdelegate hook...');

    const projectRoot = context.opts.projectRoot;
    const iosPath = path.join(projectRoot, 'platforms', 'ios');

    if (!fs.existsSync(iosPath)) {
        console.log('iOS platform not found, skipping Siri AppDelegate modification');
        return;
    }

    // Find the project name by looking for .xcodeproj directory
    const files = fs.readdirSync(iosPath);
    const xcodeprojFile = files.find(f => f.endsWith('.xcodeproj'));
    
    if (!xcodeprojFile) {
        console.log('Could not find .xcodeproj file, skipping Siri AppDelegate modification');
        return;
    }
    
    const projectName = xcodeprojFile.replace('.xcodeproj', '');
    console.log('Found project:', projectName);

    // ========================================
    // STEP 1: Add Siri entitlement to .entitlements file
    // ========================================
    addSiriEntitlement(iosPath, projectName);
    
    // ========================================
    // STEP 2: Modify AppDelegate
    // ========================================
    modifyAppDelegate(iosPath, projectName);
};

function addSiriEntitlement(iosPath, projectName) {
    // Find entitlements files
    const possibleEntitlementsPaths = [
        path.join(iosPath, projectName, 'Entitlements-Debug.plist'),
        path.join(iosPath, projectName, 'Entitlements-Release.plist'),
        path.join(iosPath, projectName, `${projectName}.entitlements`),
        path.join(iosPath, projectName, 'Resources', `${projectName}.entitlements`)
    ];
    
    for (const entPath of possibleEntitlementsPaths) {
        if (fs.existsSync(entPath)) {
            try {
                let content = fs.readFileSync(entPath, 'utf8');
                
                // Check if Siri entitlement already exists
                if (content.includes('com.apple.developer.siri')) {
                    console.log(`Siri entitlement already exists in ${path.basename(entPath)}`);
                    continue;
                }
                
                // Add Siri entitlement before </dict>
                const siriEntitlement = `\t<key>com.apple.developer.siri</key>\n\t<true/>\n`;
                content = content.replace('</dict>', siriEntitlement + '</dict>');
                
                fs.writeFileSync(entPath, content, 'utf8');
                console.log(`Added Siri entitlement to ${path.basename(entPath)}`);
            } catch (error) {
                console.error(`Error modifying ${entPath}:`, error.message);
            }
        }
    }
}

function modifyAppDelegate(iosPath, projectName) {
    // Try multiple possible locations for AppDelegate
    const possiblePaths = [
        path.join(iosPath, projectName, 'Classes', 'AppDelegate.m'),
        path.join(iosPath, projectName, 'AppDelegate.m'),
        path.join(iosPath, projectName, 'Classes', 'AppDelegate.swift'),
        path.join(iosPath, projectName, 'AppDelegate.swift')
    ];
    
    let targetPath = null;
    let isSwift = false;
    
    for (const p of possiblePaths) {
        if (fs.existsSync(p)) {
            targetPath = p;
            isSwift = p.endsWith('.swift');
            console.log('Found AppDelegate at:', p);
            break;
        }
    }
    
    if (!targetPath) {
        console.log('AppDelegate file not found in any expected location, skipping Siri modification');
        console.log('Checked paths:', possiblePaths);
        return;
    }

    try {
        let content = fs.readFileSync(targetPath, 'utf8');

        if (isSwift) {
            // Add import if not present
            if (!content.includes('import Intents')) {
                content = content.replace('import UIKit', 'import UIKit\nimport Intents');
                console.log('Added Intents import to AppDelegate.swift');
            }

            let modified = false;

            // Check for continueUserActivity method with multiple possible signatures
            const hasContinueUserActivity = content.includes('continue userActivity:') || 
                                            content.includes('continue userActivity :') ||
                                            content.includes('continueUserActivity');

            // Add continueUserActivity method if not present
            if (!hasContinueUserActivity) {
                const continueUserActivityMethod = `
    // MARK: - Siri Intent Handling
    
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        print("🎤 [AppDelegate] continueUserActivity called")
        print("🎤 Activity type: \\(userActivity.activityType)")
        
        // Handle Siri intents
        if userActivity.activityType == "INPlayMediaIntent" {
            print("🎤 [AppDelegate] Detected Siri play media intent")
            
            // Get the AutoMusicPlugin instance
            if let plugin = CDVAutoMusicPlugin.sharedInstance() {
                plugin.handleSiriIntent(userActivity: userActivity)
                return true
            } else {
                print("⚠️ [AppDelegate] CDVAutoMusicPlugin not initialized yet")
            }
        }
        
        return false
    }
`;
                // Insert before the last closing brace
                const lastBraceIndex = content.lastIndexOf('}');
                content = content.substring(0, lastBraceIndex) + continueUserActivityMethod + '\n}\n';
                console.log('Added continueUserActivity method to AppDelegate.swift');
                modified = true;
            } else {
                console.log('continueUserActivity method already exists, skipping');
            }

            // Check for handlerFor intent method with multiple possible signatures
            const hasHandlerForIntent = content.includes('handlerFor intent:') || 
                                        content.includes('handlerFor intent :') ||
                                        content.includes('handlerForIntent');

            // Add handlerFor intent method ONLY if not already present
            if (!hasHandlerForIntent) {
                const handlerForIntentMethod = `
    @available(iOS 13.0, *)
    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
        print("🎤 [AppDelegate] handlerFor intent called")
        
        if intent is INPlayMediaIntent {
            print("🎤 [AppDelegate] Returning CDVSiriIntentHandler for INPlayMediaIntent")
            return CDVSiriIntentHandler.shared
        }
        
        return nil
    }
`;
                // Insert before the last closing brace
                const lastBraceIndex = content.lastIndexOf('}');
                content = content.substring(0, lastBraceIndex) + handlerForIntentMethod + '\n}\n';
                console.log('Added handlerFor intent method to AppDelegate.swift');
                modified = true;
            } else {
                console.log('handlerFor intent method already exists, skipping');
            }

            if (modified) {
                console.log('Successfully modified AppDelegate.swift for Siri support');
            }
        } else {
            // Objective-C implementation
            // Add import if not present
            if (!content.includes('#import <Intents/Intents.h>')) {
                content = content.replace('#import "AppDelegate.h"', '#import "AppDelegate.h"\n#import <Intents/Intents.h>');
                console.log('Added Intents import to AppDelegate.m');
            }
            
            // Add Swift bridging header import to access Swift classes
            // The bridging header name follows pattern: ProjectName-Swift.h
            const swiftBridgingHeader = `#if __has_include("${projectName}-Swift.h")\n#import "${projectName}-Swift.h"\n#endif`;
            if (!content.includes('-Swift.h')) {
                content = content.replace('#import <Intents/Intents.h>', `#import <Intents/Intents.h>\n${swiftBridgingHeader}`);
                console.log('Added Swift bridging header import to AppDelegate.m');
            }

            let modified = false;

            // Add continueUserActivity method if not present
            if (!content.includes('application:continueUserActivity:restorationHandler:')) {
                const continueUserActivityMethod = `
#pragma mark - Siri Intent Handling

- (BOOL)application:(UIApplication *)application continueUserActivity:(NSUserActivity *)userActivity restorationHandler:(void (^)(NSArray<id<UIUserActivityRestoring>> * _Nullable))restorationHandler {
    NSLog(@"🎤 [AppDelegate] continueUserActivity called");
    NSLog(@"🎤 Activity type: %@", userActivity.activityType);
    
    // Handle Siri intents
    if ([userActivity.activityType isEqualToString:@"INPlayMediaIntent"]) {
        NSLog(@"🎤 [AppDelegate] Detected Siri play media intent");
        
        // Get the AutoMusicPlugin instance and forward the intent
        CDVAutoMusicPlugin *plugin = [CDVAutoMusicPlugin sharedInstance];
        if (plugin) {
            [plugin handleSiriIntentWithUserActivity:userActivity];
            return YES;
        } else {
            NSLog(@"⚠️ [AppDelegate] CDVAutoMusicPlugin not initialized yet");
        }
    }
    
    return NO;
}
`;
                // Insert before @end
                content = content.replace('@end', continueUserActivityMethod + '\n@end');
                console.log('Added continueUserActivity method to AppDelegate.m');
                modified = true;
            }

            // Add handlerForIntent method ONLY if not already present
            if (!content.includes('handlerForIntent:')) {
                const handlerForIntentMethod = `
- (id)application:(UIApplication *)application handlerForIntent:(INIntent *)intent API_AVAILABLE(ios(13.0)) {
    NSLog(@"🎤 [AppDelegate] handlerForIntent called");
    
    if ([intent isKindOfClass:[INPlayMediaIntent class]]) {
        NSLog(@"🎤 [AppDelegate] Returning CDVSiriIntentHandler for INPlayMediaIntent");
        return [CDVSiriIntentHandler shared];
    }
    
    return nil;
}
`;
                // Insert before @end
                content = content.replace('@end', handlerForIntentMethod + '\n@end');
                console.log('Added handlerForIntent method to AppDelegate.m');
                modified = true;
            } else {
                console.log('handlerForIntent method already exists in AppDelegate.m, skipping');
            }

            if (modified) {
                console.log('Successfully modified AppDelegate.m for Siri support');
            }
        }

        fs.writeFileSync(targetPath, content, 'utf8');
        console.log('Successfully modified AppDelegate for Siri support');

    } catch (error) {
        console.error('Error modifying AppDelegate:', error);
    }
};
