const fs = require('fs');
const files = ['web/index.html', 'web/app.js'];

files.forEach(file => {
    let content = fs.readFileSync(file, 'utf8');
    
    // Instead of doing generic byte conversion which might fail on characters that weren't double encoded,
    // let's do safe string replacement for the known corrupted characters:
    content = content
        .replace(/Ã§/g, 'ç')
        .replace(/Ã£/g, 'ã')
        .replace(/Ãµ/g, 'õ')
        .replace(/Ã¡/g, 'á')
        .replace(/Ã©/g, 'é')
        .replace(/Ã­/g, 'í')
        .replace(/Ã³/g, 'ó')
        .replace(/Ãº/g, 'ú')
        .replace(/Ã¢/g, 'â')
        .replace(/Ãª/g, 'ê')
        .replace(/Ã‡/g, 'Ç')
        .replace(/Ãƒ/g, 'Ã')
        .replace(/Ã•/g, 'Õ')
        .replace(/Ã‰/g, 'É')
        .replace(/Ã/g, 'í') // leftover Ã is often í or á, but wait, usually í is Ã­
        .replace(/âœ…/g, '✅')
        .replace(/ðŸš€/g, '🚀');
        
    // Specifically fix any weird replacements
    content = content.replace(/í­/g, 'í').replace(/í£/g, 'ã').replace(/í§/g, 'ç').replace(/íµ/g, 'õ').replace(/í¡/g, 'á').replace(/í©/g, 'é').replace(/í³/g, 'ó').replace(/íº/g, 'ú').replace(/í¢/g, 'â').replace(/íª/g, 'ê');
    
    // Some leftovers from Ã replacement
    content = content.replace(/í£o/g, 'ão').replace(/í§/g, 'ç').replace(/íµes/g, 'ões').replace(/í¡/g, 'á');

    fs.writeFileSync(file, content, 'utf8');
});
console.log('Fixed encodings.');
