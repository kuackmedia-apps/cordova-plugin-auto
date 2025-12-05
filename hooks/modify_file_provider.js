#!/usr/bin/env node

'use strict';

const fs = require('fs');
const path = require('path');

module.exports = function(context) {
    console.log('Running modify_file_provider hook...');

    // Get the project root directory
    const projectRoot = context.opts.projectRoot;

    // Path to the file provider paths XML file
    const filePath = path.join(
        projectRoot,
        'platforms',
        'android',
        'app',
        'src',
        'main',
        'res',
        'xml',
        'cdv_core_file_provider_paths.xml'
    );

    // Alternative path for older Cordova versions
    const alternativeFilePath = path.join(
        projectRoot,
        'platforms',
        'android',
        'res',
        'xml',
        'cdv_core_file_provider_paths.xml'
    );

    // Determine which path exists
    let targetPath = null;
    if (fs.existsSync(filePath)) {
        targetPath = filePath;
    } else if (fs.existsSync(alternativeFilePath)) {
        targetPath = alternativeFilePath;
    }

    if (!targetPath) {
        console.log('Warning: cdv_core_file_provider_paths.xml not found. It will be created by another plugin later.');
        return;
    }

    try {
        // Read the XML file
        let xmlContent = fs.readFileSync(targetPath, 'utf8');

        // Define all entries we need to add
        const entries = [
            { name: 'files_root', path: '.', comment: 'Base files directory for all subdirectories' },
            { name: 'img', path: 'img/' },
            { name: 'img_cover', path: 'img/cover/' },
            { name: 'img_playlist', path: 'img/playlist/' },
            { name: 'img_tag', path: 'img/tag/' }
        ];

        let modified = false;

        for (const entry of entries) {
            // Check if entry already exists
            if (xmlContent.includes(`name="${entry.name}"`) && xmlContent.includes(`path="${entry.path}"`)) {
                console.log(`File provider path for "${entry.name}" already exists. Skipping.`);
                continue;
            }

            // Build the new entry line
            let newEntry = '';
            if (entry.comment) {
                newEntry += `    <!-- ${entry.comment} -->\n`;
            }
            newEntry += `    <files-path name="${entry.name}" path="${entry.path}"/>`;

            if (xmlContent.includes('</paths>')) {
                // Insert before </paths>
                xmlContent = xmlContent.replace(
                    '</paths>',
                    newEntry + '\n</paths>'
                );
                console.log(`Added files-path for "${entry.name}" (path="${entry.path}")`);
                modified = true;
            }
        }

        if (modified) {
            // Write the modified content back
            fs.writeFileSync(targetPath, xmlContent, 'utf8');
            console.log('Successfully updated cdv_core_file_provider_paths.xml');
        } else {
            console.log('All required file provider paths already exist.');
        }

    } catch (error) {
        console.error('Error modifying cdv_core_file_provider_paths.xml:', error.message);
    }
};
