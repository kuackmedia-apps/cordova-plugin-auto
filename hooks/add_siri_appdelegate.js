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

    // Read CarPlayEnabled preference from config.xml
    const carplayEnabled = getPreference(projectRoot, 'CarPlayEnabled') === 'true';
    console.log('CarPlay enabled:', carplayEnabled);

    // ========================================
    // STEP 1: Add Siri entitlement to .entitlements file
    // ========================================
    addSiriEntitlement(iosPath, projectName);

    // ========================================
    // STEP 2: Add CarPlay entitlement (conditional)
    // ========================================
    if (carplayEnabled) {
        addCarPlayEntitlement(iosPath, projectName);
    }

    // ========================================
    // STEP 2b: Add Sign in with Apple entitlement (conditional)
    // ========================================
    // Gated by AppleSignInEnabled so only apps that opt in (and have SIWA
    // enabled on their App ID) get the entitlement — otherwise signing fails.
    const appleSignInEnabled = getPreference(projectRoot, 'AppleSignInEnabled') === 'true';
    console.log('Apple Sign In enabled:', appleSignInEnabled);
    if (appleSignInEnabled) {
        addAppleSignInEntitlement(iosPath, projectName);
    }

    // ========================================
    // STEP 3: Modify AppDelegate
    // ========================================
    modifyAppDelegate(iosPath, projectName);
};

function getPreference(projectRoot, name) {
    const configPath = path.join(projectRoot, 'config.xml');
    try {
        const content = fs.readFileSync(configPath, 'utf8');
        const regex = new RegExp(`<preference\\s+name="${name}"\\s+value="([^"]*)"`, 'i');
        const match = content.match(regex);
        return match ? match[1] : '';
    } catch (e) {
        console.log(`Could not read config.xml for preference ${name}:`, e.message);
        return '';
    }
}

function addCarPlayEntitlement(iosPath, projectName) {
    const entitlementsPaths = [
        path.join(iosPath, projectName, 'Entitlements-Debug.plist'),
        path.join(iosPath, projectName, 'Entitlements-Release.plist')
    ];

    for (const entPath of entitlementsPaths) {
        if (fs.existsSync(entPath)) {
            try {
                let content = fs.readFileSync(entPath, 'utf8');

                if (content.includes('com.apple.developer.carplay-audio')) {
                    console.log(`CarPlay entitlement already exists in ${path.basename(entPath)}`);
                    continue;
                }

                const carplayEntitlement = `\t<key>com.apple.developer.carplay-audio</key>\n\t<true/>\n`;
                content = content.replace('</dict>', carplayEntitlement + '</dict>');

                fs.writeFileSync(entPath, content, 'utf8');
                console.log(`Added CarPlay entitlement to ${path.basename(entPath)}`);
            } catch (error) {
                console.error(`Error adding CarPlay entitlement to ${entPath}:`, error.message);
            }
        }
    }
}

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

function addAppleSignInEntitlement(iosPath, projectName) {
    // Same entitlements files as addSiriEntitlement. The signed file is
    // Resources/<App>.entitlements (CODE_SIGN_ENTITLEMENTS points there); the
    // deeplinks hook recreates it on clean builds, so we re-inject here.
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

                if (content.includes('com.apple.developer.applesignin')) {
                    console.log(`Apple Sign In entitlement already exists in ${path.basename(entPath)}`);
                    continue;
                }

                // applesignin is an array value (["Default"])
                const appleSignInEntitlement =
                    `\t<key>com.apple.developer.applesignin</key>\n\t<array>\n\t\t<string>Default</string>\n\t</array>\n`;
                content = content.replace('</dict>', appleSignInEntitlement + '</dict>');

                fs.writeFileSync(entPath, content, 'utf8');
                console.log(`Added Apple Sign In entitlement to ${path.basename(entPath)}`);
            } catch (error) {
                console.error(`Error adding Apple Sign In entitlement to ${entPath}:`, error.message);
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
            // Check for the method signature more thoroughly
            const hasContinueUserActivity = content.match(/- \(BOOL\)\s*application:\s*\(UIApplication\s*\*\)\s*application\s+continueUserActivity:/);
            
            if (!hasContinueUserActivity) {
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
                // Insert before the last @end
                const lastEndIndex = content.lastIndexOf('@end');
                content = content.substring(0, lastEndIndex) + continueUserActivityMethod + '\n@end\n';
                console.log('Added continueUserActivity method to AppDelegate.m');
                modified = true;
            } else {
                console.log('continueUserActivity method already exists in AppDelegate.m, skipping');
            }

            // Add handlerForIntent method ONLY if not already present
            const hasHandlerForIntent = content.match(/- \(id\)\s*application:\s*\(UIApplication\s*\*\)\s*application\s+handlerForIntent:/);
            
            if (!hasHandlerForIntent) {
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
                // Insert before the last @end
                const lastEndIndex = content.lastIndexOf('@end');
                content = content.substring(0, lastEndIndex) + handlerForIntentMethod + '\n@end\n';
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
