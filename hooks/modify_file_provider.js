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

        // Check if the entry already exists
        if (xmlContent.includes('name="img"') && xmlContent.includes('path="img/"')) {
            console.log('File provider path for "img" already exists. Skipping modification.');
            return;
        }

        // Find the closing </paths> tag and insert the new entry before it
        const newEntry = '    <files-path name="img" path="img/"/>';

        if (xmlContent.includes('</paths>')) {
            // Insert before </paths>
            xmlContent = xmlContent.replace(
                '</paths>',
                newEntry + '\n</paths>'
            );

            // Write the modified content back
            fs.writeFileSync(targetPath, xmlContent, 'utf8');
            console.log('Successfully added files-path for "img" to cdv_core_file_provider_paths.xml');
        } else {
            console.log('Error: Could not find </paths> tag in the XML file.');
        }

    } catch (error) {
        console.error('Error modifying cdv_core_file_provider_paths.xml:', error.message);
    }
};
